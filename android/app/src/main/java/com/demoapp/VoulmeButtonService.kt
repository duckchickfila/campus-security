package com.example.demoapp

import android.app.Service
import android.content.Intent
import android.media.session.MediaSession
import android.os.IBinder
import android.util.Log
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache

class VolumeButtonService : Service() {
    private lateinit var mediaSession: MediaSession
    private var pressCount = 0
    private var lastPressTime: Long = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d("VolumeService", "Service created")

        mediaSession = MediaSession(this, "VolumeButtonService")
        mediaSession.setCallback(object : MediaSession.Callback() {
            // ✅ Correct signature: non-null Intent
            override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                Log.d("VolumeService", "Media button event: $mediaButtonIntent")


                val now = System.currentTimeMillis()
                if (now - lastPressTime < 600) {
                    pressCount++
                } else {
                    pressCount = 1
                }
                lastPressTime = now

                if (pressCount == 4) {
                    triggerSOS()
                    pressCount = 0
                }

                // ✅ Pass non-null Intent to super
                return super.onMediaButtonEvent(mediaButtonIntent)
            }
        })
        mediaSession.isActive = true
    }

    private fun triggerSOS() {
        Log.d("VolumeService", "Trigger SOS called")
        Toast.makeText(this, "SOS Triggered!", Toast.LENGTH_SHORT).show()

        val flutterEngine = FlutterEngineCache.getInstance().get("my_engine_id")
        if (flutterEngine != null) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.demoapp/sos")
                .invokeMethod("triggerSOS", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaSession.release()
    }
}