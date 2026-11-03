import 'package:flutter/material.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME DE CRÉDITS & ABONNEMENTS — Tous rôles
//
// Rôles concernés :
//   Client      → crédits plateforme (cashback, parrainage, remboursements)
//   Boutiquier  → abonnement mensuel (réduit commission + augmente limites)
//   Couturier   → abonnement mensuel (déjà dans couture_options.dart)
//   Livreur     → inscription + abonnement (accès aux livraisons)
//
// Flux d'achat :
//   1. Client choisit offre → paye par MoMo
//   2. Webhook/confirmation → CreditService.crediter()
//   3. solde reflété dans Firestore (creditBalance)
//   4. Prochaine commande → peut payer par crédits
// ═══════════════════════════════════════════════════════════════════════════

// ─── Abonnement Boutiquier ────────────────────────────────────────────────────

enum TypeAbonnementBoutique { gratuit, standard, premium, enterprise }

class AbonnementBoutique {
  final TypeAbonnementBoutique type;
  final String nom;
  final double prixMensuel;
  final double tauxCommission;       // % sur chaque vente (débitée du crédit boutiquier)
  final bool commissionAvance;       // true = débit à la publication/vente ; false = à la livraison confirmée
  final double seuilCreditPublication; // crédit minimum requis pour publier un pagne
  final int limitePagesPagnes;       // nb de pagnes publiables
  final int limitePhotosParPagne;    // photos par pagne
  final bool boostMensuelInclus;
  final bool dashboardAvance;
  final bool supportPrioritaire;
  final bool accesAnalytics;
  final bool badgeVerifie;
  final List<String> avantages;
  final Color couleur;
  final IconData icone;

  const AbonnementBoutique({
    required this.type,
    required this.nom,
    required this.prixMensuel,
    required this.tauxCommission,
    this.commissionAvance = false,
    this.seuilCreditPublication = 0,
    required this.limitePagesPagnes,
    required this.limitePhotosParPagne,
    this.boostMensuelInclus = false,
    this.dashboardAvance = false,
    this.supportPrioritaire = false,
    this.accesAnalytics = false,
    this.badgeVerifie = false,
    required this.avantages,
    required this.couleur,
    required this.icone,
  });

  String get prixFmt =>
      prixMensuel == 0 ? 'Gratuit' : '${PrixFCFA.formater(prixMensuel)}/mois';

  static const Map<TypeAbonnementBoutique, AbonnementBoutique> catalogue = {
    TypeAbonnementBoutique.gratuit: AbonnementBoutique(
      type: TypeAbonnementBoutique.gratuit,
      nom: 'Débutant',
      prixMensuel: 0,
      tauxCommission: 8.0,
      commissionAvance: true,          // doit avoir le crédit AVANT de publier
      seuilCreditPublication: 2000,    // 2000 FCFA de crédit requis pour publier
      limitePagesPagnes: 10,
      limitePhotosParPagne: 2,
      couleur: Color(0xFF888780),
      icone: Icons.store_outlined,
      avantages: [
        'Jusqu\'à 10 pagnes publiés',
        '2 photos par pagne',
        'Commission 8% par vente',
        'Profil boutique visible',
      ],
    ),
    TypeAbonnementBoutique.standard: AbonnementBoutique(
      type: TypeAbonnementBoutique.standard,
      commissionAvance: true,
      seuilCreditPublication: 1000,
      nom: 'Commerçant',
      prixMensuel: 3000,
      tauxCommission: 6.0,
      limitePagesPagnes: 50,
      limitePhotosParPagne: 5,
      boostMensuelInclus: true,
      dashboardAvance: true,
      badgeVerifie: true,
      couleur: Color(0xFF534AB7),
      icone: Icons.storefront_outlined,
      avantages: [
        'Jusqu\'à 50 pagnes publiés',
        '5 photos par pagne',
        'Commission réduite à 6%',
        '1 boost mensuel gratuit',
        'Dashboard des ventes',
        'Badge "Boutique vérifiée"',
      ],
    ),
    TypeAbonnementBoutique.premium: AbonnementBoutique(
      type: TypeAbonnementBoutique.premium,
      commissionAvance: false,         // commission prélevée APRÈS livraison
      seuilCreditPublication: 0,       // publication libre
      nom: 'Marchand Pro',
      prixMensuel: 8000,
      tauxCommission: 4.5,
      limitePagesPagnes: 200,
      limitePhotosParPagne: 10,
      boostMensuelInclus: true,
      dashboardAvance: true,
      accesAnalytics: true,
      badgeVerifie: true,
      supportPrioritaire: true,
      couleur: Color(0xFFBA7517),
      icone: Icons.stars_outlined,
      avantages: [
        'Jusqu\'à 200 pagnes publiés',
        '10 photos + vidéo par pagne',
        'Commission réduite à 4.5%',
        '3 boosts mensuels gratuits',
        'Analytics marché complet',
        'Support prioritaire 24h',
        'Mise en avant dans les résultats',
      ],
    ),
    TypeAbonnementBoutique.enterprise: AbonnementBoutique(
      type: TypeAbonnementBoutique.enterprise,
      commissionAvance: false,
      seuilCreditPublication: 0,
      nom: 'Grossiste',
      prixMensuel: 20000,
      tauxCommission: 3.0,
      limitePagesPagnes: 99999,
      limitePhotosParPagne: 20,
      boostMensuelInclus: true,
      dashboardAvance: true,
      accesAnalytics: true,
      badgeVerifie: true,
      supportPrioritaire: true,
      couleur: Color(0xFF1D9E75),
      icone: Icons.business_outlined,
      avantages: [
        'Pagnes illimités',
        'Commission minimale 3%',
        'Boosts illimités',
        'API d\'intégration',
        'Gestionnaire de compte dédié',
        'Rapport mensuel personnalisé',
      ],
    ),
  };

  static AbonnementBoutique defaut() =>
      catalogue[TypeAbonnementBoutique.gratuit]!;
}

// ─── Abonnement Livreur : catalogue « véhicules » SUPPRIMÉ ──────────────────
// Il promettait des gains par course (350/400/600/800 F), une assurance et
// une priorité d'assignation qu'aucun code n'appliquait ; le type de
// véhicule est déjà saisi à la candidature. Le plan livreur réel (bonus de
// part `livreurBonusAbo`, prix `abonnementLivreurPrix`) vit dans
// AbonnementService.

// ─── Offres de crédits (ACHAT) : SUPPRIMÉES ─────────────────────────────────
// Décision 03/11/2026 : les crédits sont des AVOIRS (remboursements,
// cashback, parrainage), jamais achetés. `OffreCredit`, son catalogue et la
// collection `config_credits` n'ont plus d'écran.

// ─── Profil abonnement boutique (`profils_boutique`) : SUPPRIMÉ ─────────────
// Doublon jamais lu par le reste de l'app : le plan actif d'une boutique est
// `boutiques/{id}.abonnement` + `abonnementFinLe` (AbonnementService).
