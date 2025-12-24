import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_form_page.dart'; // ✅ import your form page

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  const CustomAppBar({super.key});

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _CustomAppBarState extends State<CustomAppBar> {
  String? _username;
  bool _isLoading = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _username = null;
      });
      return;
    }

    try {
      final response = await _supabase
          .from('student_details')
          .select('name')
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        setState(() {
          _username = (response.first as Map<String, dynamic>)['name'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _username = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch username: $e');
      setState(() {
        _username = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color.fromARGB(255, 247, 196, 196),
      title: _isLoading
          ? const SizedBox.shrink() // nothing while loading
          : (_username == null || _username!.isEmpty)
              ? const SizedBox.shrink() // nothing if no profile
              : Text(
                  _username!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.black,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: FloatingActionButton.small(
            onPressed: () {
              // ✅ Navigate to StudentFormPage when profile button is pressed
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StudentFormPage(),
                ),
              ).then((_) {
                // Refresh username when returning from form page
                _fetchUserName();
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipOval(
              child: Image.asset(
                'lib/assets/images/circle.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }
}