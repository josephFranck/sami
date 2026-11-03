import 'package:sami/utils/prix_fcfa.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/config_marketing_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STRATÉGIES COMMERCIALES — SAMI ECOSYSTEM
// Deux cibles : Acheteurs (clients) et Boutiquiers
// ═══════════════════════════════════════════════════════════════════════════

// ─── 1. FIDÉLITÉ ACHETEUR (Gamification) ────────────────────────────────────
// Basé sur le champ `niveau` existant dans Utilisateur

class NiveauFidelite {
  final int niveau;
  final String nom;
  final String emoji;
  final int pointsRequis;
  final double tauxReductionLivraison; // % de réduction sur livraison
  final bool accesVentesFlash;         // accès anticipé aux ventes flash
  final double tauxCashback;           // % cashback en crédits

  const NiveauFidelite({
    required this.niveau,
    required this.nom,
    required this.emoji,
    required this.pointsRequis,
    required this.tauxReductionLivraison,
    required this.accesVentesFlash,
    required this.tauxCashback,
  });

  // Paliers adaptés au marché de Garoua
  static const List<NiveauFidelite> paliers = [
    NiveauFidelite(
      niveau: 1, nom: 'Découvreur', emoji: '🌱',
      pointsRequis: 0,
      tauxReductionLivraison: 0,
      accesVentesFlash: false,
      tauxCashback: 0,
    ),
    NiveauFidelite(
      niveau: 2, nom: 'Habitué', emoji: '⭐',
      pointsRequis: 500,
      tauxReductionLivraison: 10,
      accesVentesFlash: false,
      tauxCashback: 1,
    ),
    NiveauFidelite(
      niveau: 3, nom: 'Connaisseur', emoji: '🏆',
      pointsRequis: 2000,
      tauxReductionLivraison: 25,
      accesVentesFlash: true,
      tauxCashback: 2,
    ),
    NiveauFidelite(
      niveau: 4, nom: 'Expert', emoji: '💎',
      pointsRequis: 5000,
      tauxReductionLivraison: 50,
      accesVentesFlash: true,
      tauxCashback: 3,
    ),
    NiveauFidelite(
      niveau: 5, nom: 'Ambassadeur', emoji: '👑',
      pointsRequis: 15000,
      tauxReductionLivraison: 100, // livraison gratuite
      accesVentesFlash: true,
      tauxCashback: 5,
    ),
  ];

  static NiveauFidelite fromPoints(int points) {
    return paliers.lastWhere((p) => points >= p.pointsRequis);
  }

  // Points gagnés par achat
  static int pointsGagnes(double montantAchat) {
    // 1 point par 100 FCFA dépensés
    return (montantAchat / 100).floor();
  }
}

// ─── 2. PARRAINAGE (Referral) ────────────────────────────────────────────────

class Parrainage {
  final String id;
  final String parrainId;         // utilisateur qui parraine
  final String? filleulId;        // nouvel utilisateur parrainé
  final String codeParrainage;    // code unique du parrain
  final StatutParrainage statut;
  final double recompenseParrain; // FCFA crédités au parrain
  final double recompenseFilleul; // FCFA crédités au filleul
  final DateTime dateCreation;
  final DateTime? dateActivation;

  Parrainage({
    required this.id,
    required this.parrainId,
    this.filleulId,
    required this.codeParrainage,
    this.statut = StatutParrainage.enAttente,
    this.recompenseParrain = 1000, // 1000 FCFA au parrain
    this.recompenseFilleul = 500,  // 500 FCFA au filleul
    required this.dateCreation,
    this.dateActivation,
  });

  // Générer un code unique lisible (ex: SAMI-MOUSSA-47)
  static String genererCode(String nomUtilisateur) {
    final suffix = DateTime.now().millisecondsSinceEpoch % 100;
    final nom = nomUtilisateur.toUpperCase().replaceAll(' ', '-');
    return 'SAMI-$nom-$suffix';
  }

  Map<String, dynamic> toMap() => {
    'parrainId': parrainId,
    'filleulId': filleulId,
    'codeParrainage': codeParrainage,
    'statut': statut.name,
    'recompenseParrain': recompenseParrain,
    'recompenseFilleul': recompenseFilleul,
    'dateCreation': dateCreation,
    'dateActivation': dateActivation,
  };
}

enum StatutParrainage { enAttente, active, recompense, expire }

