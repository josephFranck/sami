import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sami/services/livraison_service.dart';
import 'package:location/location.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/services/resilience_service.dart';
import 'package:sami/widgets/widgets_resilients.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kSuccess = Color(0xFF1D9E75);
const _kError   = Color(0xFFE24B4A);

// ═══════════════════════════════════════════════════════════════════════════
// PAGE DE SCAN QR — 100% offline-first
//
// Flux :
//   1. Charger la clé secrète depuis SharedPreferences (disponible hors ligne)
//   2. Ouvrir la caméra et scanner
//   3. Valider cryptographiquement LOCALEMENT (HMAC-SHA256)
//   4. Si valide → afficher succès immédiatement (UX fluide)
//   5. Mettre l'action en file offline → sync Firestore au retour réseau
//   6. Si clé absente localement → mode OTP SMS de secours
// ═══════════════════════════════════════════════════════════════════════════

class PageScanQR extends StatefulWidget {
  final String livraisonId;
  final TypeQR typeAttendu;       // départ ou arrivée
  final RoleLivraison role;       // boutiquier, livreur ou client
  final String? livreurId;        // rempli si role == livreur
  final VoidCallback? onSucces;

  const PageScanQR({
    super.key,
    required this.livraisonId,
    required this.typeAttendu,
    required this.role,
    this.livreurId,
    this.onSucces,
  });

  @override
  State<PageScanQR> createState() => _PageScanQRState();
}

class _PageScanQRState extends State<PageScanQR> with ActionResiliante {
  final _scannerCtrl = MobileScannerController();

  QRLocalData? _donneesLocales;
  bool _chargement = true;
  bool _traitementEnCours = false;

