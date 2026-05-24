import Cocoa
import FlutterMacOS
import AVFoundation

/// A multi-camera plugin that supports simultaneous live feeds from multiple cameras.
/// Sessions sharing the same physical device reuse one AVCaptureSession + texture.
public class MultiCameraPlugin: NSObject, FlutterPlugin {

    private let registry: FlutterTextureRegistry
    private var sessions: [String: CameraSession] = [:]
    // Maps deviceUniqueID → shared session key (first session that opened this device)
    private var deviceToSession: [String: String] = [:]

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "multi_camera", binaryMessenger: registrar.messenger)
        let instance = MultiCameraPlugin(registry: registrar.textures)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "listDevices":
            listDevices(result)
        case "start":
            let deviceId = args["deviceId"] as? String
            let sessionId = args["sessionId"] as? String ?? UUID().uuidString
            let width = args["width"] as? Int ?? 960
            let height = args["height"] as? Int ?? 540
            start(sessionId: sessionId, deviceId: deviceId, width: width, height: height, result: result)
        case "stop":
            guard let sessionId = args["sessionId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "sessionId required", details: nil))
                return
            }
            stop(sessionId: sessionId, result: result)
        case "stopAll":
            stopAll(result: result)
        case "takePicture":
            guard let sessionId = args["sessionId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "sessionId required", details: nil))
                return
            }
            takePicture(sessionId: sessionId, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func listDevices(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission not granted", details: nil))
                    return
                }
                var devices: [[String: Any]] = []
                var seen = Set<String>()
                let captured: [AVCaptureDevice]
                if #available(macOS 14.0, *) {
                    let session = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
                        mediaType: .video,
                        position: .unspecified
                    )
                    captured = session.devices
                } else if #available(macOS 10.15, *) {
                    let session = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                        mediaType: .video,
                        position: .unspecified
                    )
                    captured = session.devices
                } else {
                    captured = AVCaptureDevice.devices(for: .video)
                }
                for device in captured {
                    let name = device.localizedName.lowercased()
                    if name.contains("desk view") { continue }
                    if seen.contains(device.uniqueID) { continue }
                    seen.insert(device.uniqueID)
                    devices.append([
                        "deviceId": device.uniqueID,
                        "name": device.localizedName,
                        "manufacturer": device.manufacturer,
                    ])
                }
                result(devices)
            }
        }
    }

    private func start(sessionId: String, deviceId: String?, width: Int, height: Int, result: @escaping FlutterResult) {
        // Stop existing session with same ID
        if let existing = sessions[sessionId] {
            existing.stop(registry: registry)
            sessions.removeValue(forKey: sessionId)
            // Clean up deviceToSession if this was the owner
            deviceToSession = deviceToSession.filter { $0.value != sessionId }
        }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission not granted", details: nil))
                    return
                }

                let captured: [AVCaptureDevice]
                if #available(macOS 14.0, *) {
                    let session = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
                        mediaType: .video,
                        position: .unspecified
                    )
                    captured = session.devices
                } else if #available(macOS 10.15, *) {
                    let session = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                        mediaType: .video,
                        position: .unspecified
                    )
                    captured = session.devices
                } else {
                    captured = AVCaptureDevice.devices(for: .video)
                }

                let filtered = captured.filter { !$0.localizedName.lowercased().contains("desk view") }

                var device: AVCaptureDevice?
                if let deviceId = deviceId, !deviceId.isEmpty {
                    device = filtered.first(where: { $0.uniqueID == deviceId })
                        ?? filtered.first(where: { $0.localizedName == deviceId })
                } else {
                    device = filtered.first
                }

                guard let camera = device else {
                    result(FlutterError(code: "NO_CAMERA", message: "Device not found: \(deviceId ?? "none")", details: nil))
                    return
                }

                // If another session already owns this physical device, share its texture
                if let ownerKey = self.deviceToSession[camera.uniqueID],
                   let ownerSession = self.sessions[ownerKey] {
                    self.sessions[sessionId] = ownerSession
                    result([
                        "sessionId": sessionId,
                        "textureId": ownerSession.textureId!,
                        "width": ownerSession.outputWidth,
                        "height": ownerSession.outputHeight,
                        "deviceId": camera.uniqueID,
                        "deviceName": camera.localizedName,
                    ] as [String: Any])
                    return
                }

                let session = CameraSession()
                do {
                    try session.start(device: camera, registry: self.registry, width: width, height: height)
                    self.sessions[sessionId] = session
                    self.deviceToSession[camera.uniqueID] = sessionId
                    result([
                        "sessionId": sessionId,
                        "textureId": session.textureId!,
                        "width": session.outputWidth,
                        "height": session.outputHeight,
                        "deviceId": camera.uniqueID,
                        "deviceName": camera.localizedName,
                    ] as [String: Any])
                } catch {
                    result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func stop(sessionId: String, result: @escaping FlutterResult) {
        guard let session = sessions[sessionId] else {
            result(false)
            return
        }
        sessions.removeValue(forKey: sessionId)

        // Only actually stop the capture session if no other session key references it
        let stillInUse = sessions.values.contains(where: { $0 === session })
        if !stillInUse {
            session.stop(registry: registry)
            // Remove from deviceToSession
            deviceToSession = deviceToSession.filter { $0.value != sessionId }
        }
        result(true)
    }

    private func stopAll(result: @escaping FlutterResult) {
        // Deduplicate so shared sessions only stop once
        let uniqueSessions = Set(sessions.values.map { ObjectIdentifier($0) })
        var stopped = Set<ObjectIdentifier>()
        for (_, session) in sessions {
            let id = ObjectIdentifier(session)
            if !stopped.contains(id) {
                session.stop(registry: registry)
                stopped.insert(id)
            }
        }
        sessions.removeAll()
        deviceToSession.removeAll()
        result(true)
    }

    private func takePicture(sessionId: String, result: @escaping FlutterResult) {
        guard let session = sessions[sessionId] else {
            result(FlutterError(code: "NO_SESSION", message: "Session not found", details: nil))
            return
        }
        guard let buffer = session.latestBuffer else {
            result(FlutterError(code: "NO_FRAME", message: "No frame available yet", details: nil))
            return
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) else {
            result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode JPEG", details: nil))
            return
        }

        result(FlutterStandardTypedData(bytes: jpegData))
    }
}

