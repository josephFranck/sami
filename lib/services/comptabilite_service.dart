import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/models/transaction_financiere.dart';

/// Service central de comptabilité
/// Gère tous les flux financiers de l'écosystème
class ComptabiliteService {

  // ── Constantes tarifaires ──────────────────────────────────────────────────
  // Les taux VIVANTS viennent des Paramètres admin (app_config/parametres) ;
  // les constantes ci-dessous ne sont que des replis hors-ligne.
  static Future<double> _tauxCommission() async =>
      (await ParametresService.commissionDefautPct())
          .clamp(0, 100)
          .toDouble();
  static const double TAUX_COMMISSION_DEFAULT = 8.0;       // % (repli)
  static const double FRAIS_LIVRAISON_BASE = 600.0;        // FCFA
  static const double TAUX_GAIN_LIVREUR = 0.70;            // 70% des frais livraison
  static const double TAUX_FRAIS_CINETPAY = 2.5;           // % frais passerelle
  static const double SOLDE_MINIMUM_BOUTIQUE = 2000.0;     // FCFA
  static const double FRAIS_PUBLICATION_PAGNE = 500.0;     // FCFA (modèle A)

  // ── Création d'une transaction de vente ───────────────────────────────────

  /// Crée et enregistre toutes les transactions liées à une vente
  /// Retourne l'ID de la transaction principale
  static Future<String> enregistrerVente({
    required String commandeId,
    required String livraisonId,
    required String clientId,
    required String boutiqueId,
    required String livreurId,
    required double prixClient,
    required String methodePaiement,
    String? numeroTelephone,
    String? referenceExterne,
  }) async {
    final decomposition = DecompositionFinanciere.calculer(
      prixClient: prixClient,
      tauxCommission: await _tauxCommission(), // paramétrable (repli 6%)
      fraisLivraisonIsole: FRAIS_LIVRAISON_BASE,
      tauxFraisPaiement: methodePaiement == 'cash' ? 0.0 : TAUX_FRAIS_CINETPAY,
      tauxGainLivreur: TAUX_GAIN_LIVREUR,
    );

    final batch = FirebaseFirestore.instance.batch();
    final transRef = FirebaseFirestore.instance.collection('transactions').doc();

    // 1. Transaction principale (paiement client)
    final transactionPrincipale = TransactionFinanciere(
      id: transRef.id,
      type: TypeTransaction.paiementMobileMoney,
      statut: methodePaiement == 'cash'
          ? StatutTransaction.enAttente   // cash confirmé à la livraison
          : StatutTransaction.enAttente,  // MM confirmé par webhook
      clientId: clientId,
      boutiqueId: boutiqueId,
      livreurId: livreurId,
      commandeId: commandeId,
      livraisonId: livraisonId,
      montantBrut: prixClient,
      montantNet: prixClient,
      decomposition: decomposition,
      methodePaiement: methodePaiement,
      referenceExterne: referenceExterne,
      numeroTelephone: numeroTelephone,
      dateCreation: DateTime.now(),
    );
    batch.set(transRef, transactionPrincipale.toMap());

    // 2. Transaction commission plateforme
    final commRef = FirebaseFirestore.instance.collection('transactions').doc();
    batch.set(commRef, TransactionFinanciere(
      id: commRef.id,
      type: TypeTransaction.commissionVente,
      statut: StatutTransaction.enAttente,
      boutiqueId: boutiqueId,
      commandeId: commandeId,
      livraisonId: livraisonId,
      montantBrut: decomposition.montantCommission,
      montantNet: decomposition.netPlateforme,
      methodePaiement: 'interne',
      dateCreation: DateTime.now(),
      note: 'Commission plateforme sur vente $commandeId',
    ).toMap());

    // 3. Transaction reversement boutique (à déclencher après livraison)
    final boutRef = FirebaseFirestore.instance.collection('transactions').doc();
    batch.set(boutRef, TransactionFinanciere(
      id: boutRef.id,
      type: TypeTransaction.reversementBoutique,
      statut: StatutTransaction.enAttente, // déclenché après livraison confirmée
      boutiqueId: boutiqueId,
      commandeId: commandeId,
      livraisonId: livraisonId,
      montantBrut: decomposition.netBoutique,
      montantNet: decomposition.netBoutique,
      methodePaiement: 'mobile_money',
      dateCreation: DateTime.now(),
      note: 'Reversement boutique après livraison confirmée',
    ).toMap());

    // 4. Transaction gain livreur (à déclencher après livraison confirmée)
    final livRef = FirebaseFirestore.instance.collection('transactions').doc();
    batch.set(livRef, TransactionFinanciere(
      id: livRef.id,
      type: TypeTransaction.reversementLivreur,
      statut: StatutTransaction.enAttente,
      livreurId: livreurId,
      commandeId: commandeId,
      livraisonId: livraisonId,
      montantBrut: decomposition.gainLivreur,
      montantNet: decomposition.gainLivreur,
      methodePaiement: 'mobile_money',
      dateCreation: DateTime.now(),
      note: 'Gain livreur pour livraison $livraisonId',
    ).toMap());

    // 5. Débit commission sur solde boutique (si modèle per_commission)
    final debitRef = FirebaseFirestore.instance.collection('transactions').doc();
    batch.set(debitRef, TransactionFinanciere(
      id: debitRef.id,
      type: TypeTransaction.debitCommission,
      statut: StatutTransaction.enAttente,
      boutiqueId: boutiqueId,
      commandeId: commandeId,
      montantBrut: -decomposition.montantCommission, // négatif = débit
      montantNet: -decomposition.montantCommission,
      methodePaiement: 'credits',
      dateCreation: DateTime.now(),
      note: 'Débit commission crédits boutique',
    ).toMap());

    await batch.commit();
    return transRef.id;
  }

