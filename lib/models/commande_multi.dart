import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ARCHITECTURE COMMANDES MULTI-BOUTIQUES
//
// Quand un client commande des pagnes de 3 boutiques différentes :
//
//   SessionCommande (1)          ← vue client : "ma commande"
//     ├── SousCommande Boutique A (articles A1, A2)
//     │     └── EtapeLivraison A → domicile client
//     ├── SousCommande Boutique B (article B1 avec couture)
//     │     ├── EtapeLivraison B1 → chez couturier
//     │     └── EtapeLivraison B2 → domicile client (après couture)
//     └── SousCommande Boutique C (article C1)
//           └── EtapeLivraison C → retrait boutique
//
// Avantages :
//   - Chaque boutiquier ne voit QUE ses sous-commandes
//   - Chaque livreur ne voit QUE ses livraisons
//   - La comptabilité est par sous-commande (commission correcte)
//   - Le client voit un résumé agrégé
// ═══════════════════════════════════════════════════════════════════════════

// ─── Statuts ─────────────────────────────────────────────────────────────────

enum StatutSousCommande {
  enAttente,            // créée, pas encore confirmée par boutiquier
  confirmeeBoutique,    // boutiquier a accepté
  enPreparation,        // articles en cours de préparation
  prete,                // prête pour enlèvement/livraison
  enCoursLivraison,     // livreur en route
  livree,               // arrivée à destination
  avecCouturier,        // tissu chez le couturier (cas mixte)
  costurierTermine,     // couturier a fini, prêt pour livraison finale
  terminee,             // tout livré et validé
  annulee,
  litige,
}

enum StatutSession {
  enCours,              // au moins 1 sous-commande active
  partiellementLivree,  // certaines livrées, d'autres pas
  touteLivree,          // toutes les sous-commandes terminées
  annulee,
}

// ─── Destination d'une livraison ─────────────────────────────────────────────

enum TypeDestination {
  domicileClient,       // livraison chez le client
  retraitBoutique,      // click & collect en boutique
  chezCouturier,        // tissu livré au couturier
  retourBoutique,       // retour de marchandise
}

// ─── Une étape de livraison ───────────────────────────────────────────────────
// Une SousCommande peut avoir 1 ou 2 étapes de livraison
// (ex: pagne → couturier puis vêtement → client)

class EtapeLivraison {
  final String id;
  final String sousCommandeId;
  final int ordre;                    // 1 = première livraison, 2 = deuxième...
  final TypeDestination typeDestination;

  // Adresses
  final String adresseDepart;         // ex: adresse boutique
  final String adresseArrivee;        // ex: adresse client ou couturier
  final double? latDepart;
  final double? lngDepart;
  final double? latArrivee;
  final double? lngArrivee;

  // Livreur
  final String? livreurId;
  final DateTime? dateAssignation;

  // QR codes (sécurité)
  final String qrDepart;              // scanné en boutique par le livreur
  final String qrArrivee;             // scanné à destination par le destinataire

  // Statut et timing
  final String statut;
  final DateTime? datePrisEnCharge;
  final DateTime? dateLivraison;
  final DateTime? dateLivraisonPrevue;

  // Financier
  final double fraisLivraison;
  final double gainLivreur;

  // Preuve
  final String? photoLivraison;
  final String? signatureNom;
  final double? noteClient;

  const EtapeLivraison({
    required this.id,
    required this.sousCommandeId,
    required this.ordre,
    required this.typeDestination,
    required this.adresseDepart,
    required this.adresseArrivee,
    this.latDepart,
    this.lngDepart,
    this.latArrivee,
    this.lngArrivee,
    this.livreurId,
    this.dateAssignation,
    required this.qrDepart,
    required this.qrArrivee,
    this.statut = 'enAttente',
    this.datePrisEnCharge,
    this.dateLivraison,
    this.dateLivraisonPrevue,
    this.fraisLivraison = 600,
    this.gainLivreur = 350,
    this.photoLivraison,
    this.signatureNom,
    this.noteClient,
  });

  bool get estLivree => statut == 'livree' || dateLivraison != null;
  bool get estEnCours => statut == 'enCours';
  bool get estDomicile => typeDestination == TypeDestination.domicileClient;
  bool get estRetrait => typeDestination == TypeDestination.retraitBoutique;
  bool get estCouturier => typeDestination == TypeDestination.chezCouturier;

