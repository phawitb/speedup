package com.speakup.app.speak_up

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.io.File

class AndroidScreenRecorder(private val context: Context) {
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var recorder: MediaRecorder? = null
    var pendingFile: File? = null
        private set

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            virtualDisplay?.release()
            virtualDisplay = null
        }
    }

    fun start(resultCode: Int, data: Intent, includeAudio: Boolean) {
        discard()
        val metrics = context.resources.displayMetrics
        val width = metrics.widthPixels.let { if (it % 2 == 0) it else it - 1 }
        val height = metrics.heightPixels.let { if (it % 2 == 0) it else it - 1 }
        val output = File(context.cacheDir, "speakup-${System.currentTimeMillis()}.mp4")
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION") MediaRecorder()
        }
        if (includeAudio) mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        mediaRecorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        if (includeAudio) {
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioEncodingBitRate(128_000)
            mediaRecorder.setAudioSamplingRate(44_100)
        }
        mediaRecorder.setVideoSize(width, height)
        mediaRecorder.setVideoFrameRate(30)
        mediaRecorder.setVideoEncodingBitRate(6_000_000)
        mediaRecorder.setOutputFile(output.absolutePath)
        mediaRecorder.prepare()

        val manager = context.getSystemService(MediaProjectionManager::class.java)
        val mediaProjection = manager.getMediaProjection(resultCode, data)
            ?: error("Android did not grant a screen capture session")
        mediaProjection.registerCallback(projectionCallback, Handler(Looper.getMainLooper()))
        val display = mediaProjection.createVirtualDisplay(
            "SpeakUpPractice",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            mediaRecorder.surface,
            null,
            Handler(Looper.getMainLooper()),
        )
        projection = mediaProjection
        virtualDisplay = display
        recorder = mediaRecorder
        pendingFile = output
        mediaRecorder.start()
    }

    fun stop(): String {
        val output = pendingFile ?: error("No Android recording is active")
        try {
            recorder?.stop()
        } finally {
            recorder?.release()
            recorder = null
            virtualDisplay?.release()
            virtualDisplay = null
            projection?.unregisterCallback(projectionCallback)
            projection?.stop()
            projection = null
            context.stopService(Intent(context, ScreenCaptureService::class.java))
        }
        check(output.exists() && output.length() > 0) { "The Android recording is empty" }
        return output.absolutePath
    }

    fun save(path: String) {
        val source = File(path)
        check(source.exists() && source.length() > 0) { "The recorded video is missing" }
        val name = "SpeakUp-${System.currentTimeMillis()}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/SpeakUp")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("Could not create the Gallery video")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: error("Could not write the Gallery video")
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    fun discard(path: String? = pendingFile?.absolutePath) {
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        virtualDisplay?.release()
        virtualDisplay = null
        projection?.stop()
        projection = null
        path?.let { File(it).delete() }
        pendingFile = null
        context.stopService(Intent(context, ScreenCaptureService::class.java))
    }
}
