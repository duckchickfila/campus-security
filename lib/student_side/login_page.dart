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
  String _selectedRole = ''; // ✅ default role

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

 Future<void> _authenticate() async {
  if (!_formKey.currentState!.validate()) return;

  // ---------- Check if role is selected first ----------
  if (_selectedRole.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a role')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    if (_isLogin) {
      // ---------- LOGIN (Password → OTP) ----------
      final loginRes = await _supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (loginRes.user == null) {
        throw const AuthException('invalid login credentials');
      }

      // ---------- CHECK ROLE BEFORE OTP ----------
      final userId = loginRes.user!.id;
      bool roleValid = false;

      if (_selectedRole == 'student') {
        final studentRow = await _supabase
            .from('student_details')
            .select('user_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (studentRow == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This account is not registered as a student.'),
            ),
          );
        } else {
          roleValid = true;
        }
      } else {
        final guardRow = await _supabase
            .from('guard_details')
            .select('user_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (guardRow == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This account is not registered as a guard.'),
            ),
          );
        } else {
          roleValid = true;
        }
      }

      if (!roleValid) return; // Stop if role is invalid

      // 🔐 Send NUMERIC OTP
      await _supabase.auth.signInWithOtp(
        email: _emailController.text.trim(),
        shouldCreateUser: false,
      );

      final verified = await showOtpDialog(
        context,
        _emailController.text.trim(),
      );

      if (!verified) {
        throw const AuthException('invalid otp');
      }

      // ---------- UPSERT AND NAVIGATE ----------
      if (_selectedRole == 'student') {
        await _supabase.from('student_details').upsert(
          {'user_id': userId},
          onConflict: 'user_id',
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
      } else {
        await _supabase.from('guard_details').upsert(
          {'user_id': userId},
          onConflict: 'user_id',
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login successful')),
      );
    } else {
      // ---------- SIGN UP ----------
      final signupRes = await _supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (signupRes.user == null) {
        throw const AuthException('signup failed');
      }

      final userId = signupRes.user!.id;

      // ---------- CHECK ROLE BEFORE OTP ----------
      if (_selectedRole != 'student' && _selectedRole != 'guard') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid role selected')),
        );
        return;
      }

      // 🔐 Send NUMERIC OTP
      await _supabase.auth.signInWithOtp(
        email: _emailController.text.trim(),
        shouldCreateUser: false,
      );

      final verified = await showOtpDialog(
        context,
        _emailController.text.trim(),
      );

      if (!verified) {
        throw const AuthException('invalid otp');
      }

      // ---------- INSERT USER INTO ROLE TABLE ----------
      if (_selectedRole == 'student') {
        await _supabase.from('student_details').insert({
          'user_id': userId,
          'seen_tutorial': false,
        });
      } else {
        await _supabase.from('guard_details').insert({
          'user_id': userId,
          'seen_tutorial': false,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Please log in.'),
        ),
      );

      setState(() => _isLogin = true);
    }
  } on AuthException catch (e) {
    String message = 'Authentication failed. Please try again.';
    final error = e.message.toLowerCase();

    if (error.contains('invalid login')) {
      message = 'Incorrect email or password.';
    } else if (error.contains('invalid otp')) {
      message = 'Incorrect OTP. Please try again.';
    } else if (error.contains('expired')) {
      message = 'OTP expired. Please request a new one.';
    } else if (error.contains('email not confirmed')) {
      message = 'Please verify your email using OTP.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } on PostgrestException catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Server error. Please try again later.'),
      ),
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

Future<bool> showOtpDialog(BuildContext context, String email) async {
  final otpController = TextEditingController();
  bool verified = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text(
        'OTP Verification',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'We have sent a verification code to your email.\n\n'
            'Please ENTER the OTP.\n'
            'Do NOT click the link in the email.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: otpController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Enter 8-digit OTP',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              final res = await Supabase.instance.client.auth.verifyOTP(
                type: OtpType.email,
                email: email,
                token: otpController.text.trim(),
              );

              if (res.user != null) {
                verified = true;
                Navigator.pop(context);
              }
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid OTP')),
              );
            }
          },
          child: const Text('Verify OTP'),
        ),
      ],
    ),
  );

  return verified;
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