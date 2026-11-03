import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sami/services/parametres_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE STOCKAGE — Switch Firebase Storage ↔ Cloudflare R2
//
// Comment switcher vers Cloudflare R2 :
// ──────────────────────────────────────
// 1. Créer un bucket R2 sur dash.cloudflare.com
// 2. Créer un Worker R2 (ou utiliser l'API S3-compatible)
// 3. Renseigner les 3 constantes ci-dessous
// 4. Appeler StockageService.activerCloudflare(true)
//
// Coûts comparatifs :
// ──────────────────────────────────────
// Firebase Storage : $0.026/Go stocké + $0.12/Go téléchargé
// Cloudflare R2    : $0.015/Go stocké + 0$/Go téléchargé (egress GRATUIT)
// → R2 est ~2x moins cher au stockage + GRATUIT pour les téléchargements
// ═══════════════════════════════════════════════════════════════════════════

// ── Configuration Cloudflare R2 (à remplir quand tu migres) ──────────────
/// Jeton d'authentification pour le worker : le JETON FIREBASE de
/// l'utilisateur connecté (vérifié par le worker contre les clés
/// publiques Google). Repli : token partagé si posé explicitement
/// dans le code (déploiements existants) — jamais lu depuis Firestore.
Future<String> _jetonAuth() async {
  try {
    final t = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (t != null && t.isNotEmpty) return t;
  } catch (_) {}
  return _R2Config.authToken;
}

class _R2Config {
  // Ton URL publique R2 (ex: https://pub-xxx.r2.dev)
  // ou ton domaine custom (ex: https://media.sami-garoua.com)
  static String urlPublique = 'https://TON_URL_R2_ICI';

  // URL de ton Worker Cloudflare pour les uploads authentifiés
  // Worker minimal : reçoit le fichier, l'upload dans R2, retourne l'URL
  // DYNAMIQUE : chargé depuis Firestore app_config/stockage — vos clés
  // survivent aux mises à jour du code. Les valeurs ci-dessous ne sont
  // que des replis si le doc n'existe pas.
  static String workerUrl = 'https://TON_WORKER_ICI';

  // Token d'authentification pour le Worker (depuis Cloudflare Dashboard)
  static String authToken = 'TON_TOKEN_ICI';
}

// ── Fournisseur de stockage ───────────────────────────────────────────────
enum FournisseurStockage { firebase, cloudflare, local }

class StockageService {

  static const _kPrefsKey = 'stockage_fournisseur';
  // Mode 'local' par défaut : images en base64 dans Firestore
  // (temporaire — Firebase Storage exige le plan Blaze, R2 pas encore configuré)
  static FournisseurStockage _fournisseur = FournisseurStockage.local;

  // ── Initialisation ────────────────────────────────────────────────────────
  static Future<void> init() async {
    // Config R2 depuis Firestore (app_config/stockage) — remplace les
    // constantes si présente ; renseignée UNE fois, jamais ré-écrasée
    // par les mises à jour du code.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config').doc('stockage').get();
      final d = doc.data();
      if (d != null) {
        if ((d['workerUrl'] as String?)?.startsWith('http') ?? false) {
          _R2Config.workerUrl = d['workerUrl'] as String? ?? '';
        }
        // SÉCURITÉ : le token partagé n'est PLUS lu ici — un document
        // Firestore lisible par les clients n'est pas un coffre. L'auth
        // du worker passe par le JETON FIREBASE de l'utilisateur connecté
        // (vérifié côté worker) : aucun secret dans l'app ni en base.
        if ((d['urlPublique'] as String?)?.startsWith('http') ?? false) {
          _R2Config.urlPublique = d['urlPublique'] as String? ?? '';
        }
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_kPrefsKey);
    if (val == 'cloudflare') {
      _fournisseur = FournisseurStockage.cloudflare;
    }
    if (kDebugMode) print('[Stockage] Fournisseur : $_fournisseur');
  }

  static FournisseurStockage get fournisseur => _fournisseur;
  static bool get estCloudflare => _fournisseur == FournisseurStockage.cloudflare;
  static bool get estFirebase => _fournisseur == FournisseurStockage.firebase;
  static bool get estLocal => _fournisseur == FournisseurStockage.local;

