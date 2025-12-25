import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'recording_screen.dart';
import 'custom_appbar.dart';
import 'submit_report_page.dart';

class Demopage1 extends StatefulWidget {
  const Demopage1({super.key});

  @override
  State<Demopage1> createState() {
    return _DemopageState();
  }
}

class _DemopageState extends State<Demopage1> {
  double result = 0;
  final TextEditingController texteditingcontroller = TextEditingController();

  Widget _buildReportCard({
  required String type,
  required String date,
  required Color color,
  required IconData icon,
}) {
  return Card(
    elevation: 8,
    margin: EdgeInsets.zero, // prevents extra white space
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias, // ensures corners are clipped
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: $type',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Submitted On: $date',
                    style: const TextStyle(fontSize: 20)),
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
      body:
       Padding(
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
                      MaterialPageRoute(builder: (_) => const RecordingScreen()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Camera, mic & location permissions required')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  elevation: 8,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(60), // makes it large & circular
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
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '+ Report',
                style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
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
              child: ListView(
                children: [
                  GestureDetector(
                    onTap: () {
                      print('Open report details: Theft');
                    },
                    child: _buildReportCard(
                      type: 'Theft',
                      date: '02-01-2015',
                      color: const Color.fromARGB(255, 147, 204, 251),
                      icon: Icons.edit,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      print('Open report details: Theft verified');
                    },
                    child: _buildReportCard(
                      type: 'Theft',
                      date: '02-01-2015',
                      color: const Color.fromARGB(255, 248, 240, 171),
                      icon: Icons.check_circle,
                    ),
                  ),
                ],
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