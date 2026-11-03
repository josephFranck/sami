import 'package:cloud_firestore/cloud_firestore.dart';

/// Type de chaque mouvement d'argent dans l'écosystème
enum TypeTransaction {
  // ── Revenus plateforme ──
  commissionVente,        // % sur vente pagne/produit
  fraisLivraison,         // livraison incluse dans prix → on isole
  abonnementBoutique,     // abonnement mensuel boutique
  publicationPagne,       // modèle A : payer pour publier
  fraisService,           // frais divers

  // ── Paiements clients ──
  paiementMobileMoney,    // Orange Money / MTN MoMo
  paiementCash,           // cash à la livraison
  paiementCredits,        // crédits plateforme

  // ── Reversements ──
  reversementBoutique,    // argent reversé à la boutique
  reversementLivreur,     // gain reversé au livreur
  reversementCouturier,   // gain reversé au couturier

  // ── Remboursements ──
  remboursementClient,    // remboursement suite litige
  remboursementBoutique,  // remboursement boutique

  // ── Crédits ──
  rechargeCreditBoutique, // boutique recharge son solde
  debitCommission,        // débit commission sur vente
  debitPublication,       // débit publication pagne
}

enum StatutTransaction {
  enAttente,    // initiée, pas encore confirmée
  confirmee,    // paiement confirmé
  echouee,      // échec paiement
  annulee,      // annulée
  remboursee,   // remboursée
}

/// Décomposition financière d'une commande
/// Exemple : Pagne vendu 10 000 FCFA
/// → Prix HT : 9 434 FCFA
/// → Commission plateforme (6%) : 566 FCFA
/// → Frais livraison inclus : 500 FCFA (isolé pour le livreur)
/// → Net boutique : 8 934 FCFA
class DecompositionFinanciere {
  final double prixClient;          // ce que paie le client
  final double tauxCommission;      // ex: 6.0 (%)
  final double montantCommission;   // prixClient * tauxCommission / 100
  final double fraisLivraisonIsole; // part pour le livreur
  final double fraisPaiement;       // frais CinetPay/Monetbil (~2.5%)
  final double netBoutique;         // ce que reçoit la boutique
  final double netPlateforme;       // bénéfice net plateforme
  final double gainLivreur;         // ce que reçoit le livreur

  DecompositionFinanciere({
    required this.prixClient,
    required this.tauxCommission,
    required this.montantCommission,
    required this.fraisLivraisonIsole,
    required this.fraisPaiement,
    required this.netBoutique,
    required this.netPlateforme,
    required this.gainLivreur,
  });

  /// Calcul automatique depuis le prix client
  factory DecompositionFinanciere.calculer({
    required double prixClient,
    double tauxCommission = 6.0,
    double fraisLivraisonIsole = 600.0,  // FCFA — aligné sur fraisLivraisonBase
    double tauxFraisPaiement = 2.5,      // CinetPay ~2.5%
    double tauxGainLivreur = 0.70,       // livreur garde 70% des frais livraison
  }) {
    final commission = prixClient * tauxCommission / 100;
    final fraisPaiement = prixClient * tauxFraisPaiement / 100;
    final gainLivreur = fraisLivraisonIsole * tauxGainLivreur;
    final netBoutique = prixClient - commission - fraisLivraisonIsole;
    final netPlateforme = commission - fraisPaiement + (fraisLivraisonIsole - gainLivreur);

    return DecompositionFinanciere(
      prixClient: prixClient,
      tauxCommission: tauxCommission,
      montantCommission: commission,
      fraisLivraisonIsole: fraisLivraisonIsole,
      fraisPaiement: fraisPaiement,
      netBoutique: netBoutique,
      netPlateforme: netPlateforme,
      gainLivreur: gainLivreur,
    );
  }

  Map<String, dynamic> toMap() => {
    'prixClient': prixClient,
    'tauxCommission': tauxCommission,
    'montantCommission': montantCommission,
    'fraisLivraisonIsole': fraisLivraisonIsole,
    'fraisPaiement': fraisPaiement,
    'netBoutique': netBoutique,
    'netPlateforme': netPlateforme,
    'gainLivreur': gainLivreur,
  };

  factory DecompositionFinanciere.fromMap(Map<String, dynamic> m) =>
    DecompositionFinanciere(
      prixClient: (m['prixClient'] as num? ?? 0).toDouble(),
      tauxCommission: (m['tauxCommission'] as num? ?? 0).toDouble(),
      montantCommission: (m['montantCommission'] as num? ?? 0).toDouble(),
      fraisLivraisonIsole: (m['fraisLivraisonIsole'] as num? ?? 0).toDouble(),
      fraisPaiement: (m['fraisPaiement'] as num? ?? 0).toDouble(),
      netBoutique: (m['netBoutique'] as num? ?? 0).toDouble(),
      netPlateforme: (m['netPlateforme'] as num? ?? 0).toDouble(),
      gainLivreur: (m['gainLivreur'] as num? ?? 0).toDouble(),
    );