  String get labelDestination => switch (typeDestination) {
    TypeDestination.domicileClient  => 'Livraison domicile',
    TypeDestination.retraitBoutique => 'Retrait boutique',
    TypeDestination.chezCouturier   => 'Livraison couturier',
    TypeDestination.retourBoutique  => 'Retour boutique',
  };

  static CollectionReference<Map<String, dynamic>> collection(String sousCommandeId) =>
      FirebaseFirestore.instance
          .collection('sous_commandes')
          .doc(sousCommandeId)
          .collection('livraisons');

  Map<String, dynamic> toMap() => {
    'id': id,
    'sousCommandeId': sousCommandeId,
    'ordre': ordre,
    'typeDestination': typeDestination.name,
    'adresseDepart': adresseDepart,
    'adresseArrivee': adresseArrivee,
    'latDepart': latDepart,
    'lngDepart': lngDepart,
    'latArrivee': latArrivee,
    'lngArrivee': lngArrivee,
    'livreurId': livreurId,
    'dateAssignation': dateAssignation,
    'qrDepart': qrDepart,
    'qrArrivee': qrArrivee,
    'statut': statut,
    'datePrisEnCharge': datePrisEnCharge,
    'dateLivraison': dateLivraison,
    'dateLivraisonPrevue': dateLivraisonPrevue,
    'fraisLivraison': fraisLivraison,
    'gainLivreur': gainLivreur,
    'photoLivraison': photoLivraison,
    'signatureNom': signatureNom,
    'noteClient': noteClient,
  };

  factory EtapeLivraison.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return EtapeLivraison(
      id: doc.id,
      sousCommandeId: d['sousCommandeId'] as String? ?? '',
      ordre: d['ordre'] as int? ?? 1,
      typeDestination: TypeDestination.values.firstWhere((e) => e.name == (d['typeDestination'] as String? ?? 'domicileClient'), orElse: () => TypeDestination.values.first),
      adresseDepart: d['adresseDepart'] as String? ?? '',
      adresseArrivee: d['adresseArrivee'] as String? ?? '',
      latDepart: (d['latDepart'] as num?)?.toDouble(),
      lngDepart: (d['lngDepart'] as num?)?.toDouble(),
      latArrivee: (d['latArrivee'] as num?)?.toDouble(),
      lngArrivee: (d['lngArrivee'] as num?)?.toDouble(),
      livreurId: d['livreurId'] as String?,
      dateAssignation: (d['dateAssignation'] as Timestamp?)?.toDate(),
      qrDepart: d['qrDepart'] as String? ?? '',
      qrArrivee: d['qrArrivee'] as String? ?? '',
      statut: d['statut'] as String? ?? 'enAttente',
      datePrisEnCharge: (d['datePrisEnCharge'] as Timestamp?)?.toDate(),
      dateLivraison: (d['dateLivraison'] as Timestamp?)?.toDate(),
      dateLivraisonPrevue: (d['dateLivraisonPrevue'] as Timestamp?)?.toDate(),
      fraisLivraison: (d['fraisLivraison'] as num?)?.toDouble() ?? 500,
      gainLivreur: (d['gainLivreur'] as num?)?.toDouble() ?? 350,
      photoLivraison: d['photoLivraison'] as String?,
      signatureNom: d['signatureNom'] as String?,
      noteClient: (d['noteClient'] as num?)?.toDouble(),
    );
  }
}

// ─── Sous-commande (par boutique) ─────────────────────────────────────────────

class SousCommande {
  final String id;
  final String sessionId;       // ID de la SessionCommande parente
  final String clientId;
  final String boutiqueId;
  final String boutiqueNom;

  // Articles de CETTE boutique uniquement
  final List<PanierItem> articles;

  // Couture optionnelle
  final String? couturierId;
  final String? livraisonId; // lien vers la livraison (suivi client)
  final String? commandeCoutureId; // si article avec couture

  // Livraisons (1 ou 2 selon si couture ou non)
  // Stockées en sous-collection : sous_commandes/{id}/livraisons
  List<EtapeLivraison> livraisons; // chargées séparément

  // Statut
  StatutSousCommande statut;
  final DateTime dateCreation;
  DateTime? dateConfirmationBoutique;
  DateTime? dateTerminaison;

  // Financier
  final double sousTotal;             // articles de cette boutique
  final double fraisLivraison;        // total frais livraison de cette SC
  final double totalClient;           // ce que le client paie pour cette boutique
  final double commissionPlateforme;
  final double netBoutique;
  final double? netCouturier;

  // Notes
  final String? notesClient;
  final String? notesBoutique;
  double? noteBoutique;
  double? noteLivreur;

