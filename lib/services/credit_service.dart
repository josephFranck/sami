import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  recharge,           // (historique) achat de crédits — flux RETIRÉ : les
                      // crédits sont des AVOIRS, jamais rechargés en argent
  achat,              // paiement d'une commande en avoirs (débit)
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

  // Abonnements : voir AbonnementService (souscription MoMo déclaré →
  // vérification staff → activation). Les anciennes fonctions
  // souscrireAbonnementBoutique/Couturier, inscrireLivreur et
  // verifierExpirations simulaient un paiement puis écrivaient le plan
  // depuis le téléphone de l'abonné.

  /// Lire l'historique des mouvements d'un utilisateur
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamHistorique(
      String utilisateurId, {int limite = 30}) =>
      MouvementCredit.collection
          .where('utilisateurId', isEqualTo: utilisateurId)
          .orderBy('date', descending: true)
          .limit(limite)
          .snapshots();

}
