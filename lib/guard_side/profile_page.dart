import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:demo_app/student_side/login_page.dart';
import 'main_page.dart'; // ✅ guard dashboard after profile completion

class GuardProfilePage extends StatefulWidget {
  const GuardProfilePage({super.key});

  @override
  State<GuardProfilePage> createState() => _GuardProfilePageState();
}

class _GuardProfilePageState extends State<GuardProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _guardIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _campusZoneController = TextEditingController();
  final _shiftStartController = TextEditingController();
  final _shiftEndController = TextEditingController();
  final _transportController = TextEditingController();

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
    _guardIdController.dispose();
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _campusZoneController.dispose();
    _shiftStartController.dispose();
    _shiftEndController.dispose();
    _transportController.dispose();
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
          .from('guard_details')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        final data = response.first as Map<String, dynamic>;
        _guardIdController.text = data['guard_id'] ?? '';
        _nameController.text = data['name'] ?? '';
        _contactController.text = data['contact_no'] ?? '';
        _emailController.text = data['email'] ?? '';
        _campusZoneController.text = data['campus_zone'] ?? '';
        _shiftStartController.text = data['shift_start'] ?? '';
        _shiftEndController.text = data['shift_end'] ?? '';
        _transportController.text = data['transport_mode'] ?? '';
        _photoUrl = data['profile_photo'];
      }
    } catch (e) {
      debugPrint('Failed to load guard details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadProfilePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final fileBytes = await pickedFile.readAsBytes();
    final fileName = "guard_$userId.jpg";

    try {
      // Upload to Supabase Storage
      await _supabase.storage.from('guard_photos').uploadBinary(
        fileName,
        fileBytes,
        fileOptions: const FileOptions(upsert: true),
      );

      // Get public URL
      final publicUrl = _supabase.storage.from('guard_photos').getPublicUrl(fileName);

      // Save URL to guard_details
      await _supabase.from('guard_details')
          .update({'profile_photo': publicUrl})
          .eq('user_id', userId);

      if (mounted) {
        setState(() => _photoUrl = publicUrl);
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

  Future<void> _submitDetails() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("User not logged in");

      final existing = await _supabase
          .from('guard_details')
          .select()
          .eq('user_id', userId)
          .limit(1);

      final newData = {
        'user_id': userId,
        'guard_id': _guardIdController.text.trim(),
        'name': _nameController.text.trim(),
        'contact_no': _contactController.text.trim(),
        'email': _emailController.text.trim(),
        'campus_zone': _campusZoneController.text.trim(),
        'shift_start': _shiftStartController.text.trim(),
        'shift_end': _shiftEndController.text.trim(),
        'transport_mode': _transportController.text.trim(),
        'profile_photo': _photoUrl,
      };

      if (existing.isNotEmpty) {
        await _supabase.from('guard_details').update(newData).eq('user_id', userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Details updated successfully')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardMainPage()),
          );
        }
      } else {
        await _supabase.from('guard_details').insert(newData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Details saved successfully')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardMainPage()),
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
        backgroundColor: Colors.redAccent,
        title: const Text(
          'Guard Profile',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
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
                      // ✅ Profile photo preview
                      if (_photoUrl != null)
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: NetworkImage(_photoUrl!),
                        )
                      else
                        const CircleAvatar(
                          radius: 60,
                          child: Icon(Icons.person, size: 60),
                        ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _uploadProfilePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text("Upload Profile Photo"),
                      ),
                      const SizedBox(height: 20),

                      _buildTextField(_guardIdController, 'Guard ID'),
                      const SizedBox(height: 20),
                      _buildTextField(_nameController, 'Full Name'),
                      const SizedBox(height: 20),
                      _buildTextField(_contactController, 'Contact No',
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 20),
                      _buildTextField(_emailController, 'Email ID',
                          keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 20),
                      _buildTextField(_campusZoneController, 'Assigned Campus Zone'),
                      const SizedBox(height: 20),
                      _buildTextField(_shiftStartController, 'Shift Start Time'),
                      const SizedBox(height: 20),
                      _buildTextField(_shiftEndController, 'Shift End Time'),
                      const SizedBox(height: 20),
                      _buildTextField(_transportController, 'Mode of Transport on Campus(Walking/Bike/Vehicle)'),
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
          fontSize: 20,
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
        if (label == 'Email ID') {
          final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
          if (!regex.hasMatch(v.trim())) {
            return 'Enter a valid email';
          }
        }
        return null;
      },
    );
  }
}