  SousCommande({
    required this.id,
    required this.sessionId,
    required this.clientId,
    required this.boutiqueId,
    required this.boutiqueNom,
    required this.articles,
    this.couturierId,
    this.commandeCoutureId,
    this.livraisons = const [],
    required this.statut,
    this.livraisonId,
    required this.dateCreation,
    this.dateConfirmationBoutique,
    this.dateTerminaison,
    required this.sousTotal,
    required this.fraisLivraison,
    required this.totalClient,
    required this.commissionPlateforme,
    required this.netBoutique,
    this.netCouturier,
    this.notesClient,
    this.notesBoutique,
    this.noteBoutique,
    this.noteLivreur,
  });

  bool get avecCouture => couturierId != null;
  bool get estTerminee =>
      statut == StatutSousCommande.livree ||
      statut == StatutSousCommande.terminee; // legacy
  bool get estActive => ![
    StatutSousCommande.terminee,
    StatutSousCommande.annulee,
  ].contains(statut);

  // Livraison principale (vers client ou couturier)
  EtapeLivraison? get livraisonPrincipale =>
      livraisons.isEmpty ? null : livraisons.first;

  // Livraison finale (après couture, vers client)
  EtapeLivraison? get livraisonFinale =>
      livraisons.length > 1 ? livraisons.last : null;

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('sous_commandes');

  static Stream<List<SousCommande>> streamParSession(String sessionId) =>
      collection
          .where('sessionId', isEqualTo: sessionId)
          .snapshots()
          .map((snap) => snap.docs.map((d) => SousCommande.fromDoc(d)).toList());

