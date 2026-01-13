import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:geocoding/geocoding.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

// ✅ ADDED
import 'package:demo_app/guard_side/map_navigation_page.dart';

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

    Map<String, dynamic>? report;
    try {
      report = await _supabase
          .from('sos_reports')
          .select(
              'id, user_id, student_name, location, lat, lng, status, video_url')
          .eq('id', widget.sosId)
          .maybeSingle();
      debugPrint("📄 sos_reports row: $report");
    } catch (e) {
      debugPrint("❌ Error fetching sos_reports: $e");
    }

    if (report != null) {
      final userId = report['user_id']?.toString().trim();
      debugPrint("🧾 sos_reports.user_id: $userId");

      if (userId != null && userId.isNotEmpty) {
        try {
          final student = await _supabase
              .from('student_details')
              .select(
                  'user_id, name, enrollment_no, contact_no, address, department, semester')
              .eq('user_id', userId)
              .maybeSingle();

          debugPrint("👤 student_details row for user_id=$userId: $student");
          _studentDetails = student;
        } catch (e) {
          debugPrint(
              "❌ Error fetching student_details for user_id=$userId: $e");
        }
      } else {
        debugPrint(
            "⚠️ sos_reports.user_id is null/empty; cannot fetch student_details");
      }

      final lat = double.tryParse(report['lat']?.toString() ?? '');
      final lng = double.tryParse(report['lng']?.toString() ?? '');
      if (lat != null && lng != null) {
        debugPrint("🌍 Reverse geocoding lat=$lat, lng=$lng");
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _address =
                "${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.country ?? ''}";
            debugPrint("📍 Resolved address: $_address");
          } else {
            debugPrint("⚠️ No placemarks returned for lat/lng");
            _address = "Lat: $lat, Lng: $lng";
          }
        } catch (e) {
          debugPrint("⚠️ Reverse geocoding failed: $e");
          _address = "Lat: $lat, Lng: $lng";
        }
      }

      final videoUrl = report['video_url']?.toString() ?? '';
      if (videoUrl.isNotEmpty) {
        debugPrint("🎥 Initializing video controller for URL=$videoUrl");
        _videoController = VideoPlayerController.network(videoUrl)
          ..initialize().then((_) {
            debugPrint("✅ Video initialized");
            setState(() {});
          }).catchError((e) {
            debugPrint("❌ Video initialization error: $e");
          });
      }
    }

    setState(() => _report = report);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String number) async {
    debugPrint("📞 Attempting to dial $number");

    var status = await Permission.phone.status;
    if (!status.isGranted) {
      status = await Permission.phone.request();
    }

    if (status.isGranted) {
      final Uri uri = Uri(scheme: 'tel', path: number);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint("✅ Direct call placed to $number");
      } catch (e) {
        debugPrint("❌ Could not place call: $e");
      }
    } else if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Phone permission is required to place calls")),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  // ✅ CHANGED: now opens in-app navigation screen
  void _openMapNavigation(double lat, double lng, String guardId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapNavigationPage(
          studentLat: lat,
          studentLng: lng,
          guardUserId: guardId, // ✅ pass guardId here
        ),
      ),
    );
  }

  void _openResolvePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(
            child: Text(
              "Resolve & Report Page (to be implemented)",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required String label,
    required String? value,
    bool clickable = false,
    VoidCallback? onTap,
  }) {
    final display = (value == null || value.isEmpty) ? 'N/A' : value;

    final labelStyle = const TextStyle(
        fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87);
    final valueStyle = TextStyle(
      fontSize: 20,
      color: clickable && value != null && value.isNotEmpty
          ? Colors.blue
          : Colors.black87,
      decoration: clickable && value != null && value.isNotEmpty
          ? TextDecoration.underline
          : TextDecoration.none,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ", style: labelStyle),
        Expanded(child: Text(display, style: valueStyle)),
      ],
    );

    if (clickable && onTap != null && value != null && value.isNotEmpty) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    if (_report == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final studentName = _studentDetails?['name']?.toString();
    final studentEnrollment =
        _studentDetails?['enrollment_no']?.toString();
    final studentContact =
        _studentDetails?['contact_no']?.toString();

    debugPrint(
        "🔧 Render values -> name=$studentName, enrollment=$studentEnrollment, contact=$studentContact");

    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: Container(
        color: Colors.grey[100],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                  label: "Student",
                  value: studentName ??
                      _report!['student_name']?.toString()),
              const SizedBox(height: 12),
              _detailRow(
                  label: "Enrollment No", value: studentEnrollment),
              const SizedBox(height: 12),
              _detailRow(
                label: "Contact No",
                value: studentContact,
                clickable: true,
                onTap: () => _makePhoneCall(studentContact!),
              ),
              const SizedBox(height: 12),
              _detailRow(
                  label: "Location",
                  value: _address ??
                      _report!['location']?.toString()),
              const SizedBox(height: 12),
              _detailRow(
                  label: "Status",
                  value: _report!['status']?.toString()),
              const SizedBox(height: 20),

              if (_videoController != null &&
                  _videoController!.value.isInitialized)
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio:
                          _videoController!.value.aspectRatio,
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
                    child: Text("No video available",
                        style:
                            TextStyle(fontSize: 18, color: Colors.grey)),
                  ),
                ),

              const SizedBox(height: 30),
              Center(
                child: Column(
                  children: [
                    if (_report!['lat'] != null &&
                        _report!['lng'] != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          _openMapNavigation(
                            double.parse(
                                _report!['lat'].toString()),
                            double.parse(
                                _report!['lng'].toString()),
                            _report!['guard_id'].toString(),
                          );
                        },
                        icon: const Icon(Icons.map,
                            color: Colors.white),
                        label: const Text("Open Map Navigation",
                            style: TextStyle(
                                fontSize: 18, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _openResolvePage,
                      icon: const Icon(Icons.check_circle,
                          color: Colors.white),
                      label: const Text("Resolve & Report",
                          style: TextStyle(
                              fontSize: 18, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
