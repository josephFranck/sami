import 'package:sami/services/log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION DES TAXES — PARAMÉTRABLE
// Contexte camerounais : TVA 19.25%, taxe communale, droit de timbre
// Mode "informel" : toutes taxes à 0% par défaut
//
// IMPORTANT : Seul l'admin (superviseur humain) peut modifier ces paramètres.
// L'agent IA applique la config mais ne peut pas la modifier.
// ═══════════════════════════════════════════════════════════════════════════

enum TypeTaxe {
  tva,             // TVA — 19.25% au Cameroun (DGI)
  taxeCommunale,   // Taxe communale locale (variable par ville)
  droitTimbre,     // Droit de timbre sur transactions (fixe en FCFA)
  taxeService,     // Taxe sur les services numériques (si applicable)
}

enum BaseCalculTaxe {
  surPrixHT,         // taxe calculée sur le prix hors taxes
  surPrixTTC,        // taxe calculée sur le prix TTC (cas particulier)
  montantFixe,       // montant fixe en FCFA (ex: droit de timbre)
}

enum RegimeTaxe {
  informel,          // aucune taxe collectée (secteur informel)
  microEntreprise,   // régime simplifié (seuil DGI Cameroun)
  reel,              // régime réel (grande entreprise, TVA obligatoire)
}

// ─── Configuration d'une taxe individuelle ──────────────────────────────────

class ConfigTaxe {
  final TypeTaxe type;
  final String nom;
  final String description;
  bool estActive;                 // peut être désactivée par l'admin
  final BaseCalculTaxe baseCalcul;
  double taux;                    // pourcentage (0-100) OU montant fixe FCFA
  final bool inclushDansPrix;     // true = prix TTC affiché, false = ajouté au prix
  final bool appliqueAuxBoutiques; // s'applique aux boutiques (B2B)
  final bool appliqueAuxClients;   // s'applique aux clients (B2C)
  final String? codeComptable;    // pour l'export comptable
  DateTime? dateActivation;
  DateTime? dateDerniereModif;
  String? modifiePar;             // ID admin qui a modifié

  ConfigTaxe({
    required this.type,
    required this.nom,
    required this.description,
    required this.estActive,
    required this.baseCalcul,
    required this.taux,
    required this.inclushDansPrix,
    required this.appliqueAuxBoutiques,
    required this.appliqueAuxClients,
    this.codeComptable,
    this.dateActivation,
    this.dateDerniereModif,
    this.modifiePar,
  });

  // Calcule le montant de la taxe sur un prix donné
  double calculerMontant(double prixBase) {
    if (!estActive) return 0.0;
    switch (baseCalcul) {
      case BaseCalculTaxe.montantFixe:
        return PrixFCFA.arrondirAu50(taux); // taux = montant fixe FCFA
      case BaseCalculTaxe.surPrixHT:
        return PrixFCFA.arrondirAu50(prixBase * taux / 100);
      case BaseCalculTaxe.surPrixTTC:
        // Extraction TVA d'un prix TTC : TVA = TTC * taux / (100 + taux)
        return PrixFCFA.arrondirAu50(prixBase * taux / (100 + taux));
    }
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'nom': nom,
    'description': description,
    'estActive': estActive,
    'baseCalcul': baseCalcul.name,
    'taux': taux,
    'inclushDansPrix': inclushDansPrix,
    'appliqueAuxBoutiques': appliqueAuxBoutiques,
    'appliqueAuxClients': appliqueAuxClients,
    'codeComptable': codeComptable,
    'dateActivation': dateActivation,
    'dateDerniereModif': dateDerniereModif,
    'modifiePar': modifiePar,
  };

