import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION MARKETING (éditable par l'admin)
//
// Stocke dans Firestore (collection 'config_marketing', document 'parametres')
// les réglages de fidélité, cashback et promotions. Si le document n'existe
// pas, on utilise les valeurs par défaut (alignées sur le code historique).
//
// Cela permet à l'admin d'ajuster les taux SANS toucher au code.
// ═══════════════════════════════════════════════════════════════════════════

class ConfigMarketing {
  // Points de fidélité
  final int fcfaParPoint;           // combien de FCFA = 1 point (défaut 100)

  // Paliers : nom, points requis, réduction livraison %, cashback %
  final List<PalierConfig> paliers;

  // Promotions globales
  final bool promotionsActives;
  final double reductionFlashDefaut; // % suggéré pour les ventes flash

  ConfigMarketing({
    required this.fcfaParPoint,
    required this.paliers,
    required this.promotionsActives,
    required this.reductionFlashDefaut,
  });

  factory ConfigMarketing.defaut() => ConfigMarketing(
        fcfaParPoint: 100,
        promotionsActives: true,
        reductionFlashDefaut: 20,
        paliers: [
          PalierConfig('Découvreur', '🌱', 0, 0, 0),
          PalierConfig('Habitué', '⭐', 500, 10, 1),
          PalierConfig('Connaisseur', '🏆', 2000, 25, 2),
          PalierConfig('Expert', '💎', 5000, 50, 3),
          PalierConfig('Ambassadeur', '👑', 10000, 100, 5),
        ],
      );

  factory ConfigMarketing.fromMap(Map<String, dynamic> m) {
    final paliersRaw = m['paliers'] as List<dynamic>?;
    return ConfigMarketing(
      fcfaParPoint: m['fcfaParPoint'] as int? ?? 100,
      promotionsActives: m['promotionsActives'] as bool? ?? true,
      reductionFlashDefaut:
          (m['reductionFlashDefaut'] as num?)?.toDouble() ?? 20,
      paliers: paliersRaw != null && paliersRaw.isNotEmpty
          ? paliersRaw
              .map((p) => PalierConfig.fromMap(p as Map<String, dynamic>))
              .toList()
          : ConfigMarketing.defaut().paliers,
    );
  }

  Map<String, dynamic> toMap() => {
        'fcfaParPoint': fcfaParPoint,
        'promotionsActives': promotionsActives,
        'reductionFlashDefaut': reductionFlashDefaut,
        'paliers': paliers.map((p) => p.toMap()).toList(),
      };
}

class PalierConfig {
  final String nom;
  final String emoji;
  final int pointsRequis;
  final double reductionLivraison; // %
  final double cashback;           // %

  PalierConfig(this.nom, this.emoji, this.pointsRequis, this.reductionLivraison,
      this.cashback);

  factory PalierConfig.fromMap(Map<String, dynamic> m) => PalierConfig(
        m['nom'] as String? ?? '',
        m['emoji'] as String? ?? '⭐',
        m['pointsRequis'] as int? ?? 0,
        (m['reductionLivraison'] as num?)?.toDouble() ?? 0,
        (m['cashback'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'nom': nom,
        'emoji': emoji,
        'pointsRequis': pointsRequis,
        'reductionLivraison': reductionLivraison,
        'cashback': cashback,
      };

  PalierConfig copyWith({
    String? nom,
    int? pointsRequis,
    double? reductionLivraison,
    double? cashback,
  }) =>
      PalierConfig(
        nom ?? this.nom,
        emoji,
        pointsRequis ?? this.pointsRequis,
        reductionLivraison ?? this.reductionLivraison,
        cashback ?? this.cashback,
      );
}

class ConfigMarketingService {
  static final _ref = FirebaseFirestore.instance
      .collection('config_marketing')
      .doc('parametres');

  /// Charge la config (ou les valeurs par défaut si absente).
  static Future<ConfigMarketing> charger() async {
    try {
      final doc = await _ref.get();
      if (doc.exists && doc.data() != null) {
        return ConfigMarketing.fromMap(doc.data()!);
      }
    } catch (_) {}
    return ConfigMarketing.defaut();
  }

  /// Enregistre la config (réservé admin).
  static Future<void> sauvegarder(ConfigMarketing config) async {
    await _ref.set(config.toMap());
  }
}
