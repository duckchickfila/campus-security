import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'custom_appbar.dart';
import 'demo_page.dart'; // back navigation target


class SubmitReportPage extends StatefulWidget {
  const SubmitReportPage({super.key, this.reportData, this.isEditable = true});
  final Map<String, dynamic>? reportData;
  final bool isEditable;
  @override
  State<SubmitReportPage> createState() => _SubmitReportPageState();
}

class _SubmitReportPageState extends State<SubmitReportPage> {
  final _formKey = GlobalKey<FormState>();

  String? selectedType;
  String? selectedLocation;
  final _otherLocationController = TextEditingController();
  DateTime? selectedDate;
  final _detailsController = TextEditingController();
  List<XFile> attachments = [];

  bool _isSubmitting = false;

  final types = [
    'Harassment',
    'Theft',
    'Physical Assault',
    'Unsafe Situation',
    'Stalking',
  ];

  final zones = [
    'Academic building',
    'Classroom',
    'Laboratory',
    'Library',
    'Lecture hall',
    'Parking area',
    'Internal road',
    'Entry gate',
    'Exit gate',
    'Cafeteria',
    'Washroom',
    'Open ground',
    'Security office',
    'Other',
  ];

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    if (widget.reportData != null) {
      selectedType = widget.reportData!['type'];
      selectedLocation = widget.reportData!['location'];
      _detailsController.text = widget.reportData!['details'] ?? '';

      if (selectedLocation == 'Other') {
        _otherLocationController.text = widget.reportData!['location'] ?? '';
      }

      if (widget.reportData!['date_submitted'] != null) {
        selectedDate = DateTime.tryParse(widget.reportData!['date_submitted']);
      }
    }
  }

  @override
  void dispose() {
    _otherLocationController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

/// ✅ Pick up to 4 images and 2 videos
Future<void> _pickAttachments() async {
  final picker = ImagePicker();

  final List<XFile> images = await picker.pickMultiImage();
  final limitedImages = images.take(4).toList();

  final List<XFile> videos = [];
  for (int i = 0; i < 2; i++) {
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video != null) videos.add(video);
  }

  setState(() => attachments = [...limitedImages, ...videos]);
}

