import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentTrackingPage extends StatefulWidget {
  final double studentLat;
  final double studentLng;
  final String guardUserId; // use user_id consistently

  const StudentTrackingPage({
    super.key,
    required this.studentLat,
    required this.studentLng,
    required this.guardUserId,
  });

  @override
  State<StudentTrackingPage> createState() => _StudentTrackingPageState();
}

class _StudentTrackingPageState extends State<StudentTrackingPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _distance;

  final String _googleApiKey = "AIzaSyDfcZsNnccD6vaesWmCPbQtbjnheVDvmGk";
  late PolylinePoints polylinePoints;
  final supabase = Supabase.instance.client;

  double? _guardLat;
  double? _guardLng;

  @override
  void initState() {
    super.initState();
    polylinePoints = PolylinePoints();
    _initMarkers();
    _fetchInitialGuardLocation(); // last known location from guard_details
    _subscribeToGuardLocation();  // live updates from guard_locations
  }

  void _initMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId("student"),
        position: LatLng(widget.studentLat, widget.studentLng),
        infoWindow: const InfoWindow(title: "You (Student)"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  Future<void> _fetchInitialGuardLocation() async {
    try {
      final response = await supabase
          .from('guard_details')
          .select('last_lat, last_lng')
          .eq('user_id', widget.guardUserId)
          .maybeSingle();

      debugPrint("Guard details response: $response");

      if (response != null &&
          response['last_lat'] != null &&
          response['last_lng'] != null) {
        final lat = (response['last_lat'] as num).toDouble();
        final lng = (response['last_lng'] as num).toDouble();
        _updateGuardLocation(lat, lng);
      }
    } catch (e) {
      debugPrint("Error fetching initial guard location: $e");
    }
  }

  void _subscribeToGuardLocation() {
    final channel = supabase.channel('guard_location_channel');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'guard_locations',
      callback: (payload) {
        debugPrint("Realtime insert payload: ${payload.newRecord}");
        if (payload.newRecord['user_id'].toString() == widget.guardUserId) {
          final lat = (payload.newRecord['lat'] as num).toDouble();
          final lng = (payload.newRecord['lng'] as num).toDouble();
          _updateGuardLocation(lat, lng);
        }
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'guard_locations',
      callback: (payload) {
        debugPrint("Realtime update payload: ${payload.newRecord}");
        if (payload.newRecord['user_id'].toString() == widget.guardUserId) {
          final lat = (payload.newRecord['lat'] as num).toDouble();
          final lng = (payload.newRecord['lng'] as num).toDouble();
          _updateGuardLocation(lat, lng);
        }
      },
    );

    channel.subscribe();
  }

  Future<void> _updateGuardLocation(double lat, double lng) async {
    _guardLat = lat;
    _guardLng = lng;

    LatLng guardPos = LatLng(lat, lng);
    LatLng studentPos = LatLng(widget.studentLat, widget.studentLng);

    // Calculate distance in meters
    final meters = Geolocator.distanceBetween(
      studentPos.latitude,
      studentPos.longitude,
      guardPos.latitude,
      guardPos.longitude,
    );

    // Nudge student marker if overlapping
    if (meters < 10) {
      studentPos = LatLng(studentPos.latitude + 0.0001, studentPos.longitude);
      _polylines.clear(); // no route when overlapping
    }

    _markers = {
      Marker(
        markerId: const MarkerId("student"),
        position: studentPos,
        infoWindow: const InfoWindow(title: "You (Student)"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      Marker(
        markerId: const MarkerId("guard"),
        position: guardPos,
        infoWindow: const InfoWindow(title: "Guard"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    };

    // Draw route only if distance > ~10m
    if (meters > 10) {
      final result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(studentPos.latitude, studentPos.longitude),
          destination: PointLatLng(guardPos.latitude, guardPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("route"),
            color: Colors.blue,
            width: 5,
            points: result.points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
          ),
        };
      } else {
        debugPrint("Route error: ${result.errorMessage}");
        _polylines.clear();
      }
    }

    _updateDistance();
    setState(() {});
  }

  void _updateDistance() {
    if (_guardLat == null || _guardLng == null) return;
    _distance = Geolocator.distanceBetween(
          widget.studentLat,
          widget.studentLng,
          _guardLat!,
          _guardLng!,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final hasGuard = _guardLat != null && _guardLng != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Guard Tracking")),
      body: !hasGuard
          ? const Center(child: Text("Waiting for guard location..."))
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(widget.studentLat, widget.studentLng),
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) => _mapController = controller,
                  ),
                ),
                if (_distance != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Guard is ${_distance!.toStringAsFixed(2)} km away",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}