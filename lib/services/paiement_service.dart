import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/utils/config_paiement.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE PAIEMENT — Monetbil + CinetPay
//
// Monetbil (recommandé pour le Cameroun) :
//   - Supporte Orange Money CM, MTN MoMo CM, Express Union
//   - API REST simple, pas de SDK Flutter requis
//   - Webhook de confirmation (Cloud Function ou serveur FastAPI)
//   - Docs : https://www.monetbil.com/doc/api
//
// CinetPay (fallback) :
//   - Supporte plus de pays mais plus complexe
//   - Docs : https://docs.cinetpay.com
//
// Architecture :
//   App → PaiementService.initier() → Monetbil API
//          → Retourne URL de paiement → WebView ou lien direct
//          → Webhook Monetbil → Cloud Function → Firestore (statut = confirmé)
//          → App écoute Firestore en temps réel → UI mis à jour
//
// Configuration :
//   Remplacer les clés dans _MonetbilConfig et _CinetPayConfig
// ═══════════════════════════════════════════════════════════════════════════

// ─── Config Monetbil ──────────────────────────────────────────────────────────

class _MonetbilConfig {
  // 1. Créer un compte sur https://www.monetbil.com
  // 2. Récupérer votre Service Key dans le dashboard
  // 3. Configurer l'URL webhook dans le dashboard Monetbil
  static String get serviceKey => ConfigPaiement.monetbilServiceKey;

  // Mode test (sandbox) → true pour le dev, false en production
  static bool get sandbox => ConfigPaiement.modeTest;

  static String get baseUrl => sandbox
      ? 'https://api.monetbil.com/widget/v2.1/'
      : 'https://api.monetbil.com/widget/v2.1/';

  // URL de votre Cloud Function ou serveur FastAPI qui reçoit les webhooks
  // Monetbil appellera cette URL après confirmation de paiement
  static String get webhookUrl => ConfigPaiement.monetbilWebhookUrl;

  // URL de retour après paiement (deep link vers l'app)
  static String get returnUrl => ConfigPaiement.returnUrl;
  static String get cancelUrl => ConfigPaiement.cancelUrl;
}

// ─── Config CinetPay (fallback) ───────────────────────────────────────────────

class _CinetPayConfig {
  // 1. Créer un compte sur https://cinetpay.com
  // 2. Récupérer API Key + Site ID dans le dashboard
  static String get apiKey => ConfigPaiement.cinetpayApiKey;
  static String get siteId => ConfigPaiement.cinetpaySiteId;

  static bool get sandbox => ConfigPaiement.modeTest;
  static String get baseUrl => 'https://api-checkout.cinetpay.com/v2/payment';
}

// ─── Fournisseur de paiement ──────────────────────────────────────────────────

enum FournisseurPaiement { monetbil, cinetpay }
enum StatutPaiement { enAttente, confirme, echoue, annule, expire }

// ─── Résultat initiation ─────────────────────────────────────────────────────

class ResultatInitiation {
  final bool succes;
  final String? transactionId;   // ID local SAMI
  final String? refPaiement;     // référence Monetbil/CinetPay
  final String? urlPaiement;     // URL à ouvrir pour payer
  final String? erreur;
  final FournisseurPaiement fournisseur;

  const ResultatInitiation({
    required this.succes,
    this.transactionId,
    this.refPaiement,
    this.urlPaiement,
    this.erreur,
    required this.fournisseur,
  });
}

// ─── Service principal ────────────────────────────────────────────────────────

class PaiementService {

  static final _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  // ══════════════════════════════════════════════════════════════════════════
  // INITIATION D'UN PAIEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Initier un paiement Mobile Money
  /// Retourne une URL de paiement à ouvrir dans un WebView
  static Future<ResultatInitiation> initier({
    required double montant,
    required String telephone,
    required String operateur,      // 'orange' | 'mtn' | 'express_union'
    required String description,
    required String clientId,
    String? commandeId,
    String type = 'commande', // 'recharge' → le webhook crédite le solde
    FournisseurPaiement fournisseur = FournisseurPaiement.monetbil,
  }) async {
    // Générer un ID de transaction local unique
    final transactionId = 'SAMI-${_uuid.v4().substring(0, 8).toUpperCase()}';

    // Créer l'entrée Firestore en attente
    await _db.collection('transactions_paiement').doc(transactionId).set({
      'transactionId': transactionId,
      'clientId': clientId,
      'type': type,
      'commandeId': commandeId,
      'montant': montant,
      'telephone': telephone,
      'operateur': operateur,
      'description': description,
      'fournisseur': fournisseur.name,
      'statut': StatutPaiement.enAttente.name,
      'dateCreation': FieldValue.serverTimestamp(),
      'refPaiement': null,
    });

    // Appel selon le fournisseur
    return fournisseur == FournisseurPaiement.monetbil
        ? await _initierMonetbil(
            transactionId: transactionId,
            montant: montant,
            telephone: telephone,
            operateur: operateur,
            description: description,
          )
        : await _initierCinetPay(
            transactionId: transactionId,
            montant: montant,
            telephone: telephone,
            description: description,
          );
  }