/// ✅ Submit or update a report
Future<void> _submitReport() async {
  if (!_formKey.currentState!.validate() || selectedType == null || selectedDate == null) return;

  setState(() => _isSubmitting = true);

  try {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final student = await _supabase
        .from('student_details')
        .select('id, name, enrollment_no')
        .eq('user_id', user.id)
        .single();

    // ✅ Upload attachments
    final uploadedUrls = <String>[];
    for (final file in attachments) {
      final bytes = await file.readAsBytes();
      final path = 'normal_reports/${user.id}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      await _supabase.storage.from('videos').uploadBinary(path, bytes);
      final publicUrl = _supabase.storage.from('videos').getPublicUrl(path);
      uploadedUrls.add(publicUrl);
    }

    final locationValue = selectedLocation == 'Other'
        ? _otherLocationController.text.trim()
        : selectedLocation;

    if (widget.reportData != null) {
      // ✅ Update existing report
      final reportId = (widget.reportData!['id'] as num).toInt();

      final existingAttachments = (widget.reportData?['attachments'] as List?)?.cast<String>() ?? [];
      final updatedAttachments = [...existingAttachments, ...uploadedUrls];

      final response = await _supabase
          .from('normal_reports')
          .update({
            'type': selectedType,
            'location': locationValue,
            'details': _detailsController.text.trim(),
            'attachments': updatedAttachments, // ✅ merged old + new attachments
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reportId)
          .select(); // force return updated row

      print("Update response: $response"); // 👀 debug

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report updated successfully')),
        );
        Navigator.pop(context, true); // ✅ return flag to trigger refresh
      }
    } else {
      // ✅ Insert new report
      final guard = await _supabase
          .from('guard_details')
          .select('user_id')
          .eq('campus_zone', selectedLocation ?? '')
          .limit(1)
          .maybeSingle();

      final guardId = guard?['user_id'];

      final response = await _supabase.from('normal_reports').insert({
        'user_id': user.id,
        'student_id': student['id'],
        'student_name': student['name'],
        'enrollment_number': student['enrollment_no'],
        'type': selectedType,
        'location': locationValue,
        'campus_zone': selectedLocation,
        'date': selectedDate!.toIso8601String(),
        'details': _detailsController.text.trim(),
        'attachments': uploadedUrls, // ✅ jsonb array
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'date_submitted': DateTime.now().toIso8601String(),
        'guard_id': guardId,
      });

      print("Insert response: $response"); // 👀 debug

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted successfully')),
        );
        Navigator.pop(context, true); // ✅ return flag to trigger refresh
      }
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 20,
      fontFamily: 'Inter',
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    const inputTextStyle = TextStyle(
      fontSize: 20,
      fontFamily: 'Inter',
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    final status = widget.reportData?['status'] ?? 'pending';

    return Scaffold(
      appBar: CustomAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Demopage1()),
          ),
        ),
        extraActions: [
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.black),
            onPressed: () {
              // Placeholder for chat button
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      status == 'reviewed'
                          ? Icons.check_circle
                          : Icons.access_time,
                      color: status == 'reviewed' ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Status: $status",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (!widget.isEditable)
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

                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: types
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t, style: inputTextStyle),
                          ))
                      .toList(),
                  onChanged: widget.isEditable
                      ? (val) => setState(() => selectedType = val)
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (val) =>
                      val == null ? 'Please select a type' : null,
                ),
                const SizedBox(height: 20),

                // ✅ Location dropdown
                DropdownButtonFormField<String>(
                  value: selectedLocation,
                  items: [
                    'Academic building',
                    'Classroom',
                    'Laboratory',
                    'Library',
                    'Lecture hall',
                    'Parking area',
                    'Internal road',
                    'Entry gate',
                    'Exit gate',
                    'Cafeteria',
                    'Washroom',
                    'Open ground',
                    'Security office',
                    'Other',
                  ].map((zone) => DropdownMenuItem(
                        value: zone,
                        child: Text(zone, style: inputTextStyle),
                      ))
                    .toList(),
                  onChanged: widget.isEditable
                      ? (val) => setState(() {
                            selectedLocation = val;
                            if (val != 'Other') {
                              _otherLocationController.clear();
                            }
                          })
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Location',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (val) => val == null ? 'Please select a location' : null,
                ),
                const SizedBox(height: 20),

                // ✅ Extra textbox if "Other" is selected
                if (selectedLocation == 'Other')
                  TextFormField(
                    controller: _otherLocationController,
                    style: inputTextStyle,
                    enabled: widget.isEditable,
                    decoration: InputDecoration(
                      labelText: 'Specify other location',
                      labelStyle: labelStyle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required when Other is selected' : null,
                  ),
                // ✅ Date picker
                ListTile(
                  title: Text(
                    selectedDate == null
                        ? 'Select Date'
                        : selectedDate!.toLocal().toString().split(' ')[0],
                    style: inputTextStyle,
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: widget.isEditable
                      ? () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 20),

                // ✅ Details field
                TextFormField(
                  controller: _detailsController,
                  maxLines: 4,
                  style: inputTextStyle,
                  enabled: widget.isEditable,
                  decoration: InputDecoration(
                    labelText: 'Details of Incident',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                // ✅ Attachments button
                ElevatedButton.icon(
                  icon: const Icon(Icons.attach_file, size: 24),
                  label: const Text(
                    'Add Attachments',
                    style: inputTextStyle,
                  ),
                  onPressed: widget.isEditable ? _pickAttachments : null,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can attach up to 4 images and 2 videos.\n'
                  'Images should be clear, and videos should be short clips.',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),

                // ✅ Previews
                const SizedBox(height: 16),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Show existing URLs from DB
                    ...(widget.reportData?['attachments'] as List? ?? [])
                        .cast<String>()
                        .map((url) {
                      final isImage = url.toLowerCase().endsWith('.jpg') ||
                          url.toLowerCase().endsWith('.jpeg') ||
                          url.toLowerCase().endsWith('.png');

                      return Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: isImage
                            ? Image.network(url, fit: BoxFit.cover)
                            : const Icon(Icons.videocam, size: 40, color: Colors.blue),
                      );
                    }),

                    // Show newly picked files
                    ...attachments.map((file) {
                      final isImage = file.path.toLowerCase().endsWith('.jpg') ||
                          file.path.toLowerCase().endsWith('.jpeg') ||
                          file.path.toLowerCase().endsWith('.png');

                      return Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: isImage
                                ? Image.file(File(file.path), fit: BoxFit.cover)
                                : const Icon(Icons.videocam, size: 40, color: Colors.blue),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: widget.isEditable
                                ? () {
                                    setState(() => attachments.remove(file));
                                  }
                                : null,
                          ),
                        ],
                      );
                    }),
                  ],
                ),

                const SizedBox(height: 28),

                // ✅ Submit button only if editable
                if (widget.isEditable)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            )
                          : const Text(
                              'Submit',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Inter',
                                color: Colors.white,
                              ),
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