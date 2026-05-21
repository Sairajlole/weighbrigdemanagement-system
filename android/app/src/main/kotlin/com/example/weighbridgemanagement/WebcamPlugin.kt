package com.example.weighbridgemanagement

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class WebcamPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var cameraExecutor: ExecutorService? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var latestJpeg: ByteArray? = null
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val CAMERA_PERMISSION_CODE = 9001
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.weighbridge/webcam")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCamera" -> startCamera(result)
            "captureFrame" -> captureFrame(result)
            "stopCamera" -> stopCamera(result)
            else -> result.notImplemented()
        }
    }

    private fun startCamera(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            pendingResult = result
            ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
            return
        }

        bindCamera(result)
    }

    private fun bindCamera(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(act)
        cameraProviderFuture.addListener({
            try {
                val provider = cameraProviderFuture.get()
                cameraProvider = provider

                val imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(640, 480))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                cameraExecutor = Executors.newSingleThreadExecutor()

                imageAnalysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                    latestJpeg = imageProxyToJpeg(imageProxy)
                    imageProxy.close()
                }

                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                    .build()

                provider.unbindAll()
                provider.bindToLifecycle(act as LifecycleOwner, cameraSelector, imageAnalysis)

                result.success(true)
            } catch (e: Exception) {
                // Fallback to back camera
                try {
                    val provider = cameraProviderFuture.get()
                    val imageAnalysis = ImageAnalysis.Builder()
                        .setTargetResolution(Size(640, 480))
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()

                    imageAnalysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                        latestJpeg = imageProxyToJpeg(imageProxy)
                        imageProxy.close()
                    }

                    val backSelector = CameraSelector.Builder()
                        .requireLensFacing(CameraSelector.LENS_FACING_BACK)
                        .build()

                    provider.unbindAll()
                    provider.bindToLifecycle(act as LifecycleOwner, backSelector, imageAnalysis)
                    result.success(true)
                } catch (e2: Exception) {
                    result.error("INIT_ERROR", e2.message, null)
                }
            }
        }, ContextCompat.getMainExecutor(act))
    }

    private fun imageProxyToJpeg(imageProxy: ImageProxy): ByteArray? {
        val planes = imageProxy.planes
        if (planes.isEmpty()) return null

        val yBuffer = planes[0].buffer
        val uBuffer = planes[1].buffer
        val vBuffer = planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 85, out)
        return out.toByteArray()
    }

    private fun captureFrame(result: MethodChannel.Result) {
        val jpeg = latestJpeg
        if (jpeg == null) {
            result.error("NO_FRAME", "No frame available", null)
            return
        }
        result.success(jpeg)
    }

    private fun stopCamera(result: MethodChannel.Result) {
        cameraProvider?.unbindAll()
        cameraProvider = null
        cameraExecutor?.shutdown()
        cameraExecutor = null
        latestJpeg = null
        result.success(true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == CAMERA_PERMISSION_CODE) {
            val pending = pendingResult ?: return false
            pendingResult = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                bindCamera(pending)
            } else {
                pending.error("PERMISSION_DENIED", "Camera permission not granted", null)
            }
            return true
        }
        return false
    }
}
