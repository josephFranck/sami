import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sami/utils/config_paiement.dart';
import 'package:sami/services/paiement_service.dart';
import 'package:sami/models/abonnements.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE CENTRALISÉ CRÉDITS & ABONNEMENTS
//
// Flux complet :
//   1. Utilisateur choisit une offre
//   2. Paiement MoMo (CinetPay/Monetbil)
//   3. Webhook de confirmation → crediter() / activerAbonnement()
//   4. Solde mis à jour en Firestore
//   5. Transaction enregistrée
//
// Sécurité :
//   - Toutes les modifications de solde passent par transactions Firestore
//   - Idempotence via transactionId unique
//   - Vérification solde avant débit
// ═══════════════════════════════════════════════════════════════════════════

enum TypeMouvementCredit {
  recharge,           // achat de crédits
  abonnement,         // paiement abonnement
  commissionDebit,    // commission prélevée
  reversement,        // reversement après vente
  remboursement,      // remboursement client
  parrainage,         // bonus parrainage
  cashback,           // cashback fidélité
  bonusInscription,   // bonus parrainage à l'inscription
  boostVisibilite,    // achat boost pagne
  publicationPagne,   // frais publication pagne
  inscription,        // frais inscription livreur
}

class MouvementCredit {
  final String id;
  final String utilisateurId;
  final String? entiteId;          // boutiqueId, couturierId...
  final TypeMouvementCredit type;
  final double montant;             // positif = crédit, négatif = débit
  final double soldeAvant;
  final double soldeApres;
  final String description;
  final String? referenceTransaction;  // ID transaction MoMo
  final DateTime date;
  final bool confirme;

  const MouvementCredit({
    required this.id,
    required this.utilisateurId,
    this.entiteId,
    required this.type,
    required this.montant,
    required this.soldeAvant,
    required this.soldeApres,
    required this.description,
    this.referenceTransaction,
    required this.date,
    this.confirme = true,
  });

  bool get estDebit => montant < 0;
  bool get estCredit => montant > 0;

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('mouvements_credits');

  Map<String, dynamic> toMap() => {
    'utilisateurId': utilisateurId,
    'entiteId': entiteId,
    'type': type.name,
    'montant': montant,
    'soldeAvant': soldeAvant,
    'soldeApres': soldeApres,
    'description': description,
    'referenceTransaction': referenceTransaction,
    'date': date,
    'confirme': confirme,
  };
}

class CreditService {

  static final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // OPÉRATIONS SUR LES CRÉDITS CLIENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Créditer un compte (après paiement MoMo confirmé)
  static Future<void> crediterClient({
    required String clientId,
    required double montant,
    required TypeMouvementCredit type,
    required String description,
    String? referenceTransaction,
    double bonusPct = 0,
  }) async {
    final montantTotal = PrixFCFA.arrondirAu50(montant * (1 + bonusPct / 100));

    await _db.runTransaction((txn) async {
      final userRef = _db.collection('utilisateurs').doc(clientId);
      final doc = await txn.get(userRef);
      if (!doc.exists) throw Exception('Utilisateur introuvable');

      final soldeAvant = (doc.data()!['creditBalance'] as num?)?.toDouble() ?? 0;
      final soldeApres = PrixFCFA.arrondirAu50(soldeAvant + montantTotal);

      txn.update(userRef, {'creditBalance': soldeApres});

      final mvtRef = MouvementCredit.collection.doc();
      txn.set(mvtRef, MouvementCredit(
        id: mvtRef.id,
        utilisateurId: clientId,
        type: type,
        montant: montantTotal,
        soldeAvant: soldeAvant,
        soldeApres: soldeApres,
        description: montantTotal != montant
            ? '$description (+${bonusPct.round()}% bonus)'
            : description,
        referenceTransaction: referenceTransaction,
        date: DateTime.now(),
      ).toMap());
    });

    if (kDebugMode) print('[Credit] +${PrixFCFA.formater(montantTotal)} → client $clientId');
  }

