import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:geocoding/geocoding.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:demo_app/guard_side/map_navigation_page.dart';
import 'package:demo_app/student_side/chat_page.dart';
import 'resolve_report_page.dart';

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
  bool _videoInitError = false; // <-- add this

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // Add this helper inside _SosReportViewerState
  Future<void> _openExternalPlayer(String videoUrl) async {
    final uri = Uri.parse(videoUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint("❌ Could not launch external player for $videoUrl");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open external player")),
        );
      }
    } catch (e) {
      debugPrint("💥 Exception launching external player: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error opening external player")),
      );
    }
  }

  @override
  void dispose() {
    debugPrint("🛑 Disposing video controller");
    _videoController?.removeListener(_onVideoChanged);
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  void _onVideoChanged() {
    if (!mounted || _videoController == null) return;

    final v = _videoController!.value;
    debugPrint("🎥 Video state changed: "
        "initialized=${v.isInitialized}, "
        "playing=${v.isPlaying}, "
        "pos=${v.position}, "
        "dur=${v.duration}, "
        "buffered=${v.buffered}, "
        "error=${v.hasError ? v.errorDescription : 'none'}");

    setState(() {});
  }

  Future<void> _setupVideoController(String url) async {
    debugPrint("🎬 Setting up VideoPlayerController for URL=$url");

    // Dispose any previous controller
    if (_videoController != null) {
      debugPrint("🧹 Disposing old controller before creating new one");
      _videoController?.removeListener(_onVideoChanged);
      await _videoController?.pause();
      await _videoController?.dispose();
    }

    _videoInitError = false;

    try {
      debugPrint("📡 Creating VideoPlayerController.networkUrl");
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController!.addListener(_onVideoChanged);

      debugPrint("⏳ Initializing video controller...");
      await _videoController!.initialize();

      debugPrint("✅ Initialized: duration=${_videoController!.value.duration}, "
          "aspectRatio=${_videoController!.value.aspectRatio}, "
          "size=${_videoController!.value.size}, "
          "isPlaying=${_videoController!.value.isPlaying}, "
          "hasError=${_videoController!.value.hasError}");

      if (_videoController!.value.hasError) {
        debugPrint("❌ Video error: ${_videoController!.value.errorDescription}");
      } else {
        debugPrint("🔁 Setting looping=false, volume=1.0, autoplaying...");
        await _videoController!.setLooping(false);
        await _videoController!.setVolume(1.0);
        _videoController!.play();
      }

      if (mounted) {
        debugPrint("🔄 Triggering setState after init");
        setState(() {});
      }
    } catch (e) {
      debugPrint("💥 Exception initializing video: $e");
      _videoInitError = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadReport() async {
    debugPrint("🔎 Fetching SOS report for id=${widget.sosId}");

    Map<String, dynamic>? report;
    try {
      report = await _supabase
          .from('sos_reports')
          .select(
              'id, user_id, student_name, enrollment_number, contact_number, location, lat, lng, status, video_url, assigned_guard_id')
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
          debugPrint("❌ Error fetching student_details for user_id=$userId: $e");
        }
      }

      final lat = double.tryParse(report['lat']?.toString() ?? '');
      final lng = double.tryParse(report['lng']?.toString() ?? '');
      if (lat != null && lng != null) {
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _address =
                "${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.country ?? ''}";
          } else {
            _address = "Lat: $lat, Lng: $lng";
          }
        } catch (e) {
          debugPrint("⚠️ Reverse geocoding failed: $e");
          _address = "Lat: $lat, Lng: $lng";
        }
      }

      final videoUrl = report['video_url']?.toString() ?? '';
      debugPrint("🔗 Video URL: $videoUrl");

      if (videoUrl.isNotEmpty) {
        await _setupVideoController(videoUrl);
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
            reportData: _report!, // pass the full SOS report row
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

    return (clickable && onTap != null && value != null && value.isNotEmpty)
        ? GestureDetector(onTap: onTap, child: content)
        : content;
  }

  Widget _buildVideoPlayer() {
    debugPrint("🖼 Building video player widget...");

    final videoUrl = _report?['video_url']?.toString() ?? '';

    if (_videoInitError) {
      debugPrint("⚠️ Video init error flag set");
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Video failed to load"),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text("Open in external player"),
            onPressed: () => _openExternalPlayer(videoUrl),
          ),
        ],
      );
    }

    if (_videoController == null) {
      debugPrint("🚫 No video controller available");
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("No video available"),
          if (videoUrl.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text("Open in external player"),
              onPressed: () => _openExternalPlayer(videoUrl),
            ),
        ],
      );
    }

    if (_videoController!.value.hasError) {
      debugPrint("❌ Controller has error: ${_videoController!.value.errorDescription}");
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Video error: ${_videoController!.value.errorDescription}"),
          const SizedBox(height: 8),
          if (videoUrl.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text("Open in external player"),
              onPressed: () => _openExternalPlayer(videoUrl),
            ),
        ],
      );
    }

    if (!_videoController!.value.isInitialized) {
      debugPrint("⏳ Controller not initialized yet");
      return const Center(child: CircularProgressIndicator());
    }

    debugPrint("🎬 Rendering video: aspectRatio=${_videoController!.value.aspectRatio}");
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.position >= _videoController!.value.duration) {
            debugPrint("🔄 Restarting video from beginning");
            _videoController!.seekTo(Duration.zero);
            _videoController!.play();
          } else if (_videoController!.value.isPlaying) {
            debugPrint("⏸ Pausing video");
            _videoController!.pause();
          } else {
            debugPrint("▶️ Playing video");
            _videoController!.play();
          }
        });
      },
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
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
      body: Container(
        color: Colors.grey[100],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                label: "Student",
                value: studentName ?? _report!['student_name']?.toString(),
              ),
              const SizedBox(height: 12),
              _detailRow(label: "Enrollment No", value: studentEnrollment),
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
                value: _address ?? _report!['location']?.toString(),
              ),
              const SizedBox(height: 12),
              _detailRow(label: "Status", value: _report!['status']?.toString()),
              const SizedBox(height: 24),

              // ✅ Video player with fallback
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.95,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildVideoPlayer(),
                ),
              ),


              const SizedBox(height: 30),
              Center(
                child: Column(
                  children: [
                    if (_report!['lat'] != null && _report!['lng'] != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          _openMapNavigation(
                            double.parse(_report!['lat'].toString()),
                            double.parse(_report!['lng'].toString()),
                            _report!['assigned_guard_id'].toString(),
                          );
                        },
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: const Text(
                          "Open Map Navigation",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // ✅ Chat button
                    ElevatedButton.icon(
                      onPressed: () {
                        final sosId = _report!['id'].toString();
                        final guardId =
                            _report!['assigned_guard_id']?.toString() ?? '';
                        final studentId = _report!['user_id']?.toString() ?? '';

                        if (sosId.isNotEmpty &&
                            guardId.isNotEmpty &&
                            studentId.isNotEmpty) {
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
                            const SnackBar(
                                content: Text("Chat cannot be opened — missing IDs")),
                          );
                        }
                      },
                      icon: const Icon(Icons.chat, color: Colors.white),
                      label: const Text(
                        "Open Chat",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ✅ Resolve & Report button
                    ElevatedButton.icon(
                      onPressed: () => _openResolvePage(),
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text(
                        "Resolve & Report",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
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
