import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REÇUS AUTHENTIFIÉS — « pour servir ce que de droit »
//
// Chaque reçu (vente complétée, confection livrée, reversement partenaire)
// est numéroté, horodaté et SIGNÉ (HMAC-SHA256 avec la clé plateforme).
// Le QR du reçu contient le contenu + la signature : toute modification
// (montant, nom, date) invalide la signature → falsification détectable.
// Double garantie : le document existe aussi dans Firestore ('recus') —
// un reçu présenté peut être vérifié par scan (signature) ET par n° (base).
// ═══════════════════════════════════════════════════════════════════════════

class RecuService {
  static final _db = FirebaseFirestore.instance;

  /// Clé de signature plateforme (app_config/recus.cle). Créée au 1er usage.
  static Future<String> _cle() async {
    final ref = _db.collection('app_config').doc('recus');
    final doc = await ref.get();
    var cle = doc.data()?['cle'] as String?;
    if (cle == null) {
      cle = base64Encode(
          List<int>.generate(32, (i) => DateTime.now().microsecond + i * 7));
      await ref.set({'cle': cle}, SetOptions(merge: true));
    }
    return cle;
  }

  static String _signer(String contenu, String cle) =>
      Hmac(sha256, utf8.encode(cle)).convert(utf8.encode(contenu)).toString();

  /// Crée (ou retourne s'il existe) le reçu d'une référence donnée.
  /// [type] : 'vente' | 'couture' | 'reversement'
  /// [beneficiaireId] : qui détient ce reçu (client ou partenaire payé).
  static Future<Map<String, dynamic>> creer({
    required String type,
    required String refId,
    required String beneficiaireId,
    required String beneficiaireNom,
    required double montant,
    required String detail,
    String? contrepartie,
  }) async {
    // Idempotent : un reçu par (type, refId, beneficiaireId)
    final exist = await _db
        .collection('recus')
        .where('refId', isEqualTo: refId)
        .where('beneficiaireId', isEqualTo: beneficiaireId)
        .where('type', isEqualTo: type)
        .limit(1)
        .get();
    if (exist.docs.isNotEmpty) {
      return {'id': exist.docs.first.id, ...exist.docs.first.data()};
    }

    final now = DateTime.now();
    final numero =
        'SAMI-${now.year}-${refId.substring(0, refId.length.clamp(0, 6)).toUpperCase()}'
        '${now.millisecondsSinceEpoch.toString().substring(8)}';
    final corps = {
      'numero': numero,
      'type': type,
      'refId': refId,
      'beneficiaireId': beneficiaireId,
      'beneficiaireNom': beneficiaireNom,
      'contrepartie': contrepartie ?? 'SAMI',
      'montant': montant,
      'detail': detail,
      'dateISO': now.toIso8601String(),
    };
    final canonique = jsonEncode(
        Map.fromEntries(corps.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    final cle = await _cle();
    final signature = _signer(canonique, cle);
    final data = {...corps, 'signature': signature,
        'date': FieldValue.serverTimestamp()};
    final ref = await _db.collection('recus').add(data);
    return {'id': ref.id, ...data};
  }

  /// Contenu du QR : payload canonique + signature (auto-vérifiable).
  static String qrDeRecu(Map<String, dynamic> r) {
    final corps = {
      for (final k in ['numero','type','refId','beneficiaireId',
          'beneficiaireNom','contrepartie','montant','detail','dateISO'])
        k: r[k]
    };
    final canonique = jsonEncode(Map.fromEntries(
        corps.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    return base64Encode(utf8.encode(
        jsonEncode({'c': canonique, 's': r['signature']})));
  }

  /// Vérifie un QR de reçu scanné. Retourne (authentique, contenu|null).
  static Future<(bool, Map<String, dynamic>?)> verifier(String qr) async {
    try {
      final m = jsonDecode(utf8.decode(base64Decode(qr)))
          as Map<String, dynamic>;
      final canonique = m['c'] as String? ?? '';
      final sig = m['s'] as String? ?? '';
      final cle = await _cle();
      final ok = _signer(canonique, cle) == sig;
      return (ok, jsonDecode(canonique) as Map<String, dynamic>);
    } catch (_) {
      return (false, null);
    }
  }

  /// Reçus de l'utilisateur courant (client ou partenaire).
  static Stream<List<Map<String, dynamic>>> mesRecus() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('recus')
        .where('beneficiaireId', isEqualTo: uid)
        .snapshots()
        .map((s) {
      final l = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) =>
            (b['dateISO'] as String? ?? '').compareTo(a['dateISO'] as String? ?? ''));
      return l;
    });
  }
}
