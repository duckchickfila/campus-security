package com.example.demoapp

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.demoapp/sos"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { _, result ->
                result.notImplemented()
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Test the MethodChannel immediately
        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, CHANNEL)
            .invokeMethod("triggerSOS", null)

        // Start foreground service for volume listening
        ContextCompat.startForegroundService(
            this,
            Intent(this, VolumeButtonService::class.java)
        )
    }
}