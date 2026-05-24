import Cocoa
import FlutterMacOS
import AVFoundation
import Vision

/// Simple webcam plugin for face enrollment — captures JPEG frames from a selected camera.
public class WebcamPlugin: NSObject, FlutterPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var captureSession: AVCaptureSession?
    private var latestJpeg: Data?
    private var faceDetected: Bool = false
    private var faceCount: Int = 0
    private var frameCount: Int = 0
    private let queue = DispatchQueue(label: "webcam.face.capture", qos: .userInteractive)

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.weighbridge/webcam", binaryMessenger: registrar.messenger)
        let instance = WebcamPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listCameras":
            listCameras(result: result)
        case "startCamera":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["deviceId"] as? String
            startCamera(deviceId: deviceId, result: result)
        case "captureFrame":
            captureFrame(result: result)
        case "detectFace":
            detectFace(result: result)
        case "stopCamera":
            stopCamera(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func listCameras(result: @escaping FlutterResult) {
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
                mediaType: .video,
                position: .unspecified
            )
            devices = session.devices
        } else {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                mediaType: .video,
                position: .unspecified
            )
            devices = session.devices
        }
        let cameras = devices
            .filter { !$0.localizedName.lowercased().contains("desk view") }
            .map { device -> [String: String] in
                return [
                    "id": device.uniqueID,
                    "name": device.localizedName,
                ]
            }
        result(cameras)
    }

    private func startCamera(deviceId: String?, result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission not granted", details: nil))
                    return
                }

                // Stop existing session if any
                if let existing = self.captureSession {
                    existing.stopRunning()
                    for input in existing.inputs { existing.removeInput(input) }
                    for output in existing.outputs { existing.removeOutput(output) }
                    self.captureSession = nil
                    self.latestJpeg = nil
                }

                let allDevices: [AVCaptureDevice]
                if #available(macOS 14.0, *) {
                    let disc = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
                        mediaType: .video,
                        position: .unspecified
                    )
                    allDevices = disc.devices
                } else {
                    let disc = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                        mediaType: .video,
                        position: .unspecified
                    )
                    allDevices = disc.devices
                }
                let filtered = allDevices.filter { !$0.localizedName.lowercased().contains("desk view") }

                let device: AVCaptureDevice?
                if let requestedId = deviceId, !requestedId.isEmpty {
                    device = filtered.first(where: { $0.uniqueID == requestedId })
                        ?? filtered.first(where: { $0.localizedName == requestedId })
                } else {
                    device = filtered.first(where: { $0.position == .front })
                        ?? filtered.first
                }

                guard let camera = device else {
                    result(FlutterError(code: "NO_CAMERA", message: "No camera found", details: nil))
                    return
                }

                do {
                    let captureSession = AVCaptureSession()
                    captureSession.sessionPreset = .medium

                    let input = try AVCaptureDeviceInput(device: camera)
                    guard captureSession.canAddInput(input) else {
                        result(FlutterError(code: "INIT_ERROR", message: "Cannot add camera input", details: nil))
                        return
                    }
                    captureSession.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)

                    guard captureSession.canAddOutput(output) else {
                        result(FlutterError(code: "INIT_ERROR", message: "Cannot add video output", details: nil))
                        return
                    }
                    captureSession.addOutput(output)

                    self.frameCount = 0
                    self.faceDetected = false
                    self.faceCount = 0
                    captureSession.startRunning()
                    self.captureSession = captureSession
                    result(true)
                } catch {
                    result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func captureFrame(result: @escaping FlutterResult) {
        guard let jpeg = latestJpeg else {
            result(FlutterError(code: "NO_FRAME", message: "No frame available", details: nil))
            return
        }
        result(FlutterStandardTypedData(bytes: jpeg))
    }

    private func detectFace(result: @escaping FlutterResult) {
        result(["detected": faceDetected, "count": faceCount] as [String: Any])
    }

    private func stopCamera(result: @escaping FlutterResult) {
        captureSession?.stopRunning()
        if let inputs = captureSession?.inputs {
            for input in inputs { captureSession?.removeInput(input) }
        }
        if let outputs = captureSession?.outputs {
            for output in outputs { captureSession?.removeOutput(output) }
        }
        captureSession = nil
        latestJpeg = nil
        faceDetected = false
        faceCount = 0
        result(true)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Convert to JPEG
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let jpeg = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) {
            latestJpeg = jpeg
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)

        // Run face detection every 5th frame to avoid overload
        frameCount += 1
        if frameCount % 5 == 0 {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                let faces = request.results ?? []
                faceDetected = !faces.isEmpty
                faceCount = faces.count
            } catch {
                faceDetected = false
                faceCount = 0
            }
        }
    }
}
