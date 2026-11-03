import 'dart:convert';

import 'package:sami/services/parametres_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _garoua = LatLng(9.3265, 13.3958);

/// SÉLECTEUR DE POSITION — version complète :
/// • le point BLEU montre où VOUS êtes (GPS) avant de choisir ;
/// • le point ROUGE est le lieu de livraison que vous posez ;
/// • l'ITINÉRAIRE ROUTIER réel (OSRM/OpenStreetMap) est tracé entre les
///   deux, avec distance et temps estimé à moto — le client sait
///   exactement ce qu'il demande au livreur.
class SelecteurPositionPage extends StatefulWidget {
  final LatLng? initial;
  const SelecteurPositionPage({super.key, this.initial});

  @override
  State<SelecteurPositionPage> createState() => _SelecteurPositionPageState();
}

class _SelecteurPositionPageState extends State<SelecteurPositionPage> {
  final _carte = MapController();
  LatLng? _choix;
  LatLng? _maPosition;
  List<LatLng> _itineraire = [];
  double? _distanceKm;
  int? _dureeMin;
  bool _calculEnCours = false;

  @override
  void initState() {
    super.initState();
    _choix = widget.initial;
    _localiser();
  }

  /// Ma position (point bleu) — centre la carte dessus au premier fix.
  Future<void> _localiser() async {
    try {
      final loc = Location();
      if (!await loc.serviceEnabled() && !await loc.requestService()) return;
      var perm = await loc.hasPermission();
      if (perm == PermissionStatus.denied) {
        perm = await loc.requestPermission();
      }
      if (perm != PermissionStatus.granted) return;
      final p = await loc.getLocation();
      if (p.latitude == null || !mounted) return;
      setState(() => _maPosition = LatLng(p.latitude!, p.longitude!));
      if (_choix == null) _carte.move(_maPosition!, 15);
      _calculerItineraire();
    } catch (_) {}
  }

  /// ITINÉRAIRE ROUTIER (OSRM public) : suit les vraies routes de la
  /// carte — pas le vol d'oiseau. Temps ajusté moto (~×0,8 du temps
  /// voiture OSRM : les motos filent dans Garoua).
  Future<void> _calculerItineraire() async {
    final a = _maPosition;
    final b = _choix;
    if (a == null || b == null) return;
    setState(() => _calculEnCours = true);
    try {
      final base = await ParametresService.osrmUrl();
      final url = '$base/route/v1/driving/'
          '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
          '?overview=full&geometries=geojson';
      final rep =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (rep.statusCode == 200) {
        final data = jsonDecode(rep.body) as Map<String, dynamic>;
        final route = (data['routes'] as List?)?.firstOrNull;
        if (route != null && mounted) {
          final coords =
              (route['geometry']['coordinates'] as List).cast<List>();
          setState(() {
            _itineraire = coords
                .map((c) => LatLng(
                    (c[1] as num? ?? 0).toDouble(), (c[0] as num? ?? 0).toDouble()))
                .toList();
            _distanceKm = (route['distance'] as num? ?? 0) / 1000;
            _dureeMin =
                ((route['duration'] as num? ?? 0) * 0.8 / 60).ceil(); // moto
          });
        }
      }
    } catch (_) {
      // OSRM injoignable : distance à vol d'oiseau en repli honnête
      if (mounted) {
        setState(() {
          _itineraire = [a, b];
          _distanceKm = const Distance().as(LengthUnit.Kilometer, a, b);
          _dureeMin = null;
        });
      }
    } finally {
      if (mounted) setState(() => _calculEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.placerMaPosition),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _carte,
          options: MapOptions(
            initialCenter: _choix ?? _maPosition ?? _garoua,
            initialZoom: 14,
            onTap: (_, latlng) {
              setState(() => _choix = latlng);
              _calculerItineraire();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'cm.sami.pagneshop',
            ),
            // L'ITINÉRAIRE (routes réelles)
            if (_itineraire.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                    points: _itineraire,
                    strokeWidth: 4,
                    color: _kPrimary.withOpacity(0.8)),
              ]),
            MarkerLayer(markers: [
              // MOI (bleu)
              if (_maPosition != null)
                Marker(
                  point: _maPosition!,
                  width: 22, height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              // LE LIEU DE LIVRAISON (rouge)
              if (_choix != null)
                Marker(
                  point: _choix!,
                  width: 46, height: 46,
                  child: const Icon(Icons.location_pin,
                      color: Colors.red, size: 46),
                ),
            ]),
          ],
        ),
        Positioned(
          top: 10, left: 12, right: 12,
          child: Card(
            color: Colors.white.withOpacity(0.95),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                  _choix == null
                      ? Tr.s.vousEtesIciTouchezCarte
                      : _calculEnCours
                          ? Tr.s.calculItineraire
                          : _distanceKm != null
                              ? Tr.s.kmDepuisVotrePosition(_distanceKm!.toStringAsFixed(1), _dureeMin != null ? ' · ≈ $_dureeMin min' : ' (vol d\'oiseau)')
                              : Tr.s.pointPoseValidezBas,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
        ),
        // Recentrer sur moi
        Positioned(
          right: 12, bottom: 96,
          child: FloatingActionButton.small(
            heroTag: 'moi',
            backgroundColor: Colors.white,
            onPressed: _maPosition == null
                ? _localiser
                : () => _carte.move(_maPosition!, 16),
            child: const Icon(Icons.my_location, color: _kPrimary),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed:
                _choix == null ? null : () => Navigator.pop(context, _choix),
            icon: const Icon(Icons.check),
            label: Text(_choix == null
                ? Tr.s.touchezCarteAbord
                : Tr.s.validerCettePosition),
          ),
        ),
      ),
    );
  }
}
