package com.demoapp

import android.os.Bundle
import android.view.KeyEvent
import android.util.Log
import android.content.Intent
import android.app.NotificationManager
import android.app.NotificationChannel
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pressCount = 0
    private var lastPressTime = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ✅ If app was opened via notification, auto-fire SOS
        if (intent?.getBooleanExtra("openRecordingScreen", false) == true) {
            fireSOSChannel()
            intent?.removeExtra("openRecordingScreen")
        }
    }

    override fun onResume() {
        super.onResume()
        // ✅ Also check when app resumes (foregrounded)
        if (intent?.getBooleanExtra("openRecordingScreen", false) == true) {
            fireSOSChannel()
            intent?.removeExtra("openRecordingScreen")
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            Log.d("SOS", "Volume key pressed: $keyCode")

            val now = System.currentTimeMillis()
            if (now - lastPressTime < 1500) {
                pressCount++
            } else {
                pressCount = 1
            }
            lastPressTime = now

            if (pressCount == 4) {
                triggerSOS()
                pressCount = 0
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun triggerSOS() {
        Log.d("SOS", "🚨 SOS Triggered via foreground Activity")
        fireSOSChannel()

        // ✅ Show notification to bring app to foreground if backgrounded
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openRecordingScreen", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val channelId = "sos_channel_id"
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "SOS Notifications",
                NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("SOS Triggered")
            .setContentText("Opening Recording Screen…")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        manager.notify(1001, notification)
    }

    private fun fireSOSChannel() {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        messenger?.let {
            MethodChannel(it, "sos_channel").invokeMethod("triggerSOS", null)
        }
    }
}