  @override
  String toString() => '''
┌─────────────────────────────────────────┐
│  DÉCOMPOSITION FINANCIÈRE               │
├─────────────────────────────────────────┤
│  Prix client          : ${prixClient.toStringAsFixed(0).padLeft(8)} FCFA  │
│  Commission (${tauxCommission}%)    : ${montantCommission.toStringAsFixed(0).padLeft(8)} FCFA  │
│  Frais livraison      : ${fraisLivraisonIsole.toStringAsFixed(0).padLeft(8)} FCFA  │
│  Frais paiement       : ${fraisPaiement.toStringAsFixed(0).padLeft(8)} FCFA  │
├─────────────────────────────────────────┤
│  Net boutique         : ${netBoutique.toStringAsFixed(0).padLeft(8)} FCFA  │
│  Gain livreur         : ${gainLivreur.toStringAsFixed(0).padLeft(8)} FCFA  │
│  Net plateforme       : ${netPlateforme.toStringAsFixed(0).padLeft(8)} FCFA  │
└─────────────────────────────────────────┘''';
}

/// Transaction individuelle — chaque mouvement d'argent tracé
class TransactionFinanciere {
  final String id;
  final TypeTransaction type;
  StatutTransaction statut;

  // Acteurs
  final String? clientId;
  final String? boutiqueId;
  final String? livreurId;
  final String? couturierId;

  // Référence
  final String? commandeId;
  final String? livraisonId;

  // Montants
  final double montantBrut;         // montant total de la transaction
  final double montantNet;          // après déduction frais
  final DecompositionFinanciere? decomposition;

  // Paiement
  final String methodePaiement;     // 'mobile_money', 'cash', 'credits'
  final String? referenceExterne;   // référence CinetPay/Orange Money
  final String? numeroTelephone;    // numéro Mobile Money

  // Comptabilité
  final DateTime dateCreation;
  DateTime? dateConfirmation;
  final String devise;              // 'XAF' (FCFA)
  final String? note;

  TransactionFinanciere({
    required this.id,
    required this.type,
    this.statut = StatutTransaction.enAttente,
    this.clientId,
    this.boutiqueId,
    this.livreurId,
    this.couturierId,
    this.commandeId,
    this.livraisonId,
    required this.montantBrut,
    required this.montantNet,
    this.decomposition,
    required this.methodePaiement,
    this.referenceExterne,
    this.numeroTelephone,
    required this.dateCreation,
    this.dateConfirmation,
    this.devise = 'XAF',
    this.note,
  });

  static CollectionReference<Map<String, dynamic>> collection =
      FirebaseFirestore.instance.collection('transactions');

  factory TransactionFinanciere.fromFirebaseDocument(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TransactionFinanciere(
      id: doc.id,
      type: TypeTransaction.values.firstWhere((e) => e.name == (d['type'] as String? ?? ''), orElse: () => TypeTransaction.values.first),
      statut: StatutTransaction.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enAttente'), orElse: () => StatutTransaction.values.first),
      clientId: d['clientId'] as String?,
      boutiqueId: d['boutiqueId'] as String?,
      livreurId: d['livreurId'] as String?,
      couturierId: d['couturierId'] as String?,
      commandeId: d['commandeId'] as String?,
      livraisonId: d['livraisonId'] as String?,
      montantBrut: (d['montantBrut'] as num? ?? 0).toDouble(),
      montantNet: (d['montantNet'] as num? ?? 0).toDouble(),
      decomposition: d['decomposition'] != null
          ? DecompositionFinanciere.fromMap(d['decomposition'] as Map<String, dynamic>)
          : null,
      methodePaiement: d['methodePaiement'] as String? ?? '',
      referenceExterne: d['referenceExterne'] as String?,
      numeroTelephone: d['numeroTelephone'] as String?,
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateConfirmation: (d['dateConfirmation'] as Timestamp?)?.toDate(),
      devise: d['devise'] as String? ?? 'XAF',
      note: d['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'statut': statut.name,
    'clientId': clientId,
    'boutiqueId': boutiqueId,
    'livreurId': livreurId,
    'couturierId': couturierId,
    'commandeId': commandeId,
    'livraisonId': livraisonId,
    'montantBrut': montantBrut,
    'montantNet': montantNet,
    'decomposition': decomposition?.toMap(),
    'methodePaiement': methodePaiement,
    'referenceExterne': referenceExterne,
    'numeroTelephone': numeroTelephone,
    'dateCreation': dateCreation,
    'dateConfirmation': dateConfirmation,
    'devise': devise,
    'note': note,
  };
}