  factory ConfigTaxe.fromMap(Map<String, dynamic> m) => ConfigTaxe(
    type: TypeTaxe.values.firstWhere((e) => e.name == (m['type'] as String? ?? ''), orElse: () => TypeTaxe.values.first),
    nom: m['nom'] as String? ?? '',
    description: m['description'] as String? ?? '',
    estActive: m['estActive'] as bool,
    baseCalcul: BaseCalculTaxe.values.firstWhere((e) => e.name == (m['baseCalcul'] as String? ?? ''), orElse: () => BaseCalculTaxe.values.first),
    taux: (m['taux'] as num? ?? 0).toDouble(),
    inclushDansPrix: m['inclushDansPrix'] as bool,
    appliqueAuxBoutiques: m['appliqueAuxBoutiques'] as bool,
    appliqueAuxClients: m['appliqueAuxClients'] as bool,
    codeComptable: m['codeComptable'] as String?,
    dateActivation: (m['dateActivation'] as Timestamp?)?.toDate(),
    dateDerniereModif: (m['dateDerniereModif'] as Timestamp?)?.toDate(),
    modifiePar: m['modifiePar'] as String?,
  );
}

// ─── Configuration globale des taxes (paramétrable par l'admin) ─────────────

class ConfigurationTaxes {
  final String id;
  RegimeTaxe regime;
  final List<ConfigTaxe> taxes;
  final String ville;             // ex: "Garoua" (taxes communales variables)
  final String pays;              // "CM" pour Cameroun
  DateTime dateDerniereModif;
  String modifiePar;
  String? noteAdmin;              // commentaire de l'admin

  ConfigurationTaxes({
    required this.id,
    required this.regime,
    required this.taxes,
    required this.ville,
    required this.pays,
    required this.dateDerniereModif,
    required this.modifiePar,
    this.noteAdmin,
  });

  // ── Configuration par défaut — MODE INFORMEL (Garoua au démarrage) ────────
  static ConfigurationTaxes defautInformel() => ConfigurationTaxes(
    id: 'config_taxes_principale',
    regime: RegimeTaxe.informel,
    ville: 'Garoua',
    pays: 'CM',
    dateDerniereModif: DateTime.now(),
    modifiePar: 'system',
    noteAdmin: 'Mode informel — aucune taxe collectée au démarrage. '
        'Activer TVA quand l\'entreprise dépasse le seuil DGI.',
    taxes: [
      // TVA 19.25% — INACTIVE en mode informel
      ConfigTaxe(
        type: TypeTaxe.tva,
        nom: 'TVA',
        description: 'Taxe sur la Valeur Ajoutée — Direction Générale des Impôts',
        estActive: false,           // ← désactivée par défaut
        baseCalcul: BaseCalculTaxe.surPrixHT,
        taux: 19.25,
        inclushDansPrix: false,     // s'ajoute au prix HT
        appliqueAuxBoutiques: true,
        appliqueAuxClients: true,
        codeComptable: '44571',     // compte TVA collectée (plan comptable OHADA)
      ),

      // Taxe communale — INACTIVE en mode informel
      ConfigTaxe(
        type: TypeTaxe.taxeCommunale,
        nom: 'Taxe communale Garoua',
        description: 'Taxe collectée par la Commune de Garoua',
        estActive: false,
        baseCalcul: BaseCalculTaxe.surPrixHT,
        taux: 2.0,                  // exemple — varie selon commune
        inclushDansPrix: false,
        appliqueAuxBoutiques: true,
        appliqueAuxClients: false,  // supportée par les boutiques
        codeComptable: '44731',
      ),

      // Droit de timbre — INACTIF en mode informel
      ConfigTaxe(
        type: TypeTaxe.droitTimbre,
        nom: 'Droit de timbre',
        description: 'Droit de timbre sur transactions commerciales',
        estActive: false,
        baseCalcul: BaseCalculTaxe.montantFixe,
        taux: 1000,                 // 1 000 FCFA fixe par transaction
        inclushDansPrix: false,
        appliqueAuxBoutiques: true,
        appliqueAuxClients: false,
        codeComptable: '44751',
      ),
    ],
  );

  // ── Configuration mode TVA activée (quand seuil DGI atteint) ─────────────
  static ConfigurationTaxes avecTVA() {
    final config = defautInformel();
    config.regime = RegimeTaxe.microEntreprise;
    config.taxes.firstWhere((t) => t.type == TypeTaxe.tva).estActive = true;
    return config;
  }

