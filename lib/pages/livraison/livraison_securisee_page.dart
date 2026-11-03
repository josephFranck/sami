import 'dart:convert';
import 'package:sami/services/livraison_service.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sami/widgets/image_xfile.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/services/securite_livraison_service.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/pages/livraison/scan_qr_page.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kSuccess = Color(0xFF1D9E75);

// ═══════════════════════════════════════════════════════════════════════════
// PAGE LIVRAISON SÉCURISÉE — Vue livreur avec photos obligatoires
// ═══════════════════════════════════════════════════════════════════════════

class PageLivraisonSecurisee extends StatefulWidget {
  final String sousCommandeId;
  final String livreurId;

  const PageLivraisonSecurisee({
    super.key,
    required this.sousCommandeId,
    required this.livreurId,
  });

  @override
  State<PageLivraisonSecurisee> createState() => _PageLivraisonSecuriseeState();
}

class _PageLivraisonSecuriseeState extends State<PageLivraisonSecurisee> {
  SousCommande? _sc;
  bool _chargement = true;
  Timer? _gpsTimer;
  String? _livraisonIdReelle;
  String _destination = '—';

  // Photos prises
  XFile? _photoColisRecu;
  XFile? _photoColisScelle;
  XFile? _photoRemise;
  bool _etape1OK = false; // prise en charge + photos
  double? _destLat;
  double? _destLng;
  bool _etape2OK = false; // livraison + photo remise

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final doc = await SousCommande.collection.doc(widget.sousCommandeId).get();
    // Récupérer la Livraison réelle liée à cette sous-commande
    try {
      final snap = await FirebaseFirestore.instance
          .collection('livraisons')
          .where('commandeId', isEqualTo: widget.sousCommandeId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        _livraisonIdReelle = snap.docs.first.id;
        // AVANCEMENT DERIVE DU REEL : quitter/rouvrir ne fait plus
        // oublier une prise en charge deja validee.
        final stLiv = snap.docs.first.data()['statut'] as String? ?? '';
        if (['recuperee', 'enRoute', 'enLivraison', 'livree']
            .contains(stLiv)) {
          _etape1OK = true;
        }
        if (stLiv == 'livree') _etape2OK = true;
        _destLat = (snap.docs.first.data()['destinationLat'] as num?)
            ?.toDouble();
        _destLng = (snap.docs.first.data()['destinationLng'] as num?)
            ?.toDouble();
        _destination = snap.docs.first.data()['destinationAdresse']
                as String? ??
            snap.docs.first.data()['adresseArrivee'] as String? ??
            '—';
        _demarrerSuiviGPS();
      }
    } catch (_) {}
    if (mounted) setState(() {
      _sc = SousCommande.fromDoc(doc);
      _chargement = false;
    });
  }

  /// Envoie la position GPS du livreur toutes les 30s (suivi temps réel client).
  void _demarrerSuiviGPS() {
    final location = Location();
    _gpsTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_livraisonIdReelle == null) return;
      try {
        final pos = await location.getLocation();
        if (pos.latitude == null || pos.longitude == null) return;
        await LivraisonService.mettreAJourPositionLivreur(
          livraisonId: _livraisonIdReelle!,
          livreurId: widget.livreurId,
          latitude: pos.latitude!,
          longitude: pos.longitude!,
        );
      } catch (_) {
        // hors ligne ou GPS indisponible → on réessaiera au prochain tick
      }
    });
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) return const Scaffold(body: Center(child: CircularProgressIndicator(color: _kPrimary)));
    if (_sc == null) return Scaffold(body: Center(child: Text(Tr.s.livraisonIntrouvable)));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(Tr.s.livraisonSecurisee),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Résumé commande
          _CardResume(sc: _sc!, destination: _destination),
          const SizedBox(height: 20),

          // Étape 1 : Prise en charge en boutique
          _EtapeCard(
            numero: 1,
            titre: Tr.s.priseChargeBoutique,
            sousTitre: Tr.s.scannezQrPrenezPhotosRequises,
            terminee: _etape1OK,
            child: Column(children: [
              // Photo du colis reçu
              _BoutonPhoto(
                label: Tr.s.photoColisRecu,
                obligatoire: true,
                photo: _photoColisRecu,
                icone: Icons.inventory_2_outlined,
                onPrendre: () => _prendrePhoto('colis_recu'),
              ),
              const SizedBox(height: 10),
              // Photo du scellé
              _BoutonPhoto(
                label: Tr.s.photoScelleIntact,
                obligatoire: true,
                photo: _photoColisScelle,
                icone: Icons.lock_outline,
                conseil: 'Le scellé prouve que le colis n\'a pas été ouvert',
                onPrendre: () => _prendrePhoto('scelle'),
              ),
              const SizedBox(height: 16),
              // Bouton confirmer prise en charge
              ElevatedButton.icon(
                onPressed: _photoColisRecu != null && _photoColisScelle != null
                    ? _confirmerPriseEnCharge
                    : null,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(Tr.s.confirmerPriseCharge),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_photoColisRecu == null || _photoColisScelle == null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(Tr.s.k2PhotosSontObligatoiresAvant,
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
            ]),
          ),
          const SizedBox(height: 14),

          // ═══ ITINÉRAIRE : dès la prise en charge, LA ROUTE ═══
          if (_etape1OK && !_etape2OK)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _ouvrirItineraire,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(Tr.s.ouvrirItineraireVersClient),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6A1B9A),
                      side: const BorderSide(color: Color(0xFF6A1B9A)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ),
          // Étape 2 : Remise au client
          _EtapeCard(
            numero: 2,
            titre: Tr.s.remiseClient,
            sousTitre: Tr.s.photoObligatoireAvantRemettreColis,
            terminee: _etape2OK,
            desactivee: !_etape1OK,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    Tr.s.photographiezColisAvecRepereLieu,
                    style: TextStyle(color: Colors.blue, fontSize: 12, height: 1.4),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              _BoutonPhoto(
                label: Tr.s.photoRemiseClient,
                obligatoire: true,
                photo: _photoRemise,
                icone: Icons.person_outline,
                conseil: 'Le COLIS devant le portail / point de repère du client — inutile de photographier son visage.',
                onPrendre: () => _prendrePhoto('remise'),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _photoRemise != null ? _confirmerRemise : null,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(Tr.s.confirmerLivraison),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kSuccess, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),

          if (_etape2OK) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kSuccess, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Tr.s.livraisonConfirmee, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(Tr.s.votreGainSeraVerseSous, style: TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _faireSignerClient,
              icon: const Icon(Icons.draw_outlined, size: 18),
              label: Text(Tr.s.ajouterSignatureClientOptionnel),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kSuccess,
                  side: const BorderSide(color: _kSuccess),
                  minimumSize: const Size(double.infinity, 44)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _prendrePhoto(String type) async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null || !mounted) return;
    final file = photo; // XFile : compatible web/iOS/Android
    setState(() {
      switch (type) {
        case 'colis_recu': _photoColisRecu = file; break;
        case 'scelle': _photoColisScelle = file; break;
        case 'remise': _photoRemise = file; break;
      }
    });
  }



  /// Signature du client APRÈS validation — preuve complémentaire,
  /// jamais un verrou : le scan a déjà tout validé.
  Future<void> _faireSignerClient() async {
    final ctrl = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Tr.s.signatureClient,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Container(
            height: 180,
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10)),
            child: Signature(
                controller: ctrl, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
                onPressed: () => ctrl.clear(),
                child: Text(Tr.s.effacer)),
            const Spacer(),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(Tr.s.enregistrer)),
          ]),
        ]),
      ),
    );
    if (ok != true || ctrl.isEmpty) return;
    String b64 = '';
    try {
      final bytes = await ctrl.toPngBytes();
      if (bytes != null) b64 = base64Encode(bytes);
    } catch (_) {}
    if (b64.isEmpty) return;
    try {
      await LivraisonService.validerParSignature(
        livraisonId: _livraisonIdReelle ?? '',
        signatureBase64: b64,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(Tr.s.signatureEnregistree),
            backgroundColor: Colors.green));
      }
    } catch (_) {}
  }

  Future<void> _ouvrirItineraire() async {
    double? la = _destLat, ln = _destLng;
    if (la == null || ln == null) {
      final m = RegExp(r'([0-9]+[.][0-9]+)[ ]*,[ ]*([0-9]+[.][0-9]+)')
          .firstMatch(_destination);
      la = double.tryParse(m?.group(1) ?? '');
      ln = double.tryParse(m?.group(2) ?? '');
    }
    if (la == null || ln == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(Tr.s.coordonneesIndisponiblesSuivezAdresseTexte)));
      }
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$la,$ln&travelmode=driving');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Tr.s.destination(la, ln))));
      }
    }
  }

  Future<void> _confirmerPriseEnCharge() async {
    if (_photoColisRecu == null || _photoColisScelle == null) return;
    if (_livraisonIdReelle == null || _livraisonIdReelle!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              Tr.s.livraisonIntrouvablePourCetteCommande),
          backgroundColor: Colors.orange));
      return;
    }
    try {
      // Upload photos avec géolocalisation
      await SecuriteLivraisonService.enregistrerPreuvePhoto(
        livreurId: widget.livreurId,
        livraisonId: _livraisonIdReelle ?? '',
        sousCommandeId: widget.sousCommandeId,
        type: TypePreuvePhoto.colisRecuEnBoutique,
        photoFile: _photoColisRecu!,
      );
      await SecuriteLivraisonService.enregistrerPreuvePhoto(
        livreurId: widget.livreurId,
        livraisonId: _livraisonIdReelle ?? '',
        sousCommandeId: widget.sousCommandeId,
        type: TypePreuvePhoto.colisScelle,
        photoFile: _photoColisScelle!,
      );
      // Scan QR de DÉPART (boutiquier confirme la remise au livreur)
      // → fait passer la livraison à 'enLivraison' + enregistre la position
      final livraisonId = _livraisonIdReelle ?? '';
      bool scanOk = false;
      if (mounted && livraisonId.isNotEmpty) {
        scanOk = await Navigator.push<bool>(context, MaterialPageRoute(
              builder: (_) => PageScanQR(
                livraisonId: livraisonId,
                typeAttendu: TypeQR.depart,
                role: RoleLivraison.livreur,
                livreurId: widget.livreurId,
                onSucces: () {},
              ),
            )) ??
            false;
      }
      // L'ÉTAPE NE SE COCHE QUE SUR SCAN RÉUSSI — un échec (QR expiré,
      // mauvais code) laisse l'étape ouverte au lieu de mentir.
      if (mounted && scanOk) setState(() => _etape1OK = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Tr.s.erreurUpload(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmerRemise() async {
    if (_photoRemise == null) return;
    try {
      await SecuriteLivraisonService.enregistrerPreuvePhoto(
        livreurId: widget.livreurId,
        livraisonId: _livraisonIdReelle ?? '',
        sousCommandeId: widget.sousCommandeId,
        type: TypePreuvePhoto.remiseAuClient,
        photoFile: _photoRemise!,
      );
      // Scan QR d'ARRIVÉE (le client scanne pour confirmer la réception)
      // → fait passer la livraison à 'livre' + sous-commande 'terminee'
      final livraisonId = _livraisonIdReelle ?? '';
      bool scanOk = false;
      if (mounted && livraisonId.isNotEmpty) {
        scanOk = await Navigator.push<bool>(context, MaterialPageRoute(
              builder: (_) => PageScanQR(
                livraisonId: livraisonId,
                typeAttendu: TypeQR.arrivee,
                role: RoleLivraison.client,
                livreurId: widget.livreurId,
                onSucces: () {},
              ),
            )) ??
            false;
      }
      if (mounted && scanOk) setState(() => _etape2OK = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Tr.s.erreur2(e)), backgroundColor: Colors.red));
    }
  }
}

