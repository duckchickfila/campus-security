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
  String? _photoUrl;
  bool _isLoading = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchGuardInfo();
  }

  Future<void> _fetchGuardInfo() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _username = null;
        _photoUrl = null;
      });
      return;
    }

    try {
      final response = await _supabase
          .from('guard_details')
          .select('name, profile_photo')
          .eq('user_id', userId)
          .limit(1);

      if (response.isNotEmpty) {
        final data = response.first as Map<String, dynamic>;
        _username = data['name'] as String?;
        _photoUrl = data['profile_photo'] as String?;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Failed to fetch guard info: $e');
      setState(() {
        _username = null;
        _photoUrl = null;
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
                _fetchGuardInfo(); // refresh after profile update
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipOval(
              child: _photoUrl == null || _photoUrl!.isEmpty
                  ? Image.asset(
                      'lib/assets/images/circle.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      _photoUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'lib/assets/images/circle.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}