package com.example.demoapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class VolumeButtonReceiver : BroadcastReceiver() {
    private var lastPressTime: Long = 0
    private var pressCount: Int = 0

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("VolumeReceiver", "onReceive called with intent: ${intent?.action}")

        if (intent?.action == Intent.ACTION_MEDIA_BUTTON) {
            val keyEvent = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
            Log.d("VolumeReceiver", "KeyEvent: $keyEvent")

            if (keyEvent?.action == KeyEvent.ACTION_DOWN &&
                (keyEvent.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                 keyEvent.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {

                val now = System.currentTimeMillis()
                if (now - lastPressTime < 600) {
                    pressCount++
                } else {
                    pressCount = 1
                }
                lastPressTime = now

                Log.d("VolumeReceiver", "Press count updated: $pressCount")

                if (pressCount == 4) {
                    Log.d("VolumeReceiver", "Quadruple press detected → Trigger SOS")
                    triggerSOS(context)
                    pressCount = 0
                }
            }
        }
    }

    private fun triggerSOS(context: Context?) {
        Log.d("VolumeReceiver", "triggerSOS called")

        val flutterEngine = FlutterEngineCache.getInstance().get("my_engine_id")
        if (flutterEngine != null) {
            Log.d("VolumeReceiver", "Sending triggerSOS to Flutter via MethodChannel")
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.demoapp/sos")
                .invokeMethod("triggerSOS", null)
        } else {
            Log.d("VolumeReceiver", "FlutterEngine not cached, launching MainActivity")
            val intent = Intent(context, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            context?.startActivity(intent)
        }
    }
}