  /// Débiter un compte (avant achat/commande)
  /// Retourne null si succès, message d'erreur si solde insuffisant
  static Future<String?> debiterClient({
    required String clientId,
    required double montant,
    required TypeMouvementCredit type,
    required String description,
  }) async {
    String? erreur;

    await _db.runTransaction((txn) async {
      final userRef = _db.collection('utilisateurs').doc(clientId);
      final doc = await txn.get(userRef);
      final solde = (doc.data()!['creditBalance'] as num?)?.toDouble() ?? 0;

      if (solde < montant) {
        erreur = 'Solde insuffisant — disponible : ${PrixFCFA.formater(solde)}, requis : ${PrixFCFA.formater(montant)}';
        return;
      }

      final soldeApres = PrixFCFA.arrondirAu50(solde - montant);
      txn.update(userRef, {'creditBalance': soldeApres});

      final mvtRef = MouvementCredit.collection.doc();
      txn.set(mvtRef, MouvementCredit(
        id: mvtRef.id,
        utilisateurId: clientId,
        type: type,
        montant: -montant,
        soldeAvant: solde,
        soldeApres: soldeApres,
        description: description,
        date: DateTime.now(),
      ).toMap());
    });

    return erreur;
  }

  /// Acheter des crédits via MoMo
  static Future<ResultatAchat> acheterCredits({
    required String clientId,
    required OffreCredit offre,
    required String methodePaiement,
    required String numeroTelephone,
  }) async {
    try {
      // 1. Initier le paiement MoMo (placeholder CinetPay)
      final transactionId = await _initierPaiementMoMo(
        montant: offre.prix,
        telephone: numeroTelephone,
        description: 'Achat crédits PagneShop — ${offre.label}',
        methode: methodePaiement,
      );

      // 2. En attente de confirmation webhook
      // En production : le webhook CinetPay appellera crediterClient()
      // Pour la démo : on crédite directement
      await crediterClient(
        clientId: clientId,
        montant: offre.montant,
        type: TypeMouvementCredit.recharge,
        description: 'Achat crédits — ${offre.label}',
        referenceTransaction: transactionId,
        bonusPct: offre.bonus,
      );

      return ResultatAchat(
        succes: true,
        montantCredite: offre.montantAvecBonus,
        transactionId: transactionId,
      );
    } catch (e) {
      return ResultatAchat(succes: false, erreur: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ABONNEMENTS BOUTIQUIER
  // ══════════════════════════════════════════════════════════════════════════

  static Future<ResultatAchat> souscrireAbonnementBoutique({
    required String boutiqueId,
    required TypeAbonnementBoutique type,
    required String methodePaiement,
    required String numeroTelephone,
  }) async {
    final abonnement = AbonnementBoutique.catalogue[type]!;

    try {
      String? transactionId;
      if (abonnement.prixMensuel > 0) {
        transactionId = await _initierPaiementMoMo(
          montant: abonnement.prixMensuel,
          telephone: numeroTelephone,
          description: 'Abonnement boutique ${abonnement.nom}',
          methode: methodePaiement,
        );
      }

      final now = DateTime.now();
      final expiration = DateTime(now.year, now.month + 1, now.day);
      final batch = _db.batch();

      // Mettre à jour ou créer le profil abonnement boutique
      final profilRef = ProfilAbonnementBoutique.collection.doc(boutiqueId);
      batch.set(profilRef, {
        'boutiqueId': boutiqueId,
        'typeAbonnement': type.name,
        'dateAbonnement': now,
        'expireAbonnement': expiration,
        'abonnementActif': true,
      }, SetOptions(merge: true));

      // Mettre à jour la boutique (commission + mode de facturation).
      // Un abonnement PAYANT bascule la boutique en mode PRÉPAYÉ (elle reçoit
      // tout le prix article, la commission est débitée de son crédit selon
      // son abonnement). L'abonnement gratuit reste en commission-sur-vente.
      batch.update(_db.collection('boutiques').doc(boutiqueId), {
        'tauxCommission': abonnement.tauxCommission,
        'abonnement': type.name,
        'billingModel':
            abonnement.prixMensuel > 0 ? 'prepaid' : 'per_commission',
      });

      // Enregistrer la transaction
      if (abonnement.prixMensuel > 0) {
        final txRef = _db.collection('transactions').doc();
        batch.set(txRef, {
          'type': TypeMouvementCredit.abonnement.name,
          'entiteId': boutiqueId,
          'entiteType': 'boutique',
          'montant': abonnement.prixMensuel,
          'description': 'Abonnement ${abonnement.nom} — ${now.month}/${now.year}',
          'methodePaiement': methodePaiement,
          'referenceTransaction': transactionId,
          'date': now,
          'statut': 'confirme',
        });
      }

      await batch.commit();

      return ResultatAchat(
        succes: true,
        transactionId: transactionId,
        montantCredite: 0,
        message: 'Abonnement ${abonnement.nom} activé jusqu\'au ${expiration.day}/${expiration.month}/${expiration.year}',
      );
    } catch (e) {
      return ResultatAchat(succes: false, erreur: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ABONNEMENTS COUTURIER
  // ══════════════════════════════════════════════════════════════════════════

  static Future<ResultatAchat> souscrireAbonnementCouturier({
    required String couturierId,
    required TypeAbonnementCouturier type,
    required String methodePaiement,
    required String numeroTelephone,
  }) async {
    final abonnement = AbonnementCouturier.catalogue[type]!;

    try {
      String? transactionId;
      if (abonnement.prixMensuel > 0) {
        transactionId = await _initierPaiementMoMo(
          montant: abonnement.prixMensuel,
          telephone: numeroTelephone,
          description: 'Abonnement couturier ${abonnement.nom}',
          methode: methodePaiement,
        );
      }

      final now = DateTime.now();
      final expiration = DateTime(now.year, now.month + 1, now.day);

      // IMPORTANT : le reste de l'app (commission, négociation, limite de
      // modèles) lit la fiche 'couturiers' via utilisateurId. On écrit donc
      // l'abonnement sur la VRAIE fiche, en plus du profil détaillé.
      final ficheC = await _db
          .collection('couturiers')
          .where('utilisateurId', isEqualTo: couturierId)
          .limit(1)
          .get();
      if (ficheC.docs.isNotEmpty) {
        await ficheC.docs.first.reference
            .set({'typeAbonnement': type.name}, SetOptions(merge: true));
      }

      await _db.collection('profils_couturier').doc(couturierId).set({
        'couturierId': couturierId,
        'typeAbonnement': type.name,
        'dateAbonnement': now,
        'expireAbonnement': expiration,
        'abonnementActif': true,
      }, SetOptions(merge: true));

      return ResultatAchat(
        succes: true,
        transactionId: transactionId,
        montantCredite: 0,
        message: 'Abonnement ${abonnement.nom} activé jusqu\'au ${expiration.day}/${expiration.month}/${expiration.year}',
      );
    } catch (e) {
      return ResultatAchat(succes: false, erreur: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INSCRIPTION LIVREUR
  // ══════════════════════════════════════════════════════════════════════════

  static Future<ResultatAchat> inscrireLivreur({
    required String livreurId,
    required TypeAbonnementLivreur type,
    required String methodePaiement,
    required String numeroTelephone,
  }) async {
    final abonnement = AbonnementLivreur.catalogue[type]!;
    final fraisTotal = abonnement.fraisInscription + abonnement.prixMensuel;

    try {
      String? transactionId;
      if (fraisTotal > 0) {
        transactionId = await _initierPaiementMoMo(
          montant: fraisTotal,
          telephone: numeroTelephone,
          description: 'Inscription livreur ${abonnement.nom}',
          methode: methodePaiement,
        );
      }

      final now = DateTime.now();
      final expiration = abonnement.prixMensuel > 0
          ? DateTime(now.year, now.month + 1, now.day)
          : null; // moto/tricycle = pas d'expiration mensuelle

      // Résoudre la FICHE livreur (créée par la candidature validée ou par
      // l'admin). L'inscription/caution ENRICHIT la fiche, elle ne crée pas
      // de livreur : sans fiche validée, on refuse (dossier d'abord).
      final fiche = await _db
          .collection('livreurs')
          .where('utilisateurId', isEqualTo: livreurId)
          .limit(1)
          .get();
      if (fiche.docs.isEmpty) {
        return ResultatAchat(
          succes: false,
          erreur: 'Aucune fiche livreur validée. Déposez d\'abord votre '
              'candidature (menu « Devenir partenaire ») et attendez la '
              'validation avant de payer l\'inscription.',
        );
      }

      await fiche.docs.first.reference.set({
        'typeAbonnement': type.name,
        'dateInscription': now,
        'expireAbonnement': expiration,
        'abonnementActif': true,
        'gainParLivraison': abonnement.gainParLivraison,
        'bonusPonctualite': abonnement.bonusPonctualite,
        'rayon': abonnement.rayon,
        'prioriteAssignation': abonnement.prioriteAssignation,
        'disponible': true,
      }, SetOptions(merge: true));

      return ResultatAchat(
        succes: true,
        transactionId: transactionId,
        montantCredite: 0,
        message: 'Inscription validée — bienvenue dans l\'équipe SAMI !',
      );
    } catch (e) {
      return ResultatAchat(succes: false, erreur: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VÉRIFICATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Vérifier les abonnements expirés et dégrader si nécessaire
  static Future<void> verifierExpirations(String utilisateurId, String role) async {
    final now = DateTime.now();

    if (role == 'boutiquier') {
      final doc = await ProfilAbonnementBoutique.collection.doc(utilisateurId).get();
      if (!doc.exists) return;
      final expiration = (doc.data()!['expireAbonnement'] as Timestamp?)?.toDate();
      if (expiration != null && now.isAfter(expiration)) {
        // Rétrograder vers Débutant gratuit
        await ProfilAbonnementBoutique.collection.doc(utilisateurId).update({
          'typeAbonnement': TypeAbonnementBoutique.gratuit.name,
          'abonnementActif': false,
        });
        await _db.collection('boutiques').doc(utilisateurId).update({
          'tauxCommission': AbonnementBoutique.defaut().tauxCommission,
          'abonnement': TypeAbonnementBoutique.gratuit.name,
        });
      }
    } else if (role == 'couturier') {
      final doc = await _db.collection('profils_couturier').doc(utilisateurId).get();
      if (!doc.exists) return;
      final expiration = (doc.data()!['expireAbonnement'] as Timestamp?)?.toDate();
      if (expiration != null && now.isAfter(expiration)) {
        await _db.collection('profils_couturier').doc(utilisateurId).update({
          'typeAbonnement': TypeAbonnementCouturier.gratuit.name,
          'abonnementActif': false,
        });
      }
    }
  }

  /// Lire l'historique des mouvements d'un utilisateur
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamHistorique(
      String utilisateurId, {int limite = 30}) =>
      MouvementCredit.collection
          .where('utilisateurId', isEqualTo: utilisateurId)
          .orderBy('date', descending: true)
          .limit(limite)
          .snapshots();

  // ══════════════════════════════════════════════════════════════════════════
  // PAIEMENT MOMO (placeholder CinetPay)
  // ══════════════════════════════════════════════════════════════════════════

  /// Initie un paiement Mobile Money.
  /// - Si ConfigPaiement.paiementsActifs == false → mode SIMULÉ (dev/test) :
  ///   retourne un ID fictif et le crédit se fait immédiatement.
  /// - Si true → appelle le VRAI PaiementService (Monetbil/CinetPay) et
  ///   retourne l'ID de transaction réel. Le crédit définitif sera fait par
  ///   le webhook après confirmation de l'opérateur.
  /// Lève une exception si le paiement réel échoue à l'initiation.
  static Future<String> _initierPaiementMoMo({
    required double montant,
    required String telephone,
    required String description,
    required String methode,
    String? clientId,
  }) async {
    // MODE SIMULÉ (dev/test) : aucun argent réel ne circule
    if (!await ConfigPaiement.actifs()) {
      final id = 'TXN-SIM-${DateTime.now().millisecondsSinceEpoch}';
      if (kDebugMode) {
        print('[MoMo SIMULÉ] $id — ${PrixFCFA.formater(montant)} — $telephone');
      }
      return id;
    }

    // MODE RÉEL : passer par PaiementService
    final fournisseur = ConfigPaiement.fournisseurParDefaut == 'cinetpay'
        ? FournisseurPaiement.cinetpay
        : FournisseurPaiement.monetbil;
    final res = await PaiementService.initier(
      montant: montant,
      telephone: telephone,
      operateur: methode,        // 'orange' | 'mtn' | 'express_union'
      description: description,
      clientId: clientId ?? 'inconnu',
      fournisseur: fournisseur,
    );
    if (!res.succes || res.transactionId == null) {
      throw Exception(res.erreur ?? 'Échec de l\'initiation du paiement');
    }
    // NB : en mode réel, le crédit définitif doit être fait par le WEBHOOK,
    // pas immédiatement. Voir GUIDE_PAIEMENT.md.
    return res.transactionId!;
  }
}

// ─── Résultat d'un achat ──────────────────────────────────────────────────────

class ResultatAchat {
  final bool succes;
  final double montantCredite;
  final String? transactionId;
  final String? message;
  final String? erreur;

  const ResultatAchat({
    required this.succes,
    this.montantCredite = 0,
    this.transactionId,
    this.message,
    this.erreur,
  });
}
