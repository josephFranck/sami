import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME COUTURIER — Modèles, Mesures, Commandes
// ═══════════════════════════════════════════════════════════════════════════

// ─── Langues supportées ───────────────────────────────────────────────────────

enum Langue { fr, en, ff } // ff = Fulfulde

// ─── Définition d'une mesure requise par un modèle ───────────────────────────

class DefinitionMesure {
  final String id;             // ex: 'tourPoitrine'
  final Map<Langue, String> labels; // label dans chaque langue
  final Map<Langue, String> instructions; // comment prendre la mesure
  final String zone;           // zone du corps colorée sur le mannequin
  final String couleurZone;    // couleur hex pour la zone sur le SVG
  final double min;            // valeur min en cm
  final double max;            // valeur max en cm
  final bool obligatoire;

  const DefinitionMesure({
    required this.id,
    required this.labels,
    required this.instructions,
    required this.zone,
    required this.couleurZone,
    required this.min,
    required this.max,
    this.obligatoire = true,
  });

  String label(Langue l) => labels[l] ?? labels[Langue.fr] ?? id;
  String instruction(Langue l) => instructions[l] ?? instructions[Langue.fr] ?? '';

  // ── Catalogue complet de toutes les mesures possibles ─────────────────────
  static const Map<String, DefinitionMesure> catalogue = {

    'tourPoitrine': DefinitionMesure(
      id: 'tourPoitrine',
      labels: {
        Langue.fr: 'Tour de poitrine',
        Langue.en: 'Chest circumference',
        Langue.ff: 'Demetee gite',
      },
      instructions: {
        Langue.fr: 'Mesurez autour de la partie la plus large de la poitrine, bras baissés.',
        Langue.en: 'Measure around the fullest part of the chest, arms relaxed.',
        Langue.ff: 'Ndaga demetee e nder gite mawnde, hendu gite waaɗa.',
      },
      zone: 'poitrine',
      couleurZone: '#E8593C',
      min: 70, max: 160,
    ),

    'tourTaille': DefinitionMesure(
      id: 'tourTaille',
      labels: {
        Langue.fr: 'Tour de taille',
        Langue.en: 'Waist circumference',
        Langue.ff: 'Demetee bowre',
      },
      instructions: {
        Langue.fr: 'Mesurez à la taille naturelle, la partie la plus fine.',
        Langue.en: 'Measure at the natural waistline, the narrowest part.',
        Langue.ff: 'Ndaga bowre e nder nder mum mawnde.',
      },
      zone: 'taille',
      couleurZone: '#7F77DD',
      min: 55, max: 150,
    ),

    'tourHanches': DefinitionMesure(
      id: 'tourHanches',
      labels: {
        Langue.fr: 'Tour de hanches',
        Langue.en: 'Hip circumference',
        Langue.ff: 'Demetee puccu',
      },
      instructions: {
        Langue.fr: 'Mesurez autour de la partie la plus large des hanches et fessiers.',
        Langue.en: 'Measure around the fullest part of the hips and buttocks.',
        Langue.ff: 'Ndaga demetee e nder puccu e dabbere mawnde.',
      },
      zone: 'hanches',
      couleurZone: '#1D9E75',
      min: 70, max: 170,
    ),

    'hauteurTotal': DefinitionMesure(
      id: 'hauteurTotal',
      labels: {
        Langue.fr: 'Hauteur totale',
        Langue.en: 'Total height',
        Langue.ff: 'Juutde mawnde',
      },
      instructions: {
        Langue.fr: 'Mesurez du sommet de la tête jusqu\'aux pieds, debout droit.',
        Langue.en: 'Measure from the top of the head to the floor, standing straight.',
        Langue.ff: 'Ndaga e dow hoore haa ƴiiƴe dunndu.',
      },
      zone: 'corps',
      couleurZone: '#888780',
      min: 100, max: 220,
    ),

    'couCheville': DefinitionMesure(
      id: 'couCheville',
      labels: {
        Langue.fr: 'Du cou à la cheville',
        Langue.en: 'Neck to ankle',
        Langue.ff: 'Daande haa korlal',
      },
      instructions: {
        Langue.fr:
            'Mesurez de la base du cou jusqu\'à la cheville, debout droit.',
        Langue.en: 'Measure from the base of the neck down to the ankle.',
        Langue.ff: 'Ɓetu gila daande haa korlal, darii no feewi.',
      },
      zone: 'corps',
      couleurZone: '#888780',
      min: 100,
      max: 220,
    ),

    'longueurDos': DefinitionMesure(
      id: 'longueurDos',
      labels: {
        Langue.fr: 'Longueur du dos',
        Langue.en: 'Back length',
        Langue.ff: 'Juutde futuro',
      },
      instructions: {
        Langue.fr: 'De la nuque jusqu\'à la taille, dans le dos.',
        Langue.en: 'From the nape of the neck to the waist, in the back.',
        Langue.ff: 'E hoore bowre haa bowre, e futuro.',
      },
      zone: 'dos',
      couleurZone: '#BA7517',
      min: 30, max: 60,
    ),

    'longueurManche': DefinitionMesure(
      id: 'longueurManche',
      labels: {
        Langue.fr: 'Longueur de manche',
        Langue.en: 'Sleeve length',
        Langue.ff: 'Juutde daɓɓere',
      },
      instructions: {
        Langue.fr: 'De l\'épaule jusqu\'au poignet, bras légèrement plié.',
        Langue.en: 'From shoulder to wrist, arm slightly bent.',
        Langue.ff: 'E yeeso haa goomu, daɓɓere majja waaɗa.',
      },
      zone: 'bras',
      couleurZone: '#378ADD',
      min: 40, max: 75,
    ),

    'largeurEpaule': DefinitionMesure(
      id: 'largeurEpaule',
      labels: {
        Langue.fr: 'Largeur d\'épaule',
        Langue.en: 'Shoulder width',
        Langue.ff: 'Toowngo yeeso',
      },
      instructions: {
        Langue.fr: 'D\'une épaule à l\'autre, passant par le haut du dos.',
        Langue.en: 'From one shoulder to the other, across the upper back.',
        Langue.ff: 'E yeeso gooto haa yeeso goɗɗo e dow futuro.',
      },
      zone: 'epaules',
      couleurZone: '#D4537E',
      min: 30, max: 60,
    ),

    'tourCou': DefinitionMesure(
      id: 'tourCou',
      labels: {
        Langue.fr: 'Tour de cou',
        Langue.en: 'Neck circumference',
        Langue.ff: 'Demetee koyngal',
      },
      instructions: {
        Langue.fr: 'Mesurez autour du cou, légèrement relâché.',
        Langue.en: 'Measure around the neck, slightly relaxed.',
        Langue.ff: 'Ndaga demetee e nder koyngal, laawɗi.',
      },
      zone: 'cou',
      couleurZone: '#993556',
      min: 28, max: 55,
    ),

    'longueurJupe': DefinitionMesure(
      id: 'longueurJupe',
      labels: {
        Langue.fr: 'Longueur de jupe/boubou',
        Langue.en: 'Skirt/boubou length',
        Langue.ff: 'Juutde boubou',
      },
      instructions: {
        Langue.fr: 'De la taille jusqu\'où vous voulez que le vêtement descende.',
        Langue.en: 'From the waist to where you want the garment to end.',
        Langue.ff: 'E bowre haa nokku mo jippan nguun.',
      },
      zone: 'jambes',
      couleurZone: '#639922',
      min: 40, max: 130,
    ),

    'tourBras': DefinitionMesure(
      id: 'tourBras',
      labels: {
        Langue.fr: 'Tour de bras',
        Langue.en: 'Arm circumference',
        Langue.ff: 'Demetee daɓɓere',
      },
      instructions: {
        Langue.fr: 'Autour de la partie la plus large du bras, biceps.',
        Langue.en: 'Around the fullest part of the upper arm, bicep.',
        Langue.ff: 'E nder daɓɓere mawnde, bicep.',
      },
      zone: 'bras',
      couleurZone: '#378ADD',
      min: 20, max: 55,
    ),
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'labels': labels.map((k, v) => MapEntry(k.name, v)),
    'instructions': instructions.map((k, v) => MapEntry(k.name, v)),
    'zone': zone,
    'couleurZone': couleurZone,
    'min': min,
    'max': max,
    'obligatoire': obligatoire,
  };
}

