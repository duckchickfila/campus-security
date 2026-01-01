import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:demo_app/student_side/demo_page.dart';
import 'package:demo_app/student_side/guide_page.dart';
import 'package:demo_app/guard_side/guard_guide_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isLogin = true; // ✅ toggle between login and signup
  String _selectedRole = 'student'; // ✅ default role

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _authenticate() async {
  if (!_formKey.currentState!.validate()) return;

  // ✅ Ensure role is selected
  if (_selectedRole.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a role')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    if (_isLogin) {
      // ✅ Login
      final response = await _supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        final userId = response.user!.id;

        if (_selectedRole == 'student') {
          // ✅ Check if user exists in student_details
          final studentRow = await _supabase
              .from('student_details')
              .select('user_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (studentRow == null) {
            // ❌ Prevent guard logging in as student
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are not registered as a student')),
            );
            return;
          }

          // ✅ Safe upsert
          try {
            await _supabase.from('student_details').upsert({
              'user_id': userId,
              'email': _emailController.text.trim(),
            });
          } catch (e) {
            debugPrint('Upsert into student_details failed: $e');
          }

          // ✅ Show success only after role validation passes
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login successful')),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => GuidePage(
                emailController: _emailController,
                passwordController: _passwordController,
              ),
            ),
          );
        } else if (_selectedRole == 'security') {
          // ✅ Check if user exists in guard_details
          final guardRow = await _supabase
              .from('guard_details')
              .select('user_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (guardRow == null) {
            // ❌ Prevent student logging in as guard
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are not registered as a guard')),
            );
            return;
          }

          // ✅ Safe upsert
          try {
            await _supabase.from('guard_details').upsert({
              'user_id': userId,
              'email': _emailController.text.trim(),
            });
          } catch (e) {
            debugPrint('Upsert into guard_details failed: $e');
          }

          // ✅ Show success only after role validation passes
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login successful')),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => GuardGuidePage(
                emailController: _emailController,
                passwordController: _passwordController,
              ),
            ),
          );
        }
      }
    } else {
      // ✅ Sign Up
      final response = await _supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Please log in.')),
        );
        setState(() => _isLogin = true); // switch to login mode
      }
    }
  } catch (e) {
    final errorMessage = e.toString();
    if (errorMessage.contains('email_not_confirmed')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm your email before logging in')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth failed: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 247, 196, 196),
        title: Text(
          _isLogin ? 'Login' : 'Sign Up',
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Colors.black,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildTextField(_emailController, 'Email',
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 24),
                _buildTextField(_passwordController, 'Password',
                    obscureText: true),
                const SizedBox(height: 32),

                // ✅ Role Selection
                const Text(
                  'Select Role:',
                  style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRoleButton('student', Icons.school),
                    const SizedBox(width: 20),
                    _buildRoleButton('security', Icons.security),
                  ],
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _authenticate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          )
                        : Text(
                            _isLogin ? 'Login' : 'Sign Up',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Inter',
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                // ✅ Toggle between Login and Sign Up
                TextButton(
                  onPressed: () {
                    setState(() => _isLogin = !_isLogin);
                  },
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign Up"
                        : "Already have an account? Login",
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'Inter',
                      color: Colors.blue,
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
      {TextInputType keyboardType = TextInputType.text,
      bool obscureText = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
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
        if (label == 'Email' &&
            !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
          return 'Enter a valid email';
        }
        if (label == 'Password' && v.trim().length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }

  Widget _buildRoleButton(String role, IconData icon) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedRole = role);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 40, color: isSelected ? Colors.white : Colors.black),
            const SizedBox(height: 8),
            Text(
              role[0].toUpperCase() + role.substring(1),
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}