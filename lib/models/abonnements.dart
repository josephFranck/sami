import 'package:cloud_firestore/cloud_firestore.dart';
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

// ─── Abonnement Livreur ───────────────────────────────────────────────────────

enum TypeAbonnementLivreur { moto, tricycle, voiture, vip }

class AbonnementLivreur {
  final TypeAbonnementLivreur type;
  final String nom;
  final double fraisInscription;     // unique à l'inscription
  final double prixMensuel;
  final int livraisonsMaxParJour;    // -1 = illimité
  final double gainParLivraison;     // FCFA garanti
  final double bonusPonctualite;     // bonus si <30min
  final double rayon;                // km de rayon max
  final bool assuranceMarchandise;
  final bool prioriteAssignation;    // 1er servi
  final List<String> avantages;
  final Color couleur;
  final IconData icone;

  const AbonnementLivreur({
    required this.type,
    required this.nom,
    required this.fraisInscription,
    required this.prixMensuel,
    required this.livraisonsMaxParJour,
    required this.gainParLivraison,
    required this.bonusPonctualite,
    required this.rayon,
    this.assuranceMarchandise = false,
    this.prioriteAssignation = false,
    required this.avantages,
    required this.couleur,
    required this.icone,
  });

  String get prixFmt =>
      prixMensuel == 0 ? 'Gratuit' : '${PrixFCFA.formater(prixMensuel)}/mois';

  static const Map<TypeAbonnementLivreur, AbonnementLivreur> catalogue = {
    TypeAbonnementLivreur.moto: AbonnementLivreur(
      type: TypeAbonnementLivreur.moto,
      nom: 'Moto-taxi',
      fraisInscription: 1000,
      prixMensuel: 0,
      livraisonsMaxParJour: 15,
      gainParLivraison: 350,
      bonusPonctualite: 100,
      rayon: 10,
      avantages: [
        'Frais inscription : 1 000 FCFA (unique)',
        '350 FCFA par livraison',
        '+ 100 FCFA si livré en <30 min',
        'Rayon 10 km autour de Garoua',
        'Jusqu\'à 15 livraisons/jour',
      ],
      couleur: Color(0xFF378ADD),
      icone: Icons.delivery_dining,
    ),
    TypeAbonnementLivreur.tricycle: AbonnementLivreur(
      type: TypeAbonnementLivreur.tricycle,
      nom: 'Tricycle (Kéké)',
      fraisInscription: 1500,
      prixMensuel: 0,
      livraisonsMaxParJour: 20,
      gainParLivraison: 400,
      bonusPonctualite: 150,
      rayon: 15,
      assuranceMarchandise: true,
      avantages: [
        'Frais inscription : 1 500 FCFA (unique)',
        '400 FCFA par livraison',
        '+ 150 FCFA si livré en <45 min',
        'Rayon 15 km, colis volumineux',
        'Assurance marchandise incluse',
        'Jusqu\'à 20 livraisons/jour',
      ],
      couleur: Color(0xFFFF8F00),
      icone: Icons.electric_rickshaw,
    ),
    TypeAbonnementLivreur.voiture: AbonnementLivreur(
      type: TypeAbonnementLivreur.voiture,
      nom: 'Voiture',
      fraisInscription: 2000,
      prixMensuel: 2000,
      livraisonsMaxParJour: -1,
      gainParLivraison: 600,
      bonusPonctualite: 200,
      rayon: 50,
      assuranceMarchandise: true,
      prioriteAssignation: true,
      avantages: [
        'Frais inscription : 2 000 FCFA',
        '2 000 FCFA/mois',
        '600 FCFA par livraison',
        '+ 200 FCFA bonus ponctualité',
        'Rayon 50 km (hors ville)',
        'Priorité d\'assignation',
        'Livraisons illimitées',
        'Assurance marchandise',
      ],
      couleur: Color(0xFF1D9E75),
      icone: Icons.local_shipping_outlined,
    ),
    TypeAbonnementLivreur.vip: AbonnementLivreur(
      type: TypeAbonnementLivreur.vip,
      nom: 'Livreur VIP',
      fraisInscription: 3000,
      prixMensuel: 5000,
      livraisonsMaxParJour: -1,
      gainParLivraison: 800,
      bonusPonctualite: 300,
      rayon: 100,
      assuranceMarchandise: true,
      prioriteAssignation: true,
      avantages: [
        'Frais inscription : 3 000 FCFA',
        '5 000 FCFA/mois',
        '800 FCFA par livraison',
        '+ 300 FCFA bonus',
        'Rayon illimité',
        '1er servi sur toutes les commandes',
        'Badge "Livreur VIP" visible',
        'Support dédié',
      ],
      couleur: Color(0xFFBA7517),
      icone: Icons.verified_outlined,
    ),
  };
}

// ─── Offres de crédits (ACHAT) : SUPPRIMÉES ─────────────────────────────────
// Décision 03/11/2026 : les crédits sont des AVOIRS (remboursements,
// cashback, parrainage), jamais achetés. `OffreCredit`, son catalogue et la
// collection `config_credits` n'ont plus d'écran.

// ─── Profil abonnement boutique ───────────────────────────────────────────────

class ProfilAbonnementBoutique {
  final String boutiqueId;
  final TypeAbonnementBoutique typeAbonnement;
  final DateTime? dateAbonnement;
  final DateTime? expireAbonnement;
  final bool abonnementActif;
  final double creditBalance;
  final int ventesTotal;
  final double gainsTotal;
  final double commissionsPayees;

  ProfilAbonnementBoutique({
    required this.boutiqueId,
    required this.typeAbonnement,
    this.dateAbonnement,
    this.expireAbonnement,
    required this.abonnementActif,
    this.creditBalance = 0,
    this.ventesTotal = 0,
    this.gainsTotal = 0,
    this.commissionsPayees = 0,
  });

  AbonnementBoutique get abonnement =>
      AbonnementBoutique.catalogue[typeAbonnement] ?? AbonnementBoutique.defaut();

  bool get estExpire =>
      expireAbonnement != null && DateTime.now().isAfter(expireAbonnement!);

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('profils_boutique');

  factory ProfilAbonnementBoutique.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ProfilAbonnementBoutique(
      boutiqueId: doc.id,
      typeAbonnement: TypeAbonnementBoutique.values.firstWhere((e) => e.name == (d['typeAbonnement'] as String? ?? 'gratuit'), orElse: () => TypeAbonnementBoutique.values.first),
      dateAbonnement: (d['dateAbonnement'] as Timestamp?)?.toDate(),
      expireAbonnement: (d['expireAbonnement'] as Timestamp?)?.toDate(),
      abonnementActif: d['abonnementActif'] as bool? ?? true,
      creditBalance: (d['creditBalance'] as num?)?.toDouble() ?? 0,
      ventesTotal: d['ventesTotal'] as int? ?? 0,
      gainsTotal: (d['gainsTotal'] as num?)?.toDouble() ?? 0,
      commissionsPayees: (d['commissionsPayees'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'boutiqueId': boutiqueId,
    'typeAbonnement': typeAbonnement.name,
    'dateAbonnement': dateAbonnement,
    'expireAbonnement': expireAbonnement,
    'abonnementActif': abonnementActif,
    'creditBalance': creditBalance,
    'ventesTotal': ventesTotal,
    'gainsTotal': gainsTotal,
    'commissionsPayees': commissionsPayees,
  };
}
