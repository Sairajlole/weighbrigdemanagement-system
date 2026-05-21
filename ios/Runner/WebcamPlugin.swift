import Flutter
import UIKit
import AVFoundation

public class WebcamPlugin: NSObject, FlutterPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var captureSession: AVCaptureSession?
    private var latestBuffer: CVPixelBuffer?
    private let queue = DispatchQueue(label: "webcam.face.capture", qos: .userInteractive)

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.weighbridge/webcam", binaryMessenger: registrar.messenger())
        let instance = WebcamPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            startCamera(result: result)
        case "captureFrame":
            captureFrame(result: result)
        case "stopCamera":
            stopCamera(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startCamera(result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission not granted", details: nil))
                    return
                }

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    result(FlutterError(code: "NO_CAMERA", message: "No camera found", details: nil))
                    return
                }

                do {
                    let session = AVCaptureSession()
                    session.sessionPreset = .medium

                    let input = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(input) else {
                        result(FlutterError(code: "INIT_ERROR", message: "Cannot add camera input", details: nil))
                        return
                    }
                    session.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)

                    guard session.canAddOutput(output) else {
                        result(FlutterError(code: "INIT_ERROR", message: "Cannot add video output", details: nil))
                        return
                    }
                    session.addOutput(output)

                    session.startRunning()
                    self.captureSession = session
                    result(true)
                } catch {
                    result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func captureFrame(result: @escaping FlutterResult) {
        guard let buffer = latestBuffer else {
            result(FlutterError(code: "NO_FRAME", message: "No frame available", details: nil))
            return
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) else {
            result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode frame", details: nil))
            return
        }

        result(FlutterStandardTypedData(bytes: jpegData))
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
        latestBuffer = nil
        result(true)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = imageBuffer
    }
}
