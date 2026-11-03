import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME QR CRYPTOGRAPHIQUE OFFLINE-FIRST
//
// Principe (inspiré des TOTP / JWT) :
// ─────────────────────────────────────────────────────────────────────────
// 1. À la CRÉATION de la livraison (en ligne) :
//    → Générer une clé secrète K (32 bytes aléatoires)
//    → Générer 2 tokens signés : QR_DEPART et QR_ARRIVEE
//      QR_DEPART  = base64(livraisonId + "DEP" + timestamp + HMAC(K, payload))
//      QR_ARRIVEE = base64(livraisonId + "ARR" + timestamp + HMAC(K, payload))
//    → Distribuer via Firestore :
//        • livreur  reçoit : clé K + QR_DEPART
//        • client   reçoit : clé K + QR_ARRIVEE
//        • boutique reçoit : clé K + QR_DEPART (pour vérifier le livreur)
//    → Tout est stocké localement (SharedPreferences)
//
// 2. Au SCAN (offline possible) :
//    → App lit le QR scanné
//    → Recalcule le HMAC avec la clé K locale
//    → Compare : si match → valide SANS réseau
//    → L'action est mise en file offline pour sync ultérieure
//
// Propriétés de sécurité :
//   • Sans la clé K, impossible de forger un QR valide
//   • La clé K n'est jamais dans le QR lui-même
//   • QR invalide si livraisonId ne correspond pas
//   • QR invalide après expiration (timestamp)
//   • Même principe que les TOTP bancaires et les JWT
// ═══════════════════════════════════════════════════════════════════════════

// ─── Structure d'un token QR ─────────────────────────────────────────────────

enum TypeQR { depart, arrivee }

class TokenQR {
  final String livraisonId;
  final TypeQR type;
  final int timestamp;          // Unix timestamp de création
  final int expirationUnix;     // Unix timestamp d'expiration
  final String signature;       // HMAC-SHA256 tronqué (16 bytes en hex)

  const TokenQR({
    required this.livraisonId,
    required this.type,
    required this.timestamp,
    required this.expirationUnix,
    required this.signature,
  });

  bool get estExpire => DateTime.now().millisecondsSinceEpoch ~/ 1000 > expirationUnix;
  bool get estDepart => type == TypeQR.depart;
  bool get estArrivee => type == TypeQR.arrivee;

  // ── Sérialisation compacte pour encoder dans le QR ───────────────────────
  // Format : livraisonId|type|timestamp|expiration|signature
  // Compact pour garder un QR lisible même avec une petite caméra
  String encode() {
    final payload = [
      livraisonId,
      type == TypeQR.depart ? 'D' : 'A',
      timestamp.toString(),
      expirationUnix.toString(),
      signature,
    ].join('|');
    return base64Url.encode(utf8.encode(payload));
  }

  factory TokenQR.decode(String encoded) {
    final payload = utf8.decode(base64Url.decode(encoded));
    final parts = payload.split('|');
    if (parts.length != 5) throw const FormatException('QR invalide');
    return TokenQR(
      livraisonId: parts[0],
      type: parts[1] == 'D' ? TypeQR.depart : TypeQR.arrivee,
      timestamp: int.parse(parts[2]),
      expirationUnix: int.parse(parts[3]),
      signature: parts[4],
    );
  }
}

// ─── Service principal ────────────────────────────────────────────────────────

class QRCryptoService {

  // ══════════════════════════════════════════════════════════════════════════
  // GÉNÉRATION (côté serveur / création livraison)
  // ══════════════════════════════════════════════════════════════════════════

