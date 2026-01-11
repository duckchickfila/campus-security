import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:geocoding/geocoding.dart'; // reverse geocoding
import 'package:video_player/video_player.dart'; // video playback
import 'package:url_launcher/url_launcher.dart'; // phone dialer + maps
import 'package:permission_handler/permission_handler.dart'; // runtime permission

class SosReportViewer extends StatefulWidget {
  final String sosId;
  const SosReportViewer({super.key, required this.sosId});

  @override
  State<SosReportViewer> createState() => _SosReportViewerState();
}

class _SosReportViewerState extends State<SosReportViewer> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _studentDetails;
  String? _address;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    debugPrint("🔎 Fetching SOS report for id=${widget.sosId}");

    final data = await _supabase
        .from('sos_reports')
        .select('id, user_id, student_name, location, lat, lng, status, video_url')
        .eq('id', widget.sosId)
        .maybeSingle();

    debugPrint("📄 SOS report data: $data");

    if (data != null) {
      // fetch student details using user_id
      if (data['user_id'] != null) {
        debugPrint("🔎 Looking up student_details for user_id=${data['user_id']}");

        final student = await _supabase
            .from('student_details')
            .select('enrollment_no, contact_no, address, name')
            .eq('user_id', data['user_id'])
            .maybeSingle();

        debugPrint("📄 Student details fetched: $student");
        _studentDetails = student;
      }

      // reverse geocode lat/lng
      final lat = double.tryParse(data['lat']?.toString() ?? '');
      final lng = double.tryParse(data['lng']?.toString() ?? '');
      if (lat != null && lng != null) {
        debugPrint("🌍 Reverse geocoding lat=$lat, lng=$lng");
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _address =
                "${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.country ?? ''}";
            debugPrint("📍 Resolved address: $_address");
          }
        } catch (e) {
          debugPrint("⚠️ Reverse geocoding failed: $e");
          _address = "Lat: $lat, Lng: $lng";
        }
      }

      // setup video controller
      if (data['video_url'] != null && data['video_url'].toString().isNotEmpty) {
        debugPrint("🎥 Initializing video controller for URL=${data['video_url']}");
        _videoController = VideoPlayerController.network(data['video_url'])
          ..initialize().then((_) {
            debugPrint("✅ Video initialized");
            setState(() {});
          });
      }
    }

    setState(() => _report = data);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String number) async {
    debugPrint("📞 Attempting to dial $number");
    var status = await Permission.phone.request();
    if (status.isGranted) {
      final Uri uri = Uri(scheme: 'tel', path: number);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        debugPrint("✅ Dialer launched for $number");
      } else {
        debugPrint("❌ Could not launch dialer for $number");
      }
    } else {
      debugPrint("❌ Phone permission not granted");
    }
  }

  Future<void> _openMapNavigation(double lat, double lng) async {
    final Uri uri = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    debugPrint("🗺️ Opening Google Maps navigation: $uri");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      debugPrint("✅ Maps launched");
    } else {
      debugPrint("❌ Could not launch Maps");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_report == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("👤 Student: ${_report!['student_name']}",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("🎓 Enrollment: ${_studentDetails?['enrollment_no'] ?? 'N/A'}",
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                if (_studentDetails?['contact_no'] != null) {
                  _makePhoneCall(_studentDetails!['contact_no']);
                }
              },
              child: Text("📞 Contact: ${_studentDetails?['contact_no'] ?? 'N/A'}",
                  style: const TextStyle(
                      fontSize: 20,
                      color: Colors.blue,
                      decoration: TextDecoration.underline)),
            ),
            const SizedBox(height: 12),
            Text("📍 Location: ${_address ?? _report!['location']}",
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            Text("📌 Status: ${_report!['status']}",
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 20),

            // Video preview (unchanged)
            if (_videoController != null && _videoController!.value.isInitialized)
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _videoController!.value.isPlaying
                              ? _videoController!.pause()
                              : _videoController!.play();
                        });
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoController!),
                          if (!_videoController!.value.isPlaying)
                            const Icon(Icons.play_circle_fill,
                                size: 100, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text("🎥 No video available",
                      style: TextStyle(fontSize: 20, color: Colors.grey)),
                ),
              ),

            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  if (_report!['lat'] != null && _report!['lng'] != null)
                    ElevatedButton.icon(
                      onPressed: () {
                        _openMapNavigation(
                          double.parse(_report!['lat'].toString()),
                          double.parse(_report!['lng'].toString()),
                        );
                      },
                      icon: const Icon(Icons.map),
                      label: const Text("Open Map Navigation"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        textStyle: const TextStyle(fontSize: 20),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}