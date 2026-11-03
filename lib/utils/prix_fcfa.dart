// ═══════════════════════════════════════════════════════════════
// UTILITAIRE PRIX FCFA — Contexte camerounais
// ═══════════════════════════════════════════════════════════════
// Règles monétaires locales :
//   - Pas minimal : 50 FCFA (pièce la plus petite en circulation)
//   - Jamais de centimes, jamais de pas de 10 FCFA
//   - Les prix s'arrondissent AU PLUS PROCHE multiple de 50
//   - Affichage : séparateur espace tous les 3 chiffres (1 500, 10 000)
//   - Devise : FCFA (XAF)
// ═══════════════════════════════════════════════════════════════

class PrixFCFA {

  // ─── Arrondi au pas de 50 ────────────────────────────────────────────────

  /// Arrondit au multiple de 50 le plus proche
  /// Ex: 10 320 → 10 300 | 10 350 → 10 350 | 10 370 → 10 350
  static double arrondirAu50(double prix) {
    return (prix / 50).round() * 50;
  }

  /// Arrondit AU SUPÉRIEUR multiple de 50 (pour prix vendeur)
  /// Ex: 10 301 → 10 350 | 10 350 → 10 350
  static double arrondirSuperieur50(double prix) {
    return (prix / 50).ceil() * 50;
  }

  /// Arrondit À L'INFÉRIEUR multiple de 50 (pour net boutiquier)
  /// Ex: 10 349 → 10 300 | 10 350 → 10 350
  static double arrondirInferieur50(double prix) {
    return (prix / 50).floor() * 50;
  }

  // ─── Prix psychologique ──────────────────────────────────────────────────

  /// Prix charm camerounais : multiple de 50 juste en dessous du millier
  /// Ex: 10 000 → 9 950 | 5 000 → 4 950 | 15 000 → 14 950
  /// Contrairement au modèle occidental (9 990), ici le pas est 50 FCFA
  static double prixCharm(double prix) {
    // Trouver le millier supérieur le plus proche
    final millier = (prix / 1000).ceil() * 1000;
    final candidat = (millier - 50).toDouble();
    // Ne pas descendre trop bas (ex: 1000 → 950, pas 500)
    if (candidat <= 0) return prix;
    // Appliquer seulement si le prix est proche d'un millier
    if ((millier - prix).abs() <= 200) return candidat;
    return arrondirAu50(prix);
  }

  // ─── Formatage affichage ─────────────────────────────────────────────────

  /// Format complet : "9 950 FCFA"
  static String formater(double prix) {
    final arrondi = arrondirAu50(prix).toInt();
    return '${_separerMilliers(arrondi)} FCFA';
  }

  /// Format court sans devise : "9 950"
  static String formaterSansDevise(double prix) {
    final arrondi = arrondirAu50(prix).toInt();
    return _separerMilliers(arrondi);
  }

  /// Format compact pour badges : "9,9k FCFA" au-dessus de 10 000
  static String formaterCompact(double prix) {
    final arrondi = arrondirAu50(prix);
    if (arrondi >= 1000000) {
      return '${(arrondi / 1000000).toStringAsFixed(1)}M FCFA';
    }
    if (arrondi >= 10000) {
      return '${(arrondi / 1000).toStringAsFixed(1)}k FCFA';
    }
    return formater(prix);
  }

  /// Format variation : "+500 FCFA" ou "-1 000 FCFA"
  static String formaterVariation(double variation) {
    final arrondi = arrondirAu50(variation.abs()).toInt();
    final signe = variation >= 0 ? '+' : '-';
    return '$signe${_separerMilliers(arrondi)} FCFA';
  }

  // ─── Calcul avec arrondi au 50 ──────────────────────────────────────────

