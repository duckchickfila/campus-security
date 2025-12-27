import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:demo_app/demo_page.dart';
import 'package:demo_app/student_form_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuidePage extends StatefulWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;

  const GuidePage({
    super.key,
    required this.emailController,
    required this.passwordController,
  });

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  static const MethodChannel _channel = MethodChannel('overlay_permission');

  /// Request all normal permissions
  Future<void> _grantPermissions() async {
    await _handlePermission(Permission.location, 'Location is required to tag incidents.');
    await _handlePermission(Permission.camera, 'Camera is required to capture incident images.');
    await _handlePermission(Permission.microphone, 'Microphone is required for audio/video evidence.');

    // GPS check after location permission
    await _checkGpsEnabled();

    // Overlay → open system settings if not granted
    if (Platform.isAndroid && !await Permission.systemAlertWindow.isGranted) {
      _showOverlayDialog();
    }
  }

  /// Handle normal permissions (re‑prompt unless permanently denied)
  Future<void> _handlePermission(Permission permission, String rationale) async {
    final status = await permission.status;

    if (status.isDenied) {
      await permission.request(); // re‑prompt
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog(rationale);
    }
  }

  /// GPS check
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
              await Geolocator.openLocationSettings(); // opens GPS settings
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

  /// Proceed → check all permissions
  /// Proceed → check all permissions and profile completion
Future<void> _proceed() async {
  final locationGranted = await Permission.location.isGranted;
  final cameraGranted = await Permission.camera.isGranted;
  final micGranted = await Permission.microphone.isGranted;
  final overlayGranted = await Permission.systemAlertWindow.isGranted;

  final gpsEnabled = await Geolocator.isLocationServiceEnabled();

  if (locationGranted && cameraGranted && micGranted && overlayGranted && gpsEnabled) {
    if (mounted) {
      final profileComplete = await _isProfileComplete();

      if (profileComplete) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Demopage1()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentFormPage()),
        );
      }
    }
  } else {
    if (!locationGranted) {
      _showReasonDialog('Location is required to tag incidents.', Permission.location);
    } else if (!cameraGranted) {
      _showReasonDialog('Camera is required to capture incident images.', Permission.camera);
    } else if (!micGranted) {
      _showReasonDialog('Microphone is required for audio/video evidence.', Permission.microphone);
    } else if (!gpsEnabled) {
      _showGpsDialog();
    } else if (!overlayGranted) {
      _showOverlayDialog();
    }
  }
}
  Future<bool> _checkAllPermissions() async {
  final locationGranted = await Permission.location.isGranted;
  final cameraGranted = await Permission.camera.isGranted;
  final micGranted = await Permission.microphone.isGranted;
  final overlayGranted = await Permission.systemAlertWindow.isGranted;
  final gpsEnabled = await Geolocator.isLocationServiceEnabled();

  return locationGranted && cameraGranted && micGranted && overlayGranted && gpsEnabled;
}

  Future<bool> _isProfileComplete() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;

  try {
    final response = await Supabase.instance.client
        .from('student_details')
        .select()
        .eq('user_id', userId)
        .limit(1);

    if (response.isEmpty) return false;

    final data = response.first as Map<String, dynamic>;

    // Mandatory fields check
    final requiredFields = [
      data['name'],
      data['enrollment_no'],
      data['department'],
      data['semester'],
      data['contact_no'],
      data['address'],
    ];

    return requiredFields.every((field) => field != null && field.toString().trim().isNotEmpty);
  } catch (e) {
    debugPrint("Profile check failed: $e");
    return false;
  }
}
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
                _proceed(); // re‑check
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

  /// Overlay-specific dialog
  void _showOverlayDialog() {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Overlay Permission Required'),
      content: const Text(
        'Please enable "Display over other apps" in your phone\'s system settings. '
        'After granting permission, return here and press Proceed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 247, 196, 196),
        title: const Text(
          'Permissions Guide',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPermissionCard(Icons.location_on, 'Location',
                'Needed to tag incident reports with accurate location.'),
            const SizedBox(height: 12),
            _buildPermissionCard(Icons.camera_alt, 'Camera',
                'Required to capture incident photos.'),
            const SizedBox(height: 12),
            _buildPermissionCard(Icons.mic, 'Microphone',
                'Needed for audio/video evidence.'),
            const SizedBox(height: 12),
            _buildPermissionCard(Icons.layers, 'Display over other apps',
                'Required for SOS alerts overlay.'),
            const Spacer(),

            // Grant Permissions button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _grantPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Grant Permissions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

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
                        fontSize: 16,
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

            // Proceed button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Proceed',
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
    );
  }

  /// ✅ Complete buildPermissionCard method
    /// Build a card showing each permission
  Widget _buildPermissionCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(12),
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
}