  // Résultat du scan
  ResultatValidationQR? _resultat;
  String _codeScanne = '';
  bool _valide = false;
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    _chargerCleLocale();
  }

  Future<void> _chargerCleLocale() async {
    final donnees = await QRCryptoService.chargerLocal(widget.livraisonId);
    if (mounted) setState(() { _donneesLocales = donnees; _chargement = false; });
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.typeAttendu == TypeQR.depart
              ? Tr.s.scannerBoutique
              : Tr.s.scannerPourConfirmer,
        ),
        actions: [
          // Indicateur offline
          StreamBuilder<bool>(
            stream: ConnectiviteService.instance.stream,
            builder: (_, snap) {
              final connecte = snap.data ?? ConnectiviteService.instance.estConnecte;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  connecte ? Icons.wifi : Icons.wifi_off,
                  color: connecte ? Colors.green : Colors.orange,
                  size: 20,
                ),
              );
            },
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _donneesLocales == null
              ? _buildModeDegradeSansCle()
              : _buildScanner(),
    );
  }

  // ── Scanner principal ──────────────────────────────────────────────────

  Widget _buildScanner() {
    if (_valide) return _buildSucces();
    if (_erreur && _resultat != null) return _buildErreur(_resultat!);

    return Stack(
      children: [
        // Caméra
        MobileScanner(
          controller: _scannerCtrl,
          onDetect: _onQRDetecte,
        ),

        // Overlay viseur
        _buildViseur(),

        // Instructions en bas
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              children: [
                Text(
                  widget.typeAttendu == TypeQR.depart
                      ? Tr.s.scannezQrCodeAfficheBoutique
                      : Tr.s.scannezCodeClientSurSon,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Indicateur offline avec explication
                StreamBuilder<bool>(
                  stream: ConnectiviteService.instance.stream,
                  builder: (_, snap) {
                    final connecte = snap.data ?? ConnectiviteService.instance.estConnecte;
                    if (connecte) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange, size: 14),
                          SizedBox(width: 8),
                          Text(
                            Tr.s.modeHorsLigneValidationLocale,
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Bouton code court de secours
                TextButton.icon(
                  onPressed: _afficherSaisieManuelle,
                  icon: const Icon(Icons.keyboard, color: Colors.white60, size: 16),
                  label: Text(
                    Tr.s.saisirCodeManuellement,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                // Signature (dernier recours, seulement à l'arrivée client)
                if (widget.typeAttendu == TypeQR.arrivee)
                  TextButton.icon(
                    onPressed: _afficherSignature,
                    icon: const Icon(Icons.draw_outlined,
                        color: Colors.white60, size: 16),
                    label: Text(
                      Tr.s.faireSignerClient,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Spinner pendant traitement
        if (_traitementEnCours)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }

  // ── Traitement du QR scanné ────────────────────────────────────────────

  void _onQRDetecte(BarcodeCapture capture) {
    if (_traitementEnCours || _valide) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    _traiterCode(code);
  }

  Future<void> _traiterCode(String code) async {
    if (_traitementEnCours) return;
    _codeScanne = code;
    setState(() => _traitementEnCours = true);
    await _scannerCtrl.stop();

    // Validation cryptographique LOCALE — pas de réseau nécessaire
    final resultat = QRCryptoService.validerOffline(
      qrScanne: code,
      cleSecreteLocale: _donneesLocales!.cleSecrete,
      livraisonIdAttendu: widget.livraisonId,
      typeAttendu: widget.typeAttendu,
    );

    if (resultat.valide) {
      // ✅ VALIDE — afficher succès IMMÉDIATEMENT
      setState(() { _valide = true; _resultat = resultat; _traitementEnCours = false; });

      // Puis synchroniser avec Firestore en arrière-plan (offline si nécessaire)
      await _syncFirestore();
    } else {
      // ❌ INVALIDE
      setState(() { _erreur = true; _resultat = resultat; _traitementEnCours = false; });
    }
  }

  /// Synchronisation Firestore après validation locale réussie.
  /// Appelle les méthodes qui font RÉELLEMENT avancer le statut de la livraison,
  /// avec la position GPS au moment du scan (preuve de présence sur place).
  Future<void> _syncFirestore() async {
    final code = _codeScanne;

    // Position GPS au moment du scan (best effort)
    double lat = 0, lng = 0;
    try {
      final pos = await Location().getLocation();
      lat = pos.latitude ?? 0;
      lng = pos.longitude ?? 0;
    } catch (_) {}

    final payload = {
      'livraisonId': widget.livraisonId,
      'type': widget.typeAttendu.name,
      'livreurId': widget.livreurId ?? '',
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await executerAvecResilience(
      action: () async {
        if (widget.typeAttendu == TypeQR.depart) {
          // Récupération à la boutique : livraison → enLivraison
          await LivraisonService.validerRecuperationQR(
            livraisonId: widget.livraisonId,
            livreurId: widget.livreurId ?? '',
            codeScanne: code,
            livreurLat: lat,
            livreurLng: lng,
          );
        } else {
          // Remise au client : livraison → livre (+ sous-commande terminée)
          await LivraisonService.validerLivraisonQR(
            livraisonId: widget.livraisonId,
            clientId: '',
            codeScanne: code,
            modeUtilise: ModeValidation.qrCode,
            clientLat: lat,
            clientLng: lng,
          );
        }
      },
      typeOffline: widget.typeAttendu == TypeQR.depart
          ? TypeActionOffline.scanQR
          : TypeActionOffline.confirmerLivraison,
      payloadOffline: payload,
    );
  }

  // ── Widgets d'état ─────────────────────────────────────────────────────

  Widget _buildSucces() => Container(
    color: _kSuccess,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: const Icon(Icons.check_circle, color: Colors.white, size: 100),
          ),
          const SizedBox(height: 24),
          Text(
            Tr.s.validationReussie,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Afficher si online ou offline
          StreamBuilder<bool>(
            stream: ConnectiviteService.instance.stream,
            builder: (_, snap) {
              final connecte = snap.data ?? ConnectiviteService.instance.estConnecte;
              return Text(
                connecte ? Tr.s.synchroniseAvecServeur : Tr.s.enregistreLocalementSyncAttente,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                ),
              );
            },
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              widget.onSucces?.call();
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _kSuccess,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            child: Text(Tr.s.continuer, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );

  Widget _buildErreur(ResultatValidationQR r) => Container(
    color: Colors.black,
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: _kError, size: 72),
          const SizedBox(height: 20),
          Text(
            r.message,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _conseilSelon(r.raison),
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() { _erreur = false; _resultat = null; });
                  _scannerCtrl.start();
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(Tr.s.reessayer, style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: _afficherSaisieManuelle,
                icon: const Icon(Icons.keyboard, color: Colors.orange),
                label: Text(Tr.s.codeManuel, style: TextStyle(color: Colors.orange)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _conseilSelon(RaisonEchec? raison) => switch (raison) {
    RaisonEchec.mauvaiseLivraison => Tr.s.ceQrAppartientAutreLivraison,
    RaisonEchec.mauvaistType => widget.typeAttendu == TypeQR.depart
        ? Tr.s.demandezBoutiqueAfficherBonQr
        : Tr.s.demandezLivreurAfficherQrLivraison,
    RaisonEchec.expire => Tr.s.contactezSupportLivraisonPeutEtre,
    RaisonEchec.signatureInvalide => Tr.s.qrFalsifieOuCorrompuContactez,
    _ => Tr.s.assurezVousQueCameraLit,
  };

  // ── Mode dégradé : clé absente ─────────────────────────────────────────

  Widget _buildModeDegradeSansCle() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, color: Colors.white60, size: 64),
        const SizedBox(height: 20),
        Text(
          Tr.s.donneesLivraisonNonTrouvees,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          ConnectiviteService.instance.estConnecte
              ? Tr.s.rechargezPagePourRecupererDonnees
              : Tr.s.pasConnexionUtilisezCodeSms,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (!ConnectiviteService.instance.estConnecte)
          _SaisieCodeManuel(
            livraisonId: widget.livraisonId,
            typeAttendu: widget.typeAttendu,
            onSucces: widget.onSucces,
          ),
      ],
    ),
  );

  // ── Saisie manuelle (code court) ───────────────────────────────────────

  void _afficherSaisieManuelle() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _SaisieCodeManuel(
          livraisonId: widget.livraisonId,
          typeAttendu: widget.typeAttendu,
          cleSecrete: _donneesLocales?.cleSecrete,
          onSucces: () {
            Navigator.pop(context); // fermer le bottom sheet
            setState(() => _valide = true);
            widget.onSucces?.call();
          },
        ),
      ),
    );
  }

  void _afficherSignature() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _CaptureSignature(
          livraisonId: widget.livraisonId,
          onSucces: () {
            Navigator.pop(context);
            setState(() => _valide = true);
            widget.onSucces?.call();
          },
        ),
      ),
    );
  }

  Widget _buildViseur() => Center(
    child: Container(
      width: 250, height: 250,
      decoration: BoxDecoration(
        border: Border.all(color: _kPrimary, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Coins stylisés
          ..._buildCoins(),
        ],
      ),
    ),
  );

  List<Widget> _buildCoins() {
    const taille = 24.0;
    const ep = 4.0;
    return [
      Positioned(top: 0, left: 0, child: _coin(taille, ep, top: true, left: true)),
      Positioned(top: 0, right: 0, child: _coin(taille, ep, top: true, left: false)),
      Positioned(bottom: 0, left: 0, child: _coin(taille, ep, top: false, left: true)),
      Positioned(bottom: 0, right: 0, child: _coin(taille, ep, top: false, left: false)),
    ];
  }

  Widget _coin(double t, double ep, {required bool top, required bool left}) => SizedBox(
    width: t, height: t,
    child: CustomPaint(painter: _CoinPainter(top: top, left: left, ep: ep)),
  );
}

// ─── Saisie de code court (OTP ou code alphanumérique) ───────────────────────

class _SaisieCodeManuel extends StatefulWidget {
  final String livraisonId;
  final TypeQR typeAttendu;
  final String? cleSecrete;
  final VoidCallback? onSucces;

  const _SaisieCodeManuel({
    required this.livraisonId,
    required this.typeAttendu,
    this.cleSecrete,
    this.onSucces,
  });

  @override
  State<_SaisieCodeManuel> createState() => _SaisieCodeManuelState();
}

class _SaisieCodeManuelState extends State<_SaisieCodeManuel> with ActionResiliante {
  final _ctrl = TextEditingController();
  bool _enCours = false;
  String? _messageErreur;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(Tr.s.saisirCodeReception,
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(
        widget.typeAttendu == TypeQR.depart
            ? Tr.s.code6ChiffresAfficheBoutique
            : Tr.s.code6ChiffresCommuniquePar,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: 6,
        ),
        decoration: InputDecoration(
          hintText: '000000',
          hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white30),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _kPrimary.withOpacity(0.8)),
          ),
          errorText: _messageErreur,
          errorStyle: const TextStyle(color: Colors.redAccent),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _enCours ? null : _valider,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _enCours
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              : Text(Tr.s.valider, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ],
  );

  Future<void> _valider() async {
    final code = _ctrl.text.trim();
    if (code.length < 6) {
      setState(() => _messageErreur = 'Code à 6 chiffres attendu');
      return;
    }

    setState(() { _enCours = true; _messageErreur = null; });

    // Position GPS au moment de la validation (preuve de présence)
    double? lat, lng;
    try {
      final pos = await Location().getLocation();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    // Validation RÉELLE du code court via le service (vérifie avec la clé locale)
    bool valide = false;
    try {
      valide = await LivraisonService.validerParCodeCourt(
        livraisonId: widget.livraisonId,
        codeSaisi: code,
        type: widget.typeAttendu,
        lat: lat,
        lng: lng,
      );
    } catch (_) {}

    if (!valide) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _messageErreur = 'Code incorrect';
        });
      }
      return;
    }

    // Code correct → tracer aussi dans la file offline pour synchro/audit
    await executerAvecResilience(
      action: () async {},
      typeOffline: widget.typeAttendu == TypeQR.depart
          ? TypeActionOffline.scanQR
          : TypeActionOffline.confirmerLivraison,
      payloadOffline: {
        'livraisonId': widget.livraisonId,
        'type': widget.typeAttendu.name,
        'methode': 'code_court',
        'code': code,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    if (mounted) {
      setState(() => _enCours = false);
      widget.onSucces?.call();
    }
  }
}

// ─── Painter des coins du viseur ──────────────────────────────────────────────

class _CoinPainter extends CustomPainter {
  final bool top;
  final bool left;
  final double ep;

  _CoinPainter({required this.top, required this.left, required this.ep});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kPrimary
      ..strokeWidth = ep
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Capture de signature (dernier recours, téléphone client éteint) ──────────

class _CaptureSignature extends StatefulWidget {
  final String livraisonId;
  final VoidCallback? onSucces;
  const _CaptureSignature({required this.livraisonId, this.onSucces});

  @override
  State<_CaptureSignature> createState() => _CaptureSignatureState();
}

class _CaptureSignatureState extends State<_CaptureSignature> {
  late final SignatureController _ctrl;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_ctrl.isEmpty) return;
    setState(() => _enCours = true);

    // Exporter la signature en image base64
    String signatureB64 = '';
    try {
      final bytes = await _ctrl.toPngBytes();
      if (bytes != null) signatureB64 = base64Encode(bytes);
    } catch (_) {}

    // Position GPS (preuve de présence)
    double? lat, lng;
    try {
      final pos = await Location().getLocation();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    try {
      final okSig = await LivraisonService.validerParSignature(
        livraisonId: widget.livraisonId,
        signatureBase64: signatureB64,
      );
      if (!okSig) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                  Tr.s.signatureSeuleEstRefuseeFaites)));
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _enCours = false);
      widget.onSucces?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Tr.s.signatureClient,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(Tr.s.dernierRecoursSiClientN,
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 16),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Signature(
              controller: _ctrl,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => _ctrl.clear(),
                child: Text(Tr.s.effacer,
                    style: TextStyle(color: Colors.white60)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _enCours ? null : _valider,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _enCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(Tr.s.validerSignature),
              ),
            ],
          ),
        ],
      );
}