// ─── Modèle de vêtement créé par un couturier ────────────────────────────────

enum TypeVetement {
  boubou,
  gandoura,
  robe,
  costume,
  chemise,
  jupe,
  pantalon,
  ensemble,
  autre,
}

enum ModeRencontre {
  clientVientCouturier,
  couturierVaClient,
  enLigne,               // mesures saisies suffisent, pas de RDV
}

class ModeleCouture {
  final String id;
  final String couturierId;
  final String boutiqueId;   // optionnel si couturier indépendant

  // Nom multilingue
  final Map<Langue, String> noms;

  /// Nom d'affichage : français d'abord, sinon la première langue saisie.
  /// (Les modèles sont multilingues — fulfulde en route.)
  String get nom => noms[Langue.fr] ??
      (noms.values.isNotEmpty ? noms.values.first : 'Modèle');
  final Map<Langue, String> descriptions;

  final TypeVetement typeVetement;
  final List<String> mesuresRequises; // IDs des mesures du catalogue
  final List<ModeRencontre> modesDisponibles;

  // Tarification
  final double prixBase;             // FCFA (prix fixe, OU prix indicatif si surDevis)
  final bool surDevis;               // true = prix négocié après la demande (devis libre)
  final double? prixDeplacementCouturier; // frais si couturier se déplace
  final int delaiJours;             // délai de confection

