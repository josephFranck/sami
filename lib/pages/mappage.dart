import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

// MapPage — utilise OpenStreetMap (flutter_map) — GRATUIT
// Remplace Google Maps (supprimé du projet)
class MapPage extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String? titre;

  const MapPage({
    super.key,
    required this.latitude,
    required this.longitude,
    this.titre,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre ?? 'Carte'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(widget.latitude, widget.longitude),
          initialZoom: 15.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.sami',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(widget.latitude, widget.longitude),
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF6A1B9A),
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _mapController.move(
          LatLng(widget.latitude, widget.longitude),
          15.0,
        ),
        backgroundColor: const Color(0xFF6A1B9A),
        child: const Icon(Icons.center_focus_strong, color: Colors.white),
      ),
    );
  }
}
