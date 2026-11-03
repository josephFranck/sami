import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/recu_service.dart';
import 'package:sami/services/taxes_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE REVERSEMENT (admin)
//
// Permet à l'admin de verser à chaque acteur sa part sur une sous-commande :
//   - Boutiquier : netBoutique
//   - Livreur    : gainLivreur
//   - Couturier  : netCouturier
//   - Plateforme : commissionPlateforme (revenu, pas un reversement)
//
// Chaque reversement :
//   1. crédite le creditBalance du destinataire (boutique/livreur/couturier)
//   2. trace l'opération dans la collection 'reversements'
//   3. marque la part comme "reversée" sur la sous-commande (évite double paiement)
//
// NB : "créditer le creditBalance" = l'acteur accumule un solde dans l'app.
//      Le RETRAIT réel de ce solde vers son Mobile Money est une autre étape
//      (transfert sortant), à faire via l'API payout du fournisseur. Voir
//      GUIDE_PAIEMENT.md. Ici on gère la COMPTABILITÉ des parts.
// ═══════════════════════════════════════════════════════════════════════════

enum Beneficiaire { boutique, livreur, couturier }

class RepartitionPaiement {
  final String sousCommandeId;
  final String sessionId;
  final double totalClient;
  final double netBoutique;
  final double gainLivreur;
  final double? netCouturier;
  final double commissionPlateforme;
  final double fraisLivraison;
  final String? boutiqueId;
  final String? livreurId;
  final String? couturierId;
  final String boutiqueNom;
  final String statut;
  final bool boutiqueReversee;
  final bool livreurReverse;
  final bool couturierReverse;
  final DateTime? date;

  RepartitionPaiement({
    required this.sousCommandeId,
    required this.sessionId,
    required this.totalClient,
    required this.netBoutique,
    required this.gainLivreur,
    this.netCouturier,
    required this.commissionPlateforme,
    required this.fraisLivraison,
    this.boutiqueId,
    this.livreurId,
    this.couturierId,
    required this.boutiqueNom,
    required this.statut,
    this.boutiqueReversee = false,
    this.livreurReverse = false,
    this.couturierReverse = false,
    this.date,
  });

  factory RepartitionPaiement.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return RepartitionPaiement(
      sousCommandeId: doc.id,
      sessionId: d['sessionId'] as String? ?? '',
      totalClient: (d['totalClient'] as num?)?.toDouble() ?? 0,
      netBoutique: (d['netBoutique'] as num?)?.toDouble() ?? 0,
      gainLivreur: (d['gainLivreur'] as num?)?.toDouble() ?? 0,
      netCouturier: (d['netCouturier'] as num?)?.toDouble(),
      commissionPlateforme:
          (d['commissionPlateforme'] as num?)?.toDouble() ?? 0,
      fraisLivraison: (d['fraisLivraison'] as num?)?.toDouble() ?? 0,
      boutiqueId: d['boutiqueId'] as String?,
      livreurId: d['livreurId'] as String?,
      couturierId: d['couturierId'] as String?,
      boutiqueNom: d['boutiqueNom'] as String? ?? 'Boutique',
      statut: d['statut'] as String? ?? '',
      boutiqueReversee: d['boutiqueReversee'] as bool? ?? false,
      livreurReverse: d['livreurReverse'] as bool? ?? false,
      couturierReverse: d['couturierReverse'] as bool? ?? false,
      date: (d['dateCreation'] as Timestamp?)?.toDate(),
    );
  }
}

class ReversementService {
  static final _db = FirebaseFirestore.instance;

