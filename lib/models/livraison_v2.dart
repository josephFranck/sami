import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/transaction_financiere.dart';

enum StatutLivraison {
  enAttente,          // commande passée, pas encore de livreur
  rechercheLibreur,   // agent IA cherche un livreur
  livreurAssigne,     // livreur trouvé et accepté
  enRouteOrigine,     // livreur en route vers boutique/couturier
  articleRecupere,    // livreur a récupéré l'article (QR scanné à l'origine)
  enLivraison,        // livreur en route vers client
  pretRetrait,        // disponible pour retrait client (click & collect)
  livre,              // livraison confirmée (QR scanné à destination)
  echec,              // livraison échouée
  annule,             // annulée
  litige,             // litige en cours
}

enum TypeLivraison {
  pagne,       // tissu depuis boutique
  confection,  // vêtement depuis couturier
  marche,      // courses du marché
  food,        // nourriture (suya, etc.)
  glace,       // Garoua Fraîcheur
}

/// Mode de récupération de l'article
enum ModeRecuperation {
  livreurVaBoutique,     // livreur va chercher à la boutique
  boutiquePointRelais,   // boutique dépose à un point relais
  couturierLuiMeme,      // le couturier livre lui-même
  livreurDedieBoutique,  // livreur attitré de la boutique
  retraitClient,         // client vient chercher lui-même (click & collect)
}

/// Mode de validation de la livraison
enum ModeValidation {
  qrCode,           // scan QR code (principal)
  otp,              // code OTP SMS
  photoPreuve,      // photo prise par livreur
  signatureNumerique, // signature sur écran
  cashEtQr,         // paiement cash + QR code
}

/// QR Code généré pour chaque livraison
/// Deux QR codes : un pour l'origine, un pour la destination
class QrLivraison {
  final String codeOrigine;      // scanné quand livreur récupère l'article
  final String codeDestination;  // scanné quand livraison faite au client
  final DateTime dateExpiration; // expire après 24h
  bool origineScanne;
  bool destinationScanne;
  DateTime? dateScannOrigine;
  DateTime? dateScannDestination;
  String? scannePar;             // ID du livreur ou client

  QrLivraison({
    required this.codeOrigine,
    required this.codeDestination,
    required this.dateExpiration,
    this.origineScanne = false,
    this.destinationScanne = false,
    this.dateScannOrigine,
    this.dateScannDestination,
    this.scannePar,
  });

  bool get estExpire => DateTime.now().isAfter(dateExpiration);

  Map<String, dynamic> toMap() => {
    'codeOrigine': codeOrigine,
    'codeDestination': codeDestination,
    'dateExpiration': dateExpiration,
    'origineScanne': origineScanne,
    'destinationScanne': destinationScanne,
    'dateScannOrigine': dateScannOrigine,
    'dateScannDestination': dateScannDestination,
    'scannePar': scannePar,
  };

  factory QrLivraison.fromMap(Map<String, dynamic> m) => QrLivraison(
    codeOrigine: m['codeOrigine'] as String? ?? '',
    codeDestination: m['codeDestination'] as String? ?? '',
    dateExpiration: ((m['dateExpiration'] as Timestamp?)?.toDate() ?? DateTime.now()),
    origineScanne: m['origineScanne'] as bool? ?? false,
    destinationScanne: m['destinationScanne'] as bool? ?? false,
    dateScannOrigine: (m['dateScannOrigine'] as Timestamp?)?.toDate(),
    dateScannDestination: (m['dateScannDestination'] as Timestamp?)?.toDate(),
    scannePar: m['scannePar'] as String?,
  );
}

/// Preuve de livraison — archivée pour litiges
class PreuveLivraison {
  final ModeValidation mode;
  final DateTime dateValidation;
  final String valideePar;       // ID livreur ou client
  final String? photoUrl;        // si mode photoPreuve
  final String? otpUtilise;      // si mode OTP
  final double? latitudeValidation;
  final double? longitudeValidation;
  final String? signatureBase64; // si mode signature

