import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/abonnements.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/services/log_service.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// ABONNEMENTS — décision du 03/11/2026 : souscription DANS L'APP,
/// paiement par TRANSFERT MoMo/OM DÉCLARÉ, vérification par le staff,
/// activation AUTOMATIQUE à la validation.
///
/// Flux :
///   1. l'abonné choisit un plan → transfère le prix sur le numéro de la
///      plateforme → déclare la référence du SMS → `demander()` crée
///      `abonnements_demandes/{id}` (statut `a_verifier`) ;
///   2. le staff « paiements » compare la référence au SMS reçu →
///      `valider()` écrit le plan et `abonnementFinLe` sur la fiche
///      (boutique / couturier / livreur / utilisateur), trace une
///      `transactions`, notifie ; ou `refuser()`.
///
/// UNE source par profil pour le plan actif — celle que le reste de l'app
/// LIT déjà :
///   boutique  → boutiques/{id}  : `abonnement`, `abonnementFinLe`
///               (CommissionBoutiqueService.abonnementDe, devis, HD photos)
///   couturier → couturiers/{id} : `typeAbonnement`, `abonnementFinLe`
///               (commission couture, limite de modèles, négociation)
///   livreur   → livreurs/{id}   : `abonnementLivreur`, `abonnementFinLe`
///               (ParametresService.partLivreurEffective : bonus de part)
///   client    → utilisateurs/{uid} : `abonnementClient`, `abonnementFinLe`
///               (panier : paiement en espèces à la livraison)
/// Les champs sont protégés par les règles : seul le staff les écrit.
///
/// Avant : trois fonctions « souscrire » simulaient un paiement MoMo et
/// écrivaient le plan directement depuis le téléphone de l'abonné (gratuit
/// avec une app modifiée ; refusé par les règles pour couturiers/livreurs ;
/// boutique ciblée par l'id UTILISATEUR, donc fiche inexistante), plus un
/// second écran couturier qui activait un plan payant sans paiement.
/// ═══════════════════════════════════════════════════════════════════════

enum ProfilAbonnement { boutique, couturier, livreur, client }

extension ProfilAbonnementX on ProfilAbonnement {
  String get libelle => switch (this) {
        ProfilAbonnement.boutique => 'Boutique',
        ProfilAbonnement.couturier => 'Couturier',
        ProfilAbonnement.livreur => 'Livreur',
        ProfilAbonnement.client => 'Client',
      };
  String get collection => switch (this) {
        ProfilAbonnement.boutique => 'boutiques',
        ProfilAbonnement.couturier => 'couturiers',
        ProfilAbonnement.livreur => 'livreurs',
        ProfilAbonnement.client => 'utilisateurs',
      };
  /// Champ qui porte le plan actif sur la fiche.
  String get champPlan => switch (this) {
        ProfilAbonnement.boutique => 'abonnement',
        ProfilAbonnement.couturier => 'typeAbonnement',
        ProfilAbonnement.livreur => 'abonnementLivreur',
        ProfilAbonnement.client => 'abonnementClient',
      };
}

/// Un plan tel que proposé à l'abonné : seuls les avantages RÉELLEMENT
/// appliqués par le code figurent dans `avantages` (loi 2010/021 art. 15 :
/// information exacte sur ce qui est vendu).
class PlanAbonnement {
  final ProfilAbonnement profil;
  final String id;          // valeur écrite dans le champ plan
  final String nom;
  final double prix;        // FCFA pour `dureeJours` ; 0 = gratuit
  final int dureeJours;
  final List<String> avantages;
  final Color couleur;
  final IconData icone;
  const PlanAbonnement({
    required this.profil,
    required this.id,
    required this.nom,
    required this.prix,
    required this.dureeJours,
    required this.avantages,
    required this.couleur,
    required this.icone,
  });
  bool get gratuit => prix <= 0;
  String get prixFmt =>
      gratuit ? 'Gratuit' : '${PrixFCFA.formater(prix)} / $dureeJours j';
}

/// Plan actif d'une fiche (tel que lu par le reste de l'app).
class AbonnementActuel {
  final String planId;      // 'gratuit' / 'aucun' si rien
  final DateTime? finLe;
  const AbonnementActuel({required this.planId, this.finLe});
  bool get actif =>
      planId != 'gratuit' &&
      planId != 'aucun' &&
      planId.isNotEmpty &&
      (finLe == null || finLe!.isAfter(DateTime.now()));
  String get finFmt => finLe == null
      ? ''
      : '${finLe!.day.toString().padLeft(2, '0')}/${finLe!.month.toString().padLeft(2, '0')}/${finLe!.year}';
}

