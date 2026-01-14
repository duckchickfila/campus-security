// lib/guard_side/resolve_report_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'custom_appbar.dart';

class ResolveReportPage extends StatefulWidget {
  final Map<String, dynamic> reportData;

  const ResolveReportPage({super.key, required this.reportData});

  @override
  State<ResolveReportPage> createState() => _ResolveReportPageState();
}

class _ResolveReportPageState extends State<ResolveReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  String? selectedStatus;
  List<File> evidenceFiles = [];

  final _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final List<String> statuses = [
    'resolved',
    'false_alarm',
    'escalated',
  ];

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.reportData['status'] ?? 'pending';
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
    final bucket = _supabase.storage.from('evidence');
    final urls = <String>[];

    for (final file in evidenceFiles) {
      final filename = p.basename(file.path);
      final path = 'sos/$reportId/$filename';
      await bucket.upload(path, file, fileOptions: const FileOptions(upsert: true));
      final publicUrl = bucket.getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  Future<void> _uploadSOSReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final reportId = widget.reportData['id'];
    if (reportId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid report ID')),
      );
      return;
    }

    List<String> urls = [];
    try {
      if (evidenceFiles.isNotEmpty) {
        urls = await _uploadEvidence(reportId.toString());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Evidence upload failed: $e')),
      );
    }

    try {
      final guardId = _supabase.auth.currentUser?.id;

      final payload = {
        'status': 'resolved',
        'resolved_at': DateTime.now().toIso8601String(),
        'resolved_by': guardId,
        'resolution_status': selectedStatus,
        'resolution_remarks': _remarksController.text.trim(),
        'guard_attachments': urls,
      };

      await _supabase
          .from('sos_reports')
          .update(payload)
          .eq('id', reportId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS report uploaded successfully')),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload SOS report: $e')),
      );
    }
  }

  Widget _buildReadOnlyField(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 6),
        Text(value ?? 'N/A',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
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
    final report = widget.reportData;

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
                _buildReadOnlyField('Student', report['student_name']),
                const SizedBox(height: 12),
                _buildReadOnlyField('Enrollment No', report['enrollment_number']),
                const SizedBox(height: 12),
                _buildReadOnlyField('Contact No', report['contact_number']),
                const SizedBox(height: 12),
                _buildReadOnlyField('Location', report['location']),
                const SizedBox(height: 12),
                _buildReadOnlyField('Status', report['status']),
                const SizedBox(height: 24),

                const Text('Guard Action',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  items: statuses
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => selectedStatus = val),
                  decoration: InputDecoration(
                    labelText: 'Update Status',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (val) => val == null ? 'Please select a status' : null,
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Remarks',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
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
                      onPressed: _uploadSOSReport,
                      child: const Text('Upload SOS Report'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}