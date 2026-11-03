import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GESTION DES RETOURS — SAMI ECOSYSTEM
// Initiateurs : Client, Boutiquier, Agent IA
// 4 motifs : changement avis, mauvaise taille, défectueux, retard
// ═══════════════════════════════════════════════════════════════════════════

enum MotifRetour {
  changementAvis,       // Client a changé d'avis
  mauvaiseTaille,       // Mauvaise taille livrée
  pagneDefectueux,      // Pagne défectueux / non conforme
  retardLivraison,      // Retard trop long
}

enum InitiateurRetour {
  client,
  boutiquier,
  agentIA,       // détection automatique (ex: retard >2h)
  superviseur,   // admin humain
}

enum StatutRetour {
  soumis,            // retour initié
  enExamen,          // superviseur ou agent examine
  accepte,           // retour accepté → remboursement déclenché
  rejete,            // retour refusé avec justification
  enCoursDRetour,    // article en transit retour
  articleRecu,       // boutique a reçu l'article retourné
  rembourse,         // remboursement effectué
  clos,              // dossier fermé
}

enum TypeRemboursement {
  creditsPlateforme,   // crédits sur compte SAMI (instantané)
  mobileMoney,         // Orange Money / MTN (2-3 jours)
  echange,             // échange contre autre pagne
  avoirBoutique,       // bon d'achat boutique
  aucun,               // retour refusé
}

// ─── Règles métier par motif ─────────────────────────────────────────────────

class RegleRetour {
  final MotifRetour motif;
  final int delaiMaxHeures;          // délai max pour initier le retour
  final bool retourArticleRequis;    // doit renvoyer le pagne ?
  final TypeRemboursement remboursementParDefaut;
  final double pctRembourseClient;   // % remboursé au client
  final double pctRetenuBoutique;    // % retenu à la boutique (pénalité)
  final double pctRetenuLivreur;     // % retenu au livreur si sa faute
  final bool fraisLivraisonRembourses;
  final String description;

  const RegleRetour({
    required this.motif,
    required this.delaiMaxHeures,
    required this.retourArticleRequis,
    required this.remboursementParDefaut,
    required this.pctRembourseClient,
    required this.pctRetenuBoutique,
    required this.pctRetenuLivreur,
    required this.fraisLivraisonRembourses,
    required this.description,
  });

  // Règles par défaut — modifiables par l'admin dans la config
  static const Map<MotifRetour, RegleRetour> reglesDefaut = {

    MotifRetour.changementAvis: RegleRetour(
      motif: MotifRetour.changementAvis,
      delaiMaxHeures: 2,            // 2h après livraison max
      retourArticleRequis: true,    // doit renvoyer le pagne intact
      remboursementParDefaut: TypeRemboursement.creditsPlateforme,
      pctRembourseClient: 80,       // 80% remboursé (20% frais de gestion)
      pctRetenuBoutique: 0,         // boutique non responsable
      pctRetenuLivreur: 0,
      fraisLivraisonRembourses: false, // livraison non remboursée
      description: 'Client responsable — remboursement partiel, article à retourner',
    ),

    MotifRetour.mauvaiseTaille: RegleRetour(
      motif: MotifRetour.mauvaiseTaille,
      delaiMaxHeures: 24,           // 24h pour constater
      retourArticleRequis: true,
      remboursementParDefaut: TypeRemboursement.echange,
      pctRembourseClient: 100,      // 100% si échange, sinon remboursement total
      pctRetenuBoutique: 5,         // 5% pénalité boutique (erreur de sa part)
      pctRetenuLivreur: 0,
      fraisLivraisonRembourses: true,
      description: 'Faute boutique — échange prioritaire, remboursement total si indispo',
    ),

    MotifRetour.pagneDefectueux: RegleRetour(
      motif: MotifRetour.pagneDefectueux,
      delaiMaxHeures: 48,           // 48h pour constater un défaut
      retourArticleRequis: true,
      remboursementParDefaut: TypeRemboursement.mobileMoney,
      pctRembourseClient: 100,
      pctRetenuBoutique: 10,        // 10% pénalité boutique + impact note
      pctRetenuLivreur: 0,
      fraisLivraisonRembourses: true,
      description: 'Faute boutique — remboursement total + pénalité',
    ),

    MotifRetour.retardLivraison: RegleRetour(
      motif: MotifRetour.retardLivraison,
      delaiMaxHeures: 72,           // 72h si livraison jamais arrivée
      retourArticleRequis: false,   // pas encore reçu
      remboursementParDefaut: TypeRemboursement.mobileMoney,
      pctRembourseClient: 100,
      pctRetenuBoutique: 0,
      pctRetenuLivreur: 8,          // 8% pénalité livreur
      fraisLivraisonRembourses: true,
      description: 'Faute livreur — remboursement total + pénalité livreur',
    ),
  };
}