  PreuveLivraison({
    required this.mode,
    required this.dateValidation,
    required this.valideePar,
    this.photoUrl,
    this.otpUtilise,
    this.latitudeValidation,
    this.longitudeValidation,
    this.signatureBase64,
  });

  Map<String, dynamic> toMap() => {
    'mode': mode.name,
    'dateValidation': dateValidation,
    'valideePar': valideePar,
    'photoUrl': photoUrl,
    'otpUtilise': otpUtilise,
    'latitudeValidation': latitudeValidation,
    'longitudeValidation': longitudeValidation,
    'signatureBase64': signatureBase64,
  };

  factory PreuveLivraison.fromMap(Map<String, dynamic> m) => PreuveLivraison(
    mode: ModeValidation.values.firstWhere((e) => e.name == (m['mode'] as String? ?? ''), orElse: () => ModeValidation.values.first),
    dateValidation: ((m['dateValidation'] as Timestamp?)?.toDate() ?? DateTime.now()),
    valideePar: m['valideePar'] as String? ?? '',
    photoUrl: m['photoUrl'] as String?,
    otpUtilise: m['otpUtilise'] as String?,
    latitudeValidation: (m['latitudeValidation'] as num?)?.toDouble(),
    longitudeValidation: (m['longitudeValidation'] as num?)?.toDouble(),
    signatureBase64: m['signatureBase64'] as String?,
  );
}

/// Décision de l'agent IA sur l'assignation
class DecisionAgent {
  final String livreurId;
  final String raisonnement;
  final double scoreConfiance;
  final DateTime timestamp;
  final bool valideeParHumain;
  final String? commentaireHumain;

  DecisionAgent({
    required this.livreurId,
    required this.raisonnement,
    required this.scoreConfiance,
    required this.timestamp,
    this.valideeParHumain = false,
    this.commentaireHumain,
  });

  Map<String, dynamic> toMap() => {
    'livreurId': livreurId,
    'raisonnement': raisonnement,
    'scoreConfiance': scoreConfiance,
    'timestamp': timestamp,
    'valideeParHumain': valideeParHumain,
    'commentaireHumain': commentaireHumain,
  };