  // Médias
  final List<String> photosExemples;
  final String? videoPresentation;

  // Méta
  final double noteMoyenne;
  final int nombreRealisations;
  final bool estActif;
  final DateTime dateCreation;

  ModeleCouture({
    required this.id,
    required this.couturierId,
    this.boutiqueId = '',
    required this.noms,
    required this.descriptions,
    required this.typeVetement,
    required this.mesuresRequises,
    required this.modesDisponibles,
    required this.prixBase,
    this.surDevis = false,
    this.prixDeplacementCouturier,
    required this.delaiJours,
    this.photosExemples = const [],
    this.videoPresentation,
    this.noteMoyenne = 0.0,
    this.nombreRealisations = 0,
    this.estActif = true,
    required this.dateCreation,
  });

  String nom(Langue l) => noms[l] ?? noms[Langue.fr] ?? '';
  String description(Langue l) => descriptions[l] ?? descriptions[Langue.fr] ?? '';

  // Mesures réelles requises par ce modèle
  List<DefinitionMesure> get definitionsMesures => mesuresRequises
      .map((id) => DefinitionMesure.catalogue[id])
      .whereType<DefinitionMesure>()
      .toList();

  String get prixBaseFmt => PrixFCFA.formater(prixBase);

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('modeles_couture');