  /// Confirme tous les reversements après validation QR
  static Future<void> confirmerReversementsApresLivraison({
    required String livraisonId,
    required String boutiqueId,
    required String livreurId,
  }) async {
    // Récupérer toutes les transactions liées
    final snapshot = await FirebaseFirestore.instance
        .collection('transactions')
        .where('livraisonId', isEqualTo: livraisonId)
        .where('statut', isEqualTo: StatutTransaction.enAttente.name)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    final now = DateTime.now();

    for (final doc in snapshot.docs) {
      final type = TypeTransaction.values.firstWhere((e) => e.name == (doc['type'] as String? ?? ''), orElse: () => TypeTransaction.values.first);
      // Confirmer reversements boutique et livreur
      if (type == TypeTransaction.reversementBoutique ||
          type == TypeTransaction.reversementLivreur ||
          type == TypeTransaction.commissionVente ||
          type == TypeTransaction.debitCommission) {
        batch.update(doc.reference, {
          'statut': StatutTransaction.confirmee.name,
          'dateConfirmation': now,
        });
      }
    }

    // Mettre à jour le solde du livreur
    await _incrementerSoldeLivreur(livreurId, FRAIS_LIVRAISON_BASE * TAUX_GAIN_LIVREUR);

    await batch.commit();
  }

  // ── Rapport financier mensuel ──────────────────────────────────────────────

  static Future<RapportMensuel> genererRapportMensuel(int mois, int annee) async {
    final debut = DateTime(annee, mois, 1);
    final fin = DateTime(annee, mois + 1, 1);

    final snapshot = await FirebaseFirestore.instance
        .collection('transactions')
        .where('dateCreation', isGreaterThanOrEqualTo: debut)
        .where('dateCreation', isLessThan: fin)
        .where('statut', isEqualTo: StatutTransaction.confirmee.name)
        .get();

    double chiffreAffaires = 0;
    double commissionsTotales = 0;
    double fraisLivraisonTotaux = 0;
    double fraisPaiementTotaux = 0;
    double reversementsBoutiques = 0;
    double reversementsLivreurs = 0;
    double beneficeNet = 0;
    int nombreTransactions = 0;
    Map<String, double> parType = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = TypeTransaction.values.firstWhere((e) => e.name == (data['type'] as String? ?? ''), orElse: () => TypeTransaction.values.first);
      final montant = (data['montantBrut'] as num? ?? 0).toDouble();

      parType[type.name] = (parType[type.name] ?? 0) + montant;

      switch (type) {
        case TypeTransaction.paiementMobileMoney:
        case TypeTransaction.paiementCash:
        case TypeTransaction.paiementCredits:
          chiffreAffaires += montant;
          nombreTransactions++;
          final decomp = data['decomposition'] as Map<String, dynamic>?;
          if (decomp != null) {
            fraisPaiementTotaux += (decomp['fraisPaiement'] as num?)?.toDouble() ?? 0;
          }
          break;
        case TypeTransaction.commissionVente:
          commissionsTotales += montant;
          break;
        case TypeTransaction.fraisLivraison:
          fraisLivraisonTotaux += montant;
          break;
        case TypeTransaction.reversementBoutique:
          reversementsBoutiques += montant;
          break;
        case TypeTransaction.reversementLivreur:
          reversementsLivreurs += montant;
          break;
        default:
          break;
      }
    }

    beneficeNet = commissionsTotales - fraisPaiementTotaux +
        (fraisLivraisonTotaux - reversementsLivreurs);