  factory DecisionAgent.fromMap(Map<String, dynamic> m) => DecisionAgent(
    livreurId: m['livreurId'] as String? ?? '',
    raisonnement: m['raisonnement'] as String? ?? '',
    scoreConfiance: (m['scoreConfiance'] as num? ?? 0).toDouble(),
    timestamp: ((m['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now()),
    valideeParHumain: m['valideeParHumain'] as bool? ?? false,
    commentaireHumain: m['commentaireHumain'] as String?,
  );
}

class Livraison {
  /// Map brute du doc : accès aux champs additionnels (ex. 'articles').
  final Map<String, dynamic> brut;
  final String id;
  final String commandeId;  // = ID de la SousCommande dans l'archi multi-boutiques

  /// Alias clair : une livraison correspond à une sous-commande
  String get sousCommandeId => commandeId;

  final String clientId;
  final TypeLivraison typeLivraison;
  final ModeRecuperation modeRecuperation;

  // Origine
  final String origineId;
  final String origineNom;
  final double origineLat;
  final double origineLng;
  final String origineAdresse;

  // Destination
  final double destinationLat;
  final double destinationLng;
  final String destinationAdresse;
  final String destinationQuartier;

  // Livreur
  String? livreurId;
  StatutLivraison statut;

  // Contrôle anti-fraude : levé si la validation est suspecte
  // (GPS incohérent, code de secours, signature). L'admin contrôle avant paiement.
  bool aVerifier;
  String? motifVerification;
  String? validationSecours; // 'code_court' | 'signature' | null

  // ── Financier (lié au modèle de revenus) ──────────────────
  final DecompositionFinanciere decompositionFinanciere;
  String? transactionId;          // référence vers TransactionFinanciere
  String methodePaiementChoisi;   // 'mobile_money', 'cash', 'credits'
  bool paiementConfirme;
  bool livreurPaye;               // livreur a reçu sa part

  // ── Validation QR Code ────────────────────────────────────
  final QrLivraison qrCode;
  final List<ModeValidation> modesValidationDisponibles;
  PreuveLivraison? preuveRecuperation;  // preuve à l'origine
  PreuveLivraison? preuveLivraison;     // preuve à la destination

  // ── Timing ───────────────────────────────────────────────
  final DateTime dateCreation;
  DateTime? dateAssignation;
  DateTime? dateRecuperation;
  DateTime? dateLivraison;
  final DateTime? dateLivraisonPrevue;

  // ── Tracking GPS ─────────────────────────────────────────
  double? livreurLatActuelle;
  double? livreurLngActuelle;

  // ── Agent IA ─────────────────────────────────────────────
  DecisionAgent? decisionAgent;
  String niveauAutonomie;

  // ── Évaluation ───────────────────────────────────────────
  String? noteClient;
  double? noteClientScore;
  double? noteLivreurScore;

  Livraison({
    this.brut = const {},
    required this.id,
    required this.commandeId,
    required this.clientId,
    required this.typeLivraison,
    this.modeRecuperation = ModeRecuperation.livreurVaBoutique,
    required this.origineId,
    required this.origineNom,
    required this.origineLat,
    required this.origineLng,
    required this.origineAdresse,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAdresse,
    required this.destinationQuartier,
    this.livreurId,
    this.statut = StatutLivraison.enAttente,
    this.aVerifier = false,
    this.motifVerification,
    this.validationSecours,
    required this.decompositionFinanciere,
    this.transactionId,
    this.methodePaiementChoisi = 'mobile_money',
    this.paiementConfirme = false,
    this.livreurPaye = false,
    required this.qrCode,
    this.modesValidationDisponibles = const [
      ModeValidation.qrCode,
      ModeValidation.otp,
      ModeValidation.photoPreuve,
      ModeValidation.signatureNumerique,
    ],
    this.preuveRecuperation,
    this.preuveLivraison,
    required this.dateCreation,
    this.dateAssignation,
    this.dateRecuperation,
    this.dateLivraison,
    this.dateLivraisonPrevue,
    this.livreurLatActuelle,
    this.livreurLngActuelle,
    this.decisionAgent,
    this.niveauAutonomie = 'supervised',
    this.noteClient,
    this.noteClientScore,
    this.noteLivreurScore,
  });

  /// Génère un code QR unique pour cette livraison
  static QrLivraison genererQr(String livraisonId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return QrLivraison(
      codeOrigine: 'SAMI-ORIG-$livraisonId-$ts',
      codeDestination: 'SAMI-DEST-$livraisonId-$ts',
      dateExpiration: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  static CollectionReference<Map<String, dynamic>> livraisonCollection =
      FirebaseFirestore.instance.collection('livraisons');

  factory Livraison.fromFirebaseDocument(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Livraison(
      brut: d,
      id: doc.id,
      commandeId: d['commandeId'] as String? ?? '',
      clientId: d['clientId'] as String? ?? '',
      typeLivraison: TypeLivraison.values.firstWhere((e) => e.name == (d['typeLivraison'] as String? ?? ''), orElse: () => TypeLivraison.values.first),
      modeRecuperation: ModeRecuperation.values.firstWhere((e) => e.name == (d['modeRecuperation'] as String? ?? 'livreurVaBoutique'), orElse: () => ModeRecuperation.values.first),
      origineId: d['origineId'] as String? ?? '',
      origineNom: d['origineNom'] as String? ?? '',
      origineLat: (d['origineLat'] as num? ?? 0).toDouble(),
      origineLng: (d['origineLng'] as num? ?? 0).toDouble(),
      origineAdresse: d['origineAdresse'] as String? ?? '',
      destinationLat: (d['destinationLat'] as num? ?? 0).toDouble(),
      destinationLng: (d['destinationLng'] as num? ?? 0).toDouble(),
      destinationAdresse: d['destinationAdresse'] as String? ?? '',
      destinationQuartier: d['destinationQuartier'] as String? ?? '',
      livreurId: d['livreurId'] as String?,
      statut: StatutLivraison.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enAttente'), orElse: () => StatutLivraison.values.first),
      aVerifier: d['aVerifier'] as bool? ?? false,
      motifVerification: d['motifVerification'] as String?,
      validationSecours: d['validationSecours'] as String?,
      decompositionFinanciere: DecompositionFinanciere.fromMap(
          d['decompositionFinanciere'] as Map<String, dynamic>),
      transactionId: d['transactionId'] as String?,
      methodePaiementChoisi: d['methodePaiementChoisi'] as String? ?? 'mobile_money',
      paiementConfirme: d['paiementConfirme'] as bool? ?? false,
      livreurPaye: d['livreurPaye'] as bool? ?? false,
      qrCode: QrLivraison.fromMap(d['qrCode'] as Map<String, dynamic>),
      modesValidationDisponibles: (d['modesValidationDisponibles'] as List<dynamic>?)
              ?.map((e) => ModeValidation.values.firstWhere((v) => v.name == (e?.toString() ?? ''), orElse: () => ModeValidation.values.first))
              .toList() ??
          [ModeValidation.qrCode],
      preuveRecuperation: d['preuveRecuperation'] != null
          ? PreuveLivraison.fromMap(d['preuveRecuperation'] as Map<String, dynamic>)
          : null,
      preuveLivraison: d['preuveLivraison'] != null
          ? PreuveLivraison.fromMap(d['preuveLivraison'] as Map<String, dynamic>)
          : null,
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateAssignation: (d['dateAssignation'] as Timestamp?)?.toDate(),
      dateRecuperation: (d['dateRecuperation'] as Timestamp?)?.toDate(),
      dateLivraison: (d['dateLivraison'] as Timestamp?)?.toDate(),
      dateLivraisonPrevue: (d['dateLivraisonPrevue'] as Timestamp?)?.toDate(),
      livreurLatActuelle: (d['livreurLatActuelle'] as num?)?.toDouble(),
      livreurLngActuelle: (d['livreurLngActuelle'] as num?)?.toDouble(),
      decisionAgent: d['decisionAgent'] != null
          ? DecisionAgent.fromMap(d['decisionAgent'] as Map<String, dynamic>)
          : null,
      niveauAutonomie: d['niveauAutonomie'] as String? ?? 'supervised',
      noteClient: d['noteClient'] as String?,
      noteClientScore: (d['noteClientScore'] as num?)?.toDouble(),
      noteLivreurScore: (d['noteLivreurScore'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'commandeId': commandeId,
    'clientId': clientId,
    'typeLivraison': typeLivraison.name,
    'modeRecuperation': modeRecuperation.name,
    'origineId': origineId,
    'origineNom': origineNom,
    'origineLat': origineLat,
    'origineLng': origineLng,
    'origineAdresse': origineAdresse,
    'destinationLat': destinationLat,
    'destinationLng': destinationLng,
    'destinationAdresse': destinationAdresse,
    'destinationQuartier': destinationQuartier,
    'livreurId': livreurId,
    'statut': statut.name,
    'decompositionFinanciere': decompositionFinanciere.toMap(),
    'transactionId': transactionId,
    'methodePaiementChoisi': methodePaiementChoisi,
    'paiementConfirme': paiementConfirme,
    'livreurPaye': livreurPaye,
    'qrCode': qrCode.toMap(),
    'modesValidationDisponibles': modesValidationDisponibles.map((e) => e.name).toList(),
    'preuveRecuperation': preuveRecuperation?.toMap(),
    'preuveLivraison': preuveLivraison?.toMap(),
    'dateCreation': dateCreation,
    'dateAssignation': dateAssignation,
    'dateRecuperation': dateRecuperation,
    'dateLivraison': dateLivraison,
    'dateLivraisonPrevue': dateLivraisonPrevue,
    'livreurLatActuelle': livreurLatActuelle,
    'livreurLngActuelle': livreurLngActuelle,
    'decisionAgent': decisionAgent?.toMap(),
    'niveauAutonomie': niveauAutonomie,
    'noteClient': noteClient,
    'noteClientScore': noteClientScore,
    'noteLivreurScore': noteLivreurScore,
  };
}
