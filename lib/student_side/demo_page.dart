import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recording_screen.dart';
import 'custom_appbar.dart';
import 'submit_report_page.dart';
import 'resolved_report_viewer.dart';
import 'sos_confirmation_screen.dart';
import 'package:demo_app/student_side/resolved_sos_viewer.dart';
import 'package:flutter/services.dart';


class Demopage1 extends StatefulWidget {
  const Demopage1({super.key});

  @override
  State<Demopage1> createState() => _DemopageState();
}
  class _DemopageState extends State<Demopage1> {
    // 🔄 Initialize immediately to avoid LateInitializationError
    late final Stream<List<Map<String, dynamic>>> _reportsStream =
        fetchUserReportsStream();
    late final Stream<List<Map<String, dynamic>>> _sosReportsStream;
    String _fmtDateTime(dynamic ts) {
      if (ts == null) return 'N/A';
      final dt = DateTime.tryParse(ts.toString());
      if (dt == null) return ts.toString();
      return dt.toLocal().toString().split('.').first; // yyyy-MM-dd HH:mm:ss
    }

    @override
    void initState() {
      super.initState();
      _sosReportsStream = Supabase.instance.client
      .from('sos_reports')
      .stream(primaryKey: ['id'])
      .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
      .order('created_at', ascending: false)
      .map((rows) => rows.cast<Map<String, dynamic>>());
      // no need to call _refreshReports here anymore
    }

    /// ✅ Live stream of reports for the logged-in user
    Stream<List<Map<String, dynamic>>> fetchUserReportsStream() {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return const Stream.empty();

      return Supabase.instance.client
          .from('normal_reports')
          .stream(primaryKey: ['id'])   // listen for inserts/updates/deletes
          .eq('user_id', userId)
          .order('date_submitted')
          .map((rows) => List<Map<String, dynamic>>.from(rows));
    }

    Widget _buildReportCard({
      required String type,
      required String date,
      required String label,
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
                    Text('$label: $date',
                        style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget _buildSosCard({
      required String title,
      required String label,
      required String dateText,
      required Color color,
      required Widget iconWidget,
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$label: $dateText",
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Future<void> _refreshPage() async {
      HapticFeedback.mediumImpact();
      setState(() {
        // Streams will reattach automatically
      });
    }


    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: const CustomAppBar(),
        body: RefreshIndicator(
          onRefresh: _refreshPage,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // ================= SOS BUTTON =================
                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
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
                            MaterialPageRoute(builder: (_) => const RecordingScreen()),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Camera, mic & location permissions required'),
                            ),
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
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================= REPORT BUTTON =================
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SubmitReportPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 106, 178, 237),
                      elevation: 10,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '+ Report',
                      style: TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ================= NORMAL REPORTS =================
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _reportsStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final reports = snapshot.data!;
                      final resolvedReports =
                          reports.where((r) => r['status'] == 'resolved').toList();
                      final submittedReports =
                          reports.where((r) => r['status'] != 'resolved').toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resolved Reports',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: resolvedReports.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final report = resolvedReports[index];
                              final date =
                                  (report['updated_at'] ?? report['date_submitted'])
                                      .toString()
                                      .split('T')[0];

                              return GestureDetector(
                                onTap: () async {
                                  final reportWithActions =
                                      await Supabase.instance.client
                                          .from('normal_reports')
                                          .select('*, guard_actions(*)')
                                          .eq('id', report['id'])
                                          .single();

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ResolvedReportViewer(
                                        reportData: reportWithActions,
                                      ),
                                    ),
                                  );
                                },
                                child: _buildReportCard(
                                  type: report['type'],
                                  date: date,
                                  label: "Resolved On",
                                  color: const Color.fromARGB(255, 200, 255, 200),
                                  iconWidget: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            'Reports Submitted',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: submittedReports.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final report = submittedReports[index];
                              final date =
                                  (report['updated_at'] ?? report['date_submitted'])
                                      .toString()
                                      .split('T')[0];

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SubmitReportPage(
                                        reportData: report,
                                        isEditable: report['status'] == 'pending',
                                      ),
                                    ),
                                  );
                                },
                                child: _buildReportCard(
                                  type: report['type'],
                                  date: date,
                                  label: "Submitted On",
                                  color: const Color.fromARGB(255, 255, 220, 220),
                                  iconWidget: const Icon(
                                    Icons.access_time,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // ================= SOS REPORTS =================
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _sosReportsStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final sos = snapshot.data!;
                      final pending =
                          sos.where((r) => r['resolution_status'] == null).toList();
                      final history = sos.where((r) =>
                          r['resolution_status'] == 'resolved' ||
                          r['resolution_status'] == 'false_alarm');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pending SOS',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: pending.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final r = pending[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SosConfirmationScreen(
                                        sosId: r['id'].toString(),
                                        guardId:
                                            r['assigned_guard_id']?.toString() ?? '',
                                        studentId:
                                            r['user_id']?.toString() ?? '',
                                      ),
                                    ),
                                  );
                                },
                                child: _buildSosCard(
                                  title: "SOS",
                                  label: "View details",
                                  dateText: _fmtDateTime(r['created_at']),
                                  color: const Color.fromARGB(255, 255, 240, 200),
                                  iconWidget: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            'SOS Report History',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: history.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final r = history.elementAt(index);
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ResolvedSosViewer(reportData: r),
                                    ),
                                  );
                                },
                                child: _buildSosCard(
                                  title: "SOS — ${r['resolution_status']}",
                                  label: "Resolved on",
                                  dateText: _fmtDateTime(r['resolved_at']),
                                  color: const Color.fromARGB(255, 200, 255, 200),
                                  iconWidget: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      );
    }
}

  
