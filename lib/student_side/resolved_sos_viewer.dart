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

    return Scaffold(
      appBar: AppBar(title: const Text("Resolved SOS Report")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Student: ${r['student_name'] ?? 'N/A'}"),
            Text("Enrollment: ${r['enrollment_number'] ?? 'N/A'}"),
            Text("Contact: ${r['contact_number'] ?? 'N/A'}"),
            Text("Location: ${r['location'] ?? 'N/A'}"),
            Text("Status: ${r['resolution_status'] ?? r['status'] ?? 'N/A'}"),
            Text("Resolved At: ${r['resolved_at'] ?? 'N/A'}"),
            Text("Remarks: ${r['resolution_remarks'] ?? 'N/A'}"),
            const SizedBox(height: 20),

            // ✅ Video evidence
            if (_videoController != null && _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),

            const SizedBox(height: 20),

            // ✅ Guard attachments (images/videos)
            if (r['guard_attachments'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Attachments:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...List<String>.from(r['guard_attachments']).map((url) {
                    final isImage = url.endsWith('.jpg') || url.endsWith('.png');
                    if (isImage) {
                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: Image.network(url, fit: BoxFit.contain),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Image.network(url, height: 150, fit: BoxFit.cover),
                        ),
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text("Video attachment: $url"),
                      );
                    }
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}