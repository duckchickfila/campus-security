import 'package:flutter/material.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'guard_report_viewer.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:demo_app/services/notification_handler.dart'; // ✅ centralized notifications
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ add this import

class GuardMainPage extends StatefulWidget {
  const GuardMainPage({super.key});

  @override
  State<GuardMainPage> createState() => _GuardMainPageState();
}

class _GuardMainPageState extends State<GuardMainPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isAvailable = true;
  String _guardName = '';

  String _formatDateOnly(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('dd MMM yyyy').format(dt.toLocal());
    } catch (_) {
      return isoString;
    }
  }

  List<Map<String, dynamic>> _pendingReports = [];
  List<Map<String, dynamic>> _handledReports = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _updateGuardLocation();
    _subscribeToSOS();
    _loadPendingSOS();
    _registerFcmToken(); // ✅ NEW: ensure guard’s token is saved
  }

  // ✅ NEW: Capture and persist FCM token for this guard
  Future<void> _registerFcmToken() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint("No guard ID found for FCM registration");
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _supabase
            .from('guard_details')
            .update({'fcm_token': token})
            .eq('user_id', userId);
        debugPrint("✅ FCM token registered for guard $userId: $token");
      } else {
        debugPrint("⚠️ No FCM token retrieved for guard $userId");
      }

      // Keep DB in sync if token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _supabase
            .from('guard_details')
            .update({'fcm_token': newToken})
            .eq('user_id', userId);
        debugPrint("🔄 FCM token refreshed for guard $userId: $newToken");
      });
    } catch (e) {
      debugPrint("❌ Error registering FCM token: $e");
    }
  }

  Future<void> _loadInitial() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('guard_details')
          .select('name, availability, campus_zone')
          .eq('user_id', user.id)
          .maybeSingle();

      _guardName = (profile?['name'] as String?) ?? 'Guard';
      _isAvailable = (profile?['availability'] as bool?) ?? true;
      final zone = (profile?['campus_zone'] as String?)?.trim();

      final normal = await _supabase
          .from('normal_reports')
          .select()
          .eq('guard_id', user.id)
          .order('date_submitted', ascending: false);

      final normalList = List<Map<String, dynamic>>.from(normal);

      debugPrint('Fetched reports for guard $_guardName in zone $zone: $normalList');

      _pendingReports = normalList
          .where((r) {
            final s = (r['status'] ?? '').toString().toLowerCase().trim();
            return s == 'pending' || s == 'assigned' || s == 'taking action';
          })
          .toList();

      _handledReports = normalList
          .where((r) => (r['status']?.toString().toLowerCase().trim() ?? '') == 'resolved')
          .toList();
    } catch (e) {
      debugPrint('Error loading guard main page: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPendingSOS() async {
    final guardId = _supabase.auth.currentUser?.id;
    if (guardId == null) {
      debugPrint("No guard ID found for pending SOS check");
      return;
    }

    try {
      final sosList = await _supabase
          .from('sos_reports')
          .select()
          .eq('assigned_guard_id', guardId)
          .eq('status', 'pending');

      debugPrint("Pending SOS reports fetched: $sosList");

      for (final sos in sosList) {
        NotificationHandler.showNotification(
          "🚨 Missed SOS Alert",
          "Student ${sos['student_name']} still needs help!",
          sos['id'].toString(),
        );
      }
    } catch (e) {
      debugPrint("Error fetching pending SOS: $e");
    }
  }

  Future<void> _updateGuardLocation() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _supabase
          .from('guard_details')
          .update({
            'last_lat': position.latitude,
            'last_lng': position.longitude,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);

      debugPrint("Guard location updated automatically");
    } catch (e) {
      debugPrint("Failed to update guard location: $e");
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isAvailable = value);
    try {
      await _supabase
          .from('guard_details')
          .update({'availability': value})
          .eq('user_id', user.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Availability ${value ? 'enabled' : 'disabled'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
      setState(() => _isAvailable = !value);
    }
  }

  void _openReport(Map<String, dynamic> reportData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuardReportViewer(reportData: reportData),
      ),
    ).then((_) {
      _loadInitial();
    });
  }

  void _subscribeToSOS() {
    final guardId = _supabase.auth.currentUser?.id;
    if (guardId == null) {
      debugPrint("No guard ID found, realtime subscription not started");
      return;
    }

    final channel = _supabase.channel('sos_reports_channel');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'sos_reports',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'assigned_guard_id',
        value: guardId,
      ),
      callback: (PostgresChangePayload payload) {
        debugPrint("📡 Realtime SOS payload received: ${payload.newRecord}");

        final sos = payload.newRecord;
        if (sos != null) {
          final sosId = sos['id']?.toString() ?? '';
          final studentName = sos['student_name'] ?? 'Unknown';

          NotificationHandler.showNotification(
            "🚨 New SOS Alert",
            "Student $studentName needs help!",
            sosId,
          );
        } else {
          debugPrint("⚠️ Realtime event received but sos record was null");
        }
      },
    );

    channel.subscribe();
    debugPrint("✅ Subscribed to sos_reports realtime for guard $guardId");
  }
  
  Widget _buildReportCard(Map<String, dynamic> report, bool isHandled) {
    final type = (report['type'] ?? '').toString();
    final submittedRaw = (report['date_submitted'] ?? report['created_at'] ?? '').toString();
    final submitted = _formatDateOnly(submittedRaw);

    return GestureDetector(
      onTap: () => _openReport(report),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE6E6), // light red background
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isHandled ? Icons.check_circle : Icons.access_time,
              color: isHandled ? Colors.green : Colors.redAccent,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: $type',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Submitted On: $submitted', style: const TextStyle(fontSize: 20)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_guardName,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('Update status',
                style: TextStyle(fontSize: 20, color: Colors.blueGrey)),
          ],
        ),
        const Spacer(),
        Column(
          children: [
            Text(_isAvailable ? 'Available' : 'Unavailable',
                style: TextStyle(
                  fontSize: 14,
                  color: _isAvailable ? Colors.green : Colors.redAccent,
                  fontWeight: FontWeight.w600,
                )),
            Switch(value: _isAvailable, onChanged: _toggleAvailability),
          ],
        ),
      ],
    );
  }

  Widget _buildPendingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pending Reports',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_pendingReports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No pending reports',
              style: TextStyle(fontSize: 20, color: Colors.black54),
            ),
          )
        else
          Column(
            children:
                _pendingReports.map((r) => _buildReportCard(r, false)).toList(),
          ),
      ],
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Reports Handled',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_handledReports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No handled reports yet',
              style: TextStyle(fontSize: 20, color: Colors.black54),
            ),
          )
        else
          Column(
            children:
                _handledReports.map((r) => _buildReportCard(r, true)).toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildPendingSection(),
                    const SizedBox(height: 24),
                    _buildHistorySection(),
                  ],
                ),
              ),
      ),
    );
  }
}