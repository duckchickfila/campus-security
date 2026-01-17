import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'dart:io';

class AdminDashboard extends StatefulWidget {
  final String adminId;
  const AdminDashboard({super.key, required this.adminId});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;
  late String _currentAdminId;

  List<Map<String, dynamic>> _availableGuards = [];
  bool _loadingGuards = true;

  late final Stream<List<Map<String, dynamic>>> _falseAlarmStream;

  double _campusRadiusKm = 1.0; // Default campus radius slider

  @override
  void initState() {
    super.initState();
    _currentAdminId = widget.adminId;

    // ============ FALSE ALARMS STREAM ============
    _falseAlarmStream = supabase
        .from('sos_reports')
        .stream(primaryKey: ['id'])
        .map((List<Map<String, dynamic>> event) {
      final filtered = event.where((r) {
        final count = r['false_alarm'] is int
            ? r['false_alarm'] as int
            : int.tryParse(r['false_alarm']?.toString() ?? '0') ?? 0;
        return count >= 3;
      }).toList();

      final Map<String, Map<String, dynamic>> latestByUser = {};
      for (var r in filtered) {
        final uid = r['user_id'] as String?;
        if (uid != null) {
          final existing = latestByUser[uid];
          if (existing == null ||
              DateTime.parse(r['created_at'])
                  .isAfter(DateTime.parse(existing['created_at']))) {
            latestByUser[uid] = r;
          }
        }
      }

      return latestByUser.values.toList();
    });

    _fetchAvailableGuards();
  }

  // ============ FETCH GUARDS ============
  Future<void> _fetchAvailableGuards() async {
    setState(() => _loadingGuards = true);
    try {
      final response = await supabase.from('guard_details').select().order('name');
      final guards = (response as List<dynamic>)
          .map((g) => g as Map<String, dynamic>)
          .where((g) => g['availability'] == true)
          .toList();
      setState(() => _availableGuards = guards);
    } catch (e) {
      print('Error fetching guards: $e');
      setState(() => _availableGuards = []);
    } finally {
      setState(() => _loadingGuards = false);
    }
  }

  // ============ LOCATE ADMIN ============
  Future<void> _locateAdmin() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live location is not supported on Web.')),
      );
      return;
    }
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await supabase.from('admin_locations').upsert({
        'admin_id': _currentAdminId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'admin_id');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Location updated successfully!\nLat: ${position.latitude}, Lng: ${position.longitude}'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      print('Error saving location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get/save location: $e')),
      );
    }
  }

  // ============ SAVE CAMPUS DISTANCE ============
    Future<void> _saveCampusDistance() async {
    try {
      await supabase
          .from('admin_locations')
          .update({'campus_distance': _campusRadiusKm})
          .eq('admin_id', _currentAdminId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Campus radius saved: ${_campusRadiusKm.toStringAsFixed(1)} km'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error saving campus distance: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save campus radius: $e')),
      );
    }
  }


  // ============ BUILD CARDS ============
  Widget _buildCard({
    required String title,
    required String subtitle,
    required Color color,
    required Widget icon,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildGuardCard(Map<String, dynamic> g) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 200, 240, 255),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                g['profile_photo'] != null ? NetworkImage(g['profile_photo']) : null,
            child: g['profile_photo'] == null ? const Icon(Icons.person) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g['name'],
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("Zone: ${g['campus_zone']}",
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ UI ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Admin',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 4,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAvailableGuards,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () async {
                  if (!kIsWeb) HapticFeedback.heavyImpact();
                  await _locateAdmin();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  elevation: 8,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(60),
                ),
                child: const Text(
                  'LOCATE',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Location establishment required for authorizing campus zone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 16),
              // ====== CAMPUS RADIUS SLIDER ======
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set Campus Radius: ${_campusRadiusKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    value: _campusRadiusKm,
                    min: 1.0,
                    max: 7.0,
                    divisions: 12,
                    label: '${_campusRadiusKm.toStringAsFixed(1)} km',
                    onChanged: (value) {
                      setState(() => _campusRadiusKm = value);
                    },
                  ),
                  Center(
                    child: ElevatedButton(
                      onPressed: _saveCampusDistance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Campus Radius',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ===== False Alarm Students =====
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'False Alarm Students',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _falseAlarmStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text(
                      'No students crossed false alarm limit.',
                      style: TextStyle(fontSize: 16),
                    );
                  }

                  final students = snapshot.data!;
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final r = students[index];
                      final falseAlarmCount = r['false_alarm'] is int
                          ? r['false_alarm'] as int
                          : int.tryParse(r['false_alarm']?.toString() ?? '0') ?? 0;

                      return _buildCard(
                        title: r['student_name'] ?? 'Unknown',
                        subtitle:
                            "Enrollment: ${r['enrollment_number'] ?? 'N/A'} | False Alarms: $falseAlarmCount",
                        color: const Color.fromARGB(255, 255, 220, 220),
                        icon: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: 28,
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 32),

              // ===== Guards On Duty =====
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Guards On Duty',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              if (_loadingGuards)
                const CircularProgressIndicator()
              else if (_availableGuards.isEmpty)
                const Text(
                  'No guards available.',
                  style: TextStyle(fontSize: 14),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _availableGuards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _buildGuardCard(_availableGuards[index]),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