// ─── 3. VENTES FLASH & URGENCE ───────────────────────────────────────────────

class VenteFlash {
  final String id;
  final String pagneId;
  final String boutiqueId;
  final double prixOriginal;
  final double prixFlash;
  final double reductionPct;       // calculé automatiquement
  final int stockDisponible;
  int stockRestant;
  final DateTime debutVente;
  final DateTime finVente;
  final bool reserveAmbassadeurs;  // accès anticipé niveau 5
  final DateTime? debutAmbassadeurs;

  VenteFlash({
    required this.id,
    required this.pagneId,
    required this.boutiqueId,
    required this.prixOriginal,
    required this.prixFlash,
    required this.stockDisponible,
    required this.stockRestant,
    required this.debutVente,
    required this.finVente,
    this.reserveAmbassadeurs = false,
    this.debutAmbassadeurs,
  }) : reductionPct = ((prixOriginal - prixFlash) / prixOriginal * 100);

  bool get estActive {
    final now = DateTime.now();
    return now.isAfter(debutVente) && now.isBefore(finVente) && stockRestant > 0;
  }

  Duration get tempsRestant => finVente.difference(DateTime.now());

  // Urgence psychologique
  String get messageUrgence {
    if (stockRestant <= 3) return 'Plus que $stockRestant disponible !';
    if (tempsRestant.inHours < 2) {
      return 'Expire dans ${tempsRestant.inMinutes} min !';
    }
    if (tempsRestant.inHours < 6) {
      return 'Expire dans ${tempsRestant.inHours}h !';
    }
    return '${reductionPct.round()}% de réduction';
  }

  Map<String, dynamic> toMap() => {
    'pagneId': pagneId,
    'boutiqueId': boutiqueId,
    'prixOriginal': prixOriginal,
    'prixFlash': prixFlash,
    'reductionPct': reductionPct,
    'stockDisponible': stockDisponible,
    'stockRestant': stockRestant,
    'debutVente': debutVente,
    'finVente': finVente,
    'reserveAmbassadeurs': reserveAmbassadeurs,
    'debutAmbassadeurs': debutAmbassadeurs,
  };
}

// ─── 4. PSYCHOLOGIE DES PRIX (côté boutiquier) ──────────────────────────────

class StrategiesPrix {

  /// Prix psychologique — délégué à PrixFCFA (pas de 50 FCFA)
  /// Ex: 10 000 → 9 950 | 5 000 → 4 950
  static double appliquerPrixCharm(double prix) =>
      PrixFCFA.prixCharm(prix);

  /// Prix ancré : affiche l'ancien prix barré (multiple de 50)
  static Map<String, double> prixAvecAncrage({
    required double prixActuel,
    double tauxReductionAffichee = 20,
  }) {
    final prixBarre = PrixFCFA.arrondirSuperieur50(
      prixActuel / (1 - tauxReductionAffichee / 100),
    );
    final economie = PrixFCFA.arrondirAu50(prixBarre - prixActuel);
    return {
      'prixActuel': prixActuel,
      'prixBarre': prixBarre,
      'economie': economie,
      'reductionPct': tauxReductionAffichee,
    };
  }

  /// Suggestions de prix pour le formulaire boutiquier
  static List<SuggestionPrix> genererSuggestions(double coutAchat) {
    // Bénéfices arrondis au pas de 50 FCFA
    return [
      SuggestionPrix(
        label: 'Marge faible (10%)',
        emoji: '🌱',
        benefice: PrixFCFA.arrondirAu50(coutAchat * 0.10),
        description: 'Idéal pour attirer de nouveaux clients',
      ),
      SuggestionPrix(
        label: 'Marge standard (25%)',
        emoji: '⭐',
        benefice: PrixFCFA.arrondirAu50(coutAchat * 0.25),
        description: 'Équilibre volume / rentabilité',
      ),
      SuggestionPrix(
        label: 'Marge premium (50%)',
        emoji: '💎',
        benefice: PrixFCFA.arrondirAu50(coutAchat * 0.50),
        description: 'Pour les pagnes exclusifs ou rares',
      ),
      SuggestionPrix(
        label: 'Marge gros (5%)',
        emoji: '📦',
        benefice: PrixFCFA.arrondirAu50(coutAchat * 0.05),
        description: 'Vente en grande quantité',
      ),
    ];
  }
}

