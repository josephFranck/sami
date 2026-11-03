import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/services/commission_boutique_service.dart';
import 'package:sami/services/config_marketing_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// DEVIS DE COMMANDE — LA source unique de ce que le client paie.
///
/// Avant : le panier affichait `Panier.fraisBase` (600), le service de
/// commande facturait une constante privée (500, commission 6 %), la
/// couture comptait 2 × 600 et la fiche pagne 8 %. Le client voyait un
/// prix et en payait un autre.
///
/// Maintenant : le PANIER appelle `calculer()` pour afficher, la COMMANDE
/// appelle `calculer()` pour facturer — même fonction, mêmes paramètres
/// admin (frais de base, rayon de zone, supplément hors zone, commission,
/// frais MoMo, part livreur, réduction fidélité).
/// ═══════════════════════════════════════════════════════════════════════

class DevisBoutique {
  final String boutiqueId;
  final List<PanierItem> articles;
  final double sousTotal;
  final bool estRetrait;
  final bool avecCouture;
  final int nbTrajets;
  final double fraisBase;          // par trajet (paramètre admin)
  final double? distanceKm;         // null si GPS boutique ou client inconnu
  final double supplementHorsZone;  // 0 si dans la zone / GPS inconnu
  final double fraisLivraisonBrut;  // base × trajets + supplément
  final double reductionFideliteF;  // part offerte par le palier du client
  final double fraisLivraison;      // ce que le client paie pour la livraison
  final double commission;          // commission plateforme sur la vente
  final double fraisPaiement;       // frais MoMo répercutés (0 si cash)
  final double totalClient;         // sousTotal + fraisLivraison + fraisPaiement
  final double netBoutique;         // ce que la boutique reçoit
  final double gainLivreur;         // part livreur (sur le brut, jamais réduite)
  final bool prepaye;
  final bool gratuit;

  const DevisBoutique({
    required this.boutiqueId,
    required this.articles,
    required this.sousTotal,
    required this.estRetrait,
    required this.avecCouture,
    required this.nbTrajets,
    required this.fraisBase,
    required this.distanceKm,
    required this.supplementHorsZone,
    required this.fraisLivraisonBrut,
    required this.reductionFideliteF,
    required this.fraisLivraison,
    required this.commission,
    required this.fraisPaiement,
    required this.totalClient,
    required this.netBoutique,
    required this.gainLivreur,
    required this.prepaye,
    required this.gratuit,
  });
}

class DevisCommande {
  final Map<String, DevisBoutique> parBoutique;
  final double totalArticles;
  final double totalLivraisonsBrut;
  final double reductionLivraisonPct;
  final double totalReductionF;
  final double totalLivraisons;
  final double totalSupplementsHorsZone;
  final double totalFraisPaiement;
  final double totalPaye;
  // paramètres utilisés (pour affichage / traçabilité)
  final double fraisBase;
  final double rayonZoneKm;
  final double supplementHorsZone;
  final double commissionPct;
  final double fraisMoMoPct;
  final double gainLivreurPct;

  const DevisCommande({
    required this.parBoutique,
    required this.totalArticles,
    required this.totalLivraisonsBrut,
    required this.reductionLivraisonPct,
    required this.totalReductionF,
    required this.totalLivraisons,
    required this.totalSupplementsHorsZone,
    required this.totalFraisPaiement,
    required this.totalPaye,
    required this.fraisBase,
    required this.rayonZoneKm,
    required this.supplementHorsZone,
    required this.commissionPct,
    required this.fraisMoMoPct,
    required this.gainLivreurPct,
  });

  int get nombreBoutiques => parBoutique.length;
  bool get aSupplementHorsZone => totalSupplementsHorsZone > 0;
}

class DevisCommandeService {
  static final _db = FirebaseFirestore.instance;

  /// Distance à vol d'oiseau en km (Haversine).
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static Map<String, List<PanierItem>> grouperParBoutique(
      List<PanierItem> items) {
    final g = <String, List<PanierItem>>{};
    for (final it in items) {
      g.putIfAbsent(it.boutiqueId ?? 'boutique_inconnue', () => []).add(it);
    }
    return g;
  }

