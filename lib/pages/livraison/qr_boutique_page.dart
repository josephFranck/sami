import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sami/services/qr_crypto_service.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// Affiche le QR de DÉPART d'une livraison, à présenter au livreur.
/// Utile même si le téléphone du boutiquier est limité : le QR peut être
/// montré à l'écran OU imprimé et collé sur le colis.
/// Précharge aussi le token côté boutique (résilience hors-ligne).
class QrBoutiquePage extends StatefulWidget {
  final String livraisonId;
  final String? referenceCommande;
  const QrBoutiquePage({
    super.key,
    required this.livraisonId,
    this.referenceCommande,
  });

  @override
  State<QrBoutiquePage> createState() => _QrBoutiquePageState();
}

class _QrBoutiquePageState extends State<QrBoutiquePage> {
  String? _qrDepart;
  String? _codeCourt;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    // Précharge le token de départ côté boutique (pour affichage hors-ligne)
    await QRCryptoService.prechargerDepuisFirestore(
      livraisonId: widget.livraisonId,
      role: RoleLivraison.boutique,
    );
    // Récupère le token de départ + dérive le code court de secours
    try {
      final doc = await FirebaseFirestore.instance
          .collection('qr_secrets')
          .doc(widget.livraisonId)
          .get();
      final data = doc.data();
      if (data != null) {
        final cle = data['cle'] as String?;
        // TOKEN FRAIS : régénéré à CHAQUE ouverture (48 h repartent) —
        // l'ancien, figé à la création de la commande, expirait à tort.
        if (cle != null) {
          final frais = QRCryptoService.genererQRDepart(
            livraisonId: widget.livraisonId,
            cleSecrete: cle,
          );
          _qrDepart = frais.toQRString();
          // réécrit pour que le scan offline du livreur reste cohérent
          await doc.reference
              .set({'qrDepart': _qrDepart}, SetOptions(merge: true));
        } else {
          _qrDepart = data['qrDepart'] as String?;
        }
        if (cle != null) {
          _codeCourt = QRCryptoService.genererCodeCourt(
            livraisonId: widget.livraisonId,
            cleSecrete: cle,
          );
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _chargement = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('QR de remise au livreur'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _contenu(),
    );
  }

  Widget _contenu() {
    if (_qrDepart == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'QR indisponible. Vérifiez la connexion une première fois '
              'pour le télécharger, il restera ensuite accessible hors-ligne.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (widget.referenceCommande != null)
            Text('Commande ${widget.referenceCommande}',
                style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          const Text('Montrez ce code au livreur',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Il le scanne pour confirmer la prise en charge du colis.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          // Le QR lui-même
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: QrImageView(
              data: _qrDepart!,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          // Code court de secours (si le scan échoue ou téléphone livreur limité)
          if (_codeCourt != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('Code de secours',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(_codeCourt!,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                          color: _kPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
                'Si le scan ne marche pas, dictez ce code au livreur.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          Text(
              'Astuce : vous pouvez imprimer cet écran et coller le QR sur le '
              'colis. Le livreur pourra le scanner même sans votre téléphone.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
