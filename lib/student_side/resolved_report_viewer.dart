import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'custom_appbar.dart';

class ResolvedReportViewer extends StatefulWidget {
  final Map<String, dynamic> reportData;

  const ResolvedReportViewer({super.key, required this.reportData});

  @override
  State<ResolvedReportViewer> createState() => _ResolvedReportViewerState();
}

class _ResolvedReportViewerState extends State<ResolvedReportViewer> {
  @override
  Widget build(BuildContext context) {
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

    final status = widget.reportData['status'] ?? 'pending';
    final attachments = (widget.reportData['attachments'] as List<dynamic>?) ?? [];

    return Scaffold(
      appBar: const CustomAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                  Text("Status: $status",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),

              // Banner
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

              // Read-only fields
              _buildReadOnlyField('Type', widget.reportData['type'], labelStyle, valueStyle),
              const SizedBox(height: 20),
              _buildReadOnlyField('Location', widget.reportData['location'], labelStyle, valueStyle),
              const SizedBox(height: 20),
              _buildReadOnlyField(
                'Date',
                (widget.reportData['date'] ??
                        widget.reportData['date_submitted'] ??
                        widget.reportData['created_at'])
                    ?.toString(),
                labelStyle,
                valueStyle,
              ),
              const SizedBox(height: 20),
              _buildReadOnlyField('Details of Incident', widget.reportData['details'], labelStyle, valueStyle),
              const SizedBox(height: 20),

              const Text('Attachments:', style: labelStyle),
              const SizedBox(height: 8),
              _buildAttachmentPreviews(attachments),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),

              const Text('Remarks:', style: labelStyle),
              const SizedBox(height: 8),
              Text(widget.reportData['remarks'] ?? 'No remarks', style: valueStyle),
              const SizedBox(height: 20),

              const Text('Evidence:', style: labelStyle),
              const SizedBox(height: 8),
              _buildAttachmentPreviews(attachments),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String? value, TextStyle labelStyle, TextStyle valueStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 8),
        Text(value ?? '—', style: valueStyle),
      ],
    );
  }

  Widget _buildAttachmentPreviews(List<dynamic> attachments) {
    if (attachments.isEmpty) {
      return const Text('No attachments', style: TextStyle(fontSize: 16));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((att) {
        final url = att.toString();

        // Decide preview based on file type
        Widget preview;
        if (url.endsWith('.jpg') || url.endsWith('.png')) {
          preview = Image.network(url, fit: BoxFit.cover);
        } else if (url.endsWith('.mp4')) {
          preview = const Icon(Icons.videocam, size: 40, color: Colors.blue);
        } else {
          preview = const Icon(Icons.insert_drive_file, size: 40, color: Colors.grey);
        }

        return InkWell(
          onTap: () {
            if (url.endsWith('.jpg') || url.endsWith('.png')) {
              // Show image in dialog
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(url),
                  ),
                ),
              );
            } else if (url.endsWith('.mp4')) {
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
    );
  }
}

// Full-screen video player screen
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