  // ── Monetbil ──────────────────────────────────────────────────────────────

  static Future<ResultatInitiation> _initierMonetbil({
    required String transactionId,
    required double montant,
    required String telephone,
    required String operateur,
    required String description,
  }) async {
    try {
      // Mapper l'opérateur vers le code Monetbil
      final operateurCode = switch (operateur) {
        'orange' => 'OMCM',   // Orange Money Cameroun
        'mtn'    => 'MTNMOMO', // MTN Mobile Money
        _        => 'OMCM',
      };

      final body = {
        'service_key': await ConfigPaiement.cleMonetbil(),
        'amount': montant.round().toString(),
        'phone': telephone,                    // ex: 237690000000
        'locale': 'fr',
        'operator': operateurCode,
        'item_ref': transactionId,
        'payment_ref': transactionId,
        'user1': transactionId,               // référence pour le webhook
        'notify_url': _MonetbilConfig.webhookUrl,
        'return_url': _MonetbilConfig.returnUrl,
        'logo': 'https://sami.app/logo.png',
      };

      final response = await http.post(
        Uri.parse('${_MonetbilConfig.baseUrl}${await ConfigPaiement.cleMonetbil()}'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Monetbil retourne soit une URL de paiement soit un statut direct
        if (data['success'] == true || data['status'] == 'SUCCESS') {
          final urlPaiement = data['payment_url'] as String?
              ?? data['url'] as String?;
          final refPaiement = data['paymentRef'] as String?
              ?? data['payment_ref'] as String?;

          // Mettre à jour Firestore avec la référence
          await _db.collection('transactions_paiement').doc(transactionId).update({
            'refPaiement': refPaiement,
            'urlPaiement': urlPaiement,
            'reponseInitiale': data,
          });

          return ResultatInitiation(
            succes: true,
            transactionId: transactionId,
            refPaiement: refPaiement,
            urlPaiement: urlPaiement,
            fournisseur: FournisseurPaiement.monetbil,
          );
        } else {
          final erreur = data['message'] as String?
              ?? data['error'] as String?
              ?? 'Erreur Monetbil inconnue';

          await _marquerEchoue(transactionId, erreur);

          return ResultatInitiation(
            succes: false,
            transactionId: transactionId,
            erreur: _traduitErreurMonetbil(erreur),
            fournisseur: FournisseurPaiement.monetbil,
          );
        }
      } else {
        final erreur = 'HTTP ${response.statusCode}';
        await _marquerEchoue(transactionId, erreur);
        return ResultatInitiation(
          succes: false,
          transactionId: transactionId,
          erreur: 'Service de paiement indisponible. Réessayez.',
          fournisseur: FournisseurPaiement.monetbil,
        );
      }
    } catch (e) {
      await _marquerEchoue(transactionId, e.toString());
      if (kDebugMode) print('[Monetbil] Erreur : $e');

      return ResultatInitiation(
        succes: false,
        transactionId: transactionId,
        erreur: _estErreurReseau(e)
            ? 'Pas de connexion. Vérifiez votre réseau.'
            : 'Erreur technique. Réessayez.',
        fournisseur: FournisseurPaiement.monetbil,
      );
    }
  }

  // ── CinetPay ──────────────────────────────────────────────────────────────

  static Future<ResultatInitiation> _initierCinetPay({
    required String transactionId,
    required double montant,
    required String telephone,
    required String description,
  }) async {
    try {
      final body = jsonEncode({
        'apikey': _CinetPayConfig.apiKey,
        'site_id': _CinetPayConfig.siteId,
        'transaction_id': transactionId,
        'amount': montant.round(),
        'currency': 'XAF',              // Franc CFA
        'alternative_currency': '',
        'description': description,
        'customer_id': transactionId,
        'customer_name': '',
        'customer_surname': '',
        'customer_phone_number': telephone,
        'customer_address': 'Garoua, Cameroun',
        'customer_city': 'Garoua',
        'customer_country': 'CM',
        'customer_state': 'CM',
        'customer_zip_code': '',
        'notify_url': ConfigPaiement.cinetpayWebhookUrl,
        'return_url': _CinetPayConfig.sandbox
            ? 'https://cinetpay.com'
            : _MonetbilConfig.returnUrl,
        'channels': 'MOBILE_MONEY',
        'metadata': transactionId,
      });

      final response = await http.post(
        Uri.parse(_CinetPayConfig.baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['code'] as String?;

        if (code == '201') {
          final urlPaiement = (data['data'] as Map<String, dynamic>?)?['payment_url'] as String?;
          await _db.collection('transactions_paiement').doc(transactionId).update({
            'urlPaiement': urlPaiement,
            'reponseInitiale': data,
          });
          return ResultatInitiation(
            succes: true,
            transactionId: transactionId,
            urlPaiement: urlPaiement,
            fournisseur: FournisseurPaiement.cinetpay,
          );
        } else {
          final msg = data['message'] as String? ?? 'Erreur CinetPay';
          await _marquerEchoue(transactionId, msg);
          return ResultatInitiation(
            succes: false,
            transactionId: transactionId,
            erreur: msg,
            fournisseur: FournisseurPaiement.cinetpay,
          );
        }
      } else {
        return ResultatInitiation(
          succes: false,
          transactionId: transactionId,
          erreur: 'Service indisponible (${response.statusCode})',
          fournisseur: FournisseurPaiement.cinetpay,
        );
      }
    } catch (e) {
      await _marquerEchoue(transactionId, e.toString());
      return ResultatInitiation(
        succes: false,
        transactionId: transactionId,
        erreur: _estErreurReseau(e) ? 'Pas de connexion.' : 'Erreur : $e',
        fournisseur: FournisseurPaiement.cinetpay,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VÉRIFICATION DU STATUT (polling si pas de webhook)
  // ══════════════════════════════════════════════════════════════════════════

  /// Vérifier le statut d'un paiement Monetbil
  static Future<StatutPaiement> verifierStatutMonetbil(String refPaiement) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.monetbil.com/payment/v1/status'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'service_key': await ConfigPaiement.cleMonetbil(),
          'paymentRef': refPaiement,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        return switch (status) {
          'SUCCESS'  => StatutPaiement.confirme,
          'FAILED'   => StatutPaiement.echoue,
          'CANCELLED'=> StatutPaiement.annule,
          'EXPIRED'  => StatutPaiement.expire,
          _          => StatutPaiement.enAttente,
        };
      }
    } catch (e) {
      if (kDebugMode) print('[Monetbil] Erreur vérification statut : $e');
    }
    return StatutPaiement.enAttente;
  }

  /// Écouter le statut en temps réel via Firestore (mis à jour par le webhook)
  static Stream<StatutPaiement> streamStatut(String transactionId) =>
      _db.collection('transactions_paiement').doc(transactionId)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return StatutPaiement.enAttente;
        final statut = doc.data()?['statut'] as String?;
        return StatutPaiement.values.firstWhere(
          (s) => s.name == statut,
          orElse: () => StatutPaiement.enAttente,
        );
      });

