import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/commande_multi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE D'ANALYSE BUSINESS (boutiquier)
//
// Calcule les indicateurs clés à partir des sous-commandes d'une boutique :
//   - Chiffre d'affaires, net encaissé, commissions versées
//   - Nombre de ventes, panier moyen, taux d'annulation
//   - Produits les plus vendus
//   - Évolution sur les N derniers jours
//   - Recommandations automatiques (stock, prix, tendances)
//
// Tous les calculs sont faits côté client à partir d'une seule lecture
// Firestore (pas d'index composite requis).
// ═══════════════════════════════════════════════════════════════════════════

/// Indicateurs agrégés d'une boutique sur une période.
class IndicateursBoutique {
  final int nbVentes;              // sous-commandes terminées
  final int nbCommandesTotal;      // toutes (y compris en cours/annulées)
  final int nbAnnulees;
  final double chiffreAffaires;    // somme des totalClient terminés
  final double netEncaisse;        // somme des netBoutique terminés
  final double commissionsVersees; // somme des commissions
  final double panierMoyen;        // CA / nbVentes
  final double tauxAnnulation;     // % annulées / total
  final List<ProduitVendu> topProduits;
  final List<PointVente> evolution; // ventes par jour
  final List<String> recommandations;

  IndicateursBoutique({
    required this.nbVentes,
    required this.nbCommandesTotal,
    required this.nbAnnulees,
    required this.chiffreAffaires,
    required this.netEncaisse,
    required this.commissionsVersees,
    required this.panierMoyen,
    required this.tauxAnnulation,
    required this.topProduits,
    required this.evolution,
    required this.recommandations,
  });

  factory IndicateursBoutique.vide() => IndicateursBoutique(
        nbVentes: 0,
        nbCommandesTotal: 0,
        nbAnnulees: 0,
        chiffreAffaires: 0,
        netEncaisse: 0,
        commissionsVersees: 0,
        panierMoyen: 0,
        tauxAnnulation: 0,
        topProduits: const [],
        evolution: const [],
        recommandations: const [],
      );
}

class ProduitVendu {
  final String pagneId;
  final String nom;
  final int quantite;
  final double montant;
  ProduitVendu(this.pagneId, this.nom, this.quantite, this.montant);
}

class PointVente {
  final DateTime jour;
  final double montant;
  final int nb;
  PointVente(this.jour, this.montant, this.nb);
}

class AnalyseService {
  static final _db = FirebaseFirestore.instance;

  /// Calcule les indicateurs d'une boutique sur les [jours] derniers jours.
  static Future<IndicateursBoutique> indicateurs(
    String boutiqueId, {
    int jours = 30,
  }) async {
    final depuis = DateTime.now().subtract(Duration(days: jours));

    // Une seule requête simple (pas d'index composite)
    final snap = await _db
        .collection('sous_commandes')
        .where('boutiqueId', isEqualTo: boutiqueId)
        .get();

    final toutes = snap.docs
        .map((d) => SousCommande.fromDoc(d))
        .where((sc) => sc.dateCreation.isAfter(depuis))
        .toList();

    if (toutes.isEmpty) return IndicateursBoutique.vide();

    final terminees = toutes
        .where((sc) => sc.statut == StatutSousCommande.terminee.name)
        .toList();
    final annulees = toutes
        .where((sc) => sc.statut == StatutSousCommande.annulee.name)
        .toList();

    final ca = terminees.fold<double>(0, (s, sc) => s + sc.totalClient);
    final net = terminees.fold<double>(0, (s, sc) => s + sc.netBoutique);
    final commissions =
        terminees.fold<double>(0, (s, sc) => s + sc.commissionPlateforme);
    final panierMoyen = terminees.isEmpty ? 0.0 : ca / terminees.length;
    final tauxAnnul =
        toutes.isEmpty ? 0.0 : (annulees.length / toutes.length) * 100;

    return IndicateursBoutique(
      nbVentes: terminees.length,
      nbCommandesTotal: toutes.length,
      nbAnnulees: annulees.length,
      chiffreAffaires: ca,
      netEncaisse: net,
      commissionsVersees: commissions,
      panierMoyen: panierMoyen,
      tauxAnnulation: tauxAnnul,
      topProduits: _calculerTopProduits(terminees),
      evolution: _calculerEvolution(terminees, jours),
      recommandations:
          _genererRecommandations(terminees, annulees, toutes, tauxAnnul),
    );
  }