  // ── Calcul complet des taxes sur un prix ─────────────────────────────────

  DecompositionTaxes calculerTaxes({
    required double prixHT,
    required bool estBoutique,
  }) {
    if (regime == RegimeTaxe.informel) {
      return DecompositionTaxes.aucuneTaxe(prixHT);
    }

    double totalTaxes = 0;
    final detailTaxes = <TypeTaxe, double>{};

    for (final taxe in taxes) {
      if (!taxe.estActive) continue;
      if (estBoutique && !taxe.appliqueAuxBoutiques) continue;
      if (!estBoutique && !taxe.appliqueAuxClients) continue;

      final montant = taxe.calculerMontant(prixHT);
      detailTaxes[taxe.type] = montant;
      totalTaxes += montant;
    }

    totalTaxes = PrixFCFA.arrondirAu50(totalTaxes);
    final prixTTC = PrixFCFA.arrondirSuperieur50(prixHT + totalTaxes);

    return DecompositionTaxes(
      prixHT: prixHT,
      totalTaxes: totalTaxes,
      prixTTC: prixTTC,
      detailParTaxe: detailTaxes,
      regime: regime,
    );
  }

  // Accès rapide à une taxe
  ConfigTaxe? taxe(TypeTaxe type) {
    try {
      return taxes.firstWhere((t) => t.type == type);
    } catch (_) {
      return null;
    }
  }

  bool get tvaActive => taxe(TypeTaxe.tva)?.estActive ?? false;
  double get tauxTVA => taxe(TypeTaxe.tva)?.taux ?? 0;

  static CollectionReference<Map<String, dynamic>> collection =
      FirebaseFirestore.instance.collection('config_taxes');