    return RapportMensuel(
      mois: mois,
      annee: annee,
      chiffreAffaires: chiffreAffaires,
      commissionsTotales: commissionsTotales,
      fraisLivraisonTotaux: fraisLivraisonTotaux,
      fraisPaiementTotaux: fraisPaiementTotaux,
      reversementsBoutiques: reversementsBoutiques,
      reversementsLivreurs: reversementsLivreurs,
      beneficeNet: beneficeNet,
      nombreTransactions: nombreTransactions,
      panierMoyen: nombreTransactions > 0 ? chiffreAffaires / nombreTransactions : 0,
      parType: parType,
    );
  }

  // ── Gestion crédits boutique ───────────────────────────────────────────────

  static Future<bool> verifierSoldeSuffisant(String boutiqueId, double montantRequis) async {
    final doc = await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .get();
    final solde = (doc['creditBalance'] as num?)?.toDouble() ?? 0.0;
    return solde >= montantRequis;
  }

  static Future<void> debiterCreditsBoutique(String boutiqueId, double montant, String motif) async {
    await FirebaseFirestore.instance.collection('boutiques').doc(boutiqueId).update({
      'creditBalance': FieldValue.increment(-montant),
    });
    // Enregistrer le mouvement
    // UNE seule collection de mouvements (schéma de credit_service) —
    // avant : 'credit_mouvements', doublon jamais lu par l'historique.
    await FirebaseFirestore.instance.collection('mouvements_credits').add({
      'utilisateurId': '',
      'entiteId': boutiqueId,
      'type': 'commissionDebit',
      'montant': -montant,
      'description': motif,
      'date': DateTime.now(),
    });
  }

  static Future<void> rechargerCreditsBoutique(String boutiqueId, double montant) async {
    await FirebaseFirestore.instance.collection('boutiques').doc(boutiqueId).update({
      'creditBalance': FieldValue.increment(montant),
    });
    await FirebaseFirestore.instance.collection('transactions').add(
      TransactionFinanciere(
        id: '',
        type: TypeTransaction.rechargeCreditBoutique,
        statut: StatutTransaction.confirmee,
        boutiqueId: boutiqueId,
        montantBrut: montant,
        montantNet: montant,
        methodePaiement: 'mobile_money',
        dateCreation: DateTime.now(),
        dateConfirmation: DateTime.now(),
      ).toMap(),
    );
  }

  static Future<void> _incrementerSoldeLivreur(String livreurId, double montant) async {
    await FirebaseFirestore.instance.collection('livreurs').doc(livreurId).set({
      'creditBalance': FieldValue.increment(montant),
      'gainTotal': FieldValue.increment(montant),
      'nombreLivraisons': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  /// Formate un montant en FCFA avec séparateurs
  static String formatFCFA(double montant) {
    final parts = montant.toStringAsFixed(0).split('');
    final result = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) result.write(' ');
      result.write(parts[i]);
    }
    return '${result.toString()} FCFA';
  }
}

// ─── Rapport mensuel ────────────────────────────────────────────────────────

class RapportMensuel {
  final int mois;
  final int annee;
  final double chiffreAffaires;
  final double commissionsTotales;
  final double fraisLivraisonTotaux;
  final double fraisPaiementTotaux;
  final double reversementsBoutiques;
  final double reversementsLivreurs;
  final double beneficeNet;
  final int nombreTransactions;
  final double panierMoyen;
  final Map<String, double> parType;

  RapportMensuel({
    required this.mois,
    required this.annee,
    required this.chiffreAffaires,
    required this.commissionsTotales,
    required this.fraisLivraisonTotaux,
    required this.fraisPaiementTotaux,
    required this.reversementsBoutiques,
    required this.reversementsLivreurs,
    required this.beneficeNet,
    required this.nombreTransactions,
    required this.panierMoyen,
    required this.parType,
  });

  @override
  String toString() => '''
╔══════════════════════════════════════════╗
║  RAPPORT MENSUEL — $mois/$annee           
╠══════════════════════════════════════════╣
║  Chiffre d\'affaires : ${ComptabiliteService.formatFCFA(chiffreAffaires).padLeft(16)}
║  Commissions        : ${ComptabiliteService.formatFCFA(commissionsTotales).padLeft(16)}
║  Frais livraison    : ${ComptabiliteService.formatFCFA(fraisLivraisonTotaux).padLeft(16)}
║  Frais passerelle   : ${ComptabiliteService.formatFCFA(fraisPaiementTotaux).padLeft(16)}
╠══════════════════════════════════════════╣
║  Reversé boutiques  : ${ComptabiliteService.formatFCFA(reversementsBoutiques).padLeft(16)}
║  Reversé livreurs   : ${ComptabiliteService.formatFCFA(reversementsLivreurs).padLeft(16)}
╠══════════════════════════════════════════╣
║  BÉNÉFICE NET       : ${ComptabiliteService.formatFCFA(beneficeNet).padLeft(16)}
║  Nb transactions    : ${nombreTransactions.toString().padLeft(16)}
║  Panier moyen       : ${ComptabiliteService.formatFCFA(panierMoyen).padLeft(16)}
╚══════════════════════════════════════════╝''';
}
