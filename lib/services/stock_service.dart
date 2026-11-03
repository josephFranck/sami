import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GESTION DU STOCK — Transactions atomiques Firestore
//
// Problème de race condition :
//   Client A voit 3 pagnes disponibles (cache local)
//   Client B commande les 3 pendant que A est offline
//   A tente de commander → le stock est à 0
//
// Solution : Transaction Firestore atomique
//   → Read + Write dans la même transaction
//   → Si le stock a changé entre le Read et le Write → la transaction échoue
//   → Retry automatique (Firestore réessaie jusqu'à 5 fois)
//   → Le client reçoit un message clair si stock insuffisant
//
// Structure Firestore pour le stock :
//   pagnes/{id}/
//     quantiteStock: 3          ← stock total
//     quantiteReservee: 1       ← en cours de commande (panier actif)
//     quantiteDisponible: 2     ← calculé = stock - reservee
//     disponible: true          ← false si quantiteDisponible == 0
// ═══════════════════════════════════════════════════════════════════════════

class StockService {

  static final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // RÉSERVATION TEMPORAIRE (ajout au panier)
  // ══════════════════════════════════════════════════════════════════════════

  /// Réserver du stock lors de l'ajout au panier
  /// Retourne null si succès, message d'erreur si stock insuffisant
  static Future<String?> reserverStock({
    required String pagneId,
    required int quantite,
    required String clientId,
    Duration dureeReservation = const Duration(minutes: 30),
  }) async {
    try {
      String? erreur;

      await _db.runTransaction((transaction) async {
        final pagneRef = _db.collection('pagnes').doc(pagneId);
        final pagneDoc = await transaction.get(pagneRef);

        if (!pagneDoc.exists) {
          erreur = 'Pagne introuvable';
          return;
        }

        final data = pagneDoc.data()!;
        final stock = data['quantiteStock'] as int? ?? 0;
        final reserve = data['quantiteReservee'] as int? ?? 0;
        final dispo = stock - reserve;

        if (dispo < quantite) {
          // Stock insuffisant — message précis
          if (dispo == 0) {
            erreur = 'Ce pagne est épuisé';
          } else {
            erreur = 'Stock insuffisant — seulement $dispo disponible${dispo > 1 ? "s" : ""}';
          }
          return;
        }

        // Atomic update : réserver
        transaction.update(pagneRef, {
          'quantiteReservee': FieldValue.increment(quantite),
          'quantiteDisponible': FieldValue.increment(-quantite),
          // Compteur de ventes : alimente « Meilleures ventes » (carrousel)
          'nombreVentes': FieldValue.increment(quantite),
          'disponible': (dispo - quantite) > 0,
        });

        // Enregistrer la réservation avec expiration
        final reservationRef = _db
            .collection('pagnes')
            .doc(pagneId)
            .collection('reservations')
            .doc('${clientId}_${DateTime.now().millisecondsSinceEpoch}');

        transaction.set(reservationRef, {
          'clientId': clientId,
          'pagneId': pagneId,
          'quantite': quantite,
          'dateCreation': FieldValue.serverTimestamp(),
          'dateExpiration': Timestamp.fromDate(
              DateTime.now().add(dureeReservation)),
          'statut': 'active',
        });
      });

      return erreur; // null si succès
    } catch (e) {
      if (kDebugMode) print('[Stock] Erreur réservation : $e');
      return 'Erreur technique — réessayez';
    }
  }

