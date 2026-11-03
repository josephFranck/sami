import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/pages/livraison/code_reception_page.dart';
import 'package:sami/services/message_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/models/livreur.dart';
import 'package:sami/models/couturier.dart';
import 'package:sami/l10n/tr.dart';

// Coordonnées centre de Garoua
const LatLng GAROUA_CENTER = LatLng(9.3017, 13.3984);

/// Carte principale OpenStreetMap (gratuite, zéro API key)
/// Remplace Google Maps — basée sur flutter_map + OpenStreetMap
class CarteOSM extends StatefulWidget {
  final List<MarqueurCarte> marqueurs;
  final LatLng? centreInitial;
  final double zoomInitial;
  final bool afficherPositionUtilisateur;
  final bool afficherLivreurs;
  final Function(MarqueurCarte)? onMarqueurTap;

  const CarteOSM({
    super.key,
    this.marqueurs = const [],
    this.centreInitial,
    this.zoomInitial = 13.0,
    this.afficherPositionUtilisateur = true,
    this.afficherLivreurs = false,
    this.onMarqueurTap,
  });

  @override
  State<CarteOSM> createState() => _CarteOSMState();
}

class _CarteOSMState extends State<CarteOSM> {
  final MapController _mapController = MapController();
  final Location _location = Location();
  LatLng? _positionUtilisateur;
  bool _chargementPosition = false;

  @override
  void initState() {
    super.initState();
    if (widget.afficherPositionUtilisateur) {
      _initialiserPosition();
    }
  }

  Future<void> _initialiserPosition() async {
    setState(() => _chargementPosition = true);

    try {
      bool serviceActif = await _location.serviceEnabled();
      if (!serviceActif) {
        serviceActif = await _location.requestService();
        if (!serviceActif) return;
      }

      PermissionStatus permission = await _location.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != PermissionStatus.granted) return;
      }

      final locationData = await _location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _positionUtilisateur = LatLng(
            locationData.latitude!,
            locationData.longitude!,
          );
        });

        // Centrer la carte sur l'utilisateur
        _mapController.move(_positionUtilisateur!, widget.zoomInitial);
      }

      // Écouter les mises à jour en temps réel
      _location.onLocationChanged.listen((locationData) {
        if (locationData.latitude != null && locationData.longitude != null) {
          setState(() {
            _positionUtilisateur = LatLng(
              locationData.latitude!,
              locationData.longitude!,
            );
          });
        }
      });
    } catch (e) {
      debugPrint('Erreur localisation: $e');
    } finally {
      setState(() => _chargementPosition = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.centreInitial ?? GAROUA_CENTER,
            initialZoom: widget.zoomInitial,
            minZoom: 5,
            maxZoom: 18,
          ),
          children: [
            // Tuiles OpenStreetMap — 100% gratuit
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sami',
              // Fallback si pas de connexion
              fallbackUrl: 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),

            // Marqueurs personnalisés
            MarkerLayer(
              markers: _construireMarqueurs(),
            ),

            // Ligne de trajet si livraison active
            if (_positionUtilisateur != null && widget.marqueurs.isNotEmpty)
              PolylineLayer(
                polylines: _construirePolylines(),
              ),
          ],
        ),

        // Bouton recentrer sur ma position
        if (widget.afficherPositionUtilisateur)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.small(
              onPressed: _centrerSurUtilisateur,
              backgroundColor: Colors.white,
              child: _chargementPosition
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.deepOrange),
            ),
          ),

        // Attribution OpenStreetMap (obligatoire légalement)
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            color: Colors.white.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              Tr.s.openstreetmapContributors,
              style: TextStyle(fontSize: 9),
            ),
          ),
        ),
      ],
    );
  }

  List<Marker> _construireMarqueurs() {
    final markers = <Marker>[];

    // Position utilisateur
    if (_positionUtilisateur != null) {
      markers.add(Marker(
        point: _positionUtilisateur!,
        width: 40,
        height: 40,
        child: _marqueurUtilisateur(),
      ));
    }

    // Marqueurs personnalisés
    for (final marqueur in widget.marqueurs) {
      markers.add(Marker(
        point: LatLng(marqueur.latitude, marqueur.longitude),
        width: 50,
        height: 60,
        child: GestureDetector(
          onTap: () => widget.onMarqueurTap?.call(marqueur),
          child: _iconeMarqueur(marqueur),
        ),
      ));
    }

    return markers;
  }

  List<Polyline> _construirePolylines() {
    // Ligne entre position utilisateur et destination
    // (En production : utiliser OSRM API pour le vrai trajet)
    if (_positionUtilisateur == null || widget.marqueurs.isEmpty) return [];

    final destination = widget.marqueurs
        .where((m) => m.type == TypeMarqueur.destination)
        .firstOrNull;

    if (destination == null) return [];

    return [
      Polyline(
        points: [
          _positionUtilisateur!,
          LatLng(destination.latitude, destination.longitude),
        ],
        strokeWidth: 3.0,
        color: Colors.deepOrange.withOpacity(0.7),
        isDotted: true,
      ),
    ];
  }

  Widget _marqueurUtilisateur() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 20),
    );
  }

  Widget _iconeMarqueur(MarqueurCarte marqueur) {
    final (icone, couleur) = switch (marqueur.type) {
      TypeMarqueur.boutique => (Icons.store, Colors.indigo),
      TypeMarqueur.couturier => (Icons.content_cut, Colors.purple),
      TypeMarqueur.livreur => (Icons.delivery_dining, Colors.green),
      TypeMarqueur.destination => (Icons.location_on, Colors.red),
      TypeMarqueur.origine => (Icons.flag, Colors.blue),
    };

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: couleur,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(icone, color: Colors.white, size: 18),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: couleur,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            marqueur.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _centrerSurUtilisateur() {
    if (_positionUtilisateur != null) {
      _mapController.move(_positionUtilisateur!, widget.zoomInitial);
    } else {
      _initialiserPosition();
    }
  }
}

