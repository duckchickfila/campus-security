import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ResolvedSosViewer extends StatefulWidget {
  final Map<String, dynamic> reportData;

  const ResolvedSosViewer({super.key, required this.reportData});

  @override
  State<ResolvedSosViewer> createState() => _ResolvedSosViewerState();
}

class _ResolvedSosViewerState extends State<ResolvedSosViewer> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    final videoUrl = widget.reportData['video_url']?.toString() ?? '';
    if (videoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        ..initialize().then((_) {
          setState(() {});
          _videoController!.play();
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reportData;

    const labelStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );

    const valueStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Resolved SOS Report")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field("Student", r['student_name'], labelStyle, valueStyle),
            const SizedBox(height: 12),
            _field("Enrollment", r['enrollment_number'], labelStyle, valueStyle),
            const SizedBox(height: 12),
            _field("Contact", r['contact_number'], labelStyle, valueStyle),
            const SizedBox(height: 12),
            _field("Location", r['location'], labelStyle, valueStyle),
            const SizedBox(height: 12),
            _field(
              "Status",
              r['resolution_status'] ?? r['status'],
              labelStyle,
              valueStyle,
            ),
            const SizedBox(height: 12),
            _field("Resolved At", r['resolved_at'], labelStyle, valueStyle),
            const SizedBox(height: 12),
            _field(
                "Remarks", r['resolution_remarks'], labelStyle, valueStyle),
            const SizedBox(height: 20),

            // ✅ Inline video preview (UNCHANGED dimensions)
            if (_videoController != null &&
                _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),

            const SizedBox(height: 20),

            // ✅ Attachments (same logic as ResolvedReportViewer)
            if (r['guard_attachments'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Attachments:", style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        List<String>.from(r['guard_attachments']).map((url) {
                      Widget preview;

                      if (url.toLowerCase().endsWith('.jpg') ||
                          url.toLowerCase().endsWith('.png')) {
                        preview =
                            Image.network(url, fit: BoxFit.cover);
                      } else if (url.toLowerCase().endsWith('.mp4')) {
                        preview = const Icon(Icons.videocam,
                            size: 40, color: Colors.blue);
                      } else {
                        preview = const Icon(Icons.insert_drive_file,
                            size: 40, color: Colors.grey);
                      }

                      return InkWell(
                        onTap: () {
                          if (url.toLowerCase().endsWith('.jpg') ||
                              url.toLowerCase().endsWith('.png')) {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.network(url),
                                ),
                              ),
                            );
                          } else if (url.toLowerCase().endsWith('.mp4')) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    VideoPlayerScreen(videoUrl: url),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: preview,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String? value, TextStyle l, TextStyle v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: l),
        const SizedBox(height: 4),
        Text(value ?? '—', style: v),
      ],
    );
  }
}

// ✅ SAME full-screen video player as ResolvedReportViewer
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
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
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
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