// ─── Preuve de retour (photos, etc.) ────────────────────────────────────────

class PreuveRetour {
  final List<String> photoUrls;   // photos du défaut / article
  final String? description;      // description du problème
  final String? videoUrl;         // vidéo si nécessaire
  final DateTime dateCreation;

  PreuveRetour({
    required this.photoUrls,
    this.description,
    this.videoUrl,
    required this.dateCreation,
  });

  Map<String, dynamic> toMap() => {
    'photoUrls': photoUrls,
    'description': description,
    'videoUrl': videoUrl,
    'dateCreation': dateCreation,
  };

  factory PreuveRetour.fromMap(Map<String, dynamic> m) => PreuveRetour(
    photoUrls: List<String>.from(m['photoUrls'] ?? []),
    description: m['description'] as String?,
    videoUrl: m['videoUrl'] as String?,
    dateCreation: ((m['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
  );
}

// ─── Décision agent/superviseur ──────────────────────────────────────────────

class DecisionRetour {
  final String decideurId;          // ID agent ou superviseur
  final bool estAgent;              // false = humain
  final StatutRetour decision;
  final String justification;
  final TypeRemboursement typeRemboursement;
  final double montantRembourse;    // FCFA, multiple de 50
  final DateTime dateDecision;
  final bool valideeParHumain;      // si agent → superviseur peut invalider

  DecisionRetour({
    required this.decideurId,
    required this.estAgent,
    required this.decision,
    required this.justification,
    required this.typeRemboursement,
    required this.montantRembourse,
    required this.dateDecision,
    this.valideeParHumain = false,
  });

  Map<String, dynamic> toMap() => {
    'decideurId': decideurId,
    'estAgent': estAgent,
    'decision': decision.name,
    'justification': justification,
    'typeRemboursement': typeRemboursement.name,
    'montantRembourse': montantRembourse,
    'dateDecision': dateDecision,
    'valideeParHumain': valideeParHumain,
  };

  factory DecisionRetour.fromMap(Map<String, dynamic> m) => DecisionRetour(
    decideurId: m['decideurId'] as String? ?? '',
    estAgent: m['estAgent'] as bool,
    decision: StatutRetour.values.firstWhere((e) => e.name == (m['decision'] as String? ?? ''), orElse: () => StatutRetour.values.first),
    justification: m['justification'] as String? ?? '',
    typeRemboursement: TypeRemboursement.values.firstWhere((e) => e.name == (m['typeRemboursement'] as String? ?? ''), orElse: () => TypeRemboursement.values.first),
    montantRembourse: (m['montantRembourse'] as num? ?? 0).toDouble(),
    dateDecision: ((m['dateDecision'] as Timestamp?)?.toDate() ?? DateTime.now()),
    valideeParHumain: m['valideeParHumain'] as bool? ?? false,
  );
}

// ─── Dossier de retour ───────────────────────────────────────────────────────

class DossierRetour {
  final String id;
  final String livraisonId;
  final String commandeId;
  final String clientId;
  final String boutiqueId;
  final String? livreurId;
  final String pagneId;
  final int quantite;             // nb d'unités retournées (défaut 1)

  // Motif et initiateur
  final MotifRetour motif;
  final InitiateurRetour initiateur;
  final String? initieurId;         // ID de qui a initié (null si agent auto)
  StatutRetour statut;

  // Preuves
  final PreuveRetour? preuve;

  // Montants originaux (pour calcul remboursement)
  final double montantPaye;         // ce que le client a payé
  final double fraisLivraisonPaye;  // frais livraison inclus dans le prix

  // Décision
  DecisionRetour? decision;

  // QR Code retour (si article à renvoyer)
  final String? qrCodeRetour;       // code pour valider réception article retourné

  // Timeline
  final DateTime dateCreation;
  DateTime? dateExamen;
  DateTime? dateDecision;
  DateTime? dateRetourArticle;      // quand article reçu par boutique
  DateTime? dateRemboursement;

  // Note interne
  String? noteInterne;              // visible uniquement admin/agent
  int? priorite;                    // 1=urgent, 2=normal, 3=faible

  DossierRetour({
    required this.id,
    required this.livraisonId,
    required this.commandeId,
    required this.clientId,
    required this.boutiqueId,
    this.livreurId,
    required this.pagneId,
    this.quantite = 1,
    required this.motif,
    required this.initiateur,
    this.initieurId,
    this.statut = StatutRetour.soumis,
    this.preuve,
    required this.montantPaye,
    required this.fraisLivraisonPaye,
    this.decision,
    this.qrCodeRetour,
    required this.dateCreation,
    this.dateExamen,
    this.dateDecision,
    this.dateRetourArticle,
    this.dateRemboursement,
    this.noteInterne,
    this.priorite = 2,
  });

  // Règle applicable à ce dossier
  RegleRetour get regle =>
      RegleRetour.reglesDefaut[motif]!;

  // Délai restant pour traiter le dossier (SLA)
  bool get estEnRetard {
    final sla = switch (motif) {
      MotifRetour.pagneDefectueux => const Duration(hours: 24),
      MotifRetour.retardLivraison => const Duration(hours: 12),
      _ => const Duration(hours: 48),
    };
    return statut == StatutRetour.soumis &&
        DateTime.now().difference(dateCreation) > sla;
  }

  // Montant remboursable calculé automatiquement
  double get montantRemboursable {
    final regle = this.regle;
    double base = montantPaye;
    if (!regle.fraisLivraisonRembourses) base -= fraisLivraisonPaye;
    final rembourse = base * regle.pctRembourseClient / 100;
    return PrixFCFA.arrondirAu50(rembourse);
  }

  static CollectionReference<Map<String, dynamic>> collection =
      FirebaseFirestore.instance.collection('retours');

  factory DossierRetour.fromFirebaseDocument(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DossierRetour(
      id: doc.id,
      livraisonId: d['livraisonId'] as String? ?? '',
      commandeId: d['commandeId'] as String? ?? '',
      clientId: d['clientId'] as String? ?? '',
      boutiqueId: d['boutiqueId'] as String? ?? '',
      livreurId: d['livreurId'] as String?,
      pagneId: d['pagneId'] as String? ?? '',
      quantite: (d['quantite'] as num?)?.toInt() ?? 1,
      motif: MotifRetour.values.firstWhere((e) => e.name == (d['motif'] as String? ?? ''), orElse: () => MotifRetour.values.first),
      initiateur: InitiateurRetour.values.firstWhere((e) => e.name == (d['initiateur'] as String? ?? ''), orElse: () => InitiateurRetour.values.first),
      initieurId: d['initieurId'] as String?,
      statut: StatutRetour.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'soumis'), orElse: () => StatutRetour.values.first),
      preuve: d['preuve'] != null
          ? PreuveRetour.fromMap(d['preuve'] as Map<String, dynamic>)
          : null,
      montantPaye: (d['montantPaye'] as num? ?? 0).toDouble(),
      fraisLivraisonPaye: (d['fraisLivraisonPaye'] as num? ?? 0).toDouble(),
      decision: d['decision'] != null
          ? DecisionRetour.fromMap(d['decision'] as Map<String, dynamic>)
          : null,
      qrCodeRetour: d['qrCodeRetour'] as String?,
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      dateExamen: (d['dateExamen'] as Timestamp?)?.toDate(),
      dateDecision: (d['dateDecision'] as Timestamp?)?.toDate(),
      dateRetourArticle: (d['dateRetourArticle'] as Timestamp?)?.toDate(),
      dateRemboursement: (d['dateRemboursement'] as Timestamp?)?.toDate(),
      noteInterne: d['noteInterne'] as String?,
      priorite: d['priorite'] as int? ?? 2,
    );
  }

  Map<String, dynamic> toMap() => {
    'livraisonId': livraisonId,
    'commandeId': commandeId,
    'clientId': clientId,
    'boutiqueId': boutiqueId,
    'livreurId': livreurId,
    'pagneId': pagneId,
    'quantite': quantite,
    'motif': motif.name,
    'initiateur': initiateur.name,
    'initieurId': initieurId,
    'statut': statut.name,
    'preuve': preuve?.toMap(),
    'montantPaye': montantPaye,
    'fraisLivraisonPaye': fraisLivraisonPaye,
    'decision': decision?.toMap(),
    'qrCodeRetour': qrCodeRetour,
    'dateCreation': dateCreation,
    'dateExamen': dateExamen,
    'dateDecision': dateDecision,
    'dateRetourArticle': dateRetourArticle,
    'dateRemboursement': dateRemboursement,
    'noteInterne': noteInterne,
    'priorite': priorite,
  };
}
