import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

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
    _initCameraAndStartSOS();
  }

  Future<void> _initCameraAndStartSOS() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(frontCamera, ResolutionPreset.low);
    await _controller!.initialize();
    if (mounted) setState(() {});

    // ✅ Start SOS flow immediately
    _startSOS();
  }

  Future<void> _startSOS() async {
    try {
      // ✅ Get current location (permission already asked in demo_page)
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final location = '${position.latitude}, ${position.longitude}';

      // ✅ Start recording
      if (_controller == null || _isRecording) return;
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);

      // Stop after 10 seconds
      Future.delayed(const Duration(seconds: 10), () async {
        if (!_isRecording || _controller == null) return;

        final file = await _controller!.stopVideoRecording();
        setState(() => _isRecording = false);

        try {
          final supabase = Supabase.instance.client;
          final fileName =
              'sos_videos/${DateTime.now().millisecondsSinceEpoch}.mp4';

          final fileBytes = await File(file.path).readAsBytes();

          // ✅ Upload video to Supabase Storage
          await supabase.storage.from('videos').uploadBinary(fileName, fileBytes);

          final publicUrl =
              supabase.storage.from('videos').getPublicUrl(fileName);

          // ✅ Fetch student name from profile table
          final userId = supabase.auth.currentUser?.id;
          String studentName = 'Unknown';
          if (userId != null) {
            final profile = await supabase
                .from('student_details')
                .select('name')
                .eq('user_id', userId)
                .limit(1);
            if (profile.isNotEmpty) {
              studentName = profile.first['name'] ?? 'Unknown';
            }
          }

          // ✅ Insert metadata into sos_reports table
          await supabase.from('sos_reports').insert({
            'user_id': userId,
            'student_name': studentName,
            'location': location,
            'video_url': publicUrl,
            'created_at': DateTime.now().toIso8601String(),
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('SOS report uploaded successfully')),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location fetch failed: $e')),
        );
      }
    }
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
        title: const Text('SOS Recording'),
        backgroundColor: Colors.red,
      ),
      body: CameraPreview(_controller!),
    );
  }
}