  static Stream<List<SousCommande>> streamParBoutique(String boutiqueId) =>
      collection
          .where('boutiqueId', isEqualTo: boutiqueId)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map((d) => SousCommande.fromDoc(d)).toList();
            // tri par date décroissante côté client (pas d'index requis)
            list.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
            return list;
          });

  static Stream<List<SousCommande>> streamParClient(String clientId) =>
      collection
          .where('clientId', isEqualTo: clientId)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map((d) => SousCommande.fromDoc(d)).toList();
            list.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
            return list.take(20).toList();
          });

  factory SousCommande.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SousCommande(
      id: doc.id,
      sessionId: d['sessionId'] as String? ?? '',
      clientId: d['clientId'] as String? ?? '',
      boutiqueId: d['boutiqueId'] as String? ?? '',
      boutiqueNom: d['boutiqueNom'] as String? ?? '',
      articles: (d['articles'] as List<dynamic>? ?? [])
          .map((e) => PanierItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      couturierId: d['couturierId'] as String?,
      commandeCoutureId: d['commandeCoutureId'] as String?,
      statut: StatutSousCommande.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enAttente'), orElse: () => StatutSousCommande.values.first),
      livraisonId: d['livraisonId'] as String?,
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateConfirmationBoutique: (d['dateConfirmationBoutique'] as Timestamp?)?.toDate(),
      dateTerminaison: (d['dateTerminaison'] as Timestamp?)?.toDate(),
      sousTotal: (d['sousTotal'] as num? ?? 0).toDouble(),
      fraisLivraison: (d['fraisLivraison'] as num? ?? 0).toDouble(),
      totalClient: (d['totalClient'] as num? ?? 0).toDouble(),
      commissionPlateforme: (d['commissionPlateforme'] as num? ?? 0).toDouble(),
      netBoutique: (d['netBoutique'] as num? ?? 0).toDouble(),
      netCouturier: (d['netCouturier'] as num?)?.toDouble(),
      notesClient: d['notesClient'] as String?,
      notesBoutique: d['notesBoutique'] as String?,
      noteBoutique: (d['noteBoutique'] as num?)?.toDouble(),
      noteLivreur: (d['noteLivreur'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'clientId': clientId,
    'boutiqueId': boutiqueId,
    'boutiqueNom': boutiqueNom,
    'articles': articles.map((a) => a.toMap()).toList(),
    'couturierId': couturierId,
    'commandeCoutureId': commandeCoutureId,
    'statut': statut.name,
    'dateCreation': dateCreation,
    'dateConfirmationBoutique': dateConfirmationBoutique,
    'dateTerminaison': dateTerminaison,
    'sousTotal': sousTotal,
    'fraisLivraison': fraisLivraison,
    'totalClient': totalClient,
    'commissionPlateforme': commissionPlateforme,
    'netBoutique': netBoutique,
    'netCouturier': netCouturier,
    'notesClient': notesClient,
    'notesBoutique': notesBoutique,
    'noteBoutique': noteBoutique,
    'noteLivreur': noteLivreur,
  };

  /// Retourne (label, codePoint de l'icône Material)
  /// Côté UI : Icon(IconData(codePoint, fontFamily: 'MaterialIcons'))
  (String, int) get labelStatut => switch (statut) {
    StatutSousCommande.enAttente            => ('En attente boutique', 0xe614), // clock
    StatutSousCommande.confirmeeBoutique    => ('Confirmée', 0xe156),
    StatutSousCommande.enPreparation        => ('En préparation', 0xe1b2),
    StatutSousCommande.prete                => ('Prête', 0xe86c),
    StatutSousCommande.enCoursLivraison     => ('En livraison', 0xe558),
    StatutSousCommande.livree               => ('Livrée', 0xe5ca),
    StatutSousCommande.avecCouturier        => ('Chez couturier', 0xe3ae),
    StatutSousCommande.costurierTermine     => ('Couture terminée', 0xe5ca),
    StatutSousCommande.terminee             => ('Terminée ✓', 0xe5ca),
    StatutSousCommande.annulee              => ('Annulée', 0xe5c9),
    StatutSousCommande.litige               => ('Litige', 0xe002),
  };
}

// ─── Session commande (vue client) ────────────────────────────────────────────

class SessionCommande {
  final String id;
  final String clientId;
  final List<String> sousCommandeIds;

  // Totaux agrégés (calculés à la création)
  final double totalArticles;
  final double totalLivraisons;
  final double totalPayeClient;
  final double totalCommissions;

  // Paiement
  final String methodePaiement;
  final String? referenceTransaction;
  bool paiementConfirme;

  // Statut agrégé
  StatutSession statut;
  final DateTime dateCreation;

  // Chargées à la demande
  List<SousCommande> sousCommandes;

  SessionCommande({
    required this.id,
    required this.clientId,
    required this.sousCommandeIds,
    required this.totalArticles,
    required this.totalLivraisons,
    required this.totalPayeClient,
    required this.totalCommissions,
    required this.methodePaiement,
    this.referenceTransaction,
    this.paiementConfirme = false,
    this.statut = StatutSession.enCours,
    required this.dateCreation,
    this.sousCommandes = const [],
  });

  int get nombreBoutiques => sousCommandeIds.length;
  String get totalFmt => PrixFCFA.formater(totalPayeClient);

  // Statut calculé depuis les sous-commandes
  StatutSession get statutCalcule {
    if (sousCommandes.isEmpty) return statut;
    final toutesTerminees = sousCommandes.every((sc) => sc.estTerminee);
    if (toutesTerminees) return StatutSession.touteLivree;
    final certainesTerminees = sousCommandes.any((sc) => sc.estTerminee);
    if (certainesTerminees) return StatutSession.partiellementLivree;
    return StatutSession.enCours;
  }

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('sessions_commande');

  static Stream<List<SessionCommande>> streamParClient(String clientId) =>
      collection
          .where('clientId', isEqualTo: clientId)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map((d) => SessionCommande.fromDoc(d)).toList();
            list.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
            return list.take(20).toList();
          });

  factory SessionCommande.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SessionCommande(
      id: doc.id,
      clientId: d['clientId'] as String? ?? '',
      sousCommandeIds: List<String>.from(d['sousCommandeIds'] ?? []),
      totalArticles: (d['totalArticles'] as num? ?? 0).toDouble(),
      totalLivraisons: (d['totalLivraisons'] as num? ?? 0).toDouble(),
      totalPayeClient: (d['totalPayeClient'] as num? ?? 0).toDouble(),
      totalCommissions: (d['totalCommissions'] as num? ?? 0).toDouble(),
      methodePaiement: d['methodePaiement'] as String? ?? '',
      referenceTransaction: d['referenceTransaction'] as String?,
      paiementConfirme: d['paiementConfirme'] as bool? ?? false,
      statut: StatutSession.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enCours'), orElse: () => StatutSession.values.first),
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    'sousCommandeIds': sousCommandeIds,
    'totalArticles': totalArticles,
    'totalLivraisons': totalLivraisons,
    'totalPayeClient': totalPayeClient,
    'totalCommissions': totalCommissions,
    'methodePaiement': methodePaiement,
    'referenceTransaction': referenceTransaction,
    'paiementConfirme': paiementConfirme,
    'statut': statut.name,
    'dateCreation': FieldValue.serverTimestamp(),
  };
}
