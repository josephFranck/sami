import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:sami/l10n/tr.dart';

// MapScreen — carte GPS temps réel avec OSM — GRATUIT
// Centre de Garoua : 9.3017°N, 13.3984°E
const _kGarouaCenter = LatLng(9.3017, 13.3984);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final Location _location = Location();
  LatLng? _positionActuelle;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _initialiserPosition();
  }

  Future<void> _initialiserPosition() async {
    try {
      bool serviceActif = await _location.serviceEnabled();
      if (!serviceActif) serviceActif = await _location.requestService();
      if (!serviceActif) { setState(() => _chargement = false); return; }

      PermissionStatus perm = await _location.hasPermission();
      if (perm == PermissionStatus.denied) {
        perm = await _location.requestPermission();
        if (perm != PermissionStatus.granted) { setState(() => _chargement = false); return; }
      }

      final loc = await _location.getLocation();
      if (loc.latitude != null && loc.longitude != null && mounted) {
        setState(() {
          _positionActuelle = LatLng(loc.latitude!, loc.longitude!);
          _chargement = false;
        });
        _mapController.move(_positionActuelle!, 14.0);
      }

      _location.onLocationChanged.listen((d) {
        if (d.latitude != null && d.longitude != null && mounted) {
          setState(() => _positionActuelle = LatLng(d.latitude!, d.longitude!));
        }
      });
    } catch (e) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.maCarteGps),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _kGarouaCenter,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.sami',
              ),
              if (_positionActuelle != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _positionActuelle!,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A1B9A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              // Attribution obligatoire OSM
              SimpleAttributionWidget(
                source: Text(Tr.s.openstreetmapContributors),
              ),
            ],
          ),
          if (_chargement)
            const Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          if (_positionActuelle != null) {
            _mapController.move(_positionActuelle!, 15.0);
          }
        },
        backgroundColor: const Color(0xFF6A1B9A),
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}