  /// Libérer une réservation (si client abandonne son panier)
  static Future<void> libererReservation({
    required String pagneId,
    required int quantite,
    required String reservationId,
  }) async {
    try {
      await _db.runTransaction((transaction) async {
        final pagneRef = _db.collection('pagnes').doc(pagneId);
        final doc = await transaction.get(pagneRef);
        if (!doc.exists) return;

        transaction.update(pagneRef, {
          'quantiteReservee': FieldValue.increment(-quantite),
          'quantiteDisponible': FieldValue.increment(quantite),
          'disponible': true,
        });

        transaction.update(
          _db.collection('pagnes').doc(pagneId)
              .collection('reservations').doc(reservationId),
          {'statut': 'liberee'},
        );
      });
    } catch (e) {
      if (kDebugMode) print('[Stock] Erreur libération : $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIRMATION DÉFINITIVE (validation de commande)
  // ══════════════════════════════════════════════════════════════════════════

  /// Confirmer le stock lors de la validation de commande
  /// Convertit la réservation temporaire en déduction définitive
  static Future<ResultatStock> confirmerStock({
    required List<({String pagneId, int quantite})> articles,
  }) async {
    final erreurs = <String>[];

    try {
      await _db.runTransaction((transaction) async {
        // Lire tous les pagnes en une fois (efficace)
        final refs = articles.map((a) => _db.collection('pagnes').doc(a.pagneId)).toList();
        final docs = await Future.wait(refs.map((r) => transaction.get(r)));

        // Vérifier chaque article
        for (int i = 0; i < articles.length; i++) {
          final article = articles[i];
          final doc = docs[i];

          if (!doc.exists) {
            erreurs.add('Article introuvable');
            continue;
          }

          final data = doc.data()!;
          final stock = data['quantiteStock'] as int? ?? 0;
          final dispo = data['quantiteDisponible'] as int? ?? stock;

          if (dispo < article.quantite) {
            final nomPagne = data['nom'] as String? ?? 'Pagne';
            if (dispo == 0) {
              erreurs.add('$nomPagne : épuisé depuis votre dernière consultation');
            } else {
              erreurs.add('$nomPagne : seulement $dispo disponible${dispo > 1 ? "s" : ""} (vous en avez ${ article.quantite} dans votre panier)');
            }
          }
        }

        // Si des erreurs → annuler toute la transaction
        if (erreurs.isNotEmpty) return;

        // Tout est OK → déduire définitivement
        for (int i = 0; i < articles.length; i++) {
          final article = articles[i];
          final nouvStock = (docs[i].data()!['quantiteStock'] as int? ?? 0) - article.quantite;

          transaction.update(refs[i], {
            'quantiteStock': FieldValue.increment(-article.quantite),
            'quantiteDisponible': FieldValue.increment(-article.quantite),
            'disponible': nouvStock > 0,
            'dateModifStock': FieldValue.serverTimestamp(),
          });
        }
      });

      if (erreurs.isNotEmpty) {
        return ResultatStock(succes: false, erreurs: erreurs);
      }
      return const ResultatStock(succes: true);
    } catch (e) {
      return ResultatStock(succes: false, erreurs: ['Erreur technique : $e']);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NETTOYAGE DES RÉSERVATIONS EXPIRÉES
  // ══════════════════════════════════════════════════════════════════════════

  /// Libérer les réservations expirées (à appeler au démarrage ou en Cloud Function)
  static Future<int> libererReservationsExpirees() async {
    int libere = 0;
    try {
      final maintenant = Timestamp.now();
      // Toutes les réservations actives expirées
      final expireesSnap = await _db
          .collectionGroup('reservations')
          .where('statut', isEqualTo: 'active')
          .where('dateExpiration', isIsLessThan: maintenant)
          .get();

      for (final doc in expireesSnap.docs) {
        final data = doc.data();
        final pagneId = data['pagneId'] as String? ?? '';
        final quantite = data['quantite'] as int? ?? 0;

        await _db.runTransaction((transaction) async {
          final pagneRef = _db.collection('pagnes').doc(pagneId);
          transaction.update(pagneRef, {
            'quantiteReservee': FieldValue.increment(-quantite),
            'quantiteDisponible': FieldValue.increment(quantite),
            'disponible': true,
          });
          transaction.update(doc.reference, {'statut': 'expiree'});
        });
        libere++;
      }
      if (kDebugMode && libere > 0) print('[Stock] $libere réservations expirées libérées');
    } catch (e) {
      if (kDebugMode) print('[Stock] Erreur nettoyage : $e');
    }
    return libere;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STREAM STOCK EN TEMPS RÉEL
  // ══════════════════════════════════════════════════════════════════════════

  /// Écouter le stock d'un pagne en temps réel
  /// → Le bouton "Ajouter au panier" se met à jour automatiquement
  static Stream<int> streamStockDisponible(String pagneId) =>
      _db.collection('pagnes').doc(pagneId).snapshots().map((doc) {
        if (!doc.exists) return 0;
        return doc.data()?['quantiteDisponible'] as int? ?? 0;
      });

  /// Écouter plusieurs pagnes d'un coup (pour la liste)
  static Stream<Map<String, int>> streamStocksMultiples(List<String> pagneIds) {
    if (pagneIds.isEmpty) return Stream.value({});
    // Firestore limite whereIn à 10 éléments
    // Pour plus, splitter en groupes de 10
    return _db
        .collection('pagnes')
        .where(FieldPath.documentId, whereIn: pagneIds.take(10).toList())
        .snapshots()
        .map((snap) {
      final stocks = <String, int>{};
      for (final doc in snap.docs) {
        stocks[doc.id] = doc.data()['quantiteDisponible'] as int? ?? 0;
      }
      return stocks;
    });
  }

  /// Réincrémente le stock d'un pagne (retour accepté, article réintégré).
  static Future<void> restituerStock({
    required String pagneId,
    required int quantite,
  }) async {
    try {
      await _db.collection('pagnes').doc(pagneId).update({
        'quantiteStock': FieldValue.increment(quantite),
        'quantiteDisponible': FieldValue.increment(quantite),
        'disponible': true,
        'dateModifStock': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // silencieux : la restitution ne doit pas bloquer le remboursement
    }
  }

  /// RÉAPPROVISIONNEMENT : ajoute des unités au stock existant (addition).
  /// À utiliser quand le boutiquier reçoit de nouvelles unités.
  static Future<bool> reapprovisionner({
    required String pagneId,
    required int quantiteAjoutee,
  }) async {
    if (quantiteAjoutee <= 0) return false;
    try {
      await _db.collection('pagnes').doc(pagneId).update({
        'quantiteStock': FieldValue.increment(quantiteAjoutee),
        'quantiteDisponible': FieldValue.increment(quantiteAjoutee),
        'disponible': true,
        'dateModifStock': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }
}

class ResultatStock {
  final bool succes;
  final List<String> erreurs;

  const ResultatStock({required this.succes, this.erreurs = const []});

  String get messageErreur => erreurs.join('\n');
}
