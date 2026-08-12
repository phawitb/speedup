package com.speakup.app.speak_up

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class ScreenCaptureService : Service() {
    override fun onCreate() {
        super.onCreate()
        val channelId = "speakup_recording"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Practice recording",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("SpeakUp is recording")
            .setContentText("Your practice video is being captured on this device")
            .setOngoing(true)
            .build()
        ServiceCompat.startForeground(
            this,
            9021,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            } else 0,
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
