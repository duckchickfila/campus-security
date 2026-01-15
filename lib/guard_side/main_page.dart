import 'package:flutter/material.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'guard_report_viewer.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:demo_app/services/notification_handler.dart'; // ✅ centralized notifications
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ add this import
import 'sos_report_viewer.dart';

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
  List<Map<String, dynamic>> _pendingSos = [];
  List<Map<String, dynamic>> _handledSos = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _updateGuardLocation();
    _subscribeToSOS();
    _loadSosReports(); // ✅ REQUIRED
    _registerFcmToken();
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

  Future<void> _loadSosReports() async {
    final guardId = _supabase.auth.currentUser?.id;
    if (guardId == null) {
      debugPrint("No guard ID found for SOS reports");
      return;
    }

    try {
      final sosList = await _supabase
          .from('sos_reports')
          .select()
          .eq('assigned_guard_id', guardId)
          .order('created_at', ascending: false);

      final sosListMap = List<Map<String, dynamic>>.from(sosList);

      if (mounted) {
        setState(() {
          // Pending = resolution_status is null
          _pendingSos = sosListMap.where((r) => r['resolution_status'] == null).toList();

          // Handled = resolution_status is "resolved" or "false_alarm"
          _handledSos = sosListMap.where((r) {
            final rs = (r['resolution_status'] ?? '').toString().toLowerCase().trim();
            return rs == 'resolved' || rs == 'false_alarm';
          }).toList();

          debugPrint("Pending SOS count: ${_pendingSos.length}");
          debugPrint("Handled SOS count: ${_handledSos.length}");
        });
      }
    } catch (e) {
      debugPrint("Error loading SOS reports: $e");
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

  void _openSosReport(Map<String, dynamic> sosData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuardReportViewer(
          reportData: sosData,
          source: 'sos',
        ),
      ),
    ).then((_) {
      _loadSosReports(); // refresh after returning
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

  Widget _buildPendingSosCard(Map<String, dynamic> sos) {
  final submittedRaw = (sos['created_at'] ?? '').toString();
  final submitted = _formatDateOnly(submittedRaw);

  return GestureDetector(
    onTap: () => _openSosReport(sos),
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE6E6),
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
          const Icon(Icons.access_time, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🚨 SOS Alert',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Submitted On: $submitted',
                    style: const TextStyle(fontSize: 20)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openSosReport(sos),
            child: const Text('View details'),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHandledSosCard(Map<String, dynamic> sos) {
    final status = (sos['status'] ?? '').toString();
    final resolvedRaw = (sos['resolved_at'] ?? '').toString();
    final resolvedOn = _formatDateOnly(resolvedRaw);

    return GestureDetector(
      onTap: () => _openSosReport(sos),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE6E6),
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
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🚨 SOS Alert',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Status: $status', style: const TextStyle(fontSize: 20)),
                Text('Resolved On: $resolvedOn',
                    style: const TextStyle(fontSize: 20)),
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

  Widget _buildPendingSosSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Pending SOS',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_pendingSos.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'No pending SOS',
            style: TextStyle(fontSize: 20, color: Colors.black54),
          ),
        )
      else
        Column(
          children: _pendingSos.map((s) => _buildPendingSosCard(s)).toList(),
        ),
    ],
  );
}

  Widget _buildSosHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SOS Report History',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_handledSos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No handled SOS yet',
              style: TextStyle(fontSize: 20, color: Colors.black54),
            ),
          )
        else
          Column(
            children: _handledSos.map((s) => _buildHandledSosCard(s)).toList(),
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

                    // Normal reports
                    _buildPendingSection(),
                    const SizedBox(height: 24),
                    _buildHistorySection(),
                    const SizedBox(height: 24),

                    // SOS reports
                    _buildPendingSosSection(),
                    const SizedBox(height: 24),
                    _buildSosHistorySection(),
                  ],
                ),
              ),
      ),
    );
  }
}