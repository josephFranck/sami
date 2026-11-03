import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/l10n/tr.dart';

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

  /// Le FILLEUL réclame lui-même (depuis SON téléphone) la validation de
  /// son parrainage dès qu'il a une sous-commande livrée.
  ///
  /// Pourquoi côté client : l'ancienne version tournait sur le téléphone du
  /// LIVREUR au scan d'arrivée — lecture de `parrainages` et création dans
  /// `remboursements_a_faire` au nom d'un tiers, refusées par les règles
  /// (sauf livreur staff) : les récompenses n'étaient jamais mises en file.
  ///
  /// Preuve vérifiée par les RÈGLES (pas par ce code) :
  ///  - `parrainages` : le filleul passe enAttente → valide en citant
  ///    `premiereLivraisonId`, une sous-commande à SON nom au statut `livree` ;
  ///  - `remboursements_a_faire/PARRAINAGE_<id>_parrain|_filleul` : ids
  ///    DÉTERMINISTES (create seulement → aucun doublon possible), montants
  ///    = ceux figés sur le lien, bénéficiaires = parrainId / filleulId.
  /// Idempotent : rien à faire si le lien n'est plus `enAttente`.
  static Future<void> reclamerSiPremiereLivraison(String clientId) async {
    try {
      if (!await ParametresService.parrainageActif()) return;
      final q = await _db
          .collection('parrainages')
          .where('filleulId', isEqualTo: clientId)
          .where('statut', isEqualTo: 'enAttente')
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final livree = await _db
          .collection('sous_commandes')
          .where('clientId', isEqualTo: clientId)
          .where('statut', isEqualTo: 'livree')
          .limit(1)
          .get();
      if (livree.docs.isEmpty) return;
      final d = q.docs.first;
      final p = d.data();
      final parrainId = p['parrainId'] as String? ?? '';
      final gainParrain = (p['recompenseParrain'] as num? ?? 0).toDouble();
      final gainFilleul = (p['recompenseFilleul'] as num? ?? 0).toDouble();

      // 1) le lien passe « valide » (règle : filleul + preuve de livraison)
      await d.reference.update({
        'statut': 'valide',
        'valideLe': FieldValue.serverTimestamp(),
        'premiereLivraisonId': livree.docs.first.id,
      });

      // 2) les deux récompenses, ids déterministes (règle : lien valide,
      //    montants et bénéficiaires relus sur le lien)
      for (final (suffixe, qui, montant, titre) in [
        ('parrain', parrainId, gainParrain, 'Parrainage réussi 🎉'),
        ('filleul', clientId, gainFilleul, 'Bienvenue récompensée 🎁'),
      ]) {
        if (qui.isEmpty || montant <= 0) continue;
        try {
          await _db
              .collection('remboursements_a_faire')
              .doc('PARRAINAGE_${d.id}_$suffixe')
              .set({
            'clientId': qui,
            'montant': montant,
            'type': 'parrainage',
            'parrainageId': d.id,
            'refPaiement': 'PARRAINAGE_${d.id}',
            'statut': 'a_traiter',
            'dateCreation': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          continue; // déjà créé (replay) : on n'avertit pas deux fois
        }
        await NotificationService.envoyer(
          destinataireId: qui,
          titre: titre,
          message:
              (Tr t) => t.fAvoirArriventSurVotre(montant.round()),
          route: '/moncompte',
        );
      }
    } catch (_) {}
  }
}
