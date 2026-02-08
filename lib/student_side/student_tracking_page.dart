import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class StudentTrackingPage extends StatefulWidget {
  final double studentLat;
  final double studentLng;
  final String guardUserId;

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
  final supabase = Supabase.instance.client;

  LatLng? _guardPos;
  List<LatLng> _routePoints = [];
  double? _distance;
  String? _lastUpdated;

  // 🔑 OpenRouteService API key (FREE, no billing)
  final String _orsApiKey = 'YOUR_ORS_API_KEY';

  @override
  void initState() {
    super.initState();
    _fetchInitialGuardLocation();
    _subscribeToGuardLocation();
  }

  Future<void> _fetchInitialGuardLocation() async {
    try {
      final response = await supabase
          .from('guard_details')
          .select('last_lat, last_lng, last_updated')
          .eq('user_id', widget.guardUserId)
          .maybeSingle();

      if (response != null &&
          response['last_lat'] != null &&
          response['last_lng'] != null) {
        _lastUpdated = response['last_updated'];
        _updateGuardLocation(
          (response['last_lat'] as num).toDouble(),
          (response['last_lng'] as num).toDouble(),
        );
      }
    } catch (_) {}
  }

  void _subscribeToGuardLocation() {
    final channel = supabase.channel('guard_location_channel');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'guard_locations',
      callback: (payload) {
        if (payload.newRecord['user_id'].toString() ==
            widget.guardUserId) {
          _lastUpdated = payload.newRecord['timestamp'];
          _updateGuardLocation(
            (payload.newRecord['lat'] as num).toDouble(),
            (payload.newRecord['lng'] as num).toDouble(),
          );
        }
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'guard_locations',
      callback: (payload) {
        if (payload.newRecord['user_id'].toString() ==
            widget.guardUserId) {
          _lastUpdated = payload.newRecord['timestamp'];
          _updateGuardLocation(
            (payload.newRecord['lat'] as num).toDouble(),
            (payload.newRecord['lng'] as num).toDouble(),
          );
        }
      },
    );

    channel.subscribe();
  }

  Future<void> _updateGuardLocation(double lat, double lng) async {
    final studentPos =
        LatLng(widget.studentLat, widget.studentLng);
    LatLng guardPos = LatLng(lat, lng);

    final meters = Geolocator.distanceBetween(
      studentPos.latitude,
      studentPos.longitude,
      guardPos.latitude,
      guardPos.longitude,
    );

    if (meters < 10) {
      guardPos =
          LatLng(guardPos.latitude + 0.0001, guardPos.longitude);
      _routePoints.clear();
    } else {
      await _fetchRoute(studentPos, guardPos);
    }

    _guardPos = guardPos;
    _distance = meters / 1000;

    setState(() {});
  }

  Future<void> _fetchRoute(
      LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': _orsApiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'coordinates': [
          [start.longitude, start.latitude],
          [end.longitude, end.latitude],
        ]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final coords =
          data['features'][0]['geometry']['coordinates'];

      _routePoints = coords
          .map<LatLng>((c) => LatLng(c[1], c[0]))
          .toList();
    } else {
      _routePoints.clear();
    }
  }

  String _formatTimestamp(String? iso) {
    if (iso == null) return "";
    try {
      return DateFormat("dd MMM yyyy, hh:mm a")
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGuard = _guardPos != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Guard Tracking")),
      body: !hasGuard
          ? const Center(child: Text("Waiting for guard location..."))
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        widget.studentLat,
                        widget.studentLng,
                      ),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              widget.studentLat,
                              widget.studentLng,
                            ),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                          Marker(
                            point: _guardPos!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.security,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 4,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (_distance != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Text(
                          "Guard is ${_distance!.toStringAsFixed(2)} km away",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        if (_lastUpdated != null)
                          Text(
                            "Last updated: ${_formatTimestamp(_lastUpdated)}",
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
