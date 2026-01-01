import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recording_screen.dart';
import 'custom_appbar.dart';
import 'submit_report_page.dart';

class Demopage1 extends StatefulWidget {
  const Demopage1({super.key});

  @override
  State<Demopage1> createState() => _DemopageState();
}

class _DemopageState extends State<Demopage1> {
  late Future<List<Map<String, dynamic>>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = fetchUserReports();
  }

  /// ✅ Fetch reports for the logged-in user
  Future<List<Map<String, dynamic>>> fetchUserReports() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await Supabase.instance.client
          .from('normal_reports')
          .select()
          .eq('user_id', userId)
          .order('date_submitted', ascending: false);

      // response is already the data (List<dynamic>)
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('Error fetching reports: $e');
      return [];
    }
  }

  Widget _buildReportCard({
    required String type,
    required String date,
    required String label,   // ✅ new parameter
    required Widget iconWidget,
    required Color color,
  }) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type: $type',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('$label: $date',   // ✅ show label + date
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // SOS Button
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  final statuses = await [
                    Permission.camera,
                    Permission.microphone,
                    Permission.location,
                  ].request();

                  if (statuses[Permission.camera]!.isGranted &&
                      statuses[Permission.microphone]!.isGranted &&
                      statuses[Permission.location]!.isGranted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RecordingScreen()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Camera, mic & location permissions required')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  elevation: 8,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(60),
                ),
                child: const Text(
                  'SOS',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Report Button
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubmitReportPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 106, 178, 237),
                elevation: 10,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '+ Report',
                style: TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            // Report History Title
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Report History',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            // Scrollable Report History
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _reportsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: Text("Error: ${snapshot.error.toString()}"));
                  }
                  final reports = snapshot.data ?? [];
                  if (reports.isEmpty) {
                    return const Center(child: Text("No reports found"));
                  }

                  return ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final status = report['status'];
                      final iconWidget = status == 'reviewed'
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                          : const Icon(Icons.access_time, color: Colors.red, size: 28);

                      // ✅ compute lastEdited and label BEFORE returning the widget
                      final lastEdited = report['updated_at'] ?? report['date_submitted'];
                      final isEdited = report['updated_at'] != null;
                      final label = isEdited ? "Last Edited On" : "Submitted On";

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubmitReportPage(
                                reportData: report,
                                isEditable: status == 'pending',
                              ),
                            ),
                          );
                        },
                        child: _buildReportCard(
                          type: report['type'],
                          date: lastEdited.toString().split('T')[0], // ✅ show latest date
                          label: label,                               // ✅ pass label
                          color: status == 'reviewed'
                              ? const Color.fromARGB(255, 200, 255, 200)
                              : const Color.fromARGB(255, 255, 220, 220),
                          iconWidget: iconWidget,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          print('Navigate to chat interface');
        },
        backgroundColor: Colors.pink[300],
        elevation: 6,
        child: const Icon(Icons.chat),
      ),
    );
  }
}