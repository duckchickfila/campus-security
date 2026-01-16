import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:demo_app/guard_side/map_navigation_page.dart';
import 'package:demo_app/student_side/chat_page.dart';
import 'resolve_report_page.dart';
import 'package:video_player/video_player.dart';

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
    _loadReport(); // ✅ load report will now also init video controller
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    debugPrint("🔎 Fetching SOS report for id=${widget.sosId}");
    Map<String, dynamic>? report;

    try {
      report = await _supabase
          .from('sos_reports')
          .select(
            'id, user_id, student_name, enrollment_number, contact_number, location, lat, lng, status, video_url, assigned_guard_id'
          )
          .eq('id', widget.sosId)
          .maybeSingle();
      debugPrint("📄 sos_reports row: $report");
    } catch (e) {
      debugPrint("❌ Error fetching sos_reports: $e");
    }

    if (report != null) {
      // ✅ If enrollment/contact missing in sos_reports, fetch from student_details
      if ((report['enrollment_number'] == null || report['enrollment_number'].toString().trim().isEmpty) ||
          (report['contact_number'] == null || report['contact_number'].toString().trim().isEmpty)) {
        try {
          final student = await _supabase
              .from('student_details')
              .select('enrollment_no, contact_no')
              .eq('user_id', report['user_id'])
              .maybeSingle();
          if (student != null) {
            report['enrollment_number'] ??= student['enrollment_no'];
            report['contact_number'] ??= student['contact_no'];
          }
        } catch (e) {
          debugPrint("⚠️ Could not fetch student_details: $e");
        }
      }

      // ✅ Reverse geocode location into _address
      final lat = double.tryParse(report['lat']?.toString() ?? '');
      final lng = double.tryParse(report['lng']?.toString() ?? '');
      if (lat != null && lng != null) {
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _address =
                "${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.country ?? ''}"
                .replaceAll(RegExp(r',\\s+,'), ',')
                .trim();
          } else {
            _address = "Lat: $lat, Lng: $lng";
          }
        } catch (e) {
          debugPrint("⚠️ Reverse geocoding failed: $e");
          _address = "Lat: $lat, Lng: $lng";
        }
      }

      // ✅ Video setup
      final videoUrl = report['video_url']?.toString();
      if (videoUrl != null && videoUrl.isNotEmpty) {
        String transformedUrl = videoUrl.replaceFirst(
          '/upload/',
          '/upload/f_mp4/',
        );

        _videoController?.dispose();
        debugPrint("🎬 Initializing VideoPlayerController with $transformedUrl");

        _videoController = VideoPlayerController.networkUrl(Uri.parse(transformedUrl))
          ..initialize().then((_) {
            debugPrint("✅ Video initialized successfully for new SOS");
            _videoController!.setVolume(1.0);
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _videoController!.play();
                debugPrint("▶️ Auto-play triggered after init");
              }
            });
          }).catchError((e) {
            debugPrint("❌ Video initialization failed: $e");
          });
      }
    }

    setState(() => _report = report);
  }

  Future<void> _makePhoneCall(String number) async {
    var status = await Permission.phone.status;
    if (!status.isGranted) {
      status = await Permission.phone.request();
    }

    if (status.isGranted) {
      final Uri uri = Uri(scheme: 'tel', path: number);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint("❌ Could not place call: $e");
      }
    } else if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone permission is required to place calls")),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  void _openMapNavigation(double lat, double lng, String guardId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapNavigationPage(
          studentLat: lat,
          studentLng: lng,
          guardUserId: guardId,
        ),
      ),
    );
  }

  void _openResolvePage() {
    if (_report != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResolveReportPage(
            reportData: _report!,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report data not available")),
      );
    }
  }

  Widget _detailRow({
    required String label,
    required String? value,
    bool clickable = false,
    VoidCallback? onTap,
  }) {
    // ✅ Check for non‑null, non‑empty value
    final hasValue = value != null && value.trim().isNotEmpty;
    final display = hasValue ? value!.trim() : 'N/A';

    final labelStyle = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    );

    final valueStyle = TextStyle(
      fontSize: 20,
      color: clickable && hasValue ? Colors.blue : Colors.black87,
      decoration: clickable && hasValue ? TextDecoration.underline : TextDecoration.none,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ", style: labelStyle),
        Expanded(child: Text(display, style: valueStyle)),
      ],
    );

    // ✅ Only wrap with GestureDetector if clickable and has a valid value
    return (clickable && onTap != null && hasValue)
        ? GestureDetector(onTap: onTap, child: content)
        : content;
  }

  // ✅ Updated: play/pause inline instead of external launch
  Future<void> _openVideoUrl(String url) async {
    if (_videoController != null && _videoController!.value.isInitialized) {
      debugPrint("🎬 Toggling play/pause. Currently playing=${_videoController!.value.isPlaying}");
      setState(() {
        _videoController!.value.isPlaying
            ? _videoController!.pause()
            : _videoController!.play();
      });
    } else {
      debugPrint("⚠️ Controller not ready, opening externally: $url");
      final uri = Uri.parse(url);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint("❌ Failed to open video URL externally: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open video link")),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_report == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final studentName = _studentDetails?['name']?.toString();
    final studentEnrollment = _studentDetails?['enrollment_no']?.toString();
    final studentContact = _studentDetails?['contact_no']?.toString();
    final videoUrl = _report?['video_url']?.toString() ?? '';

    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          debugPrint("🔄 Manual refresh triggered");
          await _loadReport(); // re-fetch report and re-init video
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // required for pull-to-refresh
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ───────── Student Details ─────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow(label: "Student", value: studentName ?? _report!['student_name']?.toString()),
                      const SizedBox(height: 12),
                      _detailRow(
                        label: "Enrollment No",
                        value: _report?['enrollment_number']?.toString() ?? _studentDetails?['enrollment_no']?.toString(),
                      ),
                      _detailRow(
                        label: "Contact No",
                        value: _report?['contact_number']?.toString() ?? _studentDetails?['contact_no']?.toString(),
                        clickable: true,
                        onTap: () {
                          final number = _report?['contact_number']?.toString() ?? _studentDetails?['contact_no']?.toString();
                          if (number != null && number.isNotEmpty) {
                            _makePhoneCall(number);
                          }
                        },
                      ),
                    _detailRow(label: "Location", value: _address ?? _report!['location']?.toString()),
                      const SizedBox(height: 12),
                      _detailRow(label: "Status", value: _report!['status']?.toString()),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ───────── Video Preview / Player ─────────
              Center(
                child: videoUrl.isNotEmpty && _videoController != null
                    ? ValueListenableBuilder(
                        valueListenable: _videoController!,
                        builder: (context, VideoPlayerValue value, child) {
                          if (!value.isInitialized) {
                            return const SizedBox(
                              width: 220,
                              height: 220,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          // ✅ Force Cloudinary to deliver MP4/H.264
                          final transformedUrl = videoUrl.replaceFirst(
                            '/upload/',
                            '/upload/f_mp4/',
                          );

                          return AspectRatio(
                            aspectRatio: value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_videoController!),
                                IconButton(
                                  icon: Icon(
                                    value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    value.isPlaying
                                        ? _videoController!.pause()
                                        : _videoController!.play();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Container(
                        width: MediaQuery.of(context).size.width * 0.95,
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            "No video available",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: 30),

              // ───────── Action Buttons ─────────
              Center(
                child: Column(
                  children: [
                    if (_report!['lat'] != null && _report!['lng'] != null)
                      ElevatedButton.icon(
                        onPressed: () => _openMapNavigation(
                          double.parse(_report!['lat'].toString()),
                          double.parse(_report!['lng'].toString()),
                          _report!['assigned_guard_id'].toString(),
                        ),
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: const Text("Open Map Navigation", style: TextStyle(fontSize: 18, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          elevation: 4,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Chat Button
                    ElevatedButton.icon(
                      onPressed: () {
                        final sosId = _report!['id'].toString();
                        final guardId = _report!['assigned_guard_id']?.toString() ?? '';
                        final studentId = _report!['user_id']?.toString() ?? '';

                        if (sosId.isNotEmpty && guardId.isNotEmpty && studentId.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                sosId: sosId,
                                guardId: guardId,
                                studentId: studentId,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Chat cannot be opened — missing IDs")),
                          );
                        }
                      },
                      icon: const Icon(Icons.chat, color: Colors.white),
                      label: const Text("Open Chat", style: TextStyle(fontSize: 18, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        elevation: 4,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Resolve Button
                    ElevatedButton.icon(
                      onPressed: _openResolvePage,
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text("Resolve & Report", style: TextStyle(fontSize: 18, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        elevation: 4,
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