  /// Générer la clé secrète partagée pour une livraison
  /// Appelé UNE SEULE FOIS à la création
  static String genererCleSecrete() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Génère un code court à 6 chiffres (lisible par un humain), dérivé de la
  /// clé secrète + livraisonId. Déterministe : recalculable hors-ligne pour
  /// validation, sert de secours quand le scan QR n'est pas possible.
  static String genererCodeCourt({
    required String livraisonId,
    required String cleSecrete,
  }) {
    final hmac = _calculerHMAC(
      payload: '$livraisonId|CODE_COURT',
      cle: cleSecrete,
    );
    // Prendre les premiers caractères hex → entier → 6 chiffres
    final n = int.parse(hmac.substring(0, 6), radix: 16) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  /// Vérifie un code court saisi (validation offline, déterministe).
  static bool verifierCodeCourt({
    required String livraisonId,
    required String cleSecrete,
    required String codeSaisi,
  }) {
    final attendu = genererCodeCourt(
        livraisonId: livraisonId, cleSecrete: cleSecrete);
    return codeSaisi.trim() == attendu;
  }

  /// Générer le token QR signé pour le départ (boutique → livreur)
  static TokenQR genererQRDepart({
    required String livraisonId,
    required String cleSecrete,
    Duration validite = const Duration(hours: 48),
  }) {
    return _genererToken(
      livraisonId: livraisonId,
      type: TypeQR.depart,
      cleSecrete: cleSecrete,
      validite: validite,
    );
  }

  /// Générer le token QR signé pour l'arrivée (livreur → client)
  static TokenQR genererQRArrivee({
    required String livraisonId,
    required String cleSecrete,
    Duration validite = const Duration(hours: 48),
  }) {
    return _genererToken(
      livraisonId: livraisonId,
      type: TypeQR.arrivee,
      cleSecrete: cleSecrete,
      validite: validite,
    );
  }

  /// Générer l'ensemble complet pour une livraison
  static LivraisonQRSet genererSet({
    required String livraisonId,
    Duration validite = const Duration(hours: 48),
  }) {
    final cle = genererCleSecrete();
    final qrDepart = genererQRDepart(livraisonId: livraisonId, cleSecrete: cle, validite: validite);
    final qrArrivee = genererQRArrivee(livraisonId: livraisonId, cleSecrete: cle, validite: validite);
    return LivraisonQRSet(
      livraisonId: livraisonId,
      cleSecrete: cle,
      tokenDepart: qrDepart,
      tokenArrivee: qrArrivee,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VALIDATION OFFLINE
  // ══════════════════════════════════════════════════════════════════════════

  /// Valider un QR scanné SANS réseau
  /// La clé secrète doit être disponible localement (chargée à la création)
  static ResultatValidationQR validerOffline({
    required String qrScanne,           // contenu du QR code scanné
    required String cleSecreteLocale,   // clé K stockée localement
    required String livraisonIdAttendu, // ID de la livraison en cours
    required TypeQR typeAttendu,        // départ ou arrivée
  }) {
    // 1. Décoder le QR
    TokenQR token;
    try {
      token = TokenQR.decode(qrScanne);
    } catch (e) {
      return ResultatValidationQR(
        valide: false,
        raison: RaisonEchec.formatInvalide,
        message: 'QR code illisible ou corrompu',
      );
    }

    // 2. Vérifier que c'est pour la bonne livraison
    if (token.livraisonId != livraisonIdAttendu) {
      return ResultatValidationQR(
        valide: false,
        raison: RaisonEchec.mauvaiseLivraison,
        message: 'Ce QR ne correspond pas à cette livraison',
      );
    }

    // 3. Vérifier le type (départ vs arrivée)
    if (token.type != typeAttendu) {
      return ResultatValidationQR(
        valide: false,
        raison: RaisonEchec.mauvaistType,
        message: typeAttendu == TypeQR.depart
            ? 'Utilisez le QR de départ (boutique), pas celui d\'arrivée'
            : 'Utilisez le QR d\'arrivée (client), pas celui de départ',
      );
    }

    // 4. Vérifier l'expiration
    if (token.estExpire) {
      return ResultatValidationQR(
        valide: false,
        raison: RaisonEchec.expire,
        message: 'QR code expiré — contactez le support',
      );
    }

    // 5. VÉRIFICATION CRYPTOGRAPHIQUE — le cœur du système
    // Recalculer la signature attendue avec la clé locale
    final signatureAttendue = _calculerHMAC(
      payload: _construirePayload(
        livraisonId: token.livraisonId,
        type: token.type,
        timestamp: token.timestamp,
        expiration: token.expirationUnix,
      ),
      cle: cleSecreteLocale,
    );

    // Comparaison en temps constant (évite les timing attacks)
    if (!_comparaisonSecurisee(token.signature, signatureAttendue)) {
      return ResultatValidationQR(
        valide: false,
        raison: RaisonEchec.signatureInvalide,
        message: 'QR code invalide — signature incorrecte',
      );
    }

    return ResultatValidationQR(
      valide: true,
      token: token,
      message: typeAttendu == TypeQR.depart
          ? 'Prise en charge confirmée ✓'
          : 'Livraison confirmée ✓',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STOCKAGE LOCAL DES CLÉS
  // ══════════════════════════════════════════════════════════════════════════

  /// Stocker la clé secrète localement (après réception depuis Firestore)
  static Future<void> stockerCle({
    required String livraisonId,
    required String cleSecrete,
    required RoleLivraison role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // On stocke la clé + les tokens associés au rôle
    final cle = 'qr_cle_${livraisonId}_${role.name}';
    await prefs.setString(cle, cleSecrete);
    if (kDebugMode) print('[QRCrypto] Clé stockée pour livraison $livraisonId (${role.name})');
  }

  /// Stocker les tokens QR localement selon le rôle
  static Future<void> stockerTokens({
    required String livraisonId,
    required RoleLivraison role,
    required LivraisonQRSet set,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Chaque rôle ne reçoit que les tokens dont il a besoin
    final data = <String, String>{};

    // SÉCURITÉ : on ne donne le TOKEN À PRÉSENTER qu'à celui qui doit l'afficher.
    // Le livreur SCANNE (il vérifie avec la clé) ; il ne détient aucun token,
    // sinon il pourrait valider seul sans la présence de la boutique/du client.
    switch (role) {
      case RoleLivraison.boutique:
        // La boutique affiche le QR de départ que le livreur scanne.
        data['qr_depart'] = set.tokenDepart.encode();
        break;
      case RoleLivraison.livreur:
        // Le livreur ne reçoit AUCUN token à présenter : seulement la clé,
        // qui lui sert à vérifier les QR montrés par la boutique puis le client.
        break;
      case RoleLivraison.client:
        // Le client affiche le QR d'arrivée que le livreur scanne.
        data['qr_arrivee'] = set.tokenArrivee.encode();
        break;
    }

    data['cle'] = set.cleSecrete;
    data['expiration'] = set.tokenDepart.expirationUnix.toString();

    await prefs.setString(
      'qr_set_$livraisonId',
      jsonEncode(data),
    );
  }

  /// PRÉCHARGEMENT OFFLINE-FIRST : télécharge la clé + tokens depuis Firestore
  /// (collection qr_secrets) et les stocke EN LOCAL selon le rôle. À appeler
  /// QUAND LE RÉSEAU EST DISPONIBLE (livreur qui accepte sa course, client qui
  /// ouvre sa commande), pour que la validation puisse se faire ensuite SANS
  /// réseau. Retourne true si le préchargement a réussi.
  static Future<bool> prechargerDepuisFirestore({
    required String livraisonId,
    required RoleLivraison role,
  }) async {
    try {
      // Si déjà en local, rien à faire
      final dejaLa = await chargerLocal(livraisonId);
      if (dejaLa != null) return true;

      final doc = await FirebaseFirestore.instance
          .collection('qr_secrets')
          .doc(livraisonId)
          .get();
      if (!doc.exists || doc.data() == null) return false;

      final data = doc.data()!;
      final cle = data['cle'] as String?;
      if (cle == null) return false;

      // Stocker en local selon le rôle. PRINCIPE DE SÉCURITÉ :
      //   - chacun reçoit la CLÉ (pour VÉRIFIER une signature scannée),
      //   - mais on ne donne le TOKEN à présenter qu'à celui qui doit l'afficher.
      // Le livreur SCANNE (il vérifie), il ne doit donc PAS détenir le token
      // qr_arrivee du client : sinon il pourrait valider seul, sans le client.
      final prefs = await SharedPreferences.getInstance();
      final local = <String, String>{'cle': cle};
      if (role == RoleLivraison.boutique) {
        // La boutique affiche le QR de départ que le livreur scanne.
        local['qr_depart'] = data['qrDepart'] as String? ?? '';
      }
      if (role == RoleLivraison.client) {
        // Le client affiche le QR d'arrivée que le livreur scanne.
        local['qr_arrivee'] = data['qrArrivee'] as String? ?? '';
      }
      // Le livreur ne reçoit AUCUN token à présenter : il a seulement la clé,
      // qui lui permet de vérifier les QR que la boutique/le client lui montrent.
      local['expiration'] = (data['expiration'] ?? 0).toString();
      await prefs.setString('qr_set_$livraisonId', jsonEncode(local));
      if (kDebugMode) {
        print('[QRCrypto] Préchargé pour $livraisonId (${role.name})');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('[QRCrypto] Préchargement échoué: $e');
      return false;
    }
  }

  /// Charger les informations QR d'une livraison depuis le stockage local
  static Future<QRLocalData?> chargerLocal(String livraisonId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('qr_set_$livraisonId');
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return QRLocalData(
        cleSecrete: data['cle'] as String,
        tokenDepart: data['qr_depart'] != null
            ? TokenQR.decode(data['qr_depart'] as String) : null,
        tokenArrivee: data['qr_arrivee'] != null
            ? TokenQR.decode(data['qr_arrivee'] as String) : null,
        expirationUnix: int.parse(data['expiration'] as String),
      );
    } catch (e) {
      if (kDebugMode) print('[QRCrypto] Erreur chargement local : $e');
      return null;
    }
  }

  /// Nettoyer les données QR expirées (appeler au démarrage)
  static Future<void> nettoyerExpires() async {
    final prefs = await SharedPreferences.getInstance();
    final maintenant = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final clesAEffacer = <String>[];

    for (final cle in prefs.getKeys()) {
      if (!cle.startsWith('qr_set_')) continue;
      try {
        final data = jsonDecode(prefs.getString(cle)!) as Map<String, dynamic>;
        final expiration = int.parse(data['expiration'] as String);
        if (maintenant > expiration + 3600) {
          // Expiré depuis plus d'1h
          clesAEffacer.add(cle);
        }
      } catch (_) {
        clesAEffacer.add(cle);
      }
    }

    for (final cle in List.of(clesAEffacer)) {
      await prefs.remove(cle);
    }
    if (kDebugMode && clesAEffacer.isNotEmpty) {
      print('[QRCrypto] ${clesAEffacer.length} QR expirés nettoyés');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTHODES PRIVÉES — CRYPTOGRAPHIE
  // ══════════════════════════════════════════════════════════════════════════

  static TokenQR _genererToken({
    required String livraisonId,
    required TypeQR type,
    required String cleSecrete,
    required Duration validite,
  }) {
    final maintenant = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiration = maintenant + validite.inSeconds;

    final payload = _construirePayload(
      livraisonId: livraisonId,
      type: type,
      timestamp: maintenant,
      expiration: expiration,
    );

    final signature = _calculerHMAC(payload: payload, cle: cleSecrete);

    return TokenQR(
      livraisonId: livraisonId,
      type: type,
      timestamp: maintenant,
      expirationUnix: expiration,
      signature: signature,
    );
  }

  /// Construire le message à signer (déterministe)
  static String _construirePayload({
    required String livraisonId,
    required TypeQR type,
    required int timestamp,
    required int expiration,
  }) {
    // Format stable : chaque champ séparé par ':'
    // L'ordre est critique — toujours le même des deux côtés
    return '$livraisonId:${type.name}:$timestamp:$expiration';
  }

  /// HMAC-SHA256 — renvoie les 16 premiers bytes en hexadécimal
  static String _calculerHMAC({
    required String payload,
    required String cle,
  }) {
    final cleBytes = base64Url.decode(cle);
    final hmac = Hmac(sha256, cleBytes);
    final digest = hmac.convert(utf8.encode(payload));
    // 32 premiers caractères hex (16 bytes) — suffisant, compact
    return digest.toString().substring(0, 32);
  }

  /// Comparaison en temps constant pour éviter les timing attacks
  static bool _comparaisonSecurisee(String a, String b) {
    if (a.length != b.length) return false;
    int resultat = 0;
    for (int i = 0; i < a.length; i++) {
      resultat |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return resultat == 0;
  }
}

// ─── Types de données ─────────────────────────────────────────────────────────

enum RoleLivraison { boutique, livreur, client }

enum RaisonEchec {
  formatInvalide,
  mauvaiseLivraison,
  mauvaistType,
  expire,
  signatureInvalide,
  cleAbsente,
}

class ResultatValidationQR {
  final bool valide;
  final RaisonEchec? raison;
  final String message;
  final TokenQR? token;

  const ResultatValidationQR({
    required this.valide,
    this.raison,
    required this.message,
    this.token,
  });
}

class LivraisonQRSet {
  final String livraisonId;
  final String cleSecrete;    // Ne jamais inclure dans le QR
  final TokenQR tokenDepart;
  final TokenQR tokenArrivee;

  const LivraisonQRSet({
    required this.livraisonId,
    required this.cleSecrete,
    required this.tokenDepart,
    required this.tokenArrivee,
  });

  /// Ce qu'on stocke dans Firestore (clé + tokens encodés)
  Map<String, dynamic> toFirestore() => {
    'cle': cleSecrete,
    'qrDepart': tokenDepart.encode(),
    'qrArrivee': tokenArrivee.encode(),
    'expiration': tokenDepart.expirationUnix,
    'dateCreation': DateTime.now().toIso8601String(),
  };

  /// Ce que le client voit dans son QR (juste le token, pas la clé)
  String get qrClientEncode => tokenArrivee.encode();

  /// Ce que le livreur voit (token départ pour scan en boutique)
  String get qrLivreurDepart => tokenDepart.encode();

  /// Ce que le livreur montre au client (token arrivée)
  String get qrLivreurArrivee => tokenArrivee.encode();
}

class QRLocalData {
  final String cleSecrete;
  final TokenQR? tokenDepart;
  final TokenQR? tokenArrivee;
  final int expirationUnix;

  const QRLocalData({
    required this.cleSecrete,
    this.tokenDepart,
    this.tokenArrivee,
    required this.expirationUnix,
  });

  bool get estExpire =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 > expirationUnix;
}
