import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:location/location.dart';
import 'package:sami/pages/livraison/livraison_securisee_page.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/services/livraison_service.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// SCAN-D'ABORD : le livreur scanne un QR SANS avoir sélectionné de course.
/// L'app décode l'ID de livraison contenu dans le QR, retrouve la course, et
/// vérifie que le livreur courant y est bien impliqué avant de valider.
/// Plus fluide : pas besoin d'ouvrir la bonne livraison à la main.
class ScanRapidePage extends StatefulWidget {
  const ScanRapidePage({super.key});

  @override
  State<ScanRapidePage> createState() => _ScanRapidePageState();
}

class _ScanRapidePageState extends State<ScanRapidePage> {
  final _ctrl = MobileScannerController();
  bool _traitement = false;
  String? _message;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_traitement) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    setState(() {
      _traitement = true;
      _message = 'Recherche de la course…';
    });

    final uid = _uid;
    if (uid == null) {
      setState(() {
        _message = 'Non connecté';
        _traitement = false;
      });
      return;
    }

    // Décoder le QR, retrouver la livraison, vérifier que ce livreur est l'acteur
    final liv = await LivraisonService.resoudreLivraisonDepuisQR(
      qrScanne: code,
      compteId: uid,
      roleAttendu: RoleLivraison.livreur,
    );

    if (liv == null) {
      setState(() {
        _message = 'QR non reconnu ou course non assignée à vous';
        _traitement = false;
      });
      return;
    }

    // Déterminer s'il s'agit du départ ou de l'arrivée selon le statut
    final estDepart = liv.statut == StatutLivraison.enAttente ||
        liv.statut == StatutLivraison.livreurAssigne ||
        liv.statut == StatutLivraison.enRouteOrigine;
    // GARDE PÉDAGOGIQUE : le TYPE du token scanné doit correspondre à
    // l'étape attendue — scanner le QR de DÉPART après la prise en
    // charge n'est pas une erreur mystère, c'est un mauvais code.
    final tokenType =
        code.split('|').length > 1 ? code.split('|')[1] : '';
    if (!estDepart && tokenType == 'depart') {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Tr.s.colisDejaPrisCharge),
          content: Text(
              Tr.s.ceQrEstCeluiDepart),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(Tr.s.compris)),
          ],
        ),
      );
      if (mounted) setState(() => _traitement = false);
      return;
    }

    if (!mounted) return;
    // Confirmer la course trouvée avant de valider
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Tr.s.courseTrouvee),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Tr.s.destination3(liv.destinationAdresse)),
            const SizedBox(height: 6),
            Text(estDepart
                ? Tr.s.actionPriseChargeColis
                : Tr.s.actionRemiseDestinataire),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Tr.s.annuler)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Tr.s.confirmer),
          ),
        ],
      ),
    );

    if (ok != true) {
      setState(() {
        _message = null;
        _traitement = false;
      });
      return;
    }

    // Position GPS au moment du scan (requise pour la récupération)
    double lat = 0, lng = 0;
    try {
      final pos = await Location().getLocation();
      lat = pos.latitude ?? 0;
      lng = pos.longitude ?? 0;
    } catch (_) {}

    // Valider directement avec le code déjà scanné
    bool valide = false;
    try {
      if (estDepart) {
        valide = await LivraisonService.validerRecuperationQR(
          livraisonId: liv.id,
          livreurId: uid,
          codeScanne: code,
          livreurLat: lat,
          livreurLng: lng,
        );
      } else {
        final res = await LivraisonService.validerLivraisonQR(
          livraisonId: liv.id,
          clientId: '',
          codeScanne: code,
          modeUtilise: ModeValidation.qrCode,
          clientLat: lat,
          clientLng: lng,
        );
        valide = res.succes;
      }
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(valide ? Tr.s.validationReussie2 : Tr.s.echecValidation),
      backgroundColor: valide ? Colors.green : Colors.red,
    ));
    if (valide) {
      // REDIRECTION : le livreur atterrit sur SA page de mission
      // (photos, étapes, GPS) — le scan est la porte, pas la fin.
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => PageLivraisonSecurisee(
                    sousCommandeId: liv.commandeId,
                    livreurId:
                        FirebaseAuth.instance.currentUser?.uid ?? '',
                  )));
    } else {
      setState(() {
        _message = 'Échec — réessayez ou utilisez le scan classique';
        _traitement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(Tr.s.scanRapide),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _kPrimary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Text(
                _message ??
                    Tr.s.scannezQrCourseSeraRetrouvee,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_traitement)
            Container(
              color: Colors.black45,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