  factory ModeleCouture.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ModeleCouture(
      id: doc.id,
      couturierId: d['couturierId'] as String? ?? '',
      boutiqueId: d['boutiqueId'] as String? ?? '',
      noms: (d['noms'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(Langue.values.firstWhere((l) => l.name == k, orElse: () => Langue.fr), v?.toString() ?? '')),
      descriptions: (d['descriptions'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(Langue.values.firstWhere((l) => l.name == k, orElse: () => Langue.fr), v?.toString() ?? '')),
      typeVetement: TypeVetement.values.firstWhere((e) => e.name == (d['typeVetement'] as String? ?? 'boubou'), orElse: () => TypeVetement.values.first),
      mesuresRequises: List<String>.from(d['mesuresRequises'] ?? []),
      modesDisponibles: (d['modesDisponibles'] as List<dynamic>? ?? [])
          .map((m) => ModeRencontre.values.firstWhere((e) => e.name == (m?.toString() ?? ''), orElse: () => ModeRencontre.values.first))
          .toList(),
      prixBase: (d['prixBase'] as num? ?? 0).toDouble(),
      surDevis: d['surDevis'] as bool? ?? false,
      prixDeplacementCouturier: (d['prixDeplacementCouturier'] as num?)?.toDouble(),
      delaiJours: d['delaiJours'] as int? ?? 3,
      photosExemples: List<String>.from(d['photosExemples'] ?? []),
      videoPresentation: d['videoPresentation'] as String?,
      noteMoyenne: (d['noteMoyenne'] as num?)?.toDouble() ?? 0.0,
      nombreRealisations: d['nombreRealisations'] as int? ?? 0,
      estActif: d['estActif'] as bool? ?? true,
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => {
    'couturierId': couturierId,
    'boutiqueId': boutiqueId,
    'noms': noms.map((k, v) => MapEntry(k.name, v)),
    'descriptions': descriptions.map((k, v) => MapEntry(k.name, v)),
    'typeVetement': typeVetement.name,
    'mesuresRequises': mesuresRequises,
    'modesDisponibles': modesDisponibles.map((m) => m.name).toList(),
    'prixBase': prixBase,
    'surDevis': surDevis,
    'prixDeplacementCouturier': prixDeplacementCouturier,
    'delaiJours': delaiJours,
    'photosExemples': photosExemples,
    'videoPresentation': videoPresentation,
    'noteMoyenne': noteMoyenne,
    'nombreRealisations': nombreRealisations,
    'estActif': estActif,
    'dateCreation': dateCreation,
  };
}

// ─── Mesures saisies par un client ───────────────────────────────────────────

class MesuresClient {
  final String id;
  final String clientId;
  final String? nomProfil;        // ex: "Mon profil", "Pour maman"
  final Map<String, double> valeurs; // mesureId → valeur en cm
  final DateTime dateCreation;
  final DateTime? dateMiseAJour;

  MesuresClient({
    required this.id,
    required this.clientId,
    this.nomProfil,
    required this.valeurs,
    required this.dateCreation,
    this.dateMiseAJour,
  });

  bool estComplete(List<String> mesuresRequises) =>
      mesuresRequises.every((m) => valeurs.containsKey(m) && valeurs[m]! > 0);

  double? valeur(String mesureId) => valeurs[mesureId];

  static CollectionReference<Map<String, dynamic>> collection(String clientId) =>
      FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(clientId)
          .collection('mesures');

  factory MesuresClient.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return MesuresClient(
      id: doc.id,
      clientId: d['clientId'] as String? ?? '',
      nomProfil: d['nomProfil'] as String?,
      valeurs: Map<String, double>.from(
          (d['valeurs'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num? ?? 0).toDouble()))),
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateMiseAJour: (d['dateMiseAJour'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    'nomProfil': nomProfil,
    'valeurs': valeurs,
    'dateCreation': dateCreation,
    'dateMiseAJour': dateMiseAJour ?? DateTime.now(),
  };
}

// ─── Commande couturier ───────────────────────────────────────────────────────

enum StatutCommandeCouturier {
  enAttente,         // reçue, couturier pas encore confirmé
  devisPropose,      // (sur devis) le couturier a proposé un prix, en attente du client
  confirmeeCouturier,// couturier a accepté
  rdvPlanifie,       // rendez-vous fixé (si mode rencontre)
  enConfection,      // couturier confectionne
  preteLivraison,    // vêtement prêt
  livree,            // remis au client
  terminee,          // évaluée
  annulee,
  litige,
}

class CommandeCouturier {
  final String id;
  final String clientId;
  final String couturierId;
  final String modeleId;
  final bool surDevis; // prix à négocier (sinon prix fixe)
  final int nombrePagnes;
  final double fraisLivraison; // 2 trajets (tissu + vêtement)
  final String pagneId;            // pagne acheté pour ce vêtement
  final String? livraisonPagneId;  // trajet 1 : livraison du pagne chez le couturier
  final String? livraisonRetourId; // trajet 2 : livraison du vêtement fini au client

  // Mesures utilisées
  final String mesuresClientId;
  final Map<String, double> mesuresSnapshot; // copie au moment de la commande

  // Mode de rencontre choisi
  final ModeRencontre modeRencontre;
  final DateTime? rdvDate;
  final String? rdvLieu;
  final double? fraisDeplacementPaye;

  // Financier
  final double prixConvenu;
  final double? prixPropose;        // (sur devis) prix proposé par le couturier
  final double commissionPlateforme;
  // ── Part PAGNE (l'achat du tissu fait partie de la commande couture) ──
  final double prixPagne;           // prix du pagne acheté (0 si tissu fourni par le client)
  final double netBoutique;         // part reversée au boutiquier pour le pagne
  final String boutiqueId;          // boutique qui a vendu le pagne
  final String methodePaiement;

  // Statut
  StatutCommandeCouturier statut;
  final DateTime dateCommande;
  DateTime? dateConfirmation;
  DateTime? dateLivraisonPrevue;
  DateTime? dateLivraisonReelle;

  // Notes & évaluation
  String? notesClient;       // demandes spéciales
  String? notesCouturier;    // notes de confection
  double? noteClient;        // évaluation finale
  String? commentaireClient;

  CommandeCouturier({
    required this.id,
    required this.clientId,
    required this.couturierId,
    required this.modeleId,
    this.surDevis = false,
    this.nombrePagnes = 1,
    this.fraisLivraison = 0,
    required this.pagneId,
    this.livraisonPagneId,
    this.livraisonRetourId,
    required this.mesuresClientId,
    required this.mesuresSnapshot,
    required this.modeRencontre,
    this.rdvDate,
    this.rdvLieu,
    this.fraisDeplacementPaye,
    required this.prixConvenu,
    this.prixPropose,
    required this.commissionPlateforme,
    this.prixPagne = 0,
    this.netBoutique = 0,
    this.boutiqueId = '',
    required this.methodePaiement,
    this.statut = StatutCommandeCouturier.enAttente,
    required this.dateCommande,
    this.dateConfirmation,
    this.dateLivraisonPrevue,
    this.dateLivraisonReelle,
    this.notesClient,
    this.notesCouturier,
    this.noteClient,
    this.commentaireClient,
  });

  String get prixConvenuFmt => PrixFCFA.formater(prixConvenu);

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('commandes_couturier');

  factory CommandeCouturier.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return CommandeCouturier(
      id: doc.id,
      clientId: d['clientId'] as String? ?? '',
      couturierId: d['couturierId'] as String? ?? '',
      modeleId: d['modeleId'] as String? ?? '',
      surDevis: d['surDevis'] as bool? ?? false,
      nombrePagnes: (d['nombrePagnes'] as num?)?.toInt() ?? 1,
      fraisLivraison: (d['fraisLivraison'] as num?)?.toDouble() ?? 0,
      surDevis: d['surDevis'] as bool? ?? false,
      pagneId: d['pagneId'] as String? ?? '',
      livraisonPagneId: d['livraisonPagneId'] as String?,
      livraisonRetourId: d['livraisonRetourId'] as String?,
      mesuresClientId: d['mesuresClientId'] as String? ?? '',
      mesuresSnapshot: Map<String, double>.from(
          (d['mesuresSnapshot'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num? ?? 0).toDouble()))),
      modeRencontre: ModeRencontre.values.firstWhere((e) => e.name == (d['modeRencontre'] as String? ?? 'enLigne'), orElse: () => ModeRencontre.values.first),
      rdvDate: (d['rdvDate'] as Timestamp?)?.toDate(),
      rdvLieu: d['rdvLieu'] as String?,
      fraisDeplacementPaye: (d['fraisDeplacementPaye'] as num?)?.toDouble(),
      prixConvenu: (d['prixConvenu'] as num? ?? 0).toDouble(),
      prixPropose: (d['prixPropose'] as num?)?.toDouble(),
      prixPagne: (d['prixPagne'] as num?)?.toDouble() ?? 0,
      netBoutique: (d['netBoutique'] as num?)?.toDouble() ?? 0,
      boutiqueId: d['boutiqueId'] as String? ?? '',
      commissionPlateforme: (d['commissionPlateforme'] as num? ?? 0).toDouble(),
      methodePaiement: d['methodePaiement'] as String? ?? '',
      statut: StatutCommandeCouturier.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enAttente'), orElse: () => StatutCommandeCouturier.values.first),
      dateCommande: ((d['dateCommande'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateConfirmation: (d['dateConfirmation'] as Timestamp?)?.toDate(),
      dateLivraisonPrevue: (d['dateLivraisonPrevue'] as Timestamp?)?.toDate(),
      dateLivraisonReelle: (d['dateLivraisonReelle'] as Timestamp?)?.toDate(),
      notesClient: d['notesClient'] as String?,
      notesCouturier: d['notesCouturier'] as String?,
      noteClient: (d['noteClient'] as num?)?.toDouble(),
      commentaireClient: d['commentaireClient'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    'couturierId': couturierId,
    'modeleId': modeleId,
    'surDevis': surDevis,
    'nombrePagnes': nombrePagnes,
    'fraisLivraison': fraisLivraison,
    'pagneId': pagneId,
    'livraisonPagneId': livraisonPagneId,
    'livraisonRetourId': livraisonRetourId,
    'mesuresClientId': mesuresClientId,
    'mesuresSnapshot': mesuresSnapshot,
    'modeRencontre': modeRencontre.name,
    'rdvDate': rdvDate,
    'rdvLieu': rdvLieu,
    'fraisDeplacementPaye': fraisDeplacementPaye,
    'prixConvenu': prixConvenu,
    'prixPropose': prixPropose,
    'prixPagne': prixPagne,
    'netBoutique': netBoutique,
    'boutiqueId': boutiqueId,
    'commissionPlateforme': commissionPlateforme,
    'methodePaiement': methodePaiement,
    'statut': statut.name,
    'dateCommande': dateCommande,
    'dateConfirmation': dateConfirmation,
    'dateLivraisonPrevue': dateLivraisonPrevue,
    'dateLivraisonReelle': dateLivraisonReelle,
    'notesClient': notesClient,
    'notesCouturier': notesCouturier,
    'noteClient': noteClient,
    'commentaireClient': commentaireClient,
  };
}
