import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';

/// PARRAINAGE — les trois lois du système :
/// 1. RIEN n'est crédité à l'inscription (l'auto-parrainage en boucle est
///    LA fraude classique) : le lien est créé « en attente ».
/// 2. La récompense se déclenche à la PREMIÈRE LIVRAISON RÉUSSIE du
///    filleul — un vrai client, une vraie commande, un vrai trajet.
/// 3. Les crédits passent par la file staff (remboursements_a_faire) :
///    personne ne peut augmenter un solde, pas même ce service.
class ParrainageService {
  static final _db = FirebaseFirestore.instance;

  /// Le code du client — lu, ou GÉNÉRÉ à la première demande (6 signes
  /// lisibles, sans O/0/I/1 confondables au téléphone).
  static Future<String> monCode(String uid) async {
    final ref = _db.collection('utilisateurs').doc(uid);
    final doc = await ref.get();
    final existant = doc.data()?['codeParrainage'] as String?;
    if (existant != null && existant.isNotEmpty) return existant;
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    await ref.update({'codeParrainage': code});
    return code;
  }

  /// À l'inscription : crée le LIEN (en attente) — aucun crédit ici.
  static Future<void> appliquerCode(String code, String filleulId) async {
    if (!await ParametresService.parrainageActif()) return;
    final q = await _db
        .collection('utilisateurs')
        .where('codeParrainage', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return;
    final parrainId = q.docs.first.id;
    if (parrainId == filleulId) return; // pas soi-même
    await _db.collection('parrainages').add({
      'parrainId': parrainId,
      'filleulId': filleulId,
      'codeParrainage': code.trim().toUpperCase(),
      'statut': 'enAttente',
      // montants FIGÉS au moment du lien (un changement de paramètre
      // ultérieur ne change pas les promesses déjà faites)
      'recompenseParrain': await ParametresService.recompenseParrainF(),
      'recompenseFilleul': await ParametresService.recompenseFilleulF(),
      'dateCreation': FieldValue.serverTimestamp(),
    });
  }

  /// À chaque livraison réussie : si c'est la PREMIÈRE du filleul,
  /// valider le lien et mettre les deux récompenses dans la file staff.
  static Future<void> validerSiPremiereLivraison(String clientId) async {
    try {
      if (!await ParametresService.parrainageActif()) return;
      final q = await _db
          .collection('parrainages')
          .where('filleulId', isEqualTo: clientId)
          .where('statut', isEqualTo: 'enAttente')
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final d = q.docs.first;
      final p = d.data();
      await d.reference.update(
          {'statut': 'valide', 'valideLe': FieldValue.serverTimestamp()});
      for (final (qui, montant, titre) in [
        (p['parrainId'] as String? ?? '',
            (p['recompenseParrain'] as num? ?? 0).toDouble(),
            'Parrainage réussi 🎉'),
        (clientId, (p['recompenseFilleul'] as num? ?? 0).toDouble(),
            'Bienvenue récompensée 🎁'),
      ]) {
        await _db.collection('remboursements_a_faire').add({
          'clientId': qui,
          'montant': montant,
          'type': 'parrainage',
          'refPaiement': 'PARRAINAGE_${d.id}',
          'statut': 'a_traiter',
          'dateCreation': FieldValue.serverTimestamp(),
        });
        await NotificationService.envoyer(
          destinataireId: qui,
          titre: titre,
          message:
              '$montant F de crédits arrivent sur votre compte (validation en cours).',
          route: '/moncompte',
        );
      }
    } catch (_) {}
  }
}