class SuggestionPrix {
  final String label;
  final String emoji;
  final double benefice;
  final String description;
  const SuggestionPrix({
    required this.label,
    required this.emoji,
    required this.benefice,
    required this.description,
  });
}

// ─── 5. VISIBILITÉ PREMIUM (côté boutiquier) ────────────────────────────────

enum TypeBoost {
  standard,   // apparaît normalement
  booste,     // mis en avant 48h — 1 000 FCFA
  featured,   // bandeau "Boutique vedette" — 5 000 FCFA/semaine
  topSearch,  // premier dans les recherches — 2 000 FCFA/48h
}

class BoostVisibilite {
  final String id;
  final String boutiqueId;
  final String? pagneId;       // null = boost boutique entière
  final TypeBoost type;
  final double coutCredits;
  final DateTime debut;
  final DateTime fin;
  final bool estActif;

  BoostVisibilite({
    required this.id,
    required this.boutiqueId,
    this.pagneId,
    required this.type,
    required this.coutCredits,
    required this.debut,
    required this.fin,
    this.estActif = true,
  });

  static const Map<TypeBoost, double> tarifs = {
    TypeBoost.standard: 0,
    TypeBoost.booste: 1000,
    TypeBoost.featured: 5000,
    TypeBoost.topSearch: 2000,
  };

  static const Map<TypeBoost, Duration> durees = {
    TypeBoost.booste: Duration(hours: 48),
    TypeBoost.featured: Duration(days: 7),
    TypeBoost.topSearch: Duration(hours: 48),
  };

  Map<String, dynamic> toMap() => {
    'boutiqueId': boutiqueId,
    'pagneId': pagneId,
    'type': type.name,
    'coutCredits': coutCredits,
    'debut': debut,
    'fin': fin,
    'estActif': estActif,
  };
}

// ─── 6. PROMOTIONS SAISONNIÈRES ──────────────────────────────────────────────

class EventSaisonnier {
  final String nom;
  final String emoji;
  final DateTime dateDebut;
  final DateTime dateFin;
  final double reductionSuggeree; // % de réduction suggérée
  final String messageMarketing;

  const EventSaisonnier({
    required this.nom,
    required this.emoji,
    required this.dateDebut,
    required this.dateFin,
    required this.reductionSuggeree,
    required this.messageMarketing,
  });

  // Calendrier des événements clés pour Garoua
  static List<EventSaisonnier> evenementsAnnee(int annee) => [
    EventSaisonnier(
      nom: 'Tabaski',
      emoji: '🐑',
      // Date approximative (varie selon le calendrier islamique)
      dateDebut: DateTime(annee, 6, 10),
      dateFin: DateTime(annee, 6, 17),
      reductionSuggeree: 15,
      messageMarketing: 'Préparez vos plus beaux boubous pour la Tabaski !',
    ),
    EventSaisonnier(
      nom: 'Ramadan',
      emoji: '🌙',
      dateDebut: DateTime(annee, 3, 1),
      dateFin: DateTime(annee, 3, 31),
      reductionSuggeree: 10,
      messageMarketing: 'Offrez de beaux pagnes pour la fin du Ramadan',
    ),
    EventSaisonnier(
      nom: 'Saison des mariages',
      emoji: '💒',
      dateDebut: DateTime(annee, 11, 1),
      dateFin: DateTime(annee, 12, 31),
      reductionSuggeree: 20,
      messageMarketing: 'La saison des mariages arrive — habilllez vos invités !',
    ),
    EventSaisonnier(
      nom: 'Fête nationale',
      emoji: '🇨🇲',
      dateDebut: DateTime(annee, 5, 18),
      dateFin: DateTime(annee, 5, 22),
      reductionSuggeree: 10,
      messageMarketing: 'Célébrez le Cameroun avec style',
    ),
    EventSaisonnier(
      nom: 'Rentrée scolaire',
      emoji: '🎒',
      dateDebut: DateTime(annee, 8, 25),
      dateFin: DateTime(annee, 9, 10),
      reductionSuggeree: 8,
      messageMarketing: 'Tenues de rentrée pour toute la famille',
    ),
  ];

  // Événement en cours ou prochain (depuis le calendrier codé en dur)
  static EventSaisonnier? evenementProchain(int annee) {
    return _choisirProchain(evenementsAnnee(annee));
  }

