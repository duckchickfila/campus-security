import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapNavigationPage extends StatefulWidget {
  final double studentLat;
  final double studentLng;
  final String guardUserId; // use user_id consistently

  const MapNavigationPage({
    super.key,
    required this.studentLat,
    required this.studentLng,
    required this.guardUserId,
  });

  @override
  State<MapNavigationPage> createState() => _MapNavigationPageState();
}

class _MapNavigationPageState extends State<MapNavigationPage> {
  GoogleMapController? _mapController;
  LocationData? _guardLocation;
  final Location _location = Location();

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _distance;

  final String _googleApiKey = "AIzaSyDfcZsNnccD6vaesWmCPbQtbjnheVDvmGk";
  late PolylinePoints polylinePoints;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    polylinePoints = PolylinePoints();
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    _guardLocation = await _location.getLocation();
    _updateMap();
    _updateDistance();
    _publishGuardLocation();

    _location.onLocationChanged.listen((loc) {
      _guardLocation = loc;
      _updateMap();
      _updateDistance();
      _publishGuardLocation();
    });
  }

  Future<void> _publishGuardLocation() async {
    if (_guardLocation == null) return;
    final lat = _guardLocation!.latitude;
    final lng = _guardLocation!.longitude;
    if (lat != null && lng != null) {
      await supabase.from('guard_locations').upsert({
        'user_id': widget.guardUserId,
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // ✅ also update guard_details with last_updated
      await supabase
          .from('guard_details')
          .update({
            'last_lat': lat,
            'last_lng': lng,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('user_id', widget.guardUserId);
    }
  }

  Future<void> _updateMap() async {
    if (_guardLocation == null) return;

    final guardPos = LatLng(_guardLocation!.latitude!, _guardLocation!.longitude!);
    LatLng studentPos = LatLng(widget.studentLat, widget.studentLng);

    // Calculate distance in meters
    final meters = Geolocator.distanceBetween(
      guardPos.latitude,
      guardPos.longitude,
      studentPos.latitude,
      studentPos.longitude,
    );

    // Nudge student marker if overlapping
    if (meters < 10) {
      studentPos = LatLng(studentPos.latitude + 0.0001, studentPos.longitude);
      _polylines.clear(); // no route when overlapping
    }

    _markers = {
      Marker(
        markerId: const MarkerId("guard"),
        position: guardPos,
        infoWindow: const InfoWindow(title: "Guard"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId("student"),
        position: studentPos,
        infoWindow: const InfoWindow(title: "Student"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    // Draw route only if distance > ~10m
    if (meters > 10) {
      final result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(guardPos.latitude, guardPos.longitude),
          destination: PointLatLng(studentPos.latitude, studentPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("route"),
            color: Colors.blue,
            width: 5,
            points: result.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
          ),
        };
      } else {
        debugPrint("Route error: ${result.errorMessage}");
        _polylines.clear();
      }
    }

    setState(() {});
  }

  void _updateDistance() {
    if (_guardLocation == null) return;
    _distance = Geolocator.distanceBetween(
          _guardLocation!.latitude!,
          _guardLocation!.longitude!,
          widget.studentLat,
          widget.studentLng,
        ) /
        1000;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Navigation")),
      body: _guardLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_guardLocation!.latitude!, _guardLocation!.longitude!),
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) => _mapController = controller,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                  ),
                ),
                if (_distance != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Distance: ${_distance!.toStringAsFixed(2)} km",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
    );
  }
}