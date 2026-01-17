import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'custom_appbar.dart';
import 'login_page.dart';
import 'demo_page.dart'; // ✅ import your home screen
import 'tutorial_pages.dart';
import 'package:image_picker/image_picker.dart';

class StudentFormPage extends StatefulWidget {
  const StudentFormPage({super.key});

  @override
  State<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends State<StudentFormPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _enrollmentController = TextEditingController();
  final _departmentController = TextEditingController();
  final _semesterController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _collegeController = TextEditingController();

  String? _photoUrl;
  bool _isSubmitting = false;
  bool _isLoading = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _enrollmentController.dispose();
    _departmentController.dispose();
    _semesterController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _collegeController.dispose(); 

    super.dispose();
  }

  Future<void> _loadDetails() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await _supabase
          .from('student_details')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        final data = response.first as Map<String, dynamic>;
        _nameController.text = data['name'] ?? '';
        _enrollmentController.text = data['enrollment_no'] ?? '';
        _departmentController.text = data['department'] ?? '';
        _semesterController.text = data['semester'] ?? '';
        _contactController.text = data['contact_no'] ?? '';
        _addressController.text = data['address'] ?? '';
        _photoUrl = data['profile_photo'];
        _collegeController.text = data['college_name'] ?? ''; // ADD
       


      }
    } catch (e) {
      debugPrint('Failed to load details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
Future<void> _submitDetails() async {
  if (!_formKey.currentState!.validate()) return;

  // ✅ Check if profile photo is uploaded
  if (_photoUrl == null || _photoUrl!.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a profile photo before submitting.')),
      );
    }
    return;
  }

  // ✅ Check if all fields are filled
  final requiredFields = [
    _nameController.text.trim(),
    _enrollmentController.text.trim(),
    _departmentController.text.trim(),
    _semesterController.text.trim(),
    _contactController.text.trim(),
    _addressController.text.trim(),
    _contactController.text.trim(),
    _addressController.text.trim(),
  ];

  final allFilled = requiredFields.every((field) => field.isNotEmpty);

  if (!allFilled) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields before submitting.')),
      );
    }
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not logged in");

    final existing = await _supabase
        .from('student_details')
        .select()
        .eq('user_id', userId)
        .limit(1);

    final newData = {
      'user_id': userId,
      'name': _nameController.text.trim(),
      'enrollment_no': _enrollmentController.text.trim(),
      'department': _departmentController.text.trim(),
      'semester': _semesterController.text.trim(),
      'contact_no': _contactController.text.trim(),
      'address': _addressController.text.trim(),
      'profile_photo': _photoUrl, // ✅ ensure photo is saved
      'seen_tutorial': false,
    };

    if (existing.isNotEmpty) {
      final oldData = existing.first as Map<String, dynamic>;

      bool changed = false;
      for (final key in newData.keys) {
        if (newData[key] != oldData[key]) {
          changed = true;
          break;
        }
      }

      if (changed) {
        await _supabase
            .from('student_details')
            .update(newData)
            .eq('user_id', userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Details updated successfully')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TutorialPages()),
          );
        }
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TutorialPages()),
        );
      }
    } else {
      await _supabase.from('student_details').insert(newData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Details saved successfully')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TutorialPages()),
        );
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

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Future<void> _uploadProfilePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final fileBytes = await pickedFile.readAsBytes();
    final fileName = "student_$userId.jpg";

    try {
      // Upload to Supabase Storage (overwrite if exists)
      await _supabase.storage.from('student_photos').uploadBinary(
        fileName,
        fileBytes,
        fileOptions: const FileOptions(upsert: true),
      );

      // Get public URL
      final publicUrl =
          _supabase.storage.from('student_photos').getPublicUrl(fileName);

      // Add cache-busting query param
      final refreshedUrl =
          "$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}";

      // Update student_details table with photo URL
      await _supabase
          .from('student_details')
          .update({'profile_photo': refreshedUrl})
          .eq('user_id', userId);

      if (mounted) {
        setState(() => _photoUrl = refreshedUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo uploaded successfully')),
        );
      }
    } catch (e) {
      debugPrint("Upload failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text, int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 24,
          fontFamily: 'Inter',
          color: Colors.black,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'Required';
        }
        if (label == 'Contact No') {
          final regex = RegExp(r'^[6-9]\d{9}$');
          if (!regex.hasMatch(v.trim())) {
            return 'Enter a valid 10-digit number';
          }
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 247, 196, 196),
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.black,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: _logout, // ✅ logout functionality
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // ✅ Profile photo display with proper fallback
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: (_photoUrl != null &&
                                _photoUrl!.isNotEmpty)
                            ? NetworkImage(_photoUrl!)
                            : null,
                        child: (_photoUrl == null || _photoUrl!.isEmpty)
                            ? const Icon(Icons.account_circle,
                                size: 80, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _uploadProfilePhoto,
                        icon: const Icon(Icons.upload),
                        label: const Text("Upload Profile Photo"),
                      ),
                      const SizedBox(height: 28),

                      // ✅ Existing form fields
                      _buildTextField(_nameController, 'Name'),
                      const SizedBox(height: 26),
                      _buildTextField(_enrollmentController, 'Enrollment No'),
                      const SizedBox(height: 26),
                      _buildTextField(_collegeController, 'College Name'), // ADD
                      const SizedBox(height: 26),
                      _buildTextField(_departmentController, 'Department'),
                      const SizedBox(height: 20),
                      _buildTextField(_semesterController, 'Semester'),
                      const SizedBox(height: 20),
                      _buildTextField(
                        _contactController,
                        'Contact No',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        _addressController,
                        'Address',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 28),

                      // ✅ Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitDetails,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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