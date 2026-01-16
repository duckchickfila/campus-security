import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_page.dart';        // ✅ guard profile page
import 'tutorial_pages.dart';     // ✅ guard tutorial pages
import 'main_page.dart';          // ✅ guard dashboard

class GuardGuidePage extends StatefulWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;

  const GuardGuidePage({
    super.key,
    required this.emailController,
    required this.passwordController,
  });

  @override
  State<GuardGuidePage> createState() => _GuardGuidePageState();
}

class _GuardGuidePageState extends State<GuardGuidePage> {

  /// Request all required permissions
  Future<void> _grantPermissions() async {
    await _handlePermission(Permission.location, 'Location is required to reach SOS sites.');
    await _handlePermission(Permission.notification, 'Notifications are required to receive SOS alerts.');

    // GPS check after location permission
    await _checkGpsEnabled();
  }

  Future<void> _handlePermission(Permission permission, String rationale) async {
    final status = await permission.status;

    if (status.isDenied) {
      await permission.request();
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog(rationale);
    }
  }

  Future<void> _checkGpsEnabled() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showGpsDialog();
    }
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enable GPS'),
        content: const Text(
          'Location permission is granted, but GPS is turned off.\n\n'
          'Please enable GPS in system settings to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Proceed → check all permissions and profile completion
  Future<void> _proceed() async {
    final locationGranted = await Permission.location.isGranted;
    final notificationGranted = await Permission.notification.isGranted;
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (!mounted || userId == null) return;

    // Check profile completion
    final profileComplete = await _isProfileComplete();

    // Fetch tutorial flag
    final profile = await supabase
        .from('guard_details')
        .select('seen_tutorial')
        .eq('user_id', userId)
        .maybeSingle();

    final seenTutorial = profile?['seen_tutorial'] ?? false;

    // ---- Navigation Logic ----
    if (locationGranted && notificationGranted && gpsEnabled) {
      // ✅ Permissions satisfied
      if (profileComplete) {
        if (seenTutorial == true) {
          // Case 4: Permissions ✅, Profile ✅, Tutorial ✅
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardMainPage()),
          );
        } else {
          // Case 3: Permissions ✅, Profile ✅, Tutorial ❌
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardTutorialPages()),
          );
        }
      } else {
        if (seenTutorial == true) {
          // Edge case: profile incomplete but tutorial seen → force profile
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardProfilePage()),
          );
        } else {
          // Case 2: Permissions ✅, Profile ❌, Tutorial ❌
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardProfilePage()),
          );
          // After profile completion, you should navigate to tutorial → main
        }
      }
    } else {
      // ❌ Permissions not satisfied
      if (!locationGranted) {
        _showReasonDialog(
            'Location is required to reach SOS sites.', Permission.location);
      } else if (!notificationGranted) {
        _showReasonDialog(
            'Notifications are required to receive SOS alerts.', Permission.notification);
      } else if (!gpsEnabled) {
        _showGpsDialog();
      }

      // Case 1: Permissions ❌, Profile ❌, Tutorial ❌
      // After granting permissions, flow should continue → profile → tutorial → main
    }
  }

  Future<bool> _isProfileComplete() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await Supabase.instance.client
          .from('guard_details')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (response.isEmpty) return false;

      final data = response.first as Map<String, dynamic>;

      // ✅ Mandatory fields check (aligned with DB schema)
      final requiredFields = [
        data['name'],
        data['contact_no'], // matches your DB column
        data['email'],
      ];

      return requiredFields.every(
          (field) => field != null && field.toString().trim().isNotEmpty);
    } catch (e) {
      debugPrint("Guard profile check failed: $e");
      return false;
    }
  }

  Widget _buildPermissionCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey),
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: Colors.black),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Inter',
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Normal permission dialog
  /// Normal permission dialog
void _showReasonDialog(String reason, Permission permission) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Permission Required'),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            final result = await permission.request();
            if (result.isGranted) {
              _proceed(); // re‑check after granting
            }
          },
          child: const Text('Grant'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Permanently denied → send to App Settings
  void _showSettingsDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text('$message\n\nPlease enable it in App Settings.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings(); // built into permission_handler
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }


  Future<bool> _checkAllPermissions() async {
  // Location permission
  final locationGranted = await Permission.location.isGranted;

  // Notification permission
  final notificationGranted = await Permission.notification.isGranted;

  // GPS enabled check
  final gpsEnabled = await Geolocator.isLocationServiceEnabled();

  // ✅ Return true only if all are satisfied
  return locationGranted && notificationGranted && gpsEnabled;
}

  // ✅ FIX: Add build method
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text("Guard Permissions"),
      backgroundColor: Colors.redAccent,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPermissionCard(Icons.location_on, "Location", "Required to reach SOS sites"),
            _buildPermissionCard(Icons.notifications, "Notifications", "Required to receive SOS alerts"),
            const Spacer(),

            // ✅ Show message if all permissions are granted
            FutureBuilder<bool>(
              future: _checkAllPermissions(),
              builder: (context, snapshot) {
                final allGranted = snapshot.data ?? false;
                if (allGranted) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'All permissions granted. Please click the Proceed button.',
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'Inter',
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            ElevatedButton(
              onPressed: _grantPermissions,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                "Grant Permissions",
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _proceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                "Proceed",
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}