  /// Décomposition financière complète avec arrondi FCFA correct
  static DecompositionFCFA decomposer({
    required double coutAchat,
    double beneficeSouhaite = 0,
    // Commission relevée (8 %) : compense la sortie du transport du prix.
    double tauxCommission = 8.0,
    // NE FAIT PLUS PARTIE DU PRIX DU PAGNE : la livraison est facturée
    // UNE SEULE FOIS, au panier (elle était comptée deux fois avant).
    // Conservé en paramètre pour la décomposition des gains livreur.
    double fraisLivraison = 600,
    double tauxFraisMobileMoney = 2.5,
    bool paiementCash = false,
    bool appliquerCharm = true,
  }) {
    // 1. Prix HT brut (avant arrondi) — SANS transport : le client paie
    //    la livraison au panier, pas cachée dans le prix du tissu.
    final prixHTBrut = coutAchat + beneficeSouhaite;

    // 2. Commission sur prix HT
    final commissionBrute = prixHTBrut * tauxCommission / 100;

    // 3. Prix final brut
    final prixFinalBrut = prixHTBrut + commissionBrute;

    // 4. Frais passerelle de paiement (inclus dans le prix payé par le client)
    //    Le client paie un prix unique tout compris — les frais MoMo sont
    //    intégrés au prix final, sans ligne séparée affichée au client.
    final fraisMMBrut = paiementCash
        ? 0.0
        : prixFinalBrut * tauxFraisMobileMoney / 100;

    // 5. Prix final = prix HT + commission + frais paiement, puis arrondi
    final prixAvecFrais = prixFinalBrut + fraisMMBrut;
    final prixFinalArrondi = appliquerCharm
        ? prixCharm(prixAvecFrais)
        : arrondirSuperieur50(prixAvecFrais);

    // 6. Recalculer commission et frais MoMo sur la base arrondie
    final commissionArrondie = arrondirAu50(prixFinalArrondi * tauxCommission / 100);
    final fraisMM = paiementCash
        ? 0.0
        : arrondirAu50(prixFinalArrondi * tauxFraisMobileMoney / 100);

    // 7. Gain livreur (70% des frais livraison, arrondi au 50)
    final gainLivreur = arrondirInferieur50(fraisLivraison * 0.70);

    // 8. Net boutiquier = ce qu'il reçoit réellement
    //    (frais MoMo et commission NE sont PAS à sa charge)
    // (la livraison n'est plus déduite : elle n'est plus dans le prix)
    final netBoutiqueReel = prixFinalArrondi - commissionArrondie - fraisMM;
    final netBoutiqueArrondi = arrondirInferieur50(netBoutiqueReel);

    // 9. Net plateforme : commission + reste frais livraison
    //    (les frais MoMo étant déjà couverts par le client, ils sortent au paiement)
    // La part plateforme sur la livraison (30 %) se prend sur les frais
    // facturés AU PANIER — ici, seule la commission compte.
    final netPlateforme = arrondirAu50(commissionArrondie);

    // 10. Bénéfice réel boutiquier
    final beneficeReel = netBoutiqueArrondi - coutAchat;
    final margeReelle = coutAchat > 0
        ? (beneficeReel / coutAchat * 100)
        : 0.0;

    return DecompositionFCFA(
      coutAchat: arrondirAu50(coutAchat),
      beneficeSouhaite: arrondirAu50(beneficeSouhaite),
      fraisLivraison: fraisLivraison,        // fixe, déjà multiple de 50
      commission: commissionArrondie,
      fraisPaiement: fraisMM,
      prixFinalClient: prixFinalArrondi,     // ← affiché sur l'app
      netBoutique: netBoutiqueArrondi,       // ← reçu par le boutiquier
      gainLivreur: gainLivreur,
      netPlateforme: netPlateforme,
      beneficeReel: beneficeReel,
      margeReelle: margeReelle,
      tauxCommission: tauxCommission,
    );
  }

  // ─── Utilitaire interne ──────────────────────────────────────────────────

  static String _separerMilliers(int valeur) {
    return valeur.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }
}

// ─── Modèle décomposition avec arrondi FCFA ────────────────────────────────

class DecompositionFCFA {
  final double coutAchat;
  final double beneficeSouhaite;
  final double fraisLivraison;
  final double commission;
  final double fraisPaiement;
  final double prixFinalClient;   // multiple de 50 ✅
  final double netBoutique;       // multiple de 50 ✅
  final double gainLivreur;       // multiple de 50 ✅
  final double netPlateforme;     // multiple de 50 ✅
  final double beneficeReel;
  final double margeReelle;
  final double tauxCommission;

  const DecompositionFCFA({
    required this.coutAchat,
    required this.beneficeSouhaite,
    required this.fraisLivraison,
    required this.commission,
    required this.fraisPaiement,
    required this.prixFinalClient,
    required this.netBoutique,
    required this.gainLivreur,
    required this.netPlateforme,
    required this.beneficeReel,
    required this.margeReelle,
    required this.tauxCommission,
  });

  // Formatage direct
  String get prixFinalFmt => PrixFCFA.formater(prixFinalClient);
  String get netBoutiqueFmt => PrixFCFA.formater(netBoutique);
  String get commissionFmt => PrixFCFA.formater(commission);
  String get gainLivreurFmt => PrixFCFA.formater(gainLivreur);
  String get netPlateformeFmt => PrixFCFA.formater(netPlateforme);
  String get margeReelleFmt => '${margeReelle.toStringAsFixed(1)}%';

