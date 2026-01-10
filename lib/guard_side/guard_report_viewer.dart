// lib/guard_side/guard_report_viewer.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:demo_app/guard_side/custom_appbar.dart';

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
    print("Guard UID: ${_supabase.auth.currentUser?.id}");
    print("Current session: ${_supabase.auth.currentSession}");
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
    String label, String? value, TextStyle labelStyle, TextStyle valueStyle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: labelStyle),
      const SizedBox(height: 6),
      Text(
        _formatDate(value), // ✅ format date nicely
        style: valueStyle,
      ),
    ],
  );
}

/// ✅ Helper to format ISO date strings
String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return "${dt.day.toString().padLeft(2, '0')}-"
           "${dt.month.toString().padLeft(2, '0')}-"
           "${dt.year}";
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
      children: attachments.map((u) {
        final lower = u.toLowerCase();
        final isImage = lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png');
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.network(u, fit: BoxFit.cover)
              : const Center(child: Icon(Icons.videocam, size: 40, color: Colors.blue)),
        );
      }).toList(),
    );
  }

  Widget _previewLocalFile(File file) {
    final lower = file.path.toLowerCase();
    final isImage = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png');
    if (isImage) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return const Center(child: Icon(Icons.videocam, size: 40, color: Colors.blue));
  }

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

  const inputTextStyle = TextStyle(
    fontSize: 20,
    fontFamily: 'Inter',
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  final status = widget.reportData['status'] ?? 'pending';

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
                  Text("Status: $status",
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
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

              // Non-editable fields
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
                  valueStyle),
              const SizedBox(height: 20),
              _buildReadOnlyField('Details of Incident', widget.reportData['details'], labelStyle, valueStyle),
              const SizedBox(height: 20),

              const Text('Attachments:', style: labelStyle),
              const SizedBox(height: 8),
              _buildAttachmentPreviews(widget.reportData['attachments']),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),

              // Guard Action section only if not already resolved
              if (status != 'resolved') ...[
                const Text('Guard Action', style: labelStyle),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  items: statuses
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: inputTextStyle),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => selectedStatus = val),
                  decoration: InputDecoration(
                    labelText: 'Update Status',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (val) => val == null ? 'Please select a status' : null,
                ),

                const SizedBox(height: 20),

                // Show Save Status button for any status except pending and resolved
                if (selectedStatus != null &&
                    selectedStatus != 'pending' &&
                    selectedStatus != 'resolved') ...[
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _updateStatus,
                        child: const Text('Save Status'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Show remarks + evidence + submit only when status = resolved (selected, not already resolved)
                if (selectedStatus == 'resolved') ...[
                  TextFormField(
                    controller: _remarksController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Remarks',
                      labelStyle: labelStyle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add Evidence'),
                        onPressed: _pickEvidence,
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.videocam),
                        label: const Text('Add Video'),
                        onPressed: _pickVideo,
                      ),
                      if (evidenceFiles.isNotEmpty)
                        ...evidenceFiles.map((f) => Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _previewLocalFile(f),
                            )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _updateStatus,
                        child: const Text('Submit Remark'),
                      ),
                    ),
                  ),
                ],
              ],

              // If already resolved, show remarks + attachments read-only
              if (status == 'resolved') ...[
                const SizedBox(height: 20),
                const Text('Remarks:', style: labelStyle),
                const SizedBox(height: 8),
                Text(widget.reportData['remarks'] ?? 'No remarks', style: valueStyle),
                const SizedBox(height: 20),

                const Text('Evidence:', style: labelStyle),
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