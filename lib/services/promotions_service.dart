import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/l10n/tr.dart';

/// PROMOTIONS : le boutiquier PROPOSE (sur un pagne, plusieurs, ou toute
/// sa boutique), l'admin VALIDE — avec garde anti-perte : jamais sous le
/// prix plancher déclaré, alerte rouge si sous le coût d'achat.
class PromotionsService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get collection =>
      _db.collection('promotions');

  /// Analyse d'impact AVANT proposition/validation : pour chaque pagne
  /// ciblé, le prix réduit vs plancher vs coût d'achat.
  static Future<List<Map<String, dynamic>>> analyserImpact({
    required List<String> pagneIds,
    required double reductionPct,
  }) async {
    final res = <Map<String, dynamic>>[];
    for (final id in pagneIds) {
      final d = await _db.collection('pagnes').doc(id).get();
      final data = d.data();
      if (data == null) continue;
      final prix = (data['prixParBoutique'] as num?)?.toDouble() ?? 0;
      final manuel = (data['prixPlancher'] as num?)?.toDouble();
      final fin = data['_finance'] as Map?;
      final cout = (fin?['coutAchat'] as num?)?.toDouble();
      final commission = (fin?['commission'] as num?)?.toDouble() ?? 0;
      // PLANCHER EFFECTIF : le prix d'achat SEUL n'est pas un plancher —
      // vendre au coût d'achat = perte (la commission se déduit encore).
      // Défaut automatique = SEUIL DE RENTABILITÉ (coût + commission) ;
      // le boutiquier peut déclarer PLUS HAUT (son minimum vital).
      final seuilRentabilite =
          cout != null ? PrixFCFA.arrondirAu50(cout + commission) : null;
      final plancher = manuel ?? seuilRentabilite;
      final reduit =
          PrixFCFA.arrondirAu50(prix * (1 - reductionPct / 100));
      res.add({
        'pagneId': id,
        'nom': data['nom'] ?? '?',
        'prix': prix,
        'prixReduit': reduit,
        'plancher': plancher,
        'plancherManuel': manuel != null,
        'coutAchat': cout,
        'sousPlancher': plancher != null && reduit < plancher,
        'perte': cout != null && reduit < cout,
      });
    }
    return res;
  }

  /// Le boutiquier PROPOSE. Bloqué net si un pagne passe sous son
  /// plancher (c'est SA propre limite déclarée à la création).
  static Future<String> proposer({
    required String boutiqueId,
    required String proposePar,
    required List<String> pagneIds, // vide = toute la boutique
    required double reductionPct,
    required Duration duree,
  }) async {
    var cibles = pagneIds;
    if (cibles.isEmpty) {
      final q = await _db
          .collection('pagnes')
          .where('boutiqueId', isEqualTo: boutiqueId)
          .get();
      cibles = q.docs.map((d) => d.id).toList();
    }
    final impact =
        await analyserImpact(pagneIds: cibles, reductionPct: reductionPct);
    final bloques = impact.where((i) => i['sousPlancher'] == true).toList();
    if (bloques.isNotEmpty) {
      throw Exception(
          'Promotion refusée : ${bloques.length} pagne(s) passeraient sous '
          'le plancher (ex: « ${bloques.first['nom']} » — '
          '${PrixFCFA.formater((bloques.first['prixReduit'] as num? ?? 0).toDouble())} '
          '< plancher ${PrixFCFA.formater((bloques.first['plancher'] as num? ?? 0).toDouble())}).');
    }
    final doc = await collection.add({
      'boutiqueId': boutiqueId,
      'proposePar': proposePar,
      'pagneIds': cibles,
      'reductionPct': reductionPct,
      'dureeHeures': duree.inHours,
      'statut': 'proposee',
      'dateCreation': FieldValue.serverTimestamp(),
      'impact': impact,
      'pertes': impact.where((i) => i['perte'] == true).length,
    });
    // prévenir les admins (validation requise)
    final admins = await _db
        .collection('utilisateurs')
        .where('role', isEqualTo: 'admin')
        .limit(5)
        .get();
    for (final a in admins.docs) {
      await NotificationService.envoyer(
        destinataireId: a.id,
        titre: (t) => t.promotionValider,
        message:
            (t) => t.surPagneSExaminer(reductionPct.toStringAsFixed(0), cibles.length),
        route: '/admin-promotions',
      );
    }
    return doc.id;
  }

  /// L'admin VALIDE → la promo S'APPLIQUE aux pagnes : le prix courant
  /// devient le barré (vrai barré !), le prix réduit devient le prix,
  /// mention 'promotion', échéance posée.
  static Future<void> valider(String promoId) async {
    final d = await collection.doc(promoId).get();
    final data = d.data()!;
    final fin = DateTime.now()
        .add(Duration(hours: (data['dureeHeures'] as num? ?? 0).toInt()));
    final pct = (data['reductionPct'] as num? ?? 0).toDouble();
    final batch = _db.batch();
    for (final id in List<String>.from(data['pagneIds'] ?? [])) {
      final pRef = _db.collection('pagnes').doc(id);
      final p = await pRef.get();
      final prix = (p.data()?['prixParBoutique'] as num?)?.toDouble() ?? 0;
      batch.update(pRef, {
        'prixAvantPromo': prix,
        'prixBarre': prix, // le VRAI ancien prix, barré honnêtement
        'prixParBoutique': PrixFCFA.arrondirAu50(prix * (1 - pct / 100)),
        'mention': 'promotion',
        'promoFinLe': fin,
      });
    }
    batch.update(collection.doc(promoId),
        {'statut': 'active', 'finLe': fin, 'valideeLe': FieldValue.serverTimestamp()});
    await batch.commit();
    await NotificationService.envoyer(
      destinataireId: data['proposePar'] as String? ?? '',
      titre: (t) => t.promotionValidee,
      message: (t) => t.votrePromotionEstLigne(pct.toStringAsFixed(0)),
      route: '/dashboard_boutiquier',
    );
  }

  static Future<void> refuser(String promoId, String motif) async {
    final d = await collection.doc(promoId).get();
    await collection.doc(promoId).update({'statut': 'refusee', 'motifRefus': motif});
    await NotificationService.envoyer(
      destinataireId: d.data()!['proposePar'] as String? ?? '',
      titre: (t) => t.promotionRefusee,
      message: motif,
      route: '/dashboard_boutiquier',
    );
  }

  /// RESTAURATION des promos expirées (appelée à l'ouverture des pages
  /// gestion/admin — pas de serveur, donc restauration « paresseuse »).
  static DateTime? _dernierRestaure;
  static Future<int> restaurerExpirees() async {
    // throttle : appelée depuis des build() — pas plus d'1 fois / 5 min
    if (_dernierRestaure != null &&
        DateTime.now().difference(_dernierRestaure!).inMinutes < 5) {
      return 0;
    }
    _dernierRestaure = DateTime.now();
    final q = await _db
        .collection('pagnes')
        .where('promoFinLe', isLessThan: DateTime.now())
        .limit(50)
        .get();
    if (q.docs.isEmpty) return 0;
    var n = 0;
    // updates INDIVIDUELS : si les règles refusent un pagne (autre
    // boutique), les autres restaurations passent quand même.
    for (final d in q.docs) {
      final avant = (d.data()['prixAvantPromo'] as num?)?.toDouble();
      try {
        await d.reference.update({
          if (avant != null) 'prixParBoutique': avant,
          'prixBarre': null,
          'prixAvantPromo': null,
          'promoFinLe': null,
          'mention': 'aucun',
        });
        n++;
      } catch (_) {}
    }
    return n;
  }
}
