import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'custom_appbar.dart';
import 'login_page.dart';
import 'demo_page.dart'; // ✅ import your home screen
import 'tutorial_pages.dart';

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
      }
    } catch (e) {
      debugPrint('Failed to load details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

Future<void> _submitDetails() async {
  if (!_formKey.currentState!.validate()) return;

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
      'seen_tutorial': false, // ✅ ensure tutorial shows after profile submission
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
          // ✅ Navigate to tutorial after update
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TutorialPages()),
          );
        }
      } else {
        // If nothing changed, still check tutorial
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
        // ✅ Navigate to tutorial after first save
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
                      _buildTextField(_nameController, 'Name'),
                      const SizedBox(height: 26),
                      _buildTextField(_enrollmentController, 'Enrollment No'),
                      const SizedBox(height: 26),
                      _buildTextField(_departmentController, 'Department'),
                      const SizedBox(height: 20),
                      _buildTextField(_semesterController, 'Semester'),
                      const SizedBox(height: 20),
                      _buildTextField(_contactController, 'Contact No',
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 24),
                      _buildTextField(_addressController, 'Address', maxLines: 3),
                      const SizedBox(height: 28),
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
}