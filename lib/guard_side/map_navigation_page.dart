import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';

class MapNavigationPage extends StatefulWidget {
  final double studentLat;
  final double studentLng;

  const MapNavigationPage({
    super.key,
    required this.studentLat,
    required this.studentLng,
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

  @override
  void initState() {
    super.initState();
    polylinePoints = PolylinePoints(); // ✅ FIXED
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    _guardLocation = await _location.getLocation();
    _updateMap();
    _updateDistance();

    _location.onLocationChanged.listen((loc) {
      _guardLocation = loc;
      _updateMap();
      _updateDistance();
    });
  }

  Future<void> _updateMap() async {
    if (_guardLocation == null) return;

    _markers = {
      Marker(
        markerId: const MarkerId("guard"),
        position: LatLng(
          _guardLocation!.latitude!,
          _guardLocation!.longitude!,
        ),
        infoWindow: const InfoWindow(title: "Guard"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId("student"),
        position: LatLng(widget.studentLat, widget.studentLng),
        infoWindow: const InfoWindow(title: "Student"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: _googleApiKey, // ✅ API KEY PASSED HERE
      request: PolylineRequest(
        origin: PointLatLng(
          _guardLocation!.latitude!,
          _guardLocation!.longitude!,
        ),
        destination: PointLatLng(
          widget.studentLat,
          widget.studentLng,
        ),
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
        1000; // km

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Navigation"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _guardLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        _guardLocation!.latitude!,
                        _guardLocation!.longitude!,
                      ),
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) =>
                        _mapController = controller,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
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
