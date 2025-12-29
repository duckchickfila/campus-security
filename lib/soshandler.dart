import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'recording_screen.dart';

class SOSHandler {
  static const MethodChannel _channel =
      MethodChannel('com.example.demoapp/sos');

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    print("SOSHandler.init attached"); // Debug: confirm handler attached

    _channel.setMethodCallHandler((call) async {
      print("MethodChannel call received: ${call.method}"); // Debug

      if (call.method == "triggerSOS") {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text("SOS Triggered from native!")),
          );
        }
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const RecordingScreen()),
        );
      }
    });
  }
}