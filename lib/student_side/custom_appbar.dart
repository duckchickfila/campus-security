import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_form_page.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final List<Widget>? extraActions;
  final Widget? leading;

  const CustomAppBar({
    super.key,
    this.extraActions,
    this.leading,
  });

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _CustomAppBarState extends State<CustomAppBar> {
  String? _username;
  String? _collegeName; // ✅ NEW
  String? _photoUrl;
  bool _isLoading = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchUserDetails();
  }

  Future<void> _fetchUserDetails() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _username = null;
        _collegeName = null;
        _photoUrl = null;
      });
      return;
    }

    try {
      final response = await _supabase
          .from('student_details')
          .select('name, college_name, profile_photo') // ✅ UPDATED
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        final data = response.first as Map<String, dynamic>;
        setState(() {
          _username = data['name'] as String?;
          _collegeName = data['college_name'] as String?; // ✅ NEW
          _photoUrl = data['profile_photo'] as String?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _username = null;
          _collegeName = null;
          _photoUrl = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch user details: $e');
      setState(() {
        _username = null;
        _collegeName = null;
        _photoUrl = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color.fromARGB(255, 247, 196, 196),
      leading: widget.leading,
      title: _isLoading || _username == null || _username!.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _username!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_collegeName != null && _collegeName!.isNotEmpty)
                  Text(
                    _collegeName!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.black54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
      actions: [
        ...(widget.extraActions ?? []),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: FloatingActionButton.small(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StudentFormPage(),
                ),
              ).then((_) {
                _fetchUserDetails();
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipOval(
              child: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? Image.network(
                      _photoUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    )
                  : Image.asset(
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