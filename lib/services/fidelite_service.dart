import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/config_marketing_service.dart';
import 'package:sami/services/parrainage_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// FIDÉLITÉ — UNE source : `utilisateurs.pointsFidelite` + les paliers de
/// la CONFIG ADMIN (`config_marketing/parametres`), les mêmes que le devis
/// (`DevisCommandeService`) utilise pour la réduction de livraison.
///
/// Avant : `livraison_service._crediterFidelite` écrivait `points` (champ
/// que personne ne lisait) avec les paliers constants de
/// `NiveauFidelite`, depuis le téléphone du LIVREUR — écriture sur le doc
/// d'un tiers, refusée par les règles (`utilisateurs` : soi-même ou staff).
/// Les points n'avançaient donc jamais, et « Mon compte » affichait des
/// paliers différents de ceux du devis.
///
/// Maintenant : le CLIENT réclame lui-même (à l'ouverture de l'accueil et
/// de « Mes commandes ») les points de ses sous-commandes livrées non
/// encore comptées. Idempotent : la sous-commande porte `fideliteCreditee`
/// (que les règles n'autorisent jamais à remettre à false) et la hausse de
/// `pointsFidelite` est BORNÉE par les règles au montant de la sous-commande
/// citée dans `scFidelite` — un client à l'app modifiée ne s'invente pas de
/// points. Le statut d'une sous-commande n'est jamais changé par le client.
/// Le cashback du palier (si > 0 dans la config) devient un AVOIR via la
/// file staff `remboursements_a_faire` (id déterministe `CASHBACK_<sc>`,
/// création seule → jamais en double) — jamais une augmentation directe
/// de `creditBalance` (interdite par les règles).
/// ═══════════════════════════════════════════════════════════════════════
class FideliteService {
  static final _db = FirebaseFirestore.instance;
  static ConfigMarketing? _config;
  static DateTime? _configLe;

  /// Config marketing (cache 5 min) — paliers, FCFA par point.
  static Future<ConfigMarketing> config() async {
    final c = _config;
    if (c != null &&
        _configLe != null &&
        DateTime.now().difference(_configLe!).inMinutes < 5) {
      return c;
    }
    final charge = await ConfigMarketingService.charger();
    _config = charge;
    _configLe = DateTime.now();
    return charge;
  }

  /// Palier atteint pour un nombre de points (le plus haut dont le seuil
  /// est atteint ; le premier palier sinon).
  static PalierConfig palierPour(ConfigMarketing c, int points) {
    var palier = c.paliers.first;
    for (final p in c.paliers) {
      if (points >= p.pointsRequis) palier = p;
    }
    return palier;
  }

  /// Palier suivant (null si déjà au dernier).
  static PalierConfig? palierSuivant(ConfigMarketing c, int points) {
    final actuel = palierPour(c, points);
    final i = c.paliers.indexOf(actuel);
    return i + 1 < c.paliers.length ? c.paliers[i + 1] : null;
  }

  /// Tout ce que le client réclame à l'ouverture : points des livraisons
  /// non comptées, puis parrainage (première livraison). Silencieux.
  static Future<void> reclamerTout(String clientId) async {
    await reclamerPoints(clientId);
    await ParrainageService.reclamerSiPremiereLivraison(clientId);
  }

  /// Crédite les points (et met en file le cashback) de chaque
  /// sous-commande livrée non encore comptée. Retourne le nombre de
  /// sous-commandes traitées.
  static Future<int> reclamerPoints(String clientId) async {
    int traitees = 0;
    try {
      final c = await config();
      final fcfaParPoint = c.fcfaParPoint > 0 ? c.fcfaParPoint : 100;
      final snap = await _db
          .collection('sous_commandes')
          .where('clientId', isEqualTo: clientId)
          .where('statut', isEqualTo: 'livree')
          .limit(50)
          .get();
      final aFaire =
          snap.docs.where((d) => d.data()['fideliteCreditee'] != true);
      final userRef = _db.collection('utilisateurs').doc(clientId);

      for (final sc in aFaire) {
        final montant = (sc.data()['totalClient'] as num?)?.toDouble() ?? 0;
        final gagnes = (montant / fcfaParPoint).floor();
        double cashback = 0;
        final ok = await _db.runTransaction<bool>((tx) async {
          final scDoc = await tx.get(sc.reference);
          if (scDoc.data()?['fideliteCreditee'] == true) return false;
          final uDoc = await tx.get(userRef);
          final actuels =
              (uDoc.data()?['pointsFidelite'] as num?)?.toInt() ?? 0;
          final nouveaux = actuels + gagnes;
          final palier = palierPour(c, nouveaux);
          cashback = PrixFCFA.arrondirAu50(montant * palier.cashback / 100);
          tx.update(sc.reference, {
            'fideliteCreditee': true,
            'pointsFidelite': gagnes,
          });
          tx.update(userRef, {
            'pointsFidelite': nouveaux,
            'niveau': c.paliers.indexOf(palier) + 1,
            // PREUVE pour les règles : la sous-commande livrée, à mon nom,
            // pas encore comptée, dont le montant borne la hausse de points
            'scFidelite': sc.id,
          });
          return true;
        });
        if (!ok) continue;
        traitees++;
        if (cashback > 0) {
          try {
            await _db
                .collection('remboursements_a_faire')
                .doc('CASHBACK_${sc.id}')
                .set({
              'clientId': clientId,
              'montant': cashback,
              'type': 'cashback',
              'sousCommandeId': sc.id,
              'refPaiement': 'CASHBACK_${sc.id}',
              'statut': 'a_traiter',
              'dateCreation': FieldValue.serverTimestamp(),
            });
          } catch (_) {} // déjà en file (replay) — jamais deux fois
        }
      }
    } catch (_) {}
    return traitees;
  }
}
