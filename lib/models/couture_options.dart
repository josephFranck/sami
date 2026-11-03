import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/models/couture.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PERSONNALISATIONS & TARIFICATION COUTURIER
//
// Principe :
//   Prix final = prixBase + options choisies + frais déplacement
//   Commission plateforme = % sur le total (taux selon abonnement)
//   Les couturiers sont AUSSI des clients de la plateforme
// ═══════════════════════════════════════════════════════════════════════════

// ─── Types d'options de personnalisation ─────────────────────────────────────

enum TypeOption {
  // Couleurs & fils
  couleurFil,          // couleur du fil de couture
  typeBroderie,        // style de broderie (main, machine, tradition)
  couleurBroderie,     // couleur de la broderie

  // Coupe
  typeCol,             // col rond, V, mao, carré, bateau...
  typeManche,          // sans manches, courte, 3/4, longue, évasée
  longueurVetement,    // court, mi-long, long, très long (en cm)
  ceinture,            // avec ou sans ceinture, type de ceinture

  // Ornements & décors
  perles,              // perles cousues (où, combien)
  dentelle,            // dentelle (où, quelle largeur)
  paillettesBrodees,   // paillettes cousues
  passementerie,       // galons, franges, tresses
  fermeture,           // zip, boutons, agrafe, lacet

  // Pratique
  poches,              // avec ou sans poches, nombre
  doublure,            // avec doublure, couleur
  marquageNom,         // nom brodé sur le vêtement

  // Spécifique Garoua
  styleBroderieNord,   // motifs fulani, haoussa, arabesques
  manchesGandoura,     // spécifique gandoura (courte, longue, pagode)
}

// ─── Une option de personnalisation ──────────────────────────────────────────

enum TypeValeurOption {
  choix,        // liste de choix prédéfinis (ex: rouge, bleu, vert)
  oui_non,      // case à cocher
  texte_libre,  // saisie libre (ex: nom à broder)
  nombre,       // valeur numérique (ex: nombre de boutons)
  couleur_hex,  // sélecteur de couleur
}

class ChoixOption {
  final String id;
  final Map<Langue, String> labels;
  final double surplusPrix;      // supplément en FCFA (peut être 0)
  final String? apercuUrl;       // photo de référence

  const ChoixOption({
    required this.id,
    required this.labels,
    required this.surplusPrix,
    this.apercuUrl,
  });

  String label(Langue l) => labels[l] ?? labels[Langue.fr] ?? id;

  Map<String, dynamic> toMap() => {
    'id': id,
    'labels': labels.map((k, v) => MapEntry(k.name, v)),
    'surplusPrix': surplusPrix,
    'apercuUrl': apercuUrl,
  };

  factory ChoixOption.fromMap(Map<String, dynamic> m) => ChoixOption(
    id: m['id'] as String? ?? '',
    labels: (m['labels'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(Langue.values.firstWhere((l) => l.name == k, orElse: () => Langue.values.first), v as String? ?? '')),
    surplusPrix: (m['surplusPrix'] as num? ?? 0).toDouble(),
    apercuUrl: m['apercuUrl'] as String?,
  );
}

class OptionPersonnalisation {
  final String id;
  final TypeOption type;
  final Map<Langue, String> labels;
  final Map<Langue, String> descriptions;
  final TypeValeurOption typeValeur;

  // Tarification
  final bool estGratuit;         // si true, pas de supplément quoi qu'on choisisse
  final double prixFixe;         // supplément fixe si typeValeur = oui_non
  final List<ChoixOption> choix; // si typeValeur = choix

  // Paramètres
  final bool obligatoire;        // le client DOIT choisir
  final String? valeurDefaut;    // valeur présélectionnée
  final int? min;                // pour typeValeur = nombre
  final int? max;

  // Photos de référence
  final List<String> photosReference;

  const OptionPersonnalisation({
    required this.id,
    required this.type,
    required this.labels,
    required this.descriptions,
    required this.typeValeur,
    this.estGratuit = false,
    this.prixFixe = 0,
    this.choix = const [],
    this.obligatoire = false,
    this.valeurDefaut,
    this.min,
    this.max,
    this.photosReference = const [],
  });

  String label(Langue l) => labels[l] ?? labels[Langue.fr] ?? id;
  String description(Langue l) => descriptions[l] ?? descriptions[Langue.fr] ?? '';

  // Prix minimum possible (0 si gratuit ou choix à 0)
  double get prixMin => estGratuit ? 0 :
    (typeValeur == TypeValeurOption.choix && choix.isNotEmpty)
        ? choix.map((c) => c.surplusPrix).reduce((a, b) => a < b ? a : b)
        : prixFixe;

  // Prix maximum possible
  double get prixMax => estGratuit ? 0 :
    (typeValeur == TypeValeurOption.choix && choix.isNotEmpty)
        ? choix.map((c) => c.surplusPrix).reduce((a, b) => a > b ? a : b)
        : prixFixe;

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'labels': labels.map((k, v) => MapEntry(k.name, v)),
    'descriptions': descriptions.map((k, v) => MapEntry(k.name, v)),
    'typeValeur': typeValeur.name,
    'estGratuit': estGratuit,
    'prixFixe': prixFixe,
    'choix': choix.map((c) => c.toMap()).toList(),
    'obligatoire': obligatoire,
    'valeurDefaut': valeurDefaut,
    'min': min,
    'max': max,
    'photosReference': photosReference,
  };

  factory OptionPersonnalisation.fromMap(Map<String, dynamic> m) => OptionPersonnalisation(
    id: m['id'] as String? ?? '',
    type: TypeOption.values.firstWhere((e) => e.name == (m['type'] as String? ?? ''), orElse: () => TypeOption.values.first),
    labels: (m['labels'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(Langue.values.firstWhere((l) => l.name == k, orElse: () => Langue.values.first), v as String? ?? '')),
    descriptions: (m['descriptions'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(Langue.values.firstWhere((l) => l.name == k, orElse: () => Langue.values.first), v as String? ?? '')),
    typeValeur: TypeValeurOption.values.firstWhere((e) => e.name == (m['typeValeur'] as String? ?? ''), orElse: () => TypeValeurOption.values.first),
    estGratuit: m['estGratuit'] as bool? ?? false,
    prixFixe: (m['prixFixe'] as num?)?.toDouble() ?? 0,
    choix: (m['choix'] as List<dynamic>? ?? [])
        .map((c) => ChoixOption.fromMap(c as Map<String, dynamic>))
        .toList(),
    obligatoire: m['obligatoire'] as bool? ?? false,
    valeurDefaut: m['valeurDefaut'] as String?,
    min: m['min'] as int?,
    max: m['max'] as int?,
    photosReference: List<String>.from(m['photosReference'] ?? []),
  );
}

// ─── Modèle couture enrichi avec options ─────────────────────────────────────
// Extension de ModeleCouture (on ne réécrit pas, on étend via une classe dérivée)

class ModeleCoutureComplet {
  final ModeleCouture base;
  final List<OptionPersonnalisation> options;

  // Prise de mesures
  final ModeCollecteMesures modeCollecteMesures;
  final double? fraisPriseMesuresDomicile; // si couturier se déplace pour mesures

  // Délais par mode
  final int delaiAvecRdv;      // délai si rencontre physique (jours)
  final int delaiSanRdv;       // délai si tout en ligne (jours)

  // Exemple de réalisations
  final List<String> photosRealisations; // photos de vêtements faits

  const ModeleCoutureComplet({
    required this.base,
    this.options = const [],
    this.modeCollecteMesures = ModeCollecteMesures.clientSaisit,
    this.fraisPriseMesuresDomicile,
    required this.delaiAvecRdv,
    required this.delaiSanRdv,
    this.photosRealisations = const [],
  });

  // Prix minimum possible (base + options obligatoires min)
  double get prixMin {
    double total = base.prixBase;
    for (final opt in options.where((o) => o.obligatoire)) {
      total += opt.prixMin;
    }
    return PrixFCFA.arrondirAu50(total);
  }

  // Prix maximum possible (base + toutes options au max)
  double get prixMax {
    double total = base.prixBase;
    for (final opt in options) {
      total += opt.prixMax;
    }
    return PrixFCFA.arrondirAu50(total);
  }

  // Fourchette affichée
  String get fourchettePrix {
    if (prixMin == prixMax) return PrixFCFA.formater(prixMin);
    return '${PrixFCFA.formater(prixMin)} – ${PrixFCFA.formater(prixMax)}';
  }

  // Options gratuites
  List<OptionPersonnalisation> get optionsGratuites =>
      options.where((o) => o.estGratuit).toList();

  // Options payantes
  List<OptionPersonnalisation> get optionsPayantes =>
      options.where((o) => !o.estGratuit).toList();

  Map<String, dynamic> toMap() => {
    ...base.toMap(),
    'options': options.map((o) => o.toMap()).toList(),
    'modeCollecteMesures': modeCollecteMesures.name,
    'fraisPriseMesuresDomicile': fraisPriseMesuresDomicile,
    'delaiAvecRdv': delaiAvecRdv,
    'delaiSanRdv': delaiSanRdv,
    'photosRealisations': photosRealisations,
  };
}

enum ModeCollecteMesures {
  clientSaisit,           // client saisit lui-même dans l'app
  rdvCouturier,           // RDV obligatoire pour mesures
  clientSaisitPuisRdv,    // client saisit + RDV de validation
  couturierDomicile,      // couturier vient prendre les mesures
}

// ─── Personnalisation choisie par le client ───────────────────────────────────

class PersonnalisationChoisie {
  final String optionId;
  final String? choixId;         // si typeValeur = choix
  final bool? valeurBool;        // si typeValeur = oui_non
  final String? valeurTexte;     // si typeValeur = texte_libre
  final int? valeurNombre;       // si typeValeur = nombre
  final String? valeurCouleur;   // si typeValeur = couleur_hex
  final double surplusPrix;      // copie du prix au moment du choix

  const PersonnalisationChoisie({
    required this.optionId,
    this.choixId,
    this.valeurBool,
    this.valeurTexte,
    this.valeurNombre,
    this.valeurCouleur,
    required this.surplusPrix,
  });

  Map<String, dynamic> toMap() => {
    'optionId': optionId,
    'choixId': choixId,
    'valeurBool': valeurBool,
    'valeurTexte': valeurTexte,
    'valeurNombre': valeurNombre,
    'valeurCouleur': valeurCouleur,
    'surplusPrix': surplusPrix,
  };

  factory PersonnalisationChoisie.fromMap(Map<String, dynamic> m) =>
    PersonnalisationChoisie(
      optionId: m['optionId'] as String? ?? '',
      choixId: m['choixId'] as String?,
      valeurBool: m['valeurBool'] as bool?,
      valeurTexte: m['valeurTexte'] as String?,
      valeurNombre: m['valeurNombre'] as int?,
      valeurCouleur: m['valeurCouleur'] as String?,
      surplusPrix: (m['surplusPrix'] as num? ?? 0).toDouble(),
    );
}

// ─── Décomposition financière d'une commande couturier ───────────────────────

class DecompositionCommandeCouturier {
  final double prixBase;
  final double totalOptions;
  final double fraisDeplacement;
  final double prixAvantCommission;
  final double commission;          // commission plateforme
  final double prixFinalClient;
  final double netCouturier;
  final double tauxCommission;
  final AbonnementCouturier abonnement;

  const DecompositionCommandeCouturier({
    required this.prixBase,
    required this.totalOptions,
    required this.fraisDeplacement,
    required this.prixAvantCommission,
    required this.commission,
    required this.prixFinalClient,
    required this.netCouturier,
    required this.tauxCommission,
    required this.abonnement,
  });

  static DecompositionCommandeCouturier calculer({
    required double prixBase,
    required List<PersonnalisationChoisie> personnalisations,
    double fraisDeplacement = 0,
    required AbonnementCouturier abonnement,
  }) {
    final totalOptions = personnalisations.fold<double>(
      0, (sum, p) => sum + p.surplusPrix,
    );
    final prixAvant = PrixFCFA.arrondirAu50(prixBase + totalOptions + fraisDeplacement);
    final taux = abonnement.tauxCommission;
    final commission = PrixFCFA.arrondirAu50(prixAvant * taux / 100);
    final prixFinal = PrixFCFA.arrondirSuperieur50(prixAvant + commission);
    final netCouturier = PrixFCFA.arrondirInferieur50(prixFinal - commission);

    return DecompositionCommandeCouturier(
      prixBase: prixBase,
      totalOptions: totalOptions,
      fraisDeplacement: fraisDeplacement,
      prixAvantCommission: prixAvant,
      commission: commission,
      prixFinalClient: prixFinal,
      netCouturier: netCouturier,
      tauxCommission: taux,
      abonnement: abonnement,
    );
  }

  String get prixFinalFmt => PrixFCFA.formater(prixFinalClient);
  String get netCouturierFmt => PrixFCFA.formater(netCouturier);
  String get commissionFmt => PrixFCFA.formater(commission);

  Map<String, dynamic> toMap() => {
    'prixBase': prixBase,
    'totalOptions': totalOptions,
    'fraisDeplacement': fraisDeplacement,
    'prixAvantCommission': prixAvantCommission,
    'commission': commission,
    'prixFinalClient': prixFinalClient,
    'netCouturier': netCouturier,
    'tauxCommission': tauxCommission,
  };

  @override
  String toString() => '''
┌─────────────────────────────────────────────┐
│  COMMANDE COUTURIER — ${abonnement.nom.padRight(16)} │
├─────────────────────────────────────────────┤
│  Prix de base         : ${PrixFCFA.formater(prixBase).padLeft(14)}  │
│  Options              : ${PrixFCFA.formater(totalOptions).padLeft(14)}  │
│  Frais déplacement    : ${PrixFCFA.formater(fraisDeplacement).padLeft(14)}  │
│  Commission ($tauxCommission%)      : ${commissionFmt.padLeft(14)}  │
├─────────────────────────────────────────────┤
│  PRIX CLIENT          : ${prixFinalFmt.padLeft(14)}  │
│  NET COUTURIER        : ${netCouturierFmt.padLeft(14)}  │
└─────────────────────────────────────────────┘''';
}

// ─── Abonnement couturier (couturier = client de la plateforme) ──────────────

enum TypeAbonnementCouturier {
  gratuit,      // démarrage, commission élevée
  basique,      // petite mensualité, commission réduite
  pro,          // mensualité moyenne, commission basse
  premium,      // mensualité élevée, commission minimale
}

class AbonnementCouturier {
  final TypeAbonnementCouturier type;
  final String nom;
  final double prixMensuel;       // FCFA/mois
  final double tauxCommission;    // % sur chaque commande
  final int limiteModeles;        // nb de modèles publiables
  final bool boostMensuelInclus;  // 1 boost gratuit/mois
  final bool accesStatistiques;   // stats avancées
  final bool supportPrioritaire;
  final bool negociationAutorisee; // devis libre / négociation de prix (avantage payant)
  final List<String> avantages;

  const AbonnementCouturier({
    required this.type,
    required this.nom,
    required this.prixMensuel,
    required this.tauxCommission,
    required this.limiteModeles,
    this.boostMensuelInclus = false,
    this.accesStatistiques = false,
    this.supportPrioritaire = false,
    this.negociationAutorisee = false,
    required this.avantages,
  });

  String get prixMensuelFmt => prixMensuel == 0
      ? 'Gratuit'
      : '${PrixFCFA.formater(prixMensuel)}/mois';

  // Catalogue des abonnements
  static const Map<TypeAbonnementCouturier, AbonnementCouturier> catalogue = {

    TypeAbonnementCouturier.gratuit: AbonnementCouturier(
      type: TypeAbonnementCouturier.gratuit,
      nom: 'Débutant',
      prixMensuel: 0,
      tauxCommission: 12.0,    // commission élevée car pas d'abonnement
      limiteModeles: 3,
      avantages: [
        'Jusqu\'à 3 modèles publiés',
        'Profil couturier visible',
        'Commissions à 12%',
      ],
    ),

    TypeAbonnementCouturier.basique: AbonnementCouturier(
      type: TypeAbonnementCouturier.basique,
      nom: 'Artisan',
      prixMensuel: 2000,
      tauxCommission: 9.0,
      limiteModeles: 10,
      boostMensuelInclus: false,
      accesStatistiques: false,
      avantages: [
        'Jusqu\'à 10 modèles publiés',
        'Commission réduite à 9%',
        'Badge "Artisan vérifié"',
        'Notifications commandes prioritaires',
      ],
    ),

    TypeAbonnementCouturier.pro: AbonnementCouturier(
      type: TypeAbonnementCouturier.pro,
      nom: 'Professionnel',
      prixMensuel: 5000,
      tauxCommission: 7.0,
      limiteModeles: 30,
      boostMensuelInclus: true,
      accesStatistiques: true,
      negociationAutorisee: true,
      avantages: [
        'Jusqu\'à 30 modèles publiés',
        'Commission réduite à 7%',
        '1 boost gratuit par mois',
        'Statistiques de vente détaillées',
        'Mise en avant dans les résultats',
        'Modèles « sur devis » (négociation de prix)',
      ],
    ),

    TypeAbonnementCouturier.premium: AbonnementCouturier(
      type: TypeAbonnementCouturier.premium,
      nom: 'Expert',
      prixMensuel: 12000,
      tauxCommission: 5.0,
      limiteModeles: 999,       // illimité
      boostMensuelInclus: true,
      accesStatistiques: true,
      supportPrioritaire: true,
      negociationAutorisee: true,
      avantages: [
        'Modèles illimités',
        'Commission minimale à 5%',
        '3 boosts gratuits par mois',
        'Support prioritaire',
        'Accès aux tendances et analytics marché',
        'Badge "Expert SAMI"',
      ],
    ),
  };

  static AbonnementCouturier defaut() => catalogue[TypeAbonnementCouturier.gratuit]!;
}

// ─── Profil couturier enrichi ─────────────────────────────────────────────────
// Étend le modèle Couturier existant avec abonnement + stats

class ProfilCouturierPlateforme {
  final String couturierId;
  final TypeAbonnementCouturier typeAbonnement;
  final DateTime? dateAbonnement;
  final DateTime? expireAbonnement;
  final bool abonnementActif;

  // Stats financières (pour dashboard couturier)
  final double gainsTotalMois;
  final double gainsTotal;
  final int commandesMois;
  final int commandesTotal;
  final double commissionPayeeMois;
  final double commissionPayeeTotal;

  // Crédits plateforme
  final double creditBalance;

  ProfilCouturierPlateforme({
    required this.couturierId,
    required this.typeAbonnement,
    this.dateAbonnement,
    this.expireAbonnement,
    required this.abonnementActif,
    this.gainsTotalMois = 0,
    this.gainsTotal = 0,
    this.commandesMois = 0,
    this.commandesTotal = 0,
    this.commissionPayeeMois = 0,
    this.commissionPayeeTotal = 0,
    this.creditBalance = 0,
  });

  AbonnementCouturier get abonnement =>
      AbonnementCouturier.catalogue[typeAbonnement] ??
      AbonnementCouturier.defaut();

  // Revenu net ce mois (après commission plateforme)
  double get revenNetMois => gainsTotalMois - commissionPayeeMois;

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('profils_couturier');

  factory ProfilCouturierPlateforme.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ProfilCouturierPlateforme(
      couturierId: doc.id,
      typeAbonnement: TypeAbonnementCouturier.values.firstWhere((e) => e.name == (
          d['typeAbonnement'] as String? ?? 'gratuit'), orElse: () => TypeAbonnementCouturier.values.first),
      dateAbonnement: (d['dateAbonnement'] as Timestamp?)?.toDate(),
      expireAbonnement: (d['expireAbonnement'] as Timestamp?)?.toDate(),
      abonnementActif: d['abonnementActif'] as bool? ?? true,
      gainsTotalMois: (d['gainsTotalMois'] as num?)?.toDouble() ?? 0,
      gainsTotal: (d['gainsTotal'] as num?)?.toDouble() ?? 0,
      commandesMois: d['commandesMois'] as int? ?? 0,
      commandesTotal: d['commandesTotal'] as int? ?? 0,
      commissionPayeeMois: (d['commissionPayeeMois'] as num?)?.toDouble() ?? 0,
      commissionPayeeTotal: (d['commissionPayeeTotal'] as num?)?.toDouble() ?? 0,
      creditBalance: (d['creditBalance'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'couturierId': couturierId,
    'typeAbonnement': typeAbonnement.name,
    'dateAbonnement': dateAbonnement,
    'expireAbonnement': expireAbonnement,
    'abonnementActif': abonnementActif,
    'gainsTotalMois': gainsTotalMois,
    'gainsTotal': gainsTotal,
    'commandesMois': commandesMois,
    'commandesTotal': commandesTotal,
    'commissionPayeeMois': commissionPayeeMois,
    'commissionPayeeTotal': commissionPayeeTotal,
    'creditBalance': creditBalance,
  };
}

// ─── Service couturier ────────────────────────────────────────────────────────

class CouturierService {

  /// Calcule le prix final d'une commande avec ses personnalisations
  static Future<DecompositionCommandeCouturier> calculerPrix({
    required String couturierId,
    required double prixBase,
    required List<PersonnalisationChoisie> personnalisations,
    double fraisDeplacement = 0,
  }) async {
    final profilDoc = await ProfilCouturierPlateforme.collection
        .doc(couturierId)
        .get();

    final abonnement = profilDoc.exists
        ? ProfilCouturierPlateforme.fromDoc(profilDoc).abonnement
        : AbonnementCouturier.defaut();

    return DecompositionCommandeCouturier.calculer(
      prixBase: prixBase,
      personnalisations: personnalisations,
      fraisDeplacement: fraisDeplacement,
      abonnement: abonnement,
    );
  }

  /// Enregistre une commande couturier et met à jour les stats
  static Future<String> passerCommande({
    required String clientId,
    required String couturierId,
    required ModeleCoutureComplet modele,
    required MesuresClient mesures,
    required List<PersonnalisationChoisie> personnalisations,
    required ModeRencontre modeRencontre,
    required String pagneId,
    required String methodePaiement,
    double fraisDeplacement = 0,
    DateTime? rdvDate,
    String? rdvLieu,
    String? notesClient,
  }) async {
    final decomp = await calculerPrix(
      couturierId: couturierId,
      prixBase: modele.base.prixBase,
      personnalisations: personnalisations,
      fraisDeplacement: fraisDeplacement,
    );

    final ref = FirebaseFirestore.instance
        .collection('commandes_couturier').doc();

    // Sauvegarder les mesures si nouveau profil
    String mesuresId = mesures.id;
    if (mesuresId.isEmpty) {
      final mesuresRef = FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(clientId)
          .collection('mesures')
          .doc();
      await mesuresRef.set({...mesures.toMap(), 'clientId': clientId});
      mesuresId = mesuresRef.id;
    }

    final commande = {
      'id': ref.id,
      'clientId': clientId,
      'couturierId': couturierId,
      'modeleId': modele.base.id,
      'pagneId': pagneId,
      'mesuresClientId': mesuresId,
      'mesuresSnapshot': mesures.valeurs,
      'personnalisations': personnalisations.map((p) => p.toMap()).toList(),
      'modeRencontre': modeRencontre.name,
      'rdvDate': rdvDate,
      'rdvLieu': rdvLieu,
      'fraisDeplacementPaye': fraisDeplacement,
      'prixConvenu': decomp.prixFinalClient,
      'commissionPlateforme': decomp.commission,
      'decompositionFinanciere': decomp.toMap(),
      'methodePaiement': methodePaiement,
      'statut': StatutCommandeCouturier.enAttente.name,
      'dateCommande': FieldValue.serverTimestamp(),
      'dateLivraisonPrevue': rdvDate != null
          ? rdvDate.add(Duration(days: modele.delaiAvecRdv))
          : DateTime.now().add(Duration(days: modele.delaiSanRdv)),
      'notesClient': notesClient,
    };

    await ref.set(commande);

    // Mettre à jour stats couturier
    await ProfilCouturierPlateforme.collection.doc(couturierId).update({
      'commandesMois': FieldValue.increment(1),
      'commandesTotal': FieldValue.increment(1),
    });

    return ref.id;
  }

  /// Souscrit ou change l'abonnement d'un couturier
  static Future<void> changerAbonnement({
    required String couturierId,
    required TypeAbonnementCouturier nouvelAbonnement,
    required String methodePaiement,
  }) async {
    final abonnement = AbonnementCouturier.catalogue[nouvelAbonnement]!;
    final now = DateTime.now();
    final expiration = DateTime(now.year, now.month + 1, now.day);

    final batch = FirebaseFirestore.instance.batch();

    // Mettre à jour le profil couturier
    batch.update(
      ProfilCouturierPlateforme.collection.doc(couturierId),
      {
        'typeAbonnement': nouvelAbonnement.name,
        'dateAbonnement': now,
        'expireAbonnement': expiration,
        'abonnementActif': true,
      },
    );

    // Enregistrer la transaction d'abonnement
    if (abonnement.prixMensuel > 0) {
      final txRef = FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(txRef, {
        'type': 'abonnementCouturier',
        'couturierId': couturierId,
        'montantBrut': abonnement.prixMensuel,
        'montantNet': abonnement.prixMensuel,
        'methodePaiement': methodePaiement,
        'description': 'Abonnement ${abonnement.nom} — ${now.month}/${now.year}',
        'dateCreation': now,
        'statut': 'confirmee',
      });
    }

    await batch.commit();
  }

  /// Options prédéfinies suggérées pour un type de vêtement
  static List<OptionPersonnalisation> optionsSuggerees(TypeVetement type) {
    final optionsBase = [
      OptionPersonnalisation(
        id: 'couleurFil',
        type: TypeOption.couleurFil,
        labels: {Langue.fr: 'Couleur du fil', Langue.en: 'Thread color', Langue.ff: 'Rangi filo'},
        descriptions: {Langue.fr: 'Couleur du fil principal de couture', Langue.en: 'Main thread color', Langue.ff: ''},
        typeValeur: TypeValeurOption.choix,
        estGratuit: true,   // gratuit par défaut
        choix: [
          ChoixOption(id: 'blanc', labels: {Langue.fr: 'Blanc', Langue.en: 'White', Langue.ff: 'Ranowu'}, surplusPrix: 0),
          ChoixOption(id: 'noir', labels: {Langue.fr: 'Noir', Langue.en: 'Black', Langue.ff: 'Baali'}, surplusPrix: 0),
          ChoixOption(id: 'assorti', labels: {Langue.fr: 'Assorti au tissu', Langue.en: 'Matching', Langue.ff: 'Ko welitii'}, surplusPrix: 0),
          ChoixOption(id: 'contraste', labels: {Langue.fr: 'Contraste (or/argent)', Langue.en: 'Contrast gold/silver', Langue.ff: 'Rangi wuro'}, surplusPrix: 500),
        ],
        obligatoire: true,
      ),
    ];

    switch (type) {
      case TypeVetement.boubou:
      case TypeVetement.gandoura:
        return [
          ...optionsBase,
          OptionPersonnalisation(
            id: 'broderieFulani',
            type: TypeOption.styleBroderieNord,
            labels: {Langue.fr: 'Broderie traditionnelle', Langue.en: 'Traditional embroidery', Langue.ff: 'Laral Fulɓe'},
            descriptions: {Langue.fr: 'Motifs fulani, haoussa ou arabesques', Langue.en: 'Fulani, Hausa or arabesque patterns', Langue.ff: 'Nakuuji Fulɓe'},
            typeValeur: TypeValeurOption.choix,
            estGratuit: false,
            choix: [
              ChoixOption(id: 'aucune', labels: {Langue.fr: 'Sans broderie', Langue.en: 'No embroidery', Langue.ff: 'Alaa laral'}, surplusPrix: 0),
              ChoixOption(id: 'col', labels: {Langue.fr: 'Col uniquement', Langue.en: 'Collar only', Langue.ff: 'Ko koyngal tan'}, surplusPrix: 2000),
              ChoixOption(id: 'col_manche', labels: {Langue.fr: 'Col + manches', Langue.en: 'Collar + sleeves', Langue.ff: 'Koyngal + daɓɓe'}, surplusPrix: 4000),
              ChoixOption(id: 'complet', labels: {Langue.fr: 'Broderie complète', Langue.en: 'Full embroidery', Langue.ff: 'Laral fof'}, surplusPrix: 8000),
            ],
            obligatoire: false,
          ),
          OptionPersonnalisation(
            id: 'manchesGandoura',
            type: TypeOption.manchesGandoura,
            labels: {Langue.fr: 'Type de manches', Langue.en: 'Sleeve type', Langue.ff: 'Daɓɓe moy'},
            descriptions: {Langue.fr: 'Style des manches du boubou/gandoura', Langue.en: 'Boubou/gandoura sleeve style', Langue.ff: ''},
            typeValeur: TypeValeurOption.choix,
            estGratuit: true,
            choix: [
              ChoixOption(id: 'courte', labels: {Langue.fr: 'Courte', Langue.en: 'Short', Langue.ff: 'Poke'}, surplusPrix: 0),
              ChoixOption(id: 'longue', labels: {Langue.fr: 'Longue', Langue.en: 'Long', Langue.ff: 'Juutde'}, surplusPrix: 0),
              ChoixOption(id: 'pagode', labels: {Langue.fr: 'Pagode (évasée)', Langue.en: 'Pagoda (flared)', Langue.ff: 'Feeɓunde'}, surplusPrix: 1000),
              ChoixOption(id: 'sans', labels: {Langue.fr: 'Sans manches', Langue.en: 'Sleeveless', Langue.ff: 'Alaa daɓɓe'}, surplusPrix: 0),
            ],
            obligatoire: true,
          ),
        ];

      case TypeVetement.robe:
        return [
          ...optionsBase,
          OptionPersonnalisation(
            id: 'typeCol',
            type: TypeOption.typeCol,
            labels: {Langue.fr: 'Type de col', Langue.en: 'Neckline type', Langue.ff: 'Koyngal moy'},
            descriptions: {Langue.fr: 'Forme de l\'encolure', Langue.en: 'Neckline shape', Langue.ff: ''},
            typeValeur: TypeValeurOption.choix,
            estGratuit: true,
            choix: [
              ChoixOption(id: 'rond', labels: {Langue.fr: 'Col rond', Langue.en: 'Round neck', Langue.ff: 'Welngo'}, surplusPrix: 0),
              ChoixOption(id: 'v', labels: {Langue.fr: 'Col en V', Langue.en: 'V-neck', Langue.ff: 'Ko V'}, surplusPrix: 0),
              ChoixOption(id: 'carre', labels: {Langue.fr: 'Col carré', Langue.en: 'Square neck', Langue.ff: 'Ko tofe'}, surplusPrix: 500),
              ChoixOption(id: 'bateau', labels: {Langue.fr: 'Col bateau', Langue.en: 'Boat neck', Langue.ff: 'Ko laana'}, surplusPrix: 500),
              ChoixOption(id: 'mao', labels: {Langue.fr: 'Col mao', Langue.en: 'Mandarin collar', Langue.ff: 'Ko mao'}, surplusPrix: 1000),
            ],
            obligatoire: true,
          ),
          OptionPersonnalisation(
            id: 'dentelle',
            type: TypeOption.dentelle,
            labels: {Langue.fr: 'Dentelle', Langue.en: 'Lace', Langue.ff: 'Dentele'},
            descriptions: {Langue.fr: 'Ajout de dentelle sur le bord de la robe', Langue.en: 'Lace trim on dress edge', Langue.ff: ''},
            typeValeur: TypeValeurOption.choix,
            estGratuit: false,
            choix: [
              ChoixOption(id: 'non', labels: {Langue.fr: 'Sans dentelle', Langue.en: 'No lace', Langue.ff: 'Alaa dentele'}, surplusPrix: 0),
              ChoixOption(id: 'bas', labels: {Langue.fr: 'Bas de robe uniquement', Langue.en: 'Bottom edge only', Langue.ff: 'Dow tan'}, surplusPrix: 1500),
              ChoixOption(id: 'complet', labels: {Langue.fr: 'Contour complet', Langue.en: 'Full edge', Langue.ff: 'Boo fof'}, surplusPrix: 3000),
            ],
            obligatoire: false,
          ),
        ];

      default:
        return [
          ...optionsBase,
          OptionPersonnalisation(
            id: 'poches',
            type: TypeOption.poches,
            labels: {Langue.fr: 'Poches', Langue.en: 'Pockets', Langue.ff: 'Paketeeji'},
            descriptions: {Langue.fr: 'Ajouter des poches', Langue.en: 'Add pockets', Langue.ff: ''},
            typeValeur: TypeValeurOption.oui_non,
            estGratuit: false,
            prixFixe: 1000,
            obligatoire: false,
          ),
          OptionPersonnalisation(
            id: 'marquageNom',
            type: TypeOption.marquageNom,
            labels: {Langue.fr: 'Nom brodé', Langue.en: 'Embroidered name', Langue.ff: 'Innde laral'},
            descriptions: {Langue.fr: 'Votre prénom brodé discrètement', Langue.en: 'Your first name discreetly embroidered', Langue.ff: ''},
            typeValeur: TypeValeurOption.texte_libre,
            estGratuit: false,
            prixFixe: 1500,
            obligatoire: false,
          ),
        ];
    }
  }
}