/// Individual camera session — owns one AVCaptureSession + one Flutter texture.
class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FlutterTexture {

    private var captureSession: AVCaptureSession?
    var textureId: Int64?
    var latestBuffer: CVPixelBuffer?
    var outputWidth: Int = 0
    var outputHeight: Int = 0

    private var registry: FlutterTextureRegistry?

    func start(device: AVCaptureDevice, registry: FlutterTextureRegistry, width: Int, height: Int) throws {
        self.registry = registry

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Pick a preset that matches requested resolution
        if width <= 640 && session.canSetSessionPreset(.low) {
            session.sessionPreset = .low
        } else if width <= 960 && session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        } else if width <= 1280 && session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "MultiCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue(label: "multicam.\(device.uniqueID)", qos: .userInteractive)
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            throw NSError(domain: "MultiCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        session.addOutput(output)

        session.commitConfiguration()

        // Register texture
        textureId = registry.register(self)

        // Get actual output dimensions
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        outputWidth = Int(dims.width)
        outputHeight = Int(dims.height)

        // Start
        session.startRunning()
        captureSession = session
    }

    func stop(registry: FlutterTextureRegistry) {
        captureSession?.stopRunning()
        if let inputs = captureSession?.inputs {
            for input in inputs { captureSession?.removeInput(input) }
        }
        if let outputs = captureSession?.outputs {
            for output in outputs { captureSession?.removeOutput(output) }
        }
        captureSession = nil

        if let tid = textureId {
            registry.unregisterTexture(tid)
            textureId = nil
        }
        latestBuffer = nil
    }

    // MARK: - FlutterTexture

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = imageBuffer
        if let tid = textureId, let reg = registry {
            DispatchQueue.main.async {
                reg.textureFrameAvailable(tid)
            }
        }
    }
}