  factory ConfigurationTaxes.fromFirebaseDocument(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ConfigurationTaxes(
      id: doc.id,
      regime: RegimeTaxe.values.firstWhere((e) => e.name == (d['regime'] as String? ?? ''), orElse: () => RegimeTaxe.values.first),
      ville: d['ville'] as String? ?? '',
      pays: d['pays'] as String? ?? '',
      dateDerniereModif: ((d['dateDerniereModif'] as Timestamp?)?.toDate() ?? DateTime.now()),
      modifiePar: d['modifiePar'] as String? ?? '',
      noteAdmin: d['noteAdmin'] as String?,
      taxes: (d['taxes'] as List<dynamic>)
          .map((t) => ConfigTaxe.fromMap(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'regime': regime.name,
    'ville': ville,
    'pays': pays,
    'dateDerniereModif': dateDerniereModif,
    'modifiePar': modifiePar,
    'noteAdmin': noteAdmin,
    'taxes': taxes.map((t) => t.toMap()).toList(),
  };
}

// ─── Résultat décomposition taxes ────────────────────────────────────────────

class DecompositionTaxes {
  final double prixHT;
  final double totalTaxes;
  final double prixTTC;
  final Map<TypeTaxe, double> detailParTaxe;
  final RegimeTaxe regime;

  const DecompositionTaxes({
    required this.prixHT,
    required this.totalTaxes,
    required this.prixTTC,
    required this.detailParTaxe,
    required this.regime,
  });

  factory DecompositionTaxes.aucuneTaxe(double prixHT) => DecompositionTaxes(
    prixHT: prixHT,
    totalTaxes: 0,
    prixTTC: prixHT,
    detailParTaxe: {},
    regime: RegimeTaxe.informel,
  );

  bool get avecTaxes => totalTaxes > 0;

  double get montantTVA => detailParTaxe[TypeTaxe.tva] ?? 0;
  double get montantCommunal => detailParTaxe[TypeTaxe.taxeCommunale] ?? 0;
  double get montantTimbre => detailParTaxe[TypeTaxe.droitTimbre] ?? 0;

  // Formatage pour affichage et comptabilité
  String get prixHTFmt => PrixFCFA.formater(prixHT);
  String get totalTaxesFmt => PrixFCFA.formater(totalTaxes);
  String get prixTTCFmt => PrixFCFA.formater(prixTTC);

  Map<String, dynamic> toMap() => {
    'prixHT': prixHT,
    'totalTaxes': totalTaxes,
    'prixTTC': prixTTC,
    'detailParTaxe': detailParTaxe.map((k, v) => MapEntry(k.name, v)),
    'regime': regime.name,
  };

  @override
  String toString() => regime == RegimeTaxe.informel
      ? 'Mode informel — aucune taxe (prix HT = TTC = ${PrixFCFA.formater(prixHT)})'
      : '''
Régime ${regime.name}
  Prix HT      : $prixHTFmt
  TVA          : ${PrixFCFA.formater(montantTVA)}
  Taxe commune : ${PrixFCFA.formater(montantCommunal)}
  Droit timbre : ${PrixFCFA.formater(montantTimbre)}
  ─────────────────────────────
  Prix TTC     : $prixTTCFmt
''';
}

// ─── Service taxes (lecture/écriture config) ─────────────────────────────────

class TaxesService {

  static ConfigurationTaxes? _cache;

  /// Charge la configuration depuis Firestore (avec cache)
  static Future<ConfigurationTaxes> chargerConfig() async {
    if (_cache != null) return _cache!;

    try {
      final doc = await ConfigurationTaxes.collection
          .doc('config_taxes_principale')
          .get();

      if (doc.exists) {
        _cache = ConfigurationTaxes.fromFirebaseDocument(doc);
        return _cache!;
      }
    } catch (_) {}

    // Première utilisation → créer config informelle par défaut
    final defaut = ConfigurationTaxes.defautInformel();
    await ConfigurationTaxes.collection
        .doc(defaut.id)
        .set(defaut.toMap());
    _cache = defaut;
    return defaut;
  }

  /// Sauvegarde la configuration (admin uniquement)
  static Future<void> sauvegarderConfig({
    required ConfigurationTaxes config,
    required String adminId,
  }) async {
    config.dateDerniereModif = DateTime.now();
    config.modifiePar = adminId;
    _cache = null; // invalider le cache

    await ConfigurationTaxes.collection
        .doc(config.id)
        .set(config.toMap());

    // Journal UNIQUE (app_logs via LogService) — avant : 'logs_admin'
    await LogService.log('modification_taxes', details: {
      'adminId': adminId,
      'regime': config.regime.name,
      'taxesActives': config.taxes
          .where((t) => t.estActive)
          .map((t) => '${t.nom} (${t.taux}%)')
          .toList(),
    });
  }

  /// Active/désactive une taxe spécifique (admin uniquement)
  static Future<void> toggleTaxe({
    required TypeTaxe type,
    required bool activer,
    required String adminId,
    String? note,
  }) async {
    final config = await chargerConfig();
    final taxe = config.taxe(type);
    if (taxe == null) return;

    taxe.estActive = activer;
    taxe.dateActivation = activer ? DateTime.now() : null;
    taxe.dateDerniereModif = DateTime.now();
    taxe.modifiePar = adminId;

    if (note != null) config.noteAdmin = note;

    await sauvegarderConfig(config: config, adminId: adminId);
  }

  /// Modifie le taux d'une taxe (admin uniquement)
  static Future<void> modifierTaux({
    required TypeTaxe type,
    required double nouveauTaux,
    required String adminId,
  }) async {
    final config = await chargerConfig();
    final taxe = config.taxe(type);
    if (taxe == null) return;

    taxe.taux = nouveauTaux;
    taxe.dateDerniereModif = DateTime.now();
    taxe.modifiePar = adminId;

    await sauvegarderConfig(config: config, adminId: adminId);
  }

  /// Calcule les taxes sur un prix (utilise la config en cache)
  static Future<DecompositionTaxes> calculer({
    required double prixHT,
    required bool estBoutique,
  }) async {
    final config = await chargerConfig();
    return config.calculerTaxes(prixHT: prixHT, estBoutique: estBoutique);
  }
}