// ── Carte profil public livreur (visible par le client) ───────────────────────

class CardProfilLivreur extends StatelessWidget {
  final ProfilPublicLivreur profil;
  const CardProfilLivreur({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Tr.s.votreLivreur, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 12),
        Row(children: [
          // Photo livreur
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.purple.shade50,
            backgroundImage: providerUniversel(profil.photo),
            child: profil.photo.isEmpty
                ? const Icon(Icons.delivery_dining, color: _kPrimary, size: 28) : null,
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(profil.nom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 8),
              if (profil.cniVerifiee) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified, color: Colors.green.shade700, size: 12),
                  const SizedBox(width: 2),
                  Text(Tr.s.cniVerifiee, style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            Text(profil.badgeNiveau, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
        ]),
        const SizedBox(height: 12),

        // Stats
        Row(children: [
          _Stat(icone: Icons.star, valeur: profil.noteMoyenne.toStringAsFixed(1), label: Tr.s.note, couleur: Colors.amber),
          _Stat(icone: Icons.check_circle_outline, valeur: '${profil.nombreLivraisons}', label: Tr.s.livraisons, couleur: _kPrimary),
          _Stat(icone: Icons.percent, valeur: '${profil.tauxReussite.round()}%', label: Tr.s.reussite, couleur: _kSuccess),
        ]),

        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),

        // Garanties de sécurité
        Text(Tr.s.garantiesSecuriteSami, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        _Garantie(Icons.badge_outlined, Tr.s.identiteVerifieeParNotreEquipe, profil.cniVerifiee),
        _Garantie(Icons.camera_alt_outlined, Tr.s.photoColisChaqueEtape, true),
        _Garantie(Icons.location_on_outlined, Tr.s.trajetGpsEnregistre, true),
        _Garantie(Icons.account_balance_wallet_outlined,
            Tr.s.cautionDeposee(profil.montantCautionFmt), true),

        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              Tr.s.casProblemeSignalezImmediatementVia,
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800, height: 1.4),
            )),
          ]),
        ),
      ]),
    );
  }
}

