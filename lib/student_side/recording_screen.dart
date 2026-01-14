import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math'; // ✅ for Haversine formula
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'demo_page.dart'; // for navigation back to Demopage1
import 'sos_confirmation_screen.dart'; // new confirmation screen

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
    _requestPermissionsAndStart();
  }

  Future<void> _requestPermissionsAndStart() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (cameraStatus.isGranted && micStatus.isGranted && locationStatus.isGranted) {
      _initCameraAndStartSOS();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions denied. SOS cannot start.')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initCameraAndStartSOS() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );

      _controller = CameraController(frontCamera, ResolutionPreset.low);
      await _controller!.initialize();

      if (mounted) setState(() {});

      _startSOS();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera init failed: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _startSOS() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final lat = position.latitude;
      final lng = position.longitude;
      final location = '$lat, $lng';

      if (_controller == null || _isRecording) return;
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);

      Future.delayed(const Duration(seconds: 10), () async {
        if (!_isRecording || _controller == null) return;

        try {
          final file = await _controller!.stopVideoRecording();
          setState(() => _isRecording = false);

          final supabase = Supabase.instance.client;
          final fileName =
              'sos_videos/${DateTime.now().millisecondsSinceEpoch}.mp4';

          final fileBytes = await File(file.path).readAsBytes();

          await supabase.storage.from('videos').uploadBinary(fileName, fileBytes);
          final publicUrl =
              supabase.storage.from('videos').getPublicUrl(fileName);

          final userId = supabase.auth.currentUser?.id;
          String studentName = 'Unknown';
          String enrollmentNumber = 'Unknown';
          String contactNumber = 'Unknown';
          String studentId = userId ?? 'Unknown'; 

          if (userId != null) {
            final profile = await supabase
                .from('student_details')
                .select('name, enrollment_no, contact_no')
                .eq('user_id', userId)
                .limit(1);

            if (profile.isNotEmpty) {
              studentName = profile.first['name'] ?? 'Unknown';
              enrollmentNumber = profile.first['enrollment_no'] ?? 'Unknown';
              contactNumber = profile.first['contact_no'] ?? 'Unknown';
            }
          }

          // ✅ Insert SOS report with correct mapping
          final inserted = await supabase.from('sos_reports').insert({
            'user_id': userId,
            'student_name': studentName,
            'enrollment_number': enrollmentNumber,
            'contact_number': contactNumber,
            'location': location,
            'lat': lat,
            'lng': lng,
            'video_url': publicUrl,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          }).select().single();

          final sosId = inserted['id'].toString();

          // ✅ Assign nearest guard automatically
          final guardId = await _assignNearestGuard(sosId, lat, lng);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SosConfirmationScreen(
                  sosId: sosId,
                  guardId: guardId ?? 'Unknown',
                  studentId: studentId ?? 'Unknown',
                ),
              ),
            );
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

  Future<String?> _assignNearestGuard(String sosId, double sosLat, double sosLng) async {
    final supabase = Supabase.instance.client;

    final guards = await supabase
        .from('guard_details')
        .select('user_id, last_lat, last_lng')
        .eq('availability', true) as List;

    if (guards.isEmpty) {
      debugPrint("No available guards found");
      return null;
    }

    double haversine(double lat1, double lon1, double lat2, double lon2) {
      const R = 6371000; // meters
      final dLat = (lat2 - lat1) * (pi / 180);
      final dLon = (lon2 - lon1) * (pi / 180);
      final a = sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLon / 2) * sin(dLon / 2);
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      return R * c;
    }

    guards.sort((a, b) {
      final da = haversine(sosLat, sosLng, a['last_lat'], a['last_lng']);
      final db = haversine(sosLat, sosLng, b['last_lat'], b['last_lng']);
      return da.compareTo(db);
    });

    final nearestGuard = guards.first;

    await supabase
        .from('sos_reports')
        .update({'assigned_guard_id': nearestGuard['user_id']})
        .eq('id', sosId);

    debugPrint("Assigned guard ${nearestGuard['user_id']} to SOS $sosId");

    try {
      final response = await supabase.functions.invoke(
        'clever-endpoint',
        body: {
          'sosId': sosId,
          'guardId': nearestGuard['user_id'],
        },
      );
      debugPrint("✅ SOS notification triggered: ${response.data}");
    } catch (error) {
      debugPrint("❌ Failed to trigger SOS notification: $error");
    }

    return nearestGuard['user_id'];
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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