// ─── Modèle marqueur ────────────────────────────────────────────────────────

enum TypeMarqueur { boutique, couturier, livreur, destination, origine }

class MarqueurCarte {
  final String id;
  final double latitude;
  final double longitude;
  final String label;
  final TypeMarqueur type;
  final Map<String, dynamic>? data; // données supplémentaires

  const MarqueurCarte({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.type,
    this.data,
  });

  // Factories pratiques
  factory MarqueurCarte.livreur(Livreur l) => MarqueurCarte(
        id: l.id,
        latitude: l.latitude,
        longitude: l.longitude,
        label: '${l.nom} ${l.prenom[0]}.',
        type: TypeMarqueur.livreur,
        data: {'livreurId': l.id, 'note': l.noteMoyenne},
      );

  factory MarqueurCarte.couturier(Couturier c) => MarqueurCarte(
        id: c.id,
        latitude: c.latitude,
        longitude: c.longitude,
        label: '${c.nom} ${c.prenom[0]}.',
        type: TypeMarqueur.couturier,
        data: {'couturierId': c.id, 'note': c.noteMoyenne},
      );
}

// ─── Page de suivi de livraison ──────────────────────────────────────────────

class PageSuiviLivraison extends StatelessWidget {
  final Livraison livraison;

  const PageSuiviLivraison({super.key, required this.livraison});