  // ── Switch fournisseur (admin uniquement) ─────────────────────────────────
  static Future<void> activerCloudflare(bool activer) async {
    _fournisseur = activer
        ? FournisseurStockage.cloudflare
        : FournisseurStockage.firebase;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, activer ? 'cloudflare' : 'firebase');
    if (kDebugMode) print('[Stockage] Switché vers : $_fournisseur');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MÉTHODE PRINCIPALE D'UPLOAD
  // Même API pour les deux fournisseurs — le code appelant ne change pas
  // ═══════════════════════════════════════════════════════════════════════

  /// Upload un fichier et retourne son URL publique
  static Future<String> uploadFichier({
    required File fichier,
    required String dossier,    // ex: 'pagnes', 'profils', 'boutiques'
    String? nomFichier,
    ProgressCallback? onProgress,
  }) async {
    final nom = nomFichier ??
        '${DateTime.now().millisecondsSinceEpoch}_${fichier.path.split('/').last}';
    final chemin = '$dossier/$nom';

    if (estLocal) {
      return _uploadLocal(fichier: fichier);
    }
    return estCloudflare
        ? _uploadCloudflare(fichier: fichier, chemin: chemin, onProgress: onProgress)
        : _uploadFirebase(fichier: fichier, chemin: chemin, onProgress: onProgress);
  }