  Map<String, dynamic> toMap() => {
    'coutAchat': coutAchat,
    'beneficeSouhaite': beneficeSouhaite,
    'fraisLivraison': fraisLivraison,
    'commission': commission,
    'fraisPaiement': fraisPaiement,
    'prixFinalClient': prixFinalClient,
    'netBoutique': netBoutique,
    'gainLivreur': gainLivreur,
    'netPlateforme': netPlateforme,
    'beneficeReel': beneficeReel,
    'margeReelle': margeReelle,
    'tauxCommission': tauxCommission,
  };

  factory DecompositionFCFA.fromMap(Map<String, dynamic> m) => DecompositionFCFA(
    coutAchat: (m['coutAchat'] as num? ?? 0).toDouble(),
    beneficeSouhaite: (m['beneficeSouhaite'] as num? ?? 0).toDouble(),
    fraisLivraison: (m['fraisLivraison'] as num? ?? 0).toDouble(),
    commission: (m['commission'] as num? ?? 0).toDouble(),
    fraisPaiement: (m['fraisPaiement'] as num? ?? 0).toDouble(),
    prixFinalClient: (m['prixFinalClient'] as num? ?? 0).toDouble(),
    netBoutique: (m['netBoutique'] as num? ?? 0).toDouble(),
    gainLivreur: (m['gainLivreur'] as num? ?? 0).toDouble(),
    netPlateforme: (m['netPlateforme'] as num? ?? 0).toDouble(),
    beneficeReel: (m['beneficeReel'] as num? ?? 0).toDouble(),
    margeReelle: (m['margeReelle'] as num? ?? 0).toDouble(),
    tauxCommission: (m['tauxCommission'] as num? ?? 0).toDouble(),
  );

  @override
  String toString() => '''
┌──────────────────────────────────────────┐
│  DÉCOMPOSITION PRIX (INTERNE/ADMIN)      │
├──────────────────────────────────────────┤
│  Coût achat        : ${PrixFCFA.formater(coutAchat).padLeft(14)}  │
│  Bénéfice souhaité : ${PrixFCFA.formater(beneficeSouhaite).padLeft(14)}  │
│  Frais livraison   : ${PrixFCFA.formater(fraisLivraison).padLeft(14)}  │
│  Commission (${tauxCommission.round()}%)  : ${PrixFCFA.formater(commission).padLeft(14)}  │
│  dont frais MoMo*  : ${PrixFCFA.formater(fraisPaiement).padLeft(14)}  │
├──────────────────────────────────────────┤
│  PRIX CLIENT (TTC) : ${prixFinalFmt.padLeft(14)}  │
├──────────────────────────────────────────┤
│  Net boutiquier    : ${netBoutiqueFmt.padLeft(14)}  │
│  Bénéfice réel     : ${PrixFCFA.formater(beneficeReel).padLeft(14)}  │
│  Marge réelle      : ${margeReelleFmt.padLeft(14)}  │
│  Gain livreur      : ${gainLivreurFmt.padLeft(14)}  │
│  Net plateforme    : ${netPlateformeFmt.padLeft(14)}  │
└──────────────────────────────────────────┘''';
}

// ─── Tests rapides (à lancer en mode debug) ─────────────────────────────────

void _testerArrondis() {
  assert(PrixFCFA.arrondirAu50(10320) == 10300, 'Échec arrondi proche inf');
  assert(PrixFCFA.arrondirAu50(10350) == 10350, 'Échec arrondi exact');
  assert(PrixFCFA.arrondirAu50(10370) == 10350, 'Échec arrondi proche sup');
  assert(PrixFCFA.arrondirSuperieur50(10301) == 10350, 'Échec arrondi sup');
  assert(PrixFCFA.arrondirInferieur50(10349) == 10300, 'Échec arrondi inf');
  assert(PrixFCFA.prixCharm(10000) == 9950, 'Échec prix charm 10k');
  assert(PrixFCFA.prixCharm(5000) == 4950, 'Échec prix charm 5k');
  assert(PrixFCFA.prixCharm(15000) == 14950, 'Échec prix charm 15k');

  // Test décomposition complète
  final d = PrixFCFA.decomposer(
    coutAchat: 5000,
    beneficeSouhaite: 2000,
    appliquerCharm: true,
  );
  // Vérifier que tous les montants sont multiples de 50
  assert(d.prixFinalClient % 50 == 0, 'Prix final pas multiple de 50');
  assert(d.netBoutique % 50 == 0, 'Net boutique pas multiple de 50');
  assert(d.gainLivreur % 50 == 0, 'Gain livreur pas multiple de 50');
  assert(d.netPlateforme % 50 == 0, 'Net plateforme pas multiple de 50');

  print('Tous les tests arrondis FCFA passent ✅');
  print(d.toString());
}