// ── Widgets internes ──────────────────────────────────────────────────────────

class _CardResume extends StatelessWidget {
  final SousCommande sc;
  final String destination; // fournie par l'état (livraison réelle)
  const _CardResume({required this.sc, this.destination = '—'});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Tr.s.commandeBoutique(sc.boutiqueNom),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      ...sc.articles.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: 52, height: 52,
                  child: a.pagneImage != null
                      ? ImageUniverselle(
                          source: a.pagneImage!, fit: BoxFit.cover)
                      : Container(
                          color: Colors.purple.shade50,
                          child:
                              const Icon(Icons.checkroom, size: 14)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('${a.pagneNom} × ${a.quantite}',
                      style: const TextStyle(fontSize: 12.5))),
            ]),
          )),
      const SizedBox(height: 6),
      Text(Tr.s.destination2(destination),
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
  );
}

class _EtapeCard extends StatelessWidget {
  final int numero;
  final String titre;
  final String sousTitre;
  final bool terminee;
  final bool desactivee;
  final Widget child;

  const _EtapeCard({required this.numero, required this.titre, required this.sousTitre,
    this.terminee = false, this.desactivee = false, required this.child});

  @override
  Widget build(BuildContext context) {
    final couleur = terminee ? _kSuccess : (desactivee ? Colors.grey : _kPrimary);
    return Opacity(
      opacity: desactivee ? 0.4 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: terminee ? _kSuccess : Colors.grey.shade200, width: terminee ? 2 : 1),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: couleur.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
                child: Center(child: terminee
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text('$numero', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: couleur)),
                Text(sousTitre, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
              if (terminee) Icon(Icons.check_circle, color: _kSuccess, size: 20),
            ]),
          ),
          if (!terminee) Padding(padding: const EdgeInsets.all(14), child: child),
        ]),
      ),
    );
  }
}