  /// Flux des sous-commandes terminées (= prêtes à reverser), tri client.
  static Stream<List<RepartitionPaiement>> streamARepartir() {
    return _db
        .collection('sous_commandes')
        .where('statut', isEqualTo: 'livree') // clé RÉELLE (jamais 'terminee' nulle part)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => RepartitionPaiement.fromDoc(d)).toList();
      list.sort((a, b) {
        final da = a.date, db = b.date;
        if (da != null && db != null) return db.compareTo(da);
        return 0;
      });
      return list;
    });
  }

  /// Reverse la part d'un bénéficiaire sur une sous-commande.
  /// Crédite son solde + trace + marque comme reversé (anti double paiement).
  static Future<bool> reverser({
    required RepartitionPaiement r,
    required Beneficiaire beneficiaire,
  }) async {
    try {
      final (String? destId, double montant, String collec, String champFlag, String type) =
          switch (beneficiaire) {
        Beneficiaire.boutique => (
            r.boutiqueId,
            r.netBoutique,
            'boutiques',
            'boutiqueReversee',
            'reversementBoutique'
          ),
        Beneficiaire.livreur => (
            r.livreurId,
            r.gainLivreur,
            'livreurs',
            'livreurReverse',
            'reversementLivreur'
          ),
        Beneficiaire.couturier => (
            r.couturierId,
            r.netCouturier ?? 0,
            'couturiers',
            'couturierReverse',
            'reversementCouturier'
          ),
      };

      if (destId == null || montant <= 0) return false;

      // TAXES CONFIGURABLES : inactives par défaut → montantNet == montant.
      // Actives (admin) → déduites du reversement et TRACÉES (comptabilité).
      final (totalTaxes, detailTaxes) =
          await TaxesService.calculer(base: montant, cible: type);
      final montantNet = montant - totalTaxes;

      final batch = _db.batch();

      // 1. Créditer le solde du bénéficiaire
      batch.update(_db.collection(collec).doc(destId), {
        'creditBalance': FieldValue.increment(montant),
      });

      // 2. Tracer le reversement
      final revRef = _db.collection('reversements').doc();
      batch.set(revRef, {
        'id': revRef.id,
        'sousCommandeId': r.sousCommandeId,
        'sessionId': r.sessionId,
        'beneficiaire': beneficiaire.name,
        'beneficiaireId': destId,
        'montantBrut': montant,
        'taxes': totalTaxes,
        'detailTaxes': detailTaxes,
        'montant': montantNet,
        'type': type,
        'date': FieldValue.serverTimestamp(),
      });

      // 3. Marquer la part comme reversée (empêche un second versement)
      batch.update(_db.collection('sous_commandes').doc(r.sousCommandeId), {
        champFlag: true,
      });

      await batch.commit();
      // Reçu signé pour le bénéficiaire payé (boutique/livreur/couturier)
      RecuService.creer(
        type: 'reversement',
        refId: r.sousCommandeId,
        beneficiaireId: destId,
        beneficiaireNom: beneficiaire.name,
        montant: montantNet,
        detail: 'Paiement SAMI — ${beneficiaire.name} (vente ${r.sousCommandeId.substring(0, r.sousCommandeId.length.clamp(0, 8))})',
      ).catchError((_) => <String, dynamic>{});
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── REVERSEMENT DES CONFECTIONS (commandes_couturier) ─────────────────────

  /// Confections livrées/terminées, prêtes à reverser (couturier + boutique).
  static Stream<List<RepartitionCouture>> streamCouturesAReverser() {
    return _db
        .collection('commandes_couturier')
        .where('statut', whereIn: ['livree', 'terminee'])
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => RepartitionCouture.fromDoc(d))
          .where((r) => !r.couturierReverse || (!r.boutiqueReversee && r.netBoutique > 0))
          .toList();
      list.sort((a, b) => (b.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));
      return list;
    });
  }

  /// Reverse la part du COUTURIER (confection − commission) ou de la
  /// BOUTIQUE (net du pagne) sur une commande couture.
  static Future<bool> reverserCouture({
    required RepartitionCouture r,
    required Beneficiaire beneficiaire,
  }) async {
    try {
      if (beneficiaire == Beneficiaire.couturier) {
        final montant = r.netCouturier;
        if (montant <= 0 || r.couturierReverse) return false;
        // Résoudre le DOC couturier (couturierId = utilisateurId)
        final q = await _db
            .collection('couturiers')
            .where('utilisateurId', isEqualTo: r.couturierId)
            .limit(1)
            .get();
        if (q.docs.isEmpty) return false;
        final batch = _db.batch();
        batch.update(q.docs.first.reference,
            {'creditBalance': FieldValue.increment(montant)});
        final revRef = _db.collection('reversements').doc();
        batch.set(revRef, {
          'id': revRef.id,
          'commandeCouturierId': r.commandeId,
          'beneficiaire': 'couturier',
          'beneficiaireId': r.couturierId,
          'montant': montant,
          'type': 'reversementConfection',
          'date': FieldValue.serverTimestamp(),
        });
        batch.update(_db.collection('commandes_couturier').doc(r.commandeId),
            {'couturierReverse': true});
        await batch.commit();
        // Taxes configurables (inactives par défaut)
        final (txC, detC) =
            await TaxesService.calculer(base: montant, cible: 'couturier');
        // Reçu de paiement signé pour le couturier
        RecuService.creer(
          type: 'reversement', refId: r.commandeId,
          beneficiaireId: r.couturierId,
          beneficiaireNom: 'Couturier',
          montant: montant - txC,
          detail: 'Paiement confection (commande ${r.commandeId.substring(0, r.commandeId.length.clamp(0, 8))})',
        ).catchError((_) => <String, dynamic>{});
        return true;
      } else if (beneficiaire == Beneficiaire.boutique) {
        final montant = r.netBoutique;
        if (montant <= 0 || r.boutiqueReversee || r.boutiqueId.isEmpty) {
          return false;
        }
        final batch = _db.batch();
        batch.update(_db.collection('boutiques').doc(r.boutiqueId),
            {'creditBalance': FieldValue.increment(montant)});
        final revRef = _db.collection('reversements').doc();
        batch.set(revRef, {
          'id': revRef.id,
          'commandeCouturierId': r.commandeId,
          'beneficiaire': 'boutique',
          'beneficiaireId': r.boutiqueId,
          'montant': montant,
          'type': 'reversementPagneCouture',
          'date': FieldValue.serverTimestamp(),
        });
        batch.update(_db.collection('commandes_couturier').doc(r.commandeId),
            {'boutiqueReversee': true});
        await batch.commit();
        // Reçu pour la boutique : bénéficiaire = 1er gérant (compte utilisateur)
        try {
          final b = await _db.collection('boutiques').doc(r.boutiqueId).get();
          final gerants = List<String>.from(b.data()?['gerants'] as List? ?? []);
          if (gerants.isNotEmpty) {
            await RecuService.creer(
              type: 'reversement', refId: r.commandeId,
              beneficiaireId: gerants.first,
              beneficiaireNom: b.data()?['nom'] as String? ?? 'Boutique',
              montant: montant -
                  (await TaxesService.calculer(base: montant, cible: 'boutique')).$1,
              detail: 'Paiement pagne — commande couture ${r.commandeId.substring(0, r.commandeId.length.clamp(0, 8))}',
            );
          }
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// Répartition d'une commande de COUTURE : part couturier + part boutique.
class RepartitionCouture {
  final String commandeId;
  final String couturierId;   // utilisateurId du couturier
  final String boutiqueId;
  final double prixConvenu;
  final double commissionPlateforme;
  final double prixPagne;
  final double netBoutique;
  final bool couturierReverse;
  final bool boutiqueReversee;
  final DateTime? date;

  double get netCouturier => prixConvenu - commissionPlateforme;

  RepartitionCouture({
    required this.commandeId,
    required this.couturierId,
    required this.boutiqueId,
    required this.prixConvenu,
    required this.commissionPlateforme,
    required this.prixPagne,
    required this.netBoutique,
    required this.couturierReverse,
    required this.boutiqueReversee,
    this.date,
  });

  factory RepartitionCouture.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return RepartitionCouture(
      commandeId: doc.id,
      couturierId: d['couturierId'] as String? ?? '',
      boutiqueId: d['boutiqueId'] as String? ?? '',
      prixConvenu: (d['prixConvenu'] as num?)?.toDouble() ?? 0,
      commissionPlateforme:
          (d['commissionPlateforme'] as num?)?.toDouble() ?? 0,
      prixPagne: (d['prixPagne'] as num?)?.toDouble() ?? 0,
      netBoutique: (d['netBoutique'] as num?)?.toDouble() ?? 0,
      couturierReverse: d['couturierReverse'] as bool? ?? false,
      boutiqueReversee: d['boutiqueReversee'] as bool? ?? false,
      date: (d['dateCommande'] is Timestamp)
          ? ((d['dateCommande'] as Timestamp?)?.toDate() ?? DateTime.now())
          : null,
    );
  }
}