  // Produits les plus vendus (agrégation des articles)
  static List<ProduitVendu> _calculerTopProduits(List<SousCommande> ventes) {
    final map = <String, ProduitVendu>{};
    for (final sc in ventes) {
      for (final art in sc.articles) {
        final existant = map[art.pagneId];
        if (existant == null) {
          map[art.pagneId] = ProduitVendu(
              art.pagneId, art.pagneNom, art.quantite,
              art.prixUnitaire * art.quantite);
        } else {
          map[art.pagneId] = ProduitVendu(
            art.pagneId,
            art.pagneNom,
            existant.quantite + art.quantite,
            existant.montant + art.prixUnitaire * art.quantite,
          );
        }
      }
    }
    final liste = map.values.toList()
      ..sort((a, b) => b.quantite.compareTo(a.quantite));
    return liste.take(5).toList();
  }

  // Évolution des ventes jour par jour
  static List<PointVente> _calculerEvolution(
      List<SousCommande> ventes, int jours) {
    final parJour = <String, PointVente>{};
    for (final sc in ventes) {
      final d = sc.dateCreation;
      final cle = '${d.year}-${d.month}-${d.day}';
      final existant = parJour[cle];
      final jour = DateTime(d.year, d.month, d.day);
      if (existant == null) {
        parJour[cle] = PointVente(jour, sc.totalClient, 1);
      } else {
        parJour[cle] =
            PointVente(jour, existant.montant + sc.totalClient, existant.nb + 1);
      }
    }
    final liste = parJour.values.toList()
      ..sort((a, b) => a.jour.compareTo(b.jour));
    return liste;
  }

  // Recommandations automatiques basées sur les données
  static List<String> _genererRecommandations(
    List<SousCommande> terminees,
    List<SousCommande> annulees,
    List<SousCommande> toutes,
    double tauxAnnul,
  ) {
    final reco = <String>[];

    if (terminees.isEmpty) {
      reco.add(
          'Aucune vente terminée sur la période. Vérifiez vos prix et la disponibilité de vos pagnes.');
      return reco;
    }

    // Taux d'annulation élevé
    if (tauxAnnul > 20) {
      reco.add(
          'Taux d\'annulation élevé (${tauxAnnul.toStringAsFixed(0)}%). Vérifiez vos délais de préparation et la disponibilité réelle de vos articles.');
    }

    // Produit star
    final top = _calculerTopProduits(terminees);
    if (top.isNotEmpty) {
      reco.add(
          'Votre meilleure vente : "${top.first.nom}" (${top.first.quantite} vendus). Assurez-vous d\'avoir suffisamment de stock.');
    }

    // Tendance récente (7 derniers jours vs précédents)
    final now = DateTime.now();
    final recentes = terminees
        .where((sc) => now.difference(sc.dateCreation).inDays <= 7)
        .length;
    final anterieures = terminees.length - recentes;
    if (anterieures > 0 && recentes > anterieures) {
      reco.add(
          'Vos ventes sont en hausse cette semaine. C\'est le bon moment pour ajouter du stock ou de nouveaux modèles.');
    } else if (recentes == 0 && terminees.isNotEmpty) {
      reco.add(
          'Aucune vente cette semaine. Pensez à une promotion ou à mettre en avant vos pagnes phares.');
    }

    return reco;
  }
}