  /// Upload depuis bytes (utile pour images compressées)
  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String dossier,
    required String nomFichier,
    String contentType = 'image/jpeg',
    ProgressCallback? onProgress,
  }) async {
    final chemin = '$dossier/$nomFichier';
    if (estLocal) {
      return _uploadBytesLocal(bytes: bytes, contentType: contentType);
    }
    return estCloudflare
        ? _uploadBytesCloudflare(bytes: bytes, chemin: chemin, contentType: contentType)
        : _uploadBytesFirebase(bytes: bytes, chemin: chemin, contentType: contentType);
  }

  /// Upload multiple (pagnes avec plusieurs photos)
  /// MULTIPLATEFORME (web/iOS/Android) : upload depuis un XFile via ses
  /// octets — aucun dart:io, donc fonctionne aussi dans le navigateur.
  static Future<String> uploadXFile({
    required XFile fichier,
    required String dossier,
    String? nomFichier, // optionnel : généré si absent
    String contentType = 'image/jpeg',
    ProgressCallback? onProgress,
    bool hd = false, // qualité HD (boutiques abonnées)
  }) async {
    final brut = await fichier.readAsBytes();
    // COMPRESSION ICI — c'est LE chemin réel des photos de pagnes.
    // (Avant : les octets partaient BRUTS → dépassements du 1 Mo local.)
    final bytes = await compresserBytes(brut, hd: hd);
    return uploadBytes(
      bytes: bytes,
      dossier: dossier,
      nomFichier: nomFichier ??
          '${DateTime.now().millisecondsSinceEpoch}_${fichier.name}',
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  /// Compression sur OCTETS (multiplateforme, web inclus) avec les
  /// réglages paramétrables : local = serré (1 Mo), standard, ou HD.
  static Future<Uint8List> compresserBytes(Uint8List brut,
      {bool hd = false}) async {
    final int q;
    final int l;
    if (estLocal) {
      q = 50;
      l = 720;
    } else if (hd) {
      q = await ParametresService.imageQualiteAbonnePct();
      l = await ParametresService.imageLargeurAbonneMax();
    } else {
      q = await ParametresService.imageQualitePct();
      l = await ParametresService.imageLargeurMax();
    }
    try {
      final res = await FlutterImageCompress.compressWithList(
        brut,
        quality: q,
        minWidth: l,
      );
      if (res.isNotEmpty) return res;
    } catch (_) {}
    // deuxième passe agressive, sinon refus explicite (jamais l'originale
    // en mode local : Firestore la rejetterait)
    try {
      final retry = await FlutterImageCompress.compressWithList(
        brut,
        quality: 40,
        minWidth: 640,
      );
      if (retry.isNotEmpty) return retry;
    } catch (_) {}
    if (estLocal) {
      throw Exception(
          'Photo trop lourde ou format non supporté — reprenez-la.');
    }
    return brut; // R2/Firebase : l'originale reste acceptable
  }

  static Future<List<String>> uploadMultipleXFiles({
    required List<XFile> fichiers,
    required String dossier,
    ProgressCallback? onProgress,
    bool hd = false, // qualité HD (boutiques abonnées)
  }) async {
    final futures = fichiers.map((x) => uploadXFile(
        fichier: x, dossier: dossier, onProgress: onProgress, hd: hd));
    return Future.wait(futures);
  }

  static Future<List<String>> uploadMultiple({
    required List<File> fichiers,
    required String dossier,
    ProgressCallback? onProgress,
  }) async {
    final futures = fichiers.map((f) => uploadFichier(
      fichier: f,
      dossier: dossier,
      onProgress: onProgress,
    ));
    return Future.wait(futures);
  }

  /// Supprimer un fichier par son URL
  static Future<void> supprimerFichier(String url) async {
    try {
      // Mode local : l'image est en base64 dans le document, rien à supprimer ici
      if (estLocal) return;
      if (estCloudflare) {
        await _supprimerCloudflare(url);
      } else {
        await _supprimerFirebase(url);
      }
    } catch (e) {
      if (kDebugMode) print('[Stockage] Erreur suppression : $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // IMPLÉMENTATION FIREBASE STORAGE
  // ═══════════════════════════════════════════════════════════════════════

  static Future<String> _uploadFirebase({
    required File fichier,
    required String chemin,
    ProgressCallback? onProgress,
  }) async {
    final ref = FirebaseStorage.instance.ref().child(chemin);
    final task = ref.putFile(fichier);

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        final pct = snap.bytesTransferred / snap.totalBytes;
        onProgress(pct);
      });
    }

    final snapshot = await task;
    return snapshot.ref.getDownloadURL();
  }

  static Future<String> _uploadBytesFirebase({
    required Uint8List bytes,
    required String chemin,
    required String contentType,
  }) async {
    final ref = FirebaseStorage.instance.ref().child(chemin);
    final meta = SettableMetadata(contentType: contentType);
    final task = await ref.putData(bytes, meta);
    return task.ref.getDownloadURL();
  }

  static Future<void> _supprimerFirebase(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
    } catch (e) {
      if (kDebugMode) print('[Firebase] Erreur suppression : $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // IMPLÉMENTATION CLOUDFLARE R2
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Architecture recommandée :
  //   App Flutter → Cloudflare Worker → R2 Bucket
  //
  // Le Worker authentifie la requête et gère l'upload dans R2.
  // L'app ne communique JAMAIS directement avec R2 (pas de credentials exposés).
  //
  // Worker minimal (JavaScript) à déployer sur Cloudflare :
  // ──────────────────────────────────────────────────────
  // export default {
  //   async fetch(request, env) {
  //     if (request.method !== 'PUT') return new Response('Method not allowed', {status: 405});
  //     const auth = request.headers.get('Authorization');
  //     if (auth !== `Bearer ${env.AUTH_TOKEN}`) return new Response('Unauthorized', {status: 401});
  //     const key = request.headers.get('X-File-Key');
  //     await env.R2_BUCKET.put(key, request.body, {
  //       httpMetadata: { contentType: request.headers.get('Content-Type') }
  //     });
  //     return new Response(JSON.stringify({ url: `${env.PUBLIC_URL}/${key}` }), {
  //       headers: { 'Content-Type': 'application/json' }
  //     });
  //   }
  // }

  static Future<String> _uploadCloudflare({
    required File fichier,
    required String chemin,
    ProgressCallback? onProgress,
  }) async {
    final bytes = await fichier.readAsBytes();
    final ext = fichier.path.split('.').last.toLowerCase();
    final contentType = _contentType(ext);
    return _uploadBytesCloudflare(bytes: bytes, chemin: chemin, contentType: contentType);
  }

  static Future<String> _uploadBytesCloudflare({
    required Uint8List bytes,
    required String chemin,
    required String contentType,
  }) async {
    if (_R2Config.workerUrl == 'https://TON_WORKER_ICI') {
      throw Exception(
        'Cloudflare R2 non configuré.\n'
        'Renseigne _R2Config.workerUrl et _R2Config.authToken\n'
        'dans lib/services/stockage_service.dart',
      );
    }

    final response = await http.post(
      Uri.parse('${_R2Config.workerUrl}/upload'),
      headers: {
        'Authorization': 'Bearer ${await _jetonAuth()}',
        'Content-Type': contentType,
        'X-Filename': chemin,
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw Exception('Cloudflare R2 erreur ${response.statusCode} : ${response.body}');
    }

    // Le Worker retourne {"url": "https://..."} → on construit l'URL publique
    return '${_R2Config.urlPublique}/$chemin';
  }

  static Future<void> _supprimerCloudflare(String url) async {
    final chemin = url.replaceFirst('${_R2Config.urlPublique}/', '');
    await http.delete(
      Uri.parse('${_R2Config.workerUrl}/delete?file=$chemin'),
      headers: {
        'Authorization': 'Bearer ${await _jetonAuth()}',
      },
    );
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  static String _contentType(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png'  => 'image/png',
    'webp' => 'image/webp',
    'gif'  => 'image/gif',
    'pdf'  => 'application/pdf',
    'mp4'  => 'video/mp4',
    _      => 'application/octet-stream',
  };

  /// Construire une URL miniature (si tu utilises Cloudflare Image Resizing)
  static String urlMiniature(String urlOriginal, {int largeur = 300}) {
    if (estCloudflare && !urlOriginal.contains('/cdn-cgi/')) {
      return '$urlOriginal?width=$largeur&format=webp&quality=80';
    }
    return urlOriginal;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODE LOCAL (TEMPORAIRE) — image base64 dans Firestore
  // À remplacer par Cloudflare R2 avant la production.
  // Firestore limite un document à 1 Mo → compresser l'image avant upload.
  // ═══════════════════════════════════════════════════════════════════════

  static Future<String> _uploadLocal({required File fichier}) async {
    // Compresser fortement avant base64 (limite Firestore 1 Mo/document)
    // (chemin File — utilise les mêmes réglages via compresserBytes)
    final bytes =
        await compresserBytes(await fichier.readAsBytes());
    return _encoderBase64(bytes);
  }

  /// Compresse une image et retourne ses bytes.
  /// qualite : 0-100 (60 = bon compromis). largeurMax : redimensionne si plus large.
  static Future<Uint8List> compresserImage(
    File fichier, {
    int qualite = 70,
    int largeurMax = 1080,
  }) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        fichier.absolute.path,
        quality: qualite,
        minWidth: largeurMax,
        minHeight: largeurMax,
        format: CompressFormat.jpeg,
      );
      if (result != null) return result;
    } catch (e) {
      if (kDebugMode) print('[Stockage] Compression échouée, image originale utilisée: $e');
    }
    // PAS de retour d'originale : un doc Firestore > 1 Mo serait rejeté
    // (invalid-argument). On tente une deuxième passe plus agressive.
    try {
      final retry = await FlutterImageCompress.compressWithFile(
        fichier.path,
        quality: 40,
        minWidth: 640,
      );
      if (retry != null) return retry;
    } catch (_) {}
    throw Exception(
        'Photo trop lourde ou format non supporté — reprenez-la ou choisissez-en une autre.');
  }

  static Future<String> _uploadBytesLocal({
    required Uint8List bytes,
    required String contentType,
  }) async {
    return _encoderBase64(bytes, contentType: contentType);
  }

  static String _encoderBase64(Uint8List bytes, {String contentType = 'image/jpeg'}) {
    if (bytes.lengthInBytes > 700 * 1024) {
      if (kDebugMode) {
        print('[Stockage] ⚠️ Image volumineuse (${(bytes.lengthInBytes / 1024).round()} Ko). '
            'Compressez-la (max ~700 Ko pour Firestore) ou migrez vers Cloudflare R2.');
      }
    }
    final b64 = base64Encode(bytes);
    return 'data:$contentType;base64,$b64';
  }
}

/// Callback de progression (0.0 → 1.0)
typedef ProgressCallback = void Function(double progression);