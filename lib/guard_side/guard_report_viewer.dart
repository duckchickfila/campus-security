// lib/guard_side/guard_report_viewer.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:video_player/video_player.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

class GuardReportViewer extends StatefulWidget {
  final Map<String, dynamic> reportData;
  final String source; // 'normal' or 'sos'

  const GuardReportViewer({
    super.key,
    required this.reportData,
    this.source = 'normal',
  });

  @override
  State<GuardReportViewer> createState() => _GuardReportViewerState();
}

class _GuardReportViewerState extends State<GuardReportViewer> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  VideoPlayerController? _videoController; // make it nullable
  bool _isVideoInitialized = false;

  String? selectedStatus;
  List<File> evidenceFiles = [];

  final _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final List<String> statuses = [
    'pending',
    'taking action',
    'resolved',
  ];

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.reportData['status'] ?? 'pending';

    // Debug prints
    print("Guard UID: ${_supabase.auth.currentUser?.id}");
    print("Current session: ${_supabase.auth.currentSession}");

    // Initialize video controller if video_url exists
    final videoUrl = widget.reportData['video_url'];
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        ..initialize().then((_) {
          setState(() {
            _isVideoInitialized = true;
          });
        });
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _videoController?.dispose(); // dispose safely if initialized
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        evidenceFiles.addAll(pickedFiles.map((f) => File(f.path)));
      });
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      setState(() {
        evidenceFiles.add(File(video.path));
      });
    }
  }

  Future<List<String>> _uploadEvidence(String reportId) async {
    final bucket = _supabase.storage.from('evidence'); // ensure bucket exists
    final urls = <String>[];

    for (final file in evidenceFiles) {
      final filename = p.basename(file.path);
      final path = 'normal/$reportId/$filename'; // folder by report
      await bucket.upload(path, file, fileOptions: const FileOptions(upsert: true));
      final publicUrl = bucket.getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  Future<void> _updateStatus() async {
    if (!_formKey.currentState!.validate()) {
      print("Form validation failed");
      return;
    }

    final reportId = widget.reportData['id'];
    print("Debug → reportId=$reportId");

    if (reportId == null) {
      print("Report ID is null");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid report ID')),
      );
      return;
    }

    // 1) Upload evidence (isolated try/catch)
    List<String> urls = [];
    try {
      if (evidenceFiles.isNotEmpty) {
        urls = await _uploadEvidence(reportId.toString());
        print("Evidence uploaded → $urls");
      } else {
        print("No evidence to upload");
      }
    } catch (e) {
      print("Storage upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Evidence upload failed: $e')),
      );
      // return; // optional
    }

    // 2) Insert guard action + update report status
    try {
      final payload = {
        'report_id': reportId,
        'remarks': _remarksController.text.trim(),
        'evidence_urls': urls,   // List<String> → Postgres text[]
        'status': selectedStatus,
      };

      print("DB payload → $payload");

      final response = await _supabase
          .from('guard_actions')
          .insert(payload)
          .select();

      print("Insert response: $response");

      // 🔄 Update the report’s status in normal_reports or sos_reports
      await _supabase
          .from(widget.source == 'sos' ? 'sos_reports' : 'normal_reports')
          .update({'status': selectedStatus})
          .eq('id', reportId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remark submitted')),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      print("DB insert/update failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit action: $e')),
      );
    }
  }

  Widget _buildReadOnlyField(
    String label,
    String? value,
    TextStyle labelStyle,
    TextStyle valueStyle, {
    bool isDate = false,
  }) {
    String displayValue = value ?? '';

    if (isDate && value != null && value.isNotEmpty) {
      try {
        // Parse ISO string with timezone
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          // Format as dd-MM-yyyy
          displayValue = DateFormat('dd-MM-yyyy').format(parsed.toLocal());
        }
      } catch (_) {
        // fallback: show raw string
        displayValue = value;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 6),
        Text(displayValue, style: valueStyle),
      ],
    );
  }


  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw;
      // Convert to local timezone and format
      return DateFormat('dd-MM-yyyy').format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }

  Widget _buildAttachmentPreviews(dynamic attachmentsRaw) {
    List<String> attachments;
    if (attachmentsRaw is List) {
      attachments = attachmentsRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (attachmentsRaw is String) {
      attachments = attachmentsRaw
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      attachments = <String>[];
    }

    if (attachments.isEmpty) {
      return const Text('No attachments available');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((url) {
        final lower = url.toLowerCase();

        // Decide preview based on file type
        Widget preview;
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
          preview = Image.network(url, fit: BoxFit.cover);
        } else if (lower.endsWith('.mp4')) {
          preview = const Icon(Icons.videocam, size: 40, color: Colors.blue);
        } else {
          preview = const Icon(Icons.insert_drive_file, size: 40, color: Colors.grey);
        }

        return InkWell(
          onTap: () {
            if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
              // Show image in dialog
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(url),
                  ),
                ),
              );
            } else if (lower.endsWith('.mp4')) {
              // Navigate to video player page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(videoUrl: url),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening $url')),
              );
            }
          },
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey),
            ),
            clipBehavior: Clip.antiAlias,
            child: preview,
          ),
        );
      }).toList(),
    );
  }

  Widget _previewLocalFile(File file) {
    final lower = file.path.toLowerCase();
    final isImage = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png');

    return InkWell(
      onTap: () {
        if (isImage) {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                child: Image.file(file),
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoUrl: file.path),
            ),
          );
        }
      },
      child: isImage
          ? Image.file(file, fit: BoxFit.cover)
          : const Center(child: Icon(Icons.videocam, size: 40, color: Colors.blue)),
    );
  }

  // Inside your GuardReportViewerState class
  Widget _buildVideoPlayer() {
    final videoUrl = widget.reportData['video_url']?.toString() ?? '';

    if (_videoController == null) {
      return const Text("No video available");
    }

    if (_videoController!.value.hasError) {
      return Column(
        children: [
          Text("Video error: ${_videoController!.value.errorDescription}"),
        ],
      );
    }

    if (!_videoController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.position >= _videoController!.value.duration) {
            _videoController!.seekTo(Duration.zero);
            _videoController!.play();
          } else if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
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
    final studentContact = widget.reportData['contact_number']?.toString();

    const labelStyle = TextStyle(
      fontSize: 20,
      fontFamily: 'Inter',
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    const valueStyle = TextStyle(
      fontSize: 18,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );

    const inputTextStyle = TextStyle(
      fontSize: 20,
      fontFamily: 'Inter',
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    final status = widget.reportData['status'] ?? 'pending';
    print("GuardReportViewer reportData: ${widget.reportData}");
    print("Contact number field: ${widget.reportData['contact_number']}");
    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                Row(
                  children: [
                    Icon(
                      status == 'resolved' ? Icons.check_circle : Icons.access_time,
                      color: status == 'resolved' ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Status: $status",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (status == 'resolved')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "This report has been reviewed and cannot be edited.",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // SOS reports: resolved
                if (widget.source == 'sos' && status == 'resolved') ...[
                  _buildReadOnlyField('Student Name',
                      widget.reportData['student_name'] ?? '', labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField('Enrollment No',
                      widget.reportData['enrollment_number'] ?? '', labelStyle, valueStyle),
                  const SizedBox(height: 20),

                  // Contact number: always bind from schema
                  _buildReadOnlyField(
                    'Contact No',
                    (widget.reportData['contact_number'] != null &&
                            widget.reportData['contact_number'].toString().isNotEmpty)
                        ? widget.reportData['contact_number'].toString()
                        : 'N/A',
                    labelStyle,
                    valueStyle,
                  ),
                  const SizedBox(height: 20),

                  // Reverse-geocode lat/lng into readable address
                  FutureBuilder<List<Placemark>>(
                  future: placemarkFromCoordinates(
                    double.tryParse(widget.reportData['lat']?.toString() ?? '0') ?? 0,
                    double.tryParse(widget.reportData['lng']?.toString() ?? '0') ?? 0,
                  ),
                  builder: (context, snapshot) {
                    String locationText = "${widget.reportData['lat']}, ${widget.reportData['lng']}"; // default fallback

                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      final place = snapshot.data!.first;

                      // Build a readable string using available fields
                      final parts = [
                        place.name,
                        place.locality,
                        place.subLocality,
                        place.subAdministrativeArea,
                        place.administrativeArea,
                        place.country,
                      ].where((part) => part != null && part!.isNotEmpty).toList();

                      if (parts.isNotEmpty) {
                        locationText = parts.join(", ");
                      }
                    }

                    return _buildReadOnlyField('Location', locationText, labelStyle, valueStyle);
                  },
                ),
                  const SizedBox(height: 20),

                  _buildReadOnlyField(
                    'Created At',
                    widget.reportData['created_at'] != null
                        ? DateFormat('dd-MM-yyyy')
                            .format(DateTime.parse(widget.reportData['created_at']))
                        : '',
                    labelStyle,
                    valueStyle,
                  ),
                  const SizedBox(height: 20),

                  // Video preview
                  if (widget.reportData['video_url'] != null) ...[
                    const Text('Evidence Video:', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      width: MediaQuery.of(context).size.width * 0.95,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: _buildVideoPlayer(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (widget.reportData['guard_attachments'] != null) ...[
                    const Text('Guard Attachments:', style: labelStyle),
                    const SizedBox(height: 8),
                    _buildAttachmentPreviews(widget.reportData['guard_attachments']),
                    const SizedBox(height: 20),
                  ],

                  const Text('Remarks:', style: labelStyle),
                  const SizedBox(height: 8),
                  Text(widget.reportData['resolution_remarks'] ?? 'No remarks',
                      style: valueStyle),
                ]

                // SOS reports: pending
                else if (widget.source == 'sos') ...[
                  _buildReadOnlyField('Student Name', widget.reportData['student_name'],
                      labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField('Enrollment No',
                      widget.reportData['enrollment_number'], labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField('Contact No', widget.reportData['contact_number'],
                      labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField(
                      'Location', widget.reportData['location'], labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField(
                    'Created At',
                    widget.reportData['created_at'] != null
                        ? _formatDate(widget.reportData['created_at']?.toString())
                        : '',
                    labelStyle,
                    valueStyle,
                  ),
                  const SizedBox(height: 20),

                  if (widget.reportData['video_url'] != null) ...[
                    const Text('Evidence Video:', style: labelStyle),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: _videoController != null &&
                              _videoController!.value.isInitialized
                          ? _videoController!.value.aspectRatio
                          : 16 / 9,
                      child: _videoController != null &&
                              _videoController!.value.isInitialized
                          ? Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                VideoPlayer(_videoController!),
                                VideoProgressIndicator(_videoController!,
                                    allowScrubbing: true),
                                Align(
                                  alignment: Alignment.center,
                                  child: IconButton(
                                    icon: Icon(
                                      _videoController!.value.isPlaying
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _videoController!.value.isPlaying
                                            ? _videoController!.pause()
                                            : _videoController!.play();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                    const SizedBox(height: 20),
                  ],

                  const Text('Guard Attachments:', style: labelStyle),
                  const SizedBox(height: 8),
                  _buildAttachmentPreviews(widget.reportData['guard_attachments']),
                ]

                // Normal reports
                else ...[
                  _buildReadOnlyField(
                      'Type', widget.reportData['type'], labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField(
                      'Location', widget.reportData['location'], labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  _buildReadOnlyField(
                    'Date',
                    _formatDate(
                      (widget.reportData['date'] ??
                          widget.reportData['date_submitted'] ??
                          widget.reportData['created_at'])
                          ?.toString(),
                    ),
                    labelStyle,
                    valueStyle,
                  ),
                  const SizedBox(height: 20),
                  _buildReadOnlyField('Details of Incident',
                      widget.reportData['details'], labelStyle, valueStyle),
                  const SizedBox(height: 20),
                  const Text('Attachments:', style: labelStyle),
                  const SizedBox(height: 8),
                  _buildAttachmentPreviews(widget.reportData['attachments']),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // Handle both network and local file paths
    if (widget.videoUrl.startsWith('http')) {
      _controller = VideoPlayerController.network(widget.videoUrl);
    } else {
      _controller = VideoPlayerController.file(File(widget.videoUrl));
    }
    _controller.initialize().then((_) {
      setState(() {});
      _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Video Evidence")),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}