  @override
  Widget build(BuildContext context) {
    // OFFLINE-FIRST : le client précharge sa clé QR d'arrivée tant qu'il a du
    // réseau, pour pouvoir présenter/valider son code même hors-ligne.
    QRCryptoService.prechargerDepuisFirestore(
      livraisonId: livraison.id,
      role: RoleLivraison.client,
    );
    // Suivi TEMPS RÉEL : réécoute la livraison dans Firestore.
    // Quand le livreur bouge (position envoyée toutes les 30s) ou change de
    // statut, l'affichage se met à jour automatiquement.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('livraisons')
          .doc(livraison.id)
          .snapshots(),
      builder: (context, snap) {
        // Utilise la version à jour si dispo, sinon la version initiale
        final liv = (snap.hasData && snap.data!.exists)
            ? Livraison.fromFirebaseDocument(snap.data!)
            : livraison;
        return _contenuSuivi(context, liv);
      },
    );
  }

  Widget _contenuSuivi(BuildContext context, Livraison livraison) {
    final marqueurs = [
      MarqueurCarte(
        id: 'origine',
        latitude: livraison.origineLat,
        longitude: livraison.origineLng,
        label: livraison.origineNom,
        type: TypeMarqueur.origine,
      ),
      MarqueurCarte(
        id: 'destination',
        latitude: livraison.destinationLat,
        longitude: livraison.destinationLng,
        label: Tr.s.maPosition,
        type: TypeMarqueur.destination,
      ),
      if (livraison.livreurLatActuelle != null && livraison.livreurLngActuelle != null)
        MarqueurCarte(
          id: 'livreur',
          latitude: livraison.livreurLatActuelle!,
          longitude: livraison.livreurLngActuelle!,
          label: Tr.s.livreur,
          type: TypeMarqueur.livreur,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.suiviLivraison),
        backgroundColor: Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        actions: [
          if (livraison.livreurId != null)
            IconButton(
              tooltip: Tr.s.ecrireLivreur,
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () async {
                // Résoudre l'utilisateur derrière la fiche livreur
                final fiche = await FirebaseFirestore.instance
                    .collection('livreurs').doc(livraison.livreurId).get();
                final d = fiche.data();
                if (!context.mounted || d == null) return;
                MessageService.contacter(context,
                    autreUserId: d['utilisateurId'] as String? ?? '',
                    autreNom: '${d['prenom'] ?? ''} ${d['nom'] ?? 'Livreur'}'.trim(),
                    contexte: 'Livraison en cours',
                    contexteId: livraison.id);
              },
            ),
          IconButton(
            tooltip: Tr.s.monCodeReception2,
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CodeReceptionPage(livraisonId: livraison.id),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Statut en haut
          _BandeauStatut(statut: livraison.statut),

          // Carte OSM
          Expanded(
            child: CarteOSM(
              marqueurs: marqueurs,
              centreInitial: LatLng(livraison.origineLat, livraison.origineLng),
              zoomInitial: 14.0,
              afficherPositionUtilisateur: true,
            ),
          ),

          // Infos livraison en bas
          _PanneauInfoLivraison(livraison: livraison),
        ],
      ),
    );
  }
}

class _BandeauStatut extends StatelessWidget {
  final StatutLivraison statut;

  const _BandeauStatut({required this.statut});

  @override
  Widget build(BuildContext context) {
    final (label, couleur, icone) = switch (statut) {
      StatutLivraison.enAttente => ('En attente', Colors.orange, Icons.hourglass_empty),
      StatutLivraison.rechercheLibreur => ('Recherche livreur...', Colors.blue, Icons.search),
      StatutLivraison.livreurAssigne => ('Livreur assigné ✓', Colors.teal, Icons.check_circle),
      StatutLivraison.enRouteOrigine => ('En route vers la boutique', Colors.green, Icons.directions_bike),
      StatutLivraison.articleRecupere => ('Article récupéré', Colors.indigo, Icons.inventory),
      StatutLivraison.enLivraison => ('En livraison 🏃', Colors.deepOrange, Icons.delivery_dining),
      StatutLivraison.livre => ('Livré ✓', Colors.green, Icons.done_all),
      StatutLivraison.echec => ('Échec livraison', Colors.red, Icons.error),
      StatutLivraison.annule => ('Annulée', Colors.grey, Icons.cancel),
      StatutLivraison.pretRetrait => ('Prêt pour retrait', Colors.teal, Icons.store),
      StatutLivraison.litige => ('Litige en cours', Colors.red, Icons.gavel),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: couleur,
      child: Row(
        children: [
          Icon(icone, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _PanneauInfoLivraison extends StatelessWidget {
  final Livraison livraison;

  const _PanneauInfoLivraison({required this.livraison});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(child: Text(livraison.origineNom, style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(child: Text(livraison.destinationAdresse, style: const TextStyle(color: Colors.grey))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Tr.s.fraisFcfa(livraison.decompositionFinanciere.fraisLivraisonIsole.toStringAsFixed(0)),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
              ),
              if (livraison.dateLivraisonPrevue != null)
                Text(
                  Tr.s.prevu(_formatHeure(livraison.dateLivraisonPrevue!)),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatHeure(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
