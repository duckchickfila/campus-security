import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recording_screen.dart';

class SOSHandler {
  static const MethodChannel _channel = MethodChannel('sos_channel');

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "triggerSOS") {
        debugPrint("🚨 SOS Triggered from native Activity");

        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(builder: (_) => const RecordingScreen()),
          );
        } else {
          debugPrint("❌ NavigatorState is null, cannot push RecordingScreen");
        }
      }
    });
  }
}