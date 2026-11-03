import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/abonnements.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE COMMISSION / CRÉDIT BOUTIQUIER (modèle prépayé)
//
// Modèle économique :
//   - Le boutiquier reçoit (coût d'achat + bénéfice voulu) sur chaque vente,
//     SANS que la commission ni les frais de livraison soient prélevés dessus.
//   - LA COMMISSION de la plateforme est débitée du CRÉDIT du boutiquier
//     (son creditBalance), au moment défini par son ABONNEMENT :
//       • commissionAvance == true  → débit à la PUBLICATION/vente (prépayé)
//       • commissionAvance == false → débit à la LIVRAISON confirmée (différé)
//   - Pour PUBLIER un pagne, le boutiquier doit avoir un crédit ≥
//     seuilCreditPublication (dépend de l'abonnement → levier commercial).
//
// Le creditBalance du boutiquier se recharge via achat de crédits (CreditService).
// ═══════════════════════════════════════════════════════════════════════════

class ResultatVerificationCredit {
  final bool autorise;
  final String? raison;
  final double creditActuel;
  final double seuilRequis;
  ResultatVerificationCredit({
    required this.autorise,
    this.raison,
    required this.creditActuel,
    required this.seuilRequis,
  });
}

class CommissionBoutiqueService {
  static final _db = FirebaseFirestore.instance;

  /// La boutique bénéficie-t-elle d'une PÉRIODE GRATUITE active (accordée admin) ?
  /// Pendant cette période : aucune commission, publication libre.
  static Future<bool> enFranchiseGratuite(String boutiqueId) async {
    try {
      final doc = await _db.collection('boutiques').doc(boutiqueId).get();
      final ts = doc.data()?['franchiseGratuiteJusqu'];
      if (ts == null) return false;
      final date = ((ts as Timestamp?)?.toDate() ?? DateTime.now());
      return date.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Modèle de facturation d'une boutique :
  ///   'per_commission' (défaut) → commission prélevée SUR LA VENTE (gratuit, pas de crédit requis)
  ///   'prepaid'                 → commission débitée du CRÉDIT prépayé (publication soumise à seuil)
  static Future<String> modeFacturation(String boutiqueId) async {
    try {
      final doc = await _db.collection('boutiques').doc(boutiqueId).get();
      return doc.data()?['billingModel'] as String? ?? 'per_commission';
    } catch (_) {
      return 'per_commission';
    }
  }

  /// Le boutiquier est-il en mode prépayé ?
  static Future<bool> estPrepaye(String boutiqueId) async =>
      (await modeFacturation(boutiqueId)) == 'prepaid';

  /// Récupère l'abonnement d'une boutique (défaut: gratuit).
  static Future<AbonnementBoutique> abonnementDe(String boutiqueId) async {
    try {
      final doc = await _db.collection('boutiques').doc(boutiqueId).get();
      final nom = doc.data()?['abonnement'] as String?;
      // EXPIRATION : un palier périmé retombe au gratuit
      final finLe = doc.data()?['abonnementFinLe'];
      final expire =
          finLe is Timestamp && finLe.toDate().isBefore(DateTime.now());
      if (nom != null && !expire) {
        final type = TypeAbonnementBoutique.values
            .firstWhere((t) => t.name == nom,
                orElse: () => TypeAbonnementBoutique.gratuit);
        return AbonnementBoutique.catalogue[type]!;
      }
    } catch (_) {}
    return AbonnementBoutique.catalogue[TypeAbonnementBoutique.gratuit]!;
  }

  /// Vérifie si le boutiquier a assez de crédit pour PUBLIER un pagne.
  static Future<ResultatVerificationCredit> peutPublier(
      String boutiqueId) async {
    // Période gratuite active → publication libre.
    if (await enFranchiseGratuite(boutiqueId)) {
      return ResultatVerificationCredit(
          autorise: true, creditActuel: 0, seuilRequis: 0);
    }
    // Mode commission-sur-vente : aucune barrière, publication libre.
    if (!await estPrepaye(boutiqueId)) {
      return ResultatVerificationCredit(
          autorise: true, creditActuel: 0, seuilRequis: 0);
    }
    // Mode prépayé : vérifier le seuil de crédit selon l'abonnement.
    final abo = await abonnementDe(boutiqueId);
    double credit = 0;
    try {
      final doc = await _db.collection('boutiques').doc(boutiqueId).get();
      credit = (doc.data()?['creditBalance'] as num?)?.toDouble() ?? 0;
    } catch (_) {}

    final seuil = abo.seuilCreditPublication;
    if (credit >= seuil) {
      return ResultatVerificationCredit(
          autorise: true, creditActuel: credit, seuilRequis: seuil);
    }
    return ResultatVerificationCredit(
      autorise: false,
      raison:
          'Crédit insuffisant pour publier. Il vous faut au moins ${seuil.toStringAsFixed(0)} FCFA de crédit (vous avez ${credit.toStringAsFixed(0)} FCFA). Rechargez votre crédit ou changez d\'abonnement.',
      creditActuel: credit,
      seuilRequis: seuil,
    );
  }

  /// Débite la commission du crédit du boutiquier.
  /// Appelé soit à la vente (si commissionAvance), soit à la livraison sinon.
  /// Retourne true si débité, false si crédit insuffisant (à gérer par l'appelant).
  static Future<bool> debiterCommission({
    required String boutiqueId,
    required double montantCommission,
    required String sousCommandeId,
  }) async {
    if (montantCommission <= 0) return true;
    try {
      return await _db.runTransaction<bool>((tx) async {
        final ref = _db.collection('boutiques').doc(boutiqueId);
        final doc = await tx.get(ref);
        final credit = (doc.data()?['creditBalance'] as num?)?.toDouble() ?? 0;

        // On débite même si ça passe en négatif (dette), mais on le signale.
        // Choix : autoriser le négatif évite de bloquer une vente déjà payée.
        tx.update(ref, {
          'creditBalance': credit - montantCommission,
        });

        final txRef = _db.collection('transactions').doc();
        tx.set(txRef, {
          'id': txRef.id,
          'type': 'commissionVente',
          'entiteId': boutiqueId,
          'entiteType': 'boutique',
          'sousCommandeId': sousCommandeId,
          'montant': montantCommission,
          'description': 'Commission plateforme prélevée du crédit',
          'date': FieldValue.serverTimestamp(),
        });

        return credit >= montantCommission; // false = passé en négatif
      });
    } catch (e) {
      return false;
    }
  }

  /// Indique si la commission doit être prélevée d'avance pour cette boutique.
  static Future<bool> commissionEstAvance(String boutiqueId) async {
    final abo = await abonnementDe(boutiqueId);
    return abo.commissionAvance;
  }
}
