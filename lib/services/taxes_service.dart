import 'package:cloud_firestore/cloud_firestore.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// TAXES APPLICABLES PAR CONFIGURATION (app_config/taxes)
///
/// Chaque taxe a un interrupteur `actif` : PAR DÉFAUT TOUT EST INACTIF —
/// rien ne change dans les montants tant que l'admin n'active pas.
/// Quand une taxe B2B est active, elle est DÉDUITE du reversement partenaire
/// et TRACÉE (champ `taxes` + détail) — visible en comptabilité avec son
/// code comptable. Taux, base et cible modifiables sans mise à jour.
/// ═══════════════════════════════════════════════════════════════════════
class TaxesService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic>? _cache;
  static DateTime? _chargeA;

  static Future<List<Map<String, dynamic>>> _actives() async {
    if (_cache == null ||
        _chargeA == null ||
        DateTime.now().difference(_chargeA!).inMinutes >= 5) {
      try {
        final d = await _db.collection('app_config').doc('taxes').get();
        _cache = d.data() ?? {};
        _chargeA = DateTime.now();
      } catch (_) {
        return const [];
      }
    }
    final liste = List<Map<String, dynamic>>.from(
        (_cache!['taxes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    return liste.where((t) => t['actif'] == true).toList();
  }

  static void invaliderCache() => _cache = null;

  /// Total des taxes actives applicables à [base] pour une [cible]
  /// ('boutique' | 'couturier' | 'livreur' | 'client').
  /// Retourne (montantTotal, détails [{nom, taux, montant, code}]).
  static Future<(double, List<Map<String, dynamic>>)> calculer({
    required double base,
    required String cible,
  }) async {
    if (base <= 0) return (0.0, const <Map<String, dynamic>>[]);
    final details = <Map<String, dynamic>>[];
    var total = 0.0;
    for (final t in await _actives()) {
      final cibles = List<String>.from(t['cibles'] as List? ?? []);
      if (!cibles.contains(cible)) continue;
      final taux = (t['taux'] as num?)?.toDouble() ?? 0;
      final fixe = t['montantFixe'] == true;
      final m = fixe ? taux : base * taux / 100;
      if (m <= 0) continue;
      total += m;
      details.add({
        'nom': t['nom'] ?? 'Taxe',
        'taux': taux,
        'fixe': fixe,
        'montant': m,
        'code': t['codeComptable'] ?? '',
      });
    }
    return (total, details);
  }

  /// Catalogue par défaut (contexte camerounais) — proposé à l'admin,
  /// TOUT INACTIF tant qu'il ne bascule pas les interrupteurs.
  static Future<void> initialiserSiVide() async {
    final ref = _db.collection('app_config').doc('taxes');
    final d = await ref.get();
    if (d.exists && (d.data()?['taxes'] as List?)?.isNotEmpty == true) return;
    await ref.set({
      'taxes': [
        {
          'nom': 'TVA',
          'taux': 19.25,
          'montantFixe': false,
          'cibles': ['boutique', 'couturier'],
          'actif': false,
          'codeComptable': '4431',
        },
        {
          'nom': 'Taxe communale',
          'taux': 2.0,
          'montantFixe': false,
          'cibles': ['boutique'],
          'actif': false,
          'codeComptable': '4470',
        },
      ],
    }, SetOptions(merge: true));
  }
}
