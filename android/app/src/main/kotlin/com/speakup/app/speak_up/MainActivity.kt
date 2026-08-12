package com.speakup.app.speak_up

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val screenRecorder by lazy { AndroidScreenRecorder(this) }
    private val audioExtractor by lazy { AudioExtractor(this) }
    private val videoComposer by lazy { VideoComposer(this) }
    private var pendingStartResult: MethodChannel.Result? = null
    private val projectionRequestCode = 7102
    private val microphoneRequestCode = 7103

    private val detector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .enableTracking()
            .setMinFaceSize(0.18f)
            .build()
        FaceDetection.getClient(options)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.speakup.app/video_composer",
        ).setMethodCallHandler { call, result ->
            if (call.method != "compose") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            @Suppress("UNCHECKED_CAST")
            val arguments = call.arguments as? Map<String, Any?>
            if (arguments == null) {
                result.error("missing_arguments", "Video composition settings are missing", null)
                return@setMethodCallHandler
            }
            videoComposer.compose(arguments) { composed ->
                runOnUiThread {
                    composed.onSuccess(result::success)
                        .onFailure { result.error("compose_failed", it.message, null) }
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.speakup.app/face_tracking",
        ).setMethodCallHandler { call, result ->
            if (call.method != "processFrame") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val width = call.argument<Int>("width")
            val height = call.argument<Int>("height")
            val rotation = call.argument<Int>("sensorOrientation") ?: 0
            if (bytes == null || width == null || height == null) {
                result.success(mapOf("detected" to false))
                return@setMethodCallHandler
            }
            val image = InputImage.fromByteArray(
                bytes,
                width,
                height,
                rotation,
                InputImage.IMAGE_FORMAT_NV21,
            )
            detector.process(image)
                .addOnSuccessListener { faces ->
                    val face = faces.maxByOrNull { it.boundingBox.width() }
                    result.success(face?.let { faceValues(it, width, height) } ?: mapOf("detected" to false))
                }
                .addOnFailureListener {
                    result.success(mapOf("detected" to false))
                }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.speakup.app/audio_extraction",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractWav" -> {
                    val path = call.argument<String>("videoPath")
                    if (path == null) {
                        result.error("missing_path", "The video path is missing", null)
                    } else {
                        Thread {
                            runCatching { audioExtractor.extractWav(path) }
                                .onSuccess { runOnUiThread { result.success(it) } }
                                .onFailure { runOnUiThread { result.error("audio_failed", it.message, null) } }
                        }.start()
                    }
                }
                "deleteAudio" -> {
                    call.argument<String>("path")?.let { java.io.File(it).delete() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.speakup.app/screen_recording",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "needsSeparateAudio" -> result.success(false)
                "start" -> startScreenRecording(result)
                "stop" -> runCatching { screenRecorder.stop() }
                    .onSuccess(result::success)
                    .onFailure { result.error("stop_failed", it.message, null) }
                "save" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("missing_path", "The video path is missing", null)
                    } else {
                        runCatching { screenRecorder.save(path) }
                            .onSuccess { result.success(null) }
                            .onFailure { result.error("save_failed", it.message, null) }
                    }
                }
                "discard", "discardActive" -> {
                    screenRecorder.discard(call.argument<String>("path"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startScreenRecording(result: MethodChannel.Result) {
        if (pendingStartResult != null) {
            result.error("already_starting", "Screen recording permission is already open", null)
            return
        }
        pendingStartResult = result
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphoneRequestCode)
        } else {
            requestProjectionConsent()
        }
    }

    private fun requestProjectionConsent() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        startActivityForResult(manager.createScreenCaptureIntent(), projectionRequestCode)
    }

    @Deprecated("Uses the Activity result callback required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != projectionRequestCode) return
        val result = pendingStartResult ?: return
        pendingStartResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            stopService(Intent(this, ScreenCaptureService::class.java))
            result.error("permission_denied", "Screen recording permission was not granted", null)
            return
        }
        // Android 14+ only permits a mediaProjection foreground service after
        // the user has granted this capture session. Give the service one main
        // loop turn to enter the foreground before MediaRecorder preparation.
        ContextCompat.startForegroundService(
            this,
            Intent(this, ScreenCaptureService::class.java),
        )
        Handler(Looper.getMainLooper()).postDelayed({
            runCatching {
                screenRecorder.start(
                    resultCode,
                    data,
                    ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                        PackageManager.PERMISSION_GRANTED,
                )
            }.onSuccess { result.success(null) }
                .onFailure {
                    stopService(Intent(this, ScreenCaptureService::class.java))
                    result.error("start_failed", it.message, null)
                }
        }, 150L)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == microphoneRequestCode) requestProjectionConsent()
    }

    private fun faceValues(face: Face, imageWidth: Int, imageHeight: Int): Map<String, Any> {
        val upper = face.getContour(FaceContour.UPPER_LIP_BOTTOM)?.points.orEmpty()
        val lower = face.getContour(FaceContour.LOWER_LIP_TOP)?.points.orEmpty()
        val mouthOpen = if (upper.isNotEmpty() && lower.isNotEmpty()) {
            val upperY = upper.sumOf { it.y.toDouble() } / upper.size
            val lowerY = lower.sumOf { it.y.toDouble() } / lower.size
            ((lowerY - upperY) / (face.boundingBox.height() * 0.12)).coerceIn(0.0, 1.0)
        } else 0.0
        return mapOf(
            "detected" to true,
            "yaw" to (face.headEulerAngleY / 35.0).coerceIn(-1.0, 1.0),
            "pitch" to (face.headEulerAngleX / 30.0).coerceIn(-1.0, 1.0),
            "roll" to (face.headEulerAngleZ / 35.0).coerceIn(-1.0, 1.0),
            "leftEye" to (face.leftEyeOpenProbability ?: 1f).coerceIn(0f, 1f),
            "rightEye" to (face.rightEyeOpenProbability ?: 1f).coerceIn(0f, 1f),
            "mouthOpen" to mouthOpen,
            "smile" to (face.smilingProbability ?: 0f).coerceIn(0f, 1f),
            "faceCenterX" to (face.boundingBox.exactCenterX() / imageWidth).coerceIn(0f, 1f),
            "faceCenterY" to (face.boundingBox.exactCenterY() / imageHeight).coerceIn(0f, 1f),
            "faceWidth" to (face.boundingBox.width().toFloat() / imageWidth).coerceIn(0.05f, 1f),
            "faceHeight" to (face.boundingBox.height().toFloat() / imageHeight).coerceIn(0.05f, 1f),
        )
    }

    override fun onDestroy() {
        screenRecorder.discard()
        detector.close()
        super.onDestroy()
    }
}
