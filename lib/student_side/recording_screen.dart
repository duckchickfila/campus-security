import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math'; // for Haversine formula
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http; // ✅ for Cloudinary upload
import 'dart:convert';
import 'demo_page.dart';
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
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: true,
      );

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

  /// ✅ Cloudinary upload helper
  Future<String?> _uploadVideoToCloudinary(File videoFile) async {
    const cloudName = "dthytnb9t"; // your Cloudinary cloud name
    const uploadPreset = "sos_upload"; // your unsigned preset

    final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/video/upload");

    final request = http.MultipartRequest("POST", url)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    final response = await request.send();
    final resBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = json.decode(resBody);
      return data['secure_url']; // ✅ Cloudinary video URL
    } else {
      debugPrint("❌ Cloudinary upload failed: $resBody");
      return null;
    }
  }

    Future<void> _startSOS() async {
  try {
    // 1️⃣ Get student location
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final lat = position.latitude.toDouble();
    final lng = position.longitude.toDouble();
    final location = '$lat, $lng';

    // 2️⃣ Fetch admin location and campus_distance
    final supabase = Supabase.instance.client;
    final adminRow = await supabase
        .from('admin_locations')
        .select('latitude, longitude, campus_distance')
        .limit(1)
        .maybeSingle();

    if (adminRow == null ||
        adminRow['latitude'] == null ||
        adminRow['longitude'] == null ||
        adminRow['campus_distance'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Campus radius or admin location not set. Cannot proceed.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Demopage1()),
      );
      return;
    }

    // ✅ Type-safe parsing
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    final adminLat = parseDouble(adminRow['latitude']);
    final adminLng = parseDouble(adminRow['longitude']);
    final campusRadiusKm = parseDouble(adminRow['campus_distance']);

    // 3️⃣ Calculate distance (meters)
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

    final distanceMeters = haversine(lat, lng, adminLat, adminLng);

    // 4️⃣ Check if student is within campus radius
    if (distanceMeters > campusRadiusKm * 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location out of campus radius!')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Demopage1()),
      );
      return;
    }

    // 5️⃣ ✅ Student is within radius → continue existing SOS workflow
    if (_controller == null || _isRecording) return;
    await _controller!.startVideoRecording();
    setState(() => _isRecording = true);

    Future.delayed(const Duration(seconds: 5), () async {
      if (!_isRecording || _controller == null) return;

      try {
        final file = await _controller!.stopVideoRecording();
        setState(() => _isRecording = false);

        // --- rest of your existing SOS workflow ---
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

        // Cloudinary upload
        final videoUrl = await _uploadVideoToCloudinary(File(file.path));
        if (videoUrl == null) throw Exception("Cloudinary upload failed");

        // Insert SOS report
        final inserted = await supabase.from('sos_reports').insert({
          'user_id': userId,
          'student_name': studentName,
          'enrollment_number': enrollmentNumber,
          'contact_number': contactNumber,
          'location': location,
          'lat': lat,
          'lng': lng,
          'video_url': videoUrl,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        }).select().single();

        final sosId = inserted['id'].toString();

        // Assign nearest guard
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