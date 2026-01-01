import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_page.dart'; // ✅ guard profile page

class GuardCustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final List<Widget>? extraActions; // optional additional actions (e.g., chat)
  final Widget? leading;            // optional leading widget (e.g., back button)

  const GuardCustomAppBar({
    super.key,
    this.extraActions,
    this.leading,
  });

  @override
  State<GuardCustomAppBar> createState() => _GuardCustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GuardCustomAppBarState extends State<GuardCustomAppBar> {
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
          .from('guard_details')
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
      debugPrint('Failed to fetch guard name: $e');
      setState(() {
        _username = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.redAccent, // ✅ guard theme color
      leading: widget.leading,
      title: _isLoading
          ? const SizedBox.shrink()
          : (_username == null || _username!.isEmpty)
              ? const SizedBox.shrink()
              : Text(
                  _username!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
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
                  builder: (context) => const GuardProfilePage(),
                ),
              ).then((_) {
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