  /// Calcule le devis complet. `items` est copié (jamais itéré en vivant).
  static Future<DevisCommande> calculer({
    required List<PanierItem> items,
    required String clientId,
    required String methodePaiement,
    required Map<String, ConfigLivraisonBoutique> configParBoutique,
    required String adresseLivraison,
    double? gpsClientLat,
    double? gpsClientLng,
  }) async {
    final fige = List<PanierItem>.of(items);
    final groupes = grouperParBoutique(fige);

    // ── paramètres admin (UNE lecture, mise en cache 5 min) ──
    final fraisBase = await ParametresService.fraisLivraisonBase();
    final rayonZoneKm = await ParametresService.rayonZoneKm();
    final supplementHZ = await ParametresService.supplementHorsZone();
    final commissionPct = await ParametresService.commissionDefautPct();
    final fraisMoMoPct = await ParametresService.fraisMoMoPct();
    final gainLivreurPct = await ParametresService.gainLivreurPct();

    // ── réduction de livraison selon le palier de fidélité du client ──
    double reductionPct = 0;
    try {
      final clientDoc = await _db.collection('utilisateurs').doc(clientId).get();
      final points = (clientDoc.data()?['pointsFidelite'] as num?)?.toInt() ?? 0;
      final config = await ConfigMarketingService.charger();
      var palier = config.paliers.first;
      for (final p in config.paliers) {
        if (points >= p.pointsRequis) palier = p;
      }
      reductionPct = palier.reductionLivraison.clamp(0, 100).toDouble();
    } catch (_) {}

    final parBoutique = <String, DevisBoutique>{};
    for (final e in groupes.entries) {
      final boutiqueId = e.key;
      final articles = e.value;
      final config = configParBoutique[boutiqueId] ??
          ConfigLivraisonBoutique.defaut(adresseLivraison);
      final estRetrait =
          config.typeDestination == TypeDestination.retraitBoutique;
      final avecCouture = articles.any((i) => i.avecCouture);
      final nbTrajets = estRetrait ? 0 : (avecCouture ? 2 : 1);

      final sousTotal = articles.fold<double>(0, (s, i) => s + i.sousTotal);

      // franchise gratuite / prépayé (modèle hybride boutique)
      bool gratuit = false, prepaye = false;
      try {
        gratuit = await CommissionBoutiqueService.enFranchiseGratuite(boutiqueId);
        prepaye = gratuit ? false : await CommissionBoutiqueService.estPrepaye(boutiqueId);
      } catch (_) {}

      // ── HORS ZONE : distance boutique → client si les deux GPS existent ──
      double? dKm;
      double supplement = 0;
      if (!estRetrait && gpsClientLat != null && gpsClientLng != null) {
        try {
          final b = await _db.collection('boutiques').doc(boutiqueId).get();
          final bl = (b.data()?['latitude'] as num?)?.toDouble();
          final bg = (b.data()?['longitude'] as num?)?.toDouble();
          if (bl != null && bg != null && bl != 0 && bg != 0) {
            dKm = distanceKm(bl, bg, gpsClientLat, gpsClientLng);
            if (dKm > rayonZoneKm) supplement = supplementHZ;
          }
        } catch (_) {}
      }

      final fraisBrut = nbTrajets == 0 ? 0.0 : fraisBase * nbTrajets + supplement;
      final reductionF = PrixFCFA.arrondirAu50(fraisBrut * reductionPct / 100);
      final fraisLivraison = PrixFCFA.arrondirAu50(fraisBrut - reductionF);

      // COMMISSION : celle du PLAN de la boutique (abonnement payant actif,
      // CommissionBoutiqueService.abonnementDe), sinon le défaut admin.
      // Avant : le défaut pour tout le monde — l'abonné payait son plan
      // pour une « commission réduite » jamais appliquée.
      double pctBoutique = commissionPct;
      try {
        final abo = await CommissionBoutiqueService.abonnementDe(boutiqueId);
        if (abo.prixMensuel > 0) pctBoutique = abo.tauxCommission;
      } catch (_) {}
      final commission =
          gratuit ? 0.0 : PrixFCFA.arrondirAu50(sousTotal * pctBoutique / 100);
      // Frais de transaction Mobile Money : aucun en espèces, aucun en
      // avoirs (`credits` = solde interne, aucune transaction MoMo).
      final fraisPaiement =
          (methodePaiement == 'cash' || methodePaiement == 'credits')
              ? 0.0
              : PrixFCFA.arrondirAu50(
                  (sousTotal + fraisLivraison) * fraisMoMoPct / 100);
      final totalClient = PrixFCFA.arrondirSuperieur50(
          sousTotal + fraisLivraison + fraisPaiement);
      // Le livreur est payé sur le BRUT (la réduction fidélité est un
      // geste de la plateforme, pas une baisse de sa part).
      final gainLivreur = nbTrajets == 0
          ? 0.0
          : PrixFCFA.arrondirInferieur50(fraisBrut * gainLivreurPct / 100);
      // NET BOUTIQUE : prix − commission, quel que soit le mode de facturation.
      // Avant : en mode « prépayé », net = prix entier et la commission devait
      // être débitée du crédit à la livraison par un code jamais appelé
      // (_declencherReversement) — la plateforme ne touchait rien.
      final netBoutique = PrixFCFA.arrondirInferieur50(sousTotal - commission);

      parBoutique[boutiqueId] = DevisBoutique(
        boutiqueId: boutiqueId,
        articles: articles,
        sousTotal: sousTotal,
        estRetrait: estRetrait,
        avecCouture: avecCouture,
        nbTrajets: nbTrajets,
        fraisBase: fraisBase,
        distanceKm: dKm,
        supplementHorsZone: supplement,
        fraisLivraisonBrut: fraisBrut,
        reductionFideliteF: reductionF,
        fraisLivraison: fraisLivraison,
        commission: commission,
        fraisPaiement: fraisPaiement,
        totalClient: totalClient,
        netBoutique: netBoutique,
        gainLivreur: gainLivreur,
        prepaye: prepaye,
        gratuit: gratuit,
      );
    }

    double somme(double Function(DevisBoutique) f) =>
        parBoutique.values.fold<double>(0, (s, d) => s + f(d));

    return DevisCommande(
      parBoutique: parBoutique,
      totalArticles: somme((d) => d.sousTotal),
      totalLivraisonsBrut: somme((d) => d.fraisLivraisonBrut),
      reductionLivraisonPct: reductionPct,
      totalReductionF: somme((d) => d.reductionFideliteF),
      totalLivraisons: somme((d) => d.fraisLivraison),
      totalSupplementsHorsZone: somme((d) => d.supplementHorsZone),
      totalFraisPaiement: somme((d) => d.fraisPaiement),
      // Le total payé = somme des totaux par boutique (cohérent avec les
      // sous-commandes, au franc près — plus de double arrondi global).
      totalPaye: somme((d) => d.totalClient),
      fraisBase: fraisBase,
      rayonZoneKm: rayonZoneKm,
      supplementHorsZone: supplementHZ,
      commissionPct: commissionPct,
      fraisMoMoPct: fraisMoMoPct,
      gainLivreurPct: gainLivreurPct,
    );
  }
}
