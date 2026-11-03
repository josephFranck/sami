import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);
const LatLng _kGarouaCenter = LatLng(9.3017, 13.3984);

/// Carte admin : affiche toutes les boutiques géolocalisées sur une carte OSM.
class CarteBoutiquesPage extends StatefulWidget {
  const CarteBoutiquesPage({super.key});

  @override
  State<CarteBoutiquesPage> createState() => _CarteBoutiquesPageState();
}

class _CarteBoutiquesPageState extends State<CarteBoutiquesPage>
    with PageProtegee {
  final _mapController = MapController();
  List<Boutique> _boutiques = [];
  List<Boutique> _sansGps = [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('boutiques').get();
      final toutes =
          snap.docs.map((d) => Boutique.fromFirebaseDocument(d)).toList();
      setState(() {
        _boutiques = toutes
            .where((b) => b.latitude != null && b.longitude != null)
            .toList();
        _sansGps = toutes
            .where((b) => b.latitude == null || b.longitude == null)
            .toList();
        _chargement = false;
      });
    } catch (e) {
      setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.estAdmin(u)) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Carte des boutiques'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Carte des boutiques'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() => _chargement = true);
                  _charger();
                },
              ),
            ],
          ),
          body: _chargement
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : Column(
                  children: [
                    _bandeauInfo(),
                    Expanded(child: _carte()),
                  ],
                ),
        );
      },
    );
  }

  Widget _bandeauInfo() {
    return Container(
      width: double.infinity,
      color: _kPrimary.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.store, color: _kPrimary, size: 18),
          const SizedBox(width: 8),
          Text('${_boutiques.length} boutique(s) géolocalisée(s)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (_sansGps.isNotEmpty) ...[
            const Spacer(),
            Icon(Icons.location_off, color: Colors.orange.shade700, size: 16),
            const SizedBox(width: 4),
            Text('${_sansGps.length} sans GPS',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _carte() {
    if (_boutiques.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Aucune boutique géolocalisée',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text(
                'Les boutiquiers doivent capturer leur position\nà la création de leur boutique',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    // Centrer sur la première boutique (ou Garoua)
    final centre = _boutiques.isNotEmpty
        ? LatLng(_boutiques.first.latitude!, _boutiques.first.longitude!)
        : _kGarouaCenter;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: 12,
        minZoom: 5,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.sami',
          fallbackUrl: 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
        MarkerLayer(
          markers: _boutiques.map((b) {
            return Marker(
              point: LatLng(b.latitude!, b.longitude!),
              width: 44,
              height: 54,
              child: GestureDetector(
                onTap: () => _afficherDetailsBoutique(b),
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4),
                        ],
                      ),
                      child: const Icon(Icons.store,
                          color: Colors.white, size: 18),
                    ),
                    Icon(Icons.arrow_drop_down,
                        color: _kPrimary, size: 18),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _afficherDetailsBoutique(Boutique b) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _kPrimary.withOpacity(0.12),
                  child: const Icon(Icons.store, color: _kPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(b.nom,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ligneInfo(Icons.location_on_outlined, b.adresse),
            if (b.quartier != null && b.quartier!.isNotEmpty)
              _ligneInfo(Icons.map_outlined, b.quartier!),
            _ligneInfo(Icons.phone_outlined, b.telephone),
            _ligneInfo(Icons.my_location,
                '${b.latitude!.toStringAsFixed(5)}, ${b.longitude!.toStringAsFixed(5)}'),
            if (b.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(b.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _mapController.move(
                      LatLng(b.latitude!, b.longitude!), 16);
                },
                icon: const Icon(Icons.zoom_in_map),
                label: const Text('Centrer sur cette boutique'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _kPrimary,
                    side: const BorderSide(color: _kPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(IconData icone, String texte) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