  // Sélectionne l'événement en cours, ou le prochain dans les 21 jours
  static EventSaisonnier? _choisirProchain(List<EventSaisonnier> events) {
    final now = DateTime.now();
    for (final e in events) {
      if (now.isAfter(e.dateDebut) && now.isBefore(e.dateFin)) return e;
    }
    for (final e in events) {
      if (e.dateDebut.difference(now).inDays <= 21 && e.dateDebut.isAfter(now)) {
        return e;
      }
    }
    return null;
  }

  factory EventSaisonnier.fromMap(Map<String, dynamic> m) => EventSaisonnier(
    nom: m['nom'] as String? ?? '',
    emoji: m['emoji'] as String? ?? '🎉',
    dateDebut: (m['dateDebut'] as Timestamp?)?.toDate() ?? DateTime.now(),
    dateFin: (m['dateFin'] as Timestamp?)?.toDate() ??
        DateTime.now().add(const Duration(days: 7)),
    reductionSuggeree: (m['reductionSuggeree'] as num?)?.toDouble() ?? 0,
    messageMarketing: m['messageMarketing'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'nom': nom,
    'emoji': emoji,
    'dateDebut': Timestamp.fromDate(dateDebut),
    'dateFin': Timestamp.fromDate(dateFin),
    'reductionSuggeree': reductionSuggeree,
    'messageMarketing': messageMarketing,
    'actif': true,
  };

  /// Événement prochain depuis Firestore (collection 'evenements', éditable par l'admin).
  /// Les dates religieuses (Tabaski, Ramadan) suivent le calendrier islamique et
  /// DOIVENT être saisies chaque année par l'admin — d'où le stockage en base.
  /// Fallback sur le calendrier codé en dur si la collection est vide ou en erreur.
  /// TOUS les événements actifs (pour le carrousel d'accueil).
  static Future<List<EventSaisonnier>> evenementsActifsFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('evenements')
          .where('actif', isEqualTo: true)
          .get();
      return snap.docs
          .map((d) => EventSaisonnier.fromMap(d.data()))
          .toList();
    } catch (_) {
      final un = evenementProchain(DateTime.now().year);
      return un == null ? [] : [un];
    }
  }

  static Future<EventSaisonnier?> evenementProchainFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('evenements')
          .where('actif', isEqualTo: true)
          .get();
      if (snap.docs.isNotEmpty) {
        final events = snap.docs
            .map((d) => EventSaisonnier.fromMap(d.data()))
            .toList();
        return _choisirProchain(events);
      }
    } catch (_) {
      // silencieux → fallback ci-dessous
    }
    // Fallback : calendrier codé en dur (dates approximatives)
    return evenementProchain(DateTime.now().year);
  }
}

// ─── 7. FIDÉLITÉ BOUTIQUIER B2B (paliers commission) ────────────────────────

class PalierBoutiquier {
  final String nom;
  final int ventesMinMois;
  final double tauxCommission;  // % commission prélevée
  final List<String> avantages;

  const PalierBoutiquier({
    required this.nom,
    required this.ventesMinMois,
    required this.tauxCommission,
    required this.avantages,
  });

  static const List<PalierBoutiquier> paliers = [
    PalierBoutiquier(
      nom: 'Débutant',
      ventesMinMois: 0,
      tauxCommission: 6.0,
      avantages: ['Accès basique plateforme'],
    ),
    PalierBoutiquier(
      nom: 'Partenaire',
      ventesMinMois: 20,
      tauxCommission: 5.5,
      avantages: [
        'Commission réduite à 5.5%',
        'Badge "Partenaire vérifié"',
      ],
    ),
    PalierBoutiquier(
      nom: 'Premium',
      ventesMinMois: 50,
      tauxCommission: 5.0,
      avantages: [
        'Commission réduite à 5%',
        '1 boost gratuit/mois',
        'Accès aux statistiques avancées',
      ],
    ),
    PalierBoutiquier(
      nom: 'Élite',
      ventesMinMois: 150,
      tauxCommission: 4.0,
      avantages: [
        'Commission réduite à 4%',
        '3 boosts gratuits/mois',
        'Support prioritaire',
        'Accès promotions saisonnières automatiques',
      ],
    ),
  ];

  static PalierBoutiquier fromVentes(int ventesMois) {
    return paliers.lastWhere((p) => ventesMois >= p.ventesMinMois);
  }
}