class _BoutonPhoto extends StatelessWidget {
  final String label;
  final bool obligatoire;
  final XFile? photo;
  final IconData icone;
  final String? conseil;
  final VoidCallback onPrendre;

  const _BoutonPhoto({required this.label, required this.obligatoire,
    this.photo, required this.icone, this.conseil, required this.onPrendre});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onPrendre,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: photo != null ? _kSuccess.withOpacity(0.06) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: photo != null ? _kSuccess : (obligatoire ? Colors.orange.shade300 : Colors.grey.shade300),
          width: photo != null ? 2 : 1,
        ),
      ),
      child: Row(children: [
        // Aperçu ou icône
        Container(width: 52, height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: photo != null ? null : Colors.grey.shade200,
          ),
          child: photo != null
              ? ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: ImageXFile(photo!, fit: BoxFit.cover))
              : Icon(icone, color: Colors.grey.shade400, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: photo != null ? _kSuccess : Colors.black87)),
            if (obligatoire) Text(' *', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold)),
          ]),
          if (conseil != null) Text(conseil!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (photo != null) Text(Tr.s.photoPrise, style: TextStyle(fontSize: 11, color: _kSuccess, fontWeight: FontWeight.w500)),
        ])),
        Icon(
          photo != null ? Icons.check_circle : Icons.camera_alt_outlined,
          color: photo != null ? _kSuccess : Colors.grey.shade400,
          size: 22,
        ),
      ]),
    ),
  );
}

class _Stat extends StatelessWidget {
  final IconData icone;
  final String valeur;
  final String label;
  final Color couleur;
  const _Stat({required this.icone, required this.valeur, required this.label, required this.couleur});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Icon(icone, color: couleur, size: 18),
    const SizedBox(height: 2),
    Text(valeur, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: couleur)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]));
}

class _Garantie extends StatelessWidget {
  final IconData icone;
  final String texte;
  final bool active;
  const _Garantie(this.icone, this.texte, this.active);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Icon(icone, color: active ? _kSuccess : Colors.grey, size: 15),
      const SizedBox(width: 6),
      Expanded(child: Text(texte, style: TextStyle(fontSize: 12,
          color: active ? Colors.black87 : Colors.grey))),
      if (active) Icon(Icons.check, color: _kSuccess, size: 12),
    ]),
  );
}