class DemandeAbonnement {
  final String id;
  final ProfilAbonnement profil;
  final String entiteId;
  final String entiteNom;
  final String utilisateurId;
  final String planId;
  final String planNom;
  final double prix;
  final int dureeJours;
  final String refPaiement;
  final String numeroPaiement;
  final String statut; // a_verifier | validee | refusee
  final DateTime? dateCreation;
  final String? motifRefus;
  const DemandeAbonnement({
    required this.id,
    required this.profil,
    required this.entiteId,
    required this.entiteNom,
    required this.utilisateurId,
    required this.planId,
    required this.planNom,
    required this.prix,
    required this.dureeJours,
    required this.refPaiement,
    required this.numeroPaiement,
    required this.statut,
    required this.dateCreation,
    this.motifRefus,
  });

  factory DemandeAbonnement.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return DemandeAbonnement(
      id: d.id,
      profil: ProfilAbonnement.values.firstWhere(
          (p) => p.name == (m['profil'] as String? ?? ''),
          orElse: () => ProfilAbonnement.client),
      entiteId: m['entiteId'] as String? ?? '',
      entiteNom: m['entiteNom'] as String? ?? '',
      utilisateurId: m['utilisateurId'] as String? ?? '',
      planId: m['planId'] as String? ?? '',
      planNom: m['planNom'] as String? ?? '',
      prix: (m['prix'] as num?)?.toDouble() ?? 0,
      dureeJours: (m['dureeJours'] as num?)?.toInt() ?? 30,
      refPaiement: m['refPaiement'] as String? ?? '',
      numeroPaiement: m['numeroPaiement'] as String? ?? '',
      statut: m['statut'] as String? ?? 'a_verifier',
      dateCreation: (m['dateCreation'] as Timestamp?)?.toDate(),
      motifRefus: m['motifRefus'] as String?,
    );
  }
}

