import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart'; // for reverse geocoding
import 'student_tracking_page.dart'; // ✅ import your tracking page

class SosConfirmationScreen extends StatefulWidget {
  final String sosId;
  final String guardId;

  const SosConfirmationScreen({
    super.key,
    required this.sosId,
    required this.guardId,
  });

  @override
  State<SosConfirmationScreen> createState() => _SosConfirmationScreenState();
}

class _SosConfirmationScreenState extends State<SosConfirmationScreen> {
  String? guardName;
  String? guardLocation;
  double? guardLat;
  double? guardLng;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchGuardDetails();
  }

  Future<void> _fetchGuardDetails() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('guard_details')
          .select('name, last_lat, last_lng')
          .eq('user_id', widget.guardId)
          .maybeSingle();

      if (response != null) {
        guardName = response['name'] ?? 'Unknown';
        guardLat = response['last_lat'];
        guardLng = response['last_lng'];

        if (guardLat != null && guardLng != null) {
          try {
            final placemarks = await placemarkFromCoordinates(
              guardLat!,
              guardLng!,
              localeIdentifier: "en", // ✅ force English output
            );
            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              guardLocation =
                  "${place.street}, ${place.locality}, ${place.subAdministrativeArea}, "
                  "${place.administrativeArea}, ${place.postalCode}, ${place.country}";
            } else {
              guardLocation = "Location unavailable";
            }
          } catch (e) {
            guardLocation = "Location lookup failed";
          }
        } else {
          guardLocation = "Location not recorded";
        }
      }
    } catch (e) {
      guardName = 'Unknown';
      guardLocation = 'Unknown';
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("SOS Submitted"),
        backgroundColor: Colors.red,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 20),
              const Text(
                "Your SOS alert has been submitted successfully!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text("SOS ID: ${widget.sosId}",
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(
                        loading
                            ? "Assigned Guard: Loading..."
                            : "Assigned Guard: $guardName",
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loading
                            ? "Guard Location: Loading..."
                            : "Guard Location: $guardLocation",
                        style: const TextStyle(fontSize: 20),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  if (guardLat != null && guardLng != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentTrackingPage(
                          studentLat: guardLat!,
                          studentLng: guardLng!,
                          guardUserId: widget.guardId, // ✅ fixed here
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  "Open Map Navigation",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}