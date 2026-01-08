import 'package:flutter/material.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'guard_report_viewer.dart';
import 'package:intl/intl.dart';

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
      return isoString; // fallback if parsing fails
    }
  }

  List<Map<String, dynamic>> _pendingReports = [];
  List<Map<String, dynamic>> _handledReports = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Load guard profile
      final profile = await _supabase
          .from('guard_details')
          .select('name, availability, campus_zone')
          .eq('user_id', user.id)
          .maybeSingle();

      _guardName = (profile?['name'] as String?) ?? 'Guard';
      _isAvailable = (profile?['availability'] as bool?) ?? true;
      final zone = (profile?['campus_zone'] as String?)?.trim();

      // 🔥 Step 1: Just fetch reports assigned to this guard
      final normal = await _supabase
          .from('normal_reports')
          .select()
          .eq('guard_id', user.id) // only reports assigned to this guard
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
          .where((r) =>
              (r['status']?.toString().toLowerCase().trim() ?? '') == 'resolved')
          .toList();
    } catch (e) {
      debugPrint('Error loading guard main page: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      setState(() => _isAvailable = !value); // revert on failure
    }
  }

  void _openReport(Map<String, dynamic> reportData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuardReportViewer(reportData: reportData),
      ),
    ).then((_) {
      _loadInitial(); // refresh after returning
    });
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