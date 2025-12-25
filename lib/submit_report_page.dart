import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'custom_appbar.dart';
import 'demo_page.dart'; // back navigation target

class SubmitReportPage extends StatefulWidget {
  const SubmitReportPage({super.key});

  @override
  State<SubmitReportPage> createState() => _SubmitReportPageState();
}

class _SubmitReportPageState extends State<SubmitReportPage> {
  final _formKey = GlobalKey<FormState>();

  String? selectedType;
  final _locationController = TextEditingController();
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

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _locationController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  /// ✅ Pick up to 4 images and 2 videos
  Future<void> _pickAttachments() async {
    final picker = ImagePicker();

    // Pick multiple images (limit 4)
    final List<XFile> images = await picker.pickMultiImage();
    final limitedImages = images.take(4).toList();

    // Pick up to 2 videos
    final List<XFile> videos = [];
    for (int i = 0; i < 2; i++) {
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) videos.add(video);
    }

    setState(() => attachments = [...limitedImages, ...videos]);
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || selectedType == null || selectedDate == null) return;

    setState(() => _isSubmitting = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // ✅ Fetch student details
      final student = await _supabase
          .from('student_details')
          .select('id, name, enrollment_no')
          .eq('user_id', user.id)
          .single();

      // ✅ Upload attachments
      final uploadedUrls = <String>[];
      for (final file in attachments) {
        // Get current user safely
        final user = _supabase.auth.currentUser;
        if (user == null) {
          throw Exception("User not logged in");
        }

        // Read file bytes
        final bytes = await file.readAsBytes();

        // Build path: videos/normal_reports/{user.id}/{timestamp_filename}
        final path = 'normal_reports/${user.id}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';

        // Upload to Supabase Storage
        await _supabase.storage.from('videos').uploadBinary(path, bytes);

        // Get public URL
        final publicUrl = _supabase.storage.from('videos').getPublicUrl(path);
        uploadedUrls.add(publicUrl);
      }

      // ✅ Insert report into normal_reports
      await _supabase.from('normal_reports').insert({
        'user_id': user.id,
        'student_id': student['id'],
        'student_name': student['name'],
        'enrollment_number': student['enrollment_no'],
        'type': selectedType,
        'location': _locationController.text.trim(),
        'date': selectedDate!.toIso8601String(),
        'details': _detailsController.text.trim(),
        'attachments': uploadedUrls,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted successfully')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Demopage1()),
        );
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
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t, style: inputTextStyle))).toList(),
                  onChanged: (val) => setState(() => selectedType = val),
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (val) => val == null ? 'Please select a type' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _locationController,
                  style: inputTextStyle,
                  decoration: InputDecoration(
                    labelText: 'Location',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 20),
                ListTile(
                  title: Text(
                    selectedDate == null
                        ? 'Select Date'
                        : selectedDate!.toLocal().toString().split(' ')[0],
                    style: inputTextStyle,
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _detailsController,
                  maxLines: 4,
                  style: inputTextStyle,
                  decoration: InputDecoration(
                    labelText: 'Details of Incident',
                    labelStyle: labelStyle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                // ✅ Attachments button + guidance
                ElevatedButton.icon(
                  icon: const Icon(Icons.attach_file, size: 24),
                  label: const Text(
                    'Add Attachments',
                    style: inputTextStyle,
                  ),
                  onPressed: _pickAttachments,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
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
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments.map((file) {
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
                                ? Image.file(
                                    File(file.path),
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.videocam,
                                    size: 40, color: Colors.blue),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() => attachments.remove(file));
                            },
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 28),
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
                            valueColor: AlwaysStoppedAnimation(Colors.white),
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