// ─── 8. BUNDLING (Pagne + Couture) ───────────────────────────────────────────

class OffreGroupee {
  final String id;
  final String pagneId;
  final String couturierId;
  final double prixPagne;
  final double prixCouture;
  final double prixBundle;        // inférieur à la somme
  final double economie;          // = prixPagne + prixCouture - prixBundle
  final String descriptionBundle;
  final bool estActif;

  OffreGroupee({
    required this.id,
    required this.pagneId,
    required this.couturierId,
    required this.prixPagne,
    required this.prixCouture,
    double? prixBundle,
    required this.descriptionBundle,
    this.estActif = true,
  })  : prixBundle = prixBundle ?? (prixPagne + prixCouture) * 0.90,
        economie = (prixPagne + prixCouture) -
            (prixBundle ?? (prixPagne + prixCouture) * 0.90);

  Map<String, dynamic> toMap() => {
    'pagneId': pagneId,
    'couturierId': couturierId,
    'prixPagne': prixPagne,
    'prixCouture': prixCouture,
    'prixBundle': prixBundle,
    'economie': economie,
    'descriptionBundle': descriptionBundle,
    'estActif': estActif,
  };
}

// ─── 9. STORYTELLING (contenu boutiquier) ────────────────────────────────────

class StoryPagne {
  final String pagneId;
  final String? histoireTissu;       // origine, fabrication
  final String? nomArtisan;          // nom du tisserand/créateur
  final String? villageOrigine;      // village de production
  final String? techniqueProduction; // ex: "Tissage main Fulani"
  final List<String> photosProduction; // photos du processus
  final String? anecdote;            // petite histoire attachante

  StoryPagne({
    required this.pagneId,
    this.histoireTissu,
    this.nomArtisan,
    this.villageOrigine,
    this.techniqueProduction,
    this.photosProduction = const [],
    this.anecdote,
  });

  // Score de complétude du storytelling (0-100)
  int get scoreCompletude {
    int score = 0;
    if (histoireTissu != null && histoireTissu!.isNotEmpty) score += 25;
    if (nomArtisan != null) score += 20;
    if (villageOrigine != null) score += 15;
    if (techniqueProduction != null) score += 15;
    if (photosProduction.isNotEmpty) score += 15;
    if (anecdote != null) score += 10;
    return score;
  }

  // Impact sur le prix justifié
  double get majoPrixJustifiee {
    // Un storytelling complet permet d'augmenter le prix de 15%
    return scoreCompletude / 100 * 15;
  }

  Map<String, dynamic> toMap() => {
    'pagneId': pagneId,
    'histoireTissu': histoireTissu,
    'nomArtisan': nomArtisan,
    'villageOrigine': villageOrigine,
    'techniqueProduction': techniqueProduction,
    'photosProduction': photosProduction,
    'anecdote': anecdote,
    'scoreCompletude': scoreCompletude,
  };
}

// ─── 10. PRIX DYNAMIQUE (Agent IA) ──────────────────────────────────────────

class SuggestionPrixDynamique {
  final String pagneId;
  final String boutiqueId;
  final double prixActuel;
  final double prixSuggere;
  final String raison;
  final double confianceScore; // 0-1
  final TypeAjustement typeAjustement;
  final DateTime dateAnalyse;

  SuggestionPrixDynamique({
    required this.pagneId,
    required this.boutiqueId,
    required this.prixActuel,
    required this.prixSuggere,
    required this.raison,
    required this.confianceScore,
    required this.typeAjustement,
    required this.dateAnalyse,
  });

  double get variationPct =>
      (prixSuggere - prixActuel) / prixActuel * 100;

  Map<String, dynamic> toMap() => {
    'pagneId': pagneId,
    'boutiqueId': boutiqueId,
    'prixActuel': prixActuel,
    'prixSuggere': prixSuggere,
    'raison': raison,
    'confianceScore': confianceScore,
    'typeAjustement': typeAjustement.name,
    'dateAnalyse': dateAnalyse,
  };
}

enum TypeAjustement {
  hausse,         // demande forte → monter le prix
  baisse,         // stock élevé → baisser pour écouler
  promotionEvent, // Tabaski, mariage → promo temporaire
  concurrence,    // aligner sur les prix du marché
  urgenceStock,   // rupture proche → monter légèrement
}

// ─── SERVICE ORCHESTRATEUR DES STRATÉGIES ───────────────────────────────────

class StrategiesMarketingService {

  /// Calcule et enregistre les points + cashback gagnés après un achat.
  /// Lit les taux depuis la CONFIG ADMIN (collection config_marketing),
  /// avec fallback sur les valeurs par défaut.
  static Future<void> crediterPointsFidelite({
    required String utilisateurId,
    required double montantAchat,
  }) async {
    // Charger la config admin (taux points + paliers/cashback)
    final config = await ConfigMarketingService.charger();
    final fcfaParPoint = config.fcfaParPoint > 0 ? config.fcfaParPoint : 100;
    final points = (montantAchat / fcfaParPoint).floor();

    final ref = FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(utilisateurId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final pointsActuels = doc['pointsFidelite'] as int? ?? 0;
      final nouveauxPoints = pointsActuels + points;

      // Déterminer le palier atteint selon la config admin
      PalierConfig palierAtteint = config.paliers.first;
      for (final p in config.paliers) {
        if (nouveauxPoints >= p.pointsRequis) palierAtteint = p;
      }
      final niveauIndex = config.paliers.indexOf(palierAtteint) + 1;

      // Cashback : % du montant d'achat crédité selon le palier
      final cashback = montantAchat * palierAtteint.cashback / 100;
      final creditActuel = (doc['creditBalance'] as num?)?.toDouble() ?? 0;

      tx.update(ref, {
        'pointsFidelite': nouveauxPoints,
        'niveau': niveauIndex,
        'creditBalance': creditActuel + cashback,
      });
    });
  }

  /// Valide et applique un code de parrainage
  static Future<bool> appliquerCodeParrainage({
    required String filleulId,
    required String codeParrainage,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('parrainages')
        .where('codeParrainage', isEqualTo: codeParrainage)
        .where('statut', isEqualTo: StatutParrainage.enAttente.name)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return false;
    final doc = snap.docs.first;
    final parrainId = doc['parrainId'] as String? ?? '';

    final batch = FirebaseFirestore.instance.batch();

    // Activer le parrainage
    batch.update(doc.reference, {
      'filleulId': filleulId,
      'statut': StatutParrainage.recompense.name,
      'dateActivation': DateTime.now(),
    });

    // Créditer le parrain
    batch.update(
      FirebaseFirestore.instance.collection('utilisateurs').doc(parrainId),
      {'creditBalance': FieldValue.increment(1000)},
    );

    // Créditer le filleul
    batch.update(
      FirebaseFirestore.instance.collection('utilisateurs').doc(filleulId),
      {'creditBalance': FieldValue.increment(500)},
    );

    await batch.commit();
    return true;
  }

  /// Alerte saisonnière envoyée par l'agent aux boutiquiers
  static Future<void> envoyerAlertesSaisonnieres() async {
    final prochain = EventSaisonnier.evenementProchain(DateTime.now().year);
    if (prochain == null) return;

    final jours = prochain.dateDebut.difference(DateTime.now()).inDays;
    if (jours > 21 || jours < 0) return;

    final boutiques = await FirebaseFirestore.instance
        .collection('boutiques')
        .where('estActif', isEqualTo: true)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final b in boutiques.docs) {
      final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
      batch.set(notifRef, {
        'destinataireId': b.id,
        'type': 'alerte_saisonniere',
        'titre': '${prochain.emoji} ${prochain.nom} dans $jours jours !',
        'message': prochain.messageMarketing,
        'reductionSuggeree': prochain.reductionSuggeree,
        'actionSuggere': 'Créer une promotion',
        'lu': false,
        'dateCreation': DateTime.now(),
      });
    }
    await batch.commit();
  }

  /// Calcule le palier boutiquier selon ses ventes du mois
  static Future<PalierBoutiquier> calculerPalierBoutiquier(
      String boutiqueId) async {
    final debut = DateTime.now().subtract(const Duration(days: 30));
    final snap = await FirebaseFirestore.instance
        .collection('sous_commandes')
        .where('boutiqueId', isEqualTo: boutiqueId)
        .where('dateCreation', isGreaterThan: debut)
        .where('statut', isEqualTo: 'livree')
        .get();

    final ventesMois = snap.docs.length;
    return PalierBoutiquier.fromVentes(ventesMois);
  }
}
