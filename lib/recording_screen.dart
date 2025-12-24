import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
// needed for File

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  CameraController? _controller;
  bool _isRecording = false;

@override
void initState() {
  super.initState();
  _initCamera();
}

Future<void> _initCamera() async {
  final cameras = await availableCameras();
  final frontCamera = cameras.firstWhere(
    (cam) => cam.lensDirection == CameraLensDirection.front,
  );

  _controller = CameraController(frontCamera, ResolutionPreset.low);
  await _controller!.initialize();
  if (mounted) setState(() {});

  // Start recording immediately after preview is ready
  _startRecording();
}

Future<void> _startRecording() async {
  if (_controller == null || _isRecording) return;

  await _controller!.startVideoRecording();
  setState(() => _isRecording = true);

  // Wait 10 seconds, then stop
  Future.delayed(const Duration(seconds: 10), () async {
    if (!_isRecording || _controller == null) return;

    final file = await _controller!.stopVideoRecording();
    setState(() => _isRecording = false);

    try {
      final supabase = Supabase.instance.client;
      final fileName = 'sos_videos/${DateTime.now().millisecondsSinceEpoch}.mp4';

      final fileBytes = await File(file.path).readAsBytes();

      await supabase.storage
          .from('videos')
          .uploadBinary(fileName, fileBytes);

      final publicUrl = supabase.storage.from('videos').getPublicUrl(fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video uploaded! URL: $publicUrl')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  });
}

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording...'),
        backgroundColor: Colors.red,
      ),
      body: CameraPreview(_controller!),
    );
  }
}