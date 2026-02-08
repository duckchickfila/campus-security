import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class MapNavigationPage extends StatefulWidget {
  final double studentLat;
  final double studentLng;
  final String guardUserId;

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
  final Location _location = Location();
  LocationData? _guardLocation;

  List<Marker> _markers = [];
  List<Polyline> _polylines = [];
  double? _distance;

  final supabase = Supabase.instance.client;
  DateTime? _lastPublishTime;

  // ✅ OpenRouteService API key (FREE)
  final String _orsApiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjkyZThhYmVlMTMzYzRjZmRhZGVmNGIzNDgxZDJkN2UzIiwiaCI6Im11cm11cjY0In0=";

  @override
  void initState() {
    super.initState();
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
    await _updateMap();
    _updateDistance();
    _publishGuardLocation();

    _location.onLocationChanged.listen((loc) async {
      _guardLocation = loc;
      await _updateMap();
      _updateDistance();
      _publishGuardLocation();
    });
  }

  Future<void> _publishGuardLocation() async {
    if (_guardLocation == null) return;

    final lat = _guardLocation!.latitude;
    final lng = _guardLocation!.longitude;
    if (lat == null || lng == null) return;

    final now = DateTime.now();
    if (_lastPublishTime != null &&
        now.difference(_lastPublishTime!).inMinutes < 5) {
      return;
    }
    _lastPublishTime = now;

    await supabase.from('guard_locations').upsert({
      'user_id': widget.guardUserId,
      'lat': lat,
      'lng': lng,
      'timestamp': now.toIso8601String(),
    });

    await supabase.from('guard_details').update({
      'last_lat': lat,
      'last_lng': lng,
      'last_updated': now.toIso8601String(),
    }).eq('user_id', widget.guardUserId);
  }

  Future<List<LatLng>> _fetchRoute(
    LatLng start,
    LatLng end,
  ) async {
    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car'
      '?api_key=$_orsApiKey'
      '&start=${start.longitude},${start.latitude}'
      '&end=${end.longitude},${end.latitude}',
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    final coords = data['features'][0]['geometry']['coordinates'];

    return coords
        .map<LatLng>((c) => LatLng(c[1], c[0]))
        .toList();
  }

  Future<void> _updateMap() async {
    if (_guardLocation == null) return;

    LatLng guardPos =
        LatLng(_guardLocation!.latitude!, _guardLocation!.longitude!);
    LatLng studentPos =
        LatLng(widget.studentLat, widget.studentLng);

    final meters = Geolocator.distanceBetween(
      guardPos.latitude,
      guardPos.longitude,
      studentPos.latitude,
      studentPos.longitude,
    );

    if (meters < 10) {
      studentPos = LatLng(studentPos.latitude + 0.0001, studentPos.longitude);
      _polylines.clear();
    }

    _markers = [
      Marker(
        point: guardPos,
        width: 40,
        height: 40,
        child: const Icon(Icons.security, color: Colors.blue, size: 36),
      ),
      Marker(
        point: studentPos,
        width: 40,
        height: 40,
        child: const Icon(Icons.person_pin_circle,
            color: Colors.red, size: 36),
      ),
    ];

    if (meters > 10) {
      final routePoints = await _fetchRoute(guardPos, studentPos);
      _polylines = [
        Polyline(
          points: routePoints,
          strokeWidth: 5,
          color: Colors.blue,
        ),
      ];
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
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        _guardLocation!.latitude!,
                        _guardLocation!.longitude!,
                      ),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.your.app',
                      ),
                      PolylineLayer(polylines: _polylines),
                      MarkerLayer(markers: _markers),
                    ],
                  ),
                ),
                if (_distance != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Distance: ${_distance!.toStringAsFixed(2)} km",
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
