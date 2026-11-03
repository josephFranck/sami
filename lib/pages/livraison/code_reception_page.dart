import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/services/sms_service.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// Code de réception du CLIENT : le QR d'arrivée + le code court à présenter
/// au livreur pour confirmer la réception. Fonctionne hors-ligne (préchargé).
class CodeReceptionPage extends StatefulWidget {
  final String livraisonId;
  final String? telephoneClient;
  const CodeReceptionPage({
    super.key,
    required this.livraisonId,
    this.telephoneClient,
  });

  @override
  State<CodeReceptionPage> createState() => _CodeReceptionPageState();
}

class _CodeReceptionPageState extends State<CodeReceptionPage> {
  String? _qrArrivee;
  String? _codeCourt;
  bool _chargement = true;
  bool _envoiSms = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    await QRCryptoService.prechargerDepuisFirestore(
      livraisonId: widget.livraisonId,
      role: RoleLivraison.client,
    );
    try {
      final doc = await FirebaseFirestore.instance
          .collection('qr_secrets')
          .doc(widget.livraisonId)
          .get();
      final data = doc.data();
      if (data != null) {
        final cle = data['cle'] as String?;
        // ═══ TOKEN FRAIS ═══ régénéré à CHAQUE ouverture, type
        // 'arrivee' garanti (l'ancien, figé à la création, expirait
        // — et un token périmé ressemble à n'importe quel autre).
        if (cle != null) {
          final frais = QRCryptoService.genererQRArrivee(
            livraisonId: widget.livraisonId,
            cleSecrete: cle,
          );
          _qrArrivee = frais.toQRString();
          await doc.reference
              .set({'qrArrivee': _qrArrivee}, SetOptions(merge: true));
        } else {
          _qrArrivee = data['qrArrivee'] as String?;
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

  Future<void> _envoyerParSms() async {
    if (_codeCourt == null || widget.telephoneClient == null) return;
    setState(() => _envoiSms = true);
    final ok = await SmsService.envoyerCodeLivraison(
      telephone: widget.telephoneClient!,
      code: _codeCourt!,
    );
    if (mounted) {
      setState(() => _envoiSms = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Code envoyé par SMS'
            : 'SMS indisponible (le code reste affiché ici)'),
        backgroundColor: ok ? Colors.green : Colors.orange,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mon code de réception'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('Présentez ce code au livreur',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('À la réception de votre colis.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 24),
                  if (_qrArrivee != null)
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
                        data: _qrArrivee!,
                        version: QrVersions.auto,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (_codeCourt != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
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
                        'Si votre téléphone est éteint à la livraison, '
                        'communiquez simplement ce code au livreur.',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    if (widget.telephoneClient != null)
                      OutlinedButton.icon(
                        onPressed: _envoiSms ? null : _envoyerParSms,
                        icon: _envoiSms
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kPrimary))
                            : const Icon(Icons.sms_outlined, size: 16),
                        label: const Text('Recevoir le code par SMS'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _kPrimary,
                            side: const BorderSide(color: _kPrimary)),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