class AbonnementService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get demandes =>
      _db.collection('abonnements_demandes');

  // ── CATALOGUE : avantages = ce que le code applique, rien d'autre ──

  static Future<List<PlanAbonnement>> plans(ProfilAbonnement profil) async {
    final duree = await ParametresService.abonnementDureeJours();
    switch (profil) {
      case ProfilAbonnement.boutique:
        final defaut = await ParametresService.commissionDefautPct();
        final contact = await ParametresService.abonnementDebloqueContact();
        return [
          for (final a in AbonnementBoutique.catalogue.values)
            PlanAbonnement(
              profil: profil,
              id: a.type.name,
              nom: a.nom,
              prix: a.prixMensuel,
              dureeJours: duree,
              couleur: a.couleur,
              icone: a.icone,
              avantages: [
                'Commission ${_pct(a.prixMensuel == 0 ? defaut : a.tauxCommission)} sur chaque vente',
                if (a.prixMensuel > 0) 'Photos en haute définition',
                if (a.prixMensuel > 0 && contact)
                  'Numéro de téléphone visible par les clients',
              ],
            ),
        ];
      case ProfilAbonnement.couturier:
        final defaut = await ParametresService.commissionCouturePct();
        final contact = await ParametresService.abonnementDebloqueContact();
        return [
          for (final a in AbonnementCouturier.catalogue.values)
            PlanAbonnement(
              profil: profil,
              id: a.type.name,
              nom: a.nom,
              prix: a.prixMensuel,
              dureeJours: duree,
              couleur: const Color(0xFF00897B),
              icone: Icons.content_cut,
              avantages: [
                'Commission ${_pct(a.prixMensuel == 0 ? defaut : a.tauxCommission)} sur chaque confection',
                a.limiteModeles >= 999
                    ? 'Modèles publiés illimités'
                    : 'Jusqu\'à ${a.limiteModeles} modèles publiés',
                if (a.negociationAutorisee)
                  'Modèles « sur devis » (négociation du prix)',
                if (a.prixMensuel > 0 && contact)
                  'Numéro de téléphone visible par les clients',
              ],
            ),
        ];
      case ProfilAbonnement.livreur:
        final prix = await ParametresService.abonnementLivreurPrix();
        final bonus = await ParametresService.livreurBonusAboPct();
        if (prix <= 0) return const [];
        return [
          PlanAbonnement(
            profil: profil,
            id: 'pro',
            nom: 'Livreur abonné',
            prix: prix,
            dureeJours: duree,
            couleur: const Color(0xFF1D9E75),
            icone: Icons.delivery_dining,
            avantages: [
              '+${_pct(bonus)} de part sur chaque course livrée',
            ],
          ),
        ];
      case ProfilAbonnement.client:
        final prix = await ParametresService.abonnementClientPrix();
        if (prix <= 0) return const [];
        return [
          PlanAbonnement(
            profil: profil,
            id: 'fidele',
            nom: 'Client abonné',
            prix: prix,
            dureeJours: duree,
            couleur: const Color(0xFF6A1B9A),
            icone: Icons.verified_user_outlined,
            avantages: const [
              'Paiement en espèces à la livraison',
            ],
          ),
        ];
    }
  }

  static String _pct(double v) =>
      '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)} %';

  // ── FICHE : quelle fiche porte l'abonnement de cet utilisateur ? ──

  /// Fiches (id, nom) de l'utilisateur pour ce profil : un gérant peut
  /// avoir plusieurs boutiques ; couturier/livreur/client en ont une.
  static Future<List<(String, String)>> fiches(
      ProfilAbonnement profil, String uid) async {
    try {
      switch (profil) {
        case ProfilAbonnement.boutique:
          final q = await _db
              .collection('boutiques')
              .where('gerants', arrayContains: uid)
              .get();
          return [
            for (final d in q.docs)
              (d.id, d.data()['nom'] as String? ?? 'Boutique')
          ];
        case ProfilAbonnement.couturier:
        case ProfilAbonnement.livreur:
          final q = await _db
              .collection(profil.collection)
              .where('utilisateurId', isEqualTo: uid)
              .limit(1)
              .get();
          return [
            for (final d in q.docs)
              (
                d.id,
                '${d.data()['prenom'] ?? ''} ${d.data()['nom'] ?? ''}'.trim()
              )
          ];
        case ProfilAbonnement.client:
          return [(uid, 'Mon compte')];
      }
    } catch (_) {
      return const [];
    }
  }

  /// Plan actif d'une fiche — lu EXACTEMENT comme le reste de l'app.
  static Future<AbonnementActuel> actuel(
      ProfilAbonnement profil, String entiteId) async {
    try {
      final d = await _db.collection(profil.collection).doc(entiteId).get();
      final m = d.data() ?? {};
      final brut = m[profil.champPlan];
      final planId = brut is String
          ? brut
          : (brut == true ? 'pro' : (profil == ProfilAbonnement.client ||
                  profil == ProfilAbonnement.livreur
              ? 'aucun'
              : 'gratuit'));
      return AbonnementActuel(
        planId: planId,
        finLe: (m['abonnementFinLe'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return const AbonnementActuel(planId: 'aucun');
    }
  }

  // ── DEMANDE (abonné) ──

  static Future<String> demander({
    required PlanAbonnement plan,
    required String entiteId,
    required String entiteNom,
    required String utilisateurId,
    required String refPaiement,
    required String numeroPaiement,
  }) async {
    final ref = await demandes.add({
      'profil': plan.profil.name,
      'entiteId': entiteId,
      'entiteNom': entiteNom,
      'utilisateurId': utilisateurId,
      'planId': plan.id,
      'planNom': plan.nom,
      'prix': plan.prix,
      'dureeJours': plan.dureeJours,
      'refPaiement': refPaiement.trim(),
      'numeroPaiement': numeroPaiement.trim(),
      'methodePaiement': plan.gratuit ? 'aucun' : 'momo_declare',
      'statut': 'a_verifier',
      'dateCreation': FieldValue.serverTimestamp(),
    });
    await LogService.log('abonnement_demande', details: {
      'demandeId': ref.id,
      'profil': plan.profil.name,
      'planId': plan.id,
      'prix': plan.prix,
    });
    return ref.id;
  }

  /// Demandes de l'utilisateur (toutes, récentes d'abord — tri côté app,
  /// sans index composite).
  static Stream<List<DemandeAbonnement>> mesDemandes(String uid) => demandes
      .where('utilisateurId', isEqualTo: uid)
      .snapshots()
      .map((s) {
        final l = s.docs.map(DemandeAbonnement.fromDoc).toList();
        l.sort((a, b) => (b.dateCreation ?? DateTime(0))
            .compareTo(a.dateCreation ?? DateTime(0)));
        return l;
      });

  // ── VÉRIFICATION (staff « paiements ») ──

  static Stream<List<DemandeAbonnement>> aVerifier() => demandes
      .where('statut', isEqualTo: 'a_verifier')
      .limit(100)
      .snapshots()
      .map((s) {
        final l = s.docs.map(DemandeAbonnement.fromDoc).toList();
        l.sort((a, b) => (a.dateCreation ?? DateTime(0))
            .compareTo(b.dateCreation ?? DateTime(0)));
        return l;
      });

  /// Active le plan : fin = (fin actuelle si même plan encore actif, sinon
  /// maintenant) + durée. Trace la transaction, clôt la demande, notifie.
  static Future<void> valider(DemandeAbonnement d, String staffId) async {
    final ficheRef = _db.collection(d.profil.collection).doc(d.entiteId);
    final now = DateTime.now();
    await _db.runTransaction((tx) async {
      final dem = await tx.get(demandes.doc(d.id));
      if (dem.data()?['statut'] != 'a_verifier') {
        throw Exception('Demande déjà traitée');
      }
      final fiche = await tx.get(ficheRef);
      if (!fiche.exists) throw Exception('Fiche introuvable (${d.entiteId})');
      final m = fiche.data() ?? {};
      final finActuelle = (m['abonnementFinLe'] as Timestamp?)?.toDate();
      final memePlan = m[d.profil.champPlan] == d.planId;
      final depart = (memePlan && finActuelle != null && finActuelle.isAfter(now))
          ? finActuelle
          : now;
      final finLe = d.prix <= 0
          ? null // plan gratuit : pas d'échéance
          : depart.add(Duration(days: d.dureeJours));

      final maj = <String, dynamic>{
        d.profil.champPlan: d.planId,
        'abonnementFinLe': finLe == null ? null : Timestamp.fromDate(finLe),
      };
      if (d.profil == ProfilAbonnement.boutique) {
        final type = TypeAbonnementBoutique.values.firstWhere(
            (t) => t.name == d.planId,
            orElse: () => TypeAbonnementBoutique.gratuit);
        maj['tauxCommission'] = AbonnementBoutique.catalogue[type]!.tauxCommission;
      }
      tx.update(ficheRef, maj);

      if (d.prix > 0) {
        final txRef = _db.collection('transactions').doc();
        tx.set(txRef, {
          'id': txRef.id,
          'type': 'abonnement',
          'entiteType': d.profil.name,
          'entiteId': d.entiteId,
          'clientId': d.utilisateurId,
          'demandeId': d.id,
          'montant': d.prix,
          'montantBrut': d.prix,
          'montantNet': d.prix,
          'description': 'Abonnement ${d.profil.libelle} ${d.planNom} (${d.dureeJours} j)',
          'methodePaiement': 'momo_declare',
          'referenceTransaction': d.refPaiement,
          'statut': 'confirmee',
          'dateCreation': Timestamp.fromDate(now),
          'dateConfirmation': Timestamp.fromDate(now),
          'valideePar': staffId,
        });
      }
      tx.update(demandes.doc(d.id), {
        'statut': 'validee',
        'valideeLe': FieldValue.serverTimestamp(),
        'valideePar': staffId,
        'abonnementFinLe': finLe == null ? null : Timestamp.fromDate(finLe),
      });
    });
    await LogService.log('abonnement_valide', details: {
      'demandeId': d.id,
      'profil': d.profil.name,
      'planId': d.planId,
      'prix': d.prix,
    });
    await NotificationService.envoyer(
      destinataireId: d.utilisateurId,
      titre: 'Abonnement activé ✅',
      message: d.prix > 0
          ? 'Votre abonnement ${d.planNom} est actif pour ${d.dureeJours} jours.'
          : 'Votre plan ${d.planNom} est actif.',
      route: '/abonnements',
    );
  }

  static Future<void> refuser(
      DemandeAbonnement d, String staffId, String motif) async {
    await demandes.doc(d.id).update({
      'statut': 'refusee',
      'refuseeLe': FieldValue.serverTimestamp(),
      'refuseePar': staffId,
      'motifRefus': motif.trim(),
    });
    await LogService.log('abonnement_refuse',
        details: {'demandeId': d.id, 'motif': motif});
    await NotificationService.envoyer(
      destinataireId: d.utilisateurId,
      titre: 'Abonnement non validé',
      message: motif.trim().isEmpty
          ? 'Le transfert déclaré n\'a pas pu être vérifié. Contactez-nous.'
          : motif.trim(),
      route: '/abonnements',
    );
  }
}