  // ══════════════════════════════════════════════════════════════════════════
  // WEBHOOK (appelé par votre Cloud Function / FastAPI)
  // ══════════════════════════════════════════════════════════════════════════

  /// Traiter la confirmation de paiement reçue par webhook
  /// À appeler depuis votre serveur après validation du webhook Monetbil
  static Future<void> confirmerPaiement({
    required String transactionId,
    required String refPaiement,
    required double montantConfirme,
  }) async {
    final txRef = _db.collection('transactions_paiement').doc(transactionId);
    final doc = await txRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final montantAttendu = (data['montant'] as num? ?? 0).toDouble();

    // Vérifier que le montant correspond (anti-fraude)
    if ((montantConfirme - montantAttendu).abs() > 1) {
      await txRef.update({
        'statut': StatutPaiement.echoue.name,
        'erreur': 'Montant incorrect : attendu ${PrixFCFA.formater(montantAttendu)}, reçu ${PrixFCFA.formater(montantConfirme)}',
      });
      return;
    }

    await txRef.update({
      'statut': StatutPaiement.confirme.name,
      'refPaiement': refPaiement,
      'montantConfirme': montantConfirme,
      'dateConfirmation': FieldValue.serverTimestamp(),
    });

    if (kDebugMode) print('[Paiement] ✅ Confirmé : $transactionId');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _marquerEchoue(String txId, String erreur) async {
    try {
      await _db.collection('transactions_paiement').doc(txId).update({
        'statut': StatutPaiement.echoue.name,
        'erreur': erreur,
        'dateEchec': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static bool _estErreurReseau(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socket') || msg.contains('connection')
        || msg.contains('network') || msg.contains('timeout');
  }

  static String _traduitErreurMonetbil(String erreur) {
    final e = erreur.toLowerCase();
    if (e.contains('insufficient') || e.contains('solde')) {
      return 'Solde Mobile Money insuffisant';
    }
    if (e.contains('invalid') && e.contains('phone')) {
      return 'Numéro de téléphone invalide';
    }
    if (e.contains('timeout') || e.contains('expired')) {
      return 'Délai dépassé — réessayez';
    }
    if (e.contains('cancelled')) {
      return 'Paiement annulé';
    }
    return 'Paiement refusé : $erreur';
  }

  /// Formater le numéro en international pour les API
  static String formaterNumero(String numero, {String pays = '237'}) {
    final net = numero.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (net.startsWith('00')) return net.substring(2);
    if (net.startsWith('+')) return net.substring(1);
    if (!net.startsWith(pays)) return '$pays$net';
    return net;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET PAGE DE PAIEMENT AVEC SUIVI EN TEMPS RÉEL
// ═══════════════════════════════════════════════════════════════════════════

class PagePaiementMoMo extends StatefulWidget {
  final double montant;
  final String description;
  final String clientId;
  final String? commandeId;
  final void Function(String transactionId) onSucces;
  final VoidCallback? onEchec;
  final String type; // 'commande' | 'recharge'

  const PagePaiementMoMo({
    super.key,
    required this.montant,
    required this.description,
    required this.clientId,
    this.commandeId,
    required this.onSucces,
    this.type = 'commande',
    this.onEchec,
  });

  @override
  State<PagePaiementMoMo> createState() => _PagePaiementMoMoState();
}

class _PagePaiementMoMoState extends State<PagePaiementMoMo> {
  final _telCtrl = TextEditingController();
  String _operateur = 'orange';
  bool _enCours = false;
  String? _erreur;
  String? _transactionId;
  StatutPaiement? _statut;
  bool _attente = false; // en attente de confirmation MoMo
  bool _succesNotifie = false; // onSucces appelé UNE seule fois

  static const _kPrimary = Color(0xFF6A1B9A);
  static const _kOrange = Color(0xFFFF6600);
  static const _kMTN = Color(0xFFFFCC00);

  @override
  void dispose() { _telCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Paiement Mobile Money'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: _attente && _transactionId != null
          ? _buildAttenteConfirmation()
          : _buildFormulaire(),
    );
  }

  // ── Formulaire de saisie ──────────────────────────────────────────────────

  Widget _buildFormulaire() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      // Montant
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          const Text('Montant à payer', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(PrixFCFA.formater(widget.montant),
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          Text(widget.description,
              style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
        ]),
      ),
      const SizedBox(height: 24),

      // Opérateur
      const Align(alignment: Alignment.centerLeft, child: Text('Choisir l\'opérateur',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _BoutonOperateur(
          emoji: '🟠', nom: 'Orange Money', valeur: 'orange',
          actuel: _operateur, couleur: _kOrange,
          onTap: () => setState(() => _operateur = 'orange'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _BoutonOperateur(
          emoji: '🟡', nom: 'MTN MoMo', valeur: 'mtn',
          actuel: _operateur, couleur: _kMTN,
          onTap: () => setState(() => _operateur = 'mtn'),
        )),
      ]),
      const SizedBox(height: 16),

      // Téléphone
      TextFormField(
        controller: _telCtrl,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Numéro Mobile Money',
          hintText: '6XXXXXXXX',
          prefixText: '+237 ',
          prefixIcon: Icon(Icons.phone_outlined, color: Colors.grey.shade500, size: 20),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
        ),
      ),

      // Erreur
      if (_erreur != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          ]),
        ),
      ],

      const SizedBox(height: 24),

      // Bouton payer
      SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: _enCours ? null : _payer,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _enCours
              ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 10),
                  Text('Payer ${PrixFCFA.formater(widget.montant)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
        ),
      ),

      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.security, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text('Paiement sécurisé via Monetbil',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ]),
    ]),
  );

  // ── Écran d'attente après initiation ─────────────────────────────────────

  Widget _buildAttenteConfirmation() {
    return StreamBuilder<StatutPaiement>(
      stream: PaiementService.streamStatut(_transactionId!),
      builder: (context, snap) {
        final statut = snap.data ?? StatutPaiement.enAttente;

        // Réagir aux changements de statut
        // UNE SEULE notification : le StreamBuilder rebuilde en continu —
        // sans ce verrou, onSucces (et son Navigator.pop côté panier)
        // serait rappelé en boucle et dépilerait TOUTES les pages.
        if (statut == StatutPaiement.confirme &&
            mounted &&
            !_succesNotifie &&
            _transactionId != null) {
          _succesNotifie = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onSucces(_transactionId!);
          });
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Icône animée selon statut
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: switch (statut) {
                  StatutPaiement.confirme => const Icon(Icons.check_circle,
                      color: Color(0xFF1D9E75), size: 80, key: ValueKey('ok')),
                  StatutPaiement.echoue ||
                  StatutPaiement.annule   => const Icon(Icons.cancel,
                      color: Colors.red, size: 80, key: ValueKey('fail')),
                  _                       => const SizedBox(width: 80, height: 80,
                      key: ValueKey('wait'),
                      child: CircularProgressIndicator(strokeWidth: 4, color: _kPrimary)),
                },
              ),
              const SizedBox(height: 24),

              Text(
                switch (statut) {
                  StatutPaiement.enAttente => 'En attente de confirmation…',
                  StatutPaiement.confirme  => 'Paiement confirmé ✓',
                  StatutPaiement.echoue    => 'Paiement refusé',
                  StatutPaiement.annule    => 'Paiement annulé',
                  StatutPaiement.expire    => 'Délai dépassé',
                },
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              if (statut == StatutPaiement.enAttente) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(children: [
                    const Icon(Icons.phone_android, color: Colors.blue, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      _operateur == 'orange'
                          ? 'Vérifiez votre téléphone.\nOrange va vous appeler pour confirmer.'
                          : 'Validez la notification MTN\nMoMo sur votre téléphone.',
                      style: const TextStyle(color: Colors.blue, fontSize: 14, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text('Ne quittez pas cette page.',
                        style: TextStyle(color: Colors.blue, fontSize: 12, fontStyle: FontStyle.italic)),
                  ]),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _verifierManuellement,
                  child: const Text('Vérifier manuellement', style: TextStyle(color: _kPrimary)),
                ),
              ],

              if (statut == StatutPaiement.echoue || statut == StatutPaiement.annule) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => setState(() { _attente = false; _erreur = null; }),
                  style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
                  child: const Text('Réessayer'),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _payer() async {
    if (_telCtrl.text.length < 9) {
      setState(() => _erreur = 'Entrez un numéro valide (9 chiffres)');
      return;
    }
    setState(() { _enCours = true; _erreur = null; });

    try {
      final result = await PaiementService.initier(
            type: widget.type,
        montant: widget.montant,
        telephone: PaiementService.formaterNumero(_telCtrl.text),
        operateur: _operateur,
        description: widget.description,
        clientId: widget.clientId,
        commandeId: widget.commandeId,
      );

      if (!mounted) return;

      if (result.succes) {
        setState(() {
          _transactionId = result.transactionId;
          _attente = true;
          _enCours = false;
        });
      } else {
        setState(() {
          _erreur = result.erreur;
          _enCours = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _erreur = 'Erreur : $e';
        _enCours = false;
      });
    }
  }

  Future<void> _verifierManuellement() async {
    if (_transactionId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('transactions_paiement').doc(_transactionId).get();
    final refPaiement = doc.data()?['refPaiement'] as String?;
    if (refPaiement == null) return;

    final statut = await PaiementService.verifierStatutMonetbil(refPaiement);
    if (statut == StatutPaiement.confirme) {
      await PaiementService.confirmerPaiement(
        transactionId: _transactionId!,
        refPaiement: refPaiement,
        montantConfirme: widget.montant,
      );
    }
  }
}

// ─── Bouton opérateur ─────────────────────────────────────────────────────────

class _BoutonOperateur extends StatelessWidget {
  final String emoji;
  final String nom;
  final String valeur;
  final String actuel;
  final Color couleur;
  final VoidCallback onTap;

  const _BoutonOperateur({required this.emoji, required this.nom, required this.valeur,
    required this.actuel, required this.couleur, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final actif = actuel == valeur;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: actif ? couleur.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: actif ? couleur : Colors.grey.shade300,
              width: actif ? 2 : 1),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(nom, style: TextStyle(fontSize: 12, fontWeight: actif ? FontWeight.bold : FontWeight.normal,
              color: actif ? couleur : Colors.grey)),
        ]),
      ),
    );
  }
}
