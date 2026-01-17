import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'recording_screen.dart';

PorcupineManager? porcupineManager;

// Replace this with your real AccessKey from picovoice.ai
const String _porcupineAccessKey = "<PiYxeBRmJrzFESW42gcPHxDv0gU9gONKzxoKFmS6zIC2BssZPhQRZw==>";

Future<void> startPorcupineListener(GlobalKey<NavigatorState> navigatorKey) async {
  try {
    porcupineManager = await PorcupineManager.fromKeywordPaths(
      _porcupineAccessKey,
      ['assets/porcupine/sos.ppn'], // your wake word model
      (int keywordIndex) {
        debugPrint('🎤 Wake word detected! Index: $keywordIndex');

        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const RecordingScreen()),
          );
        }
      },
      // optional:
      // modelPath: 'assets/porcupine/porcupine.pv', // your custom model if needed
      // sensitivities: [0.5], // sensitivity values 0.0–1.0
      errorCallback: (error) {
        debugPrint('❌ Porcupine error: $error');
      },
    );

    await porcupineManager?.start();
  } on PlatformException catch (e) {
    debugPrint("❌ Failed to start Porcupine: ${e.message}");
  }
}

Future<void> stopPorcupineListener() async {
  try {
    await porcupineManager?.stop();
    await porcupineManager?.delete();
    porcupineManager = null;
  } catch (e) {
    debugPrint("❌ Failed to stop Porcupine: $e");
  }
}
