import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE FAVORIS
//
// Gère la liste des pagnes favoris d'un utilisateur (champ 'favoris' = liste
// d'IDs de pagnes dans le document utilisateur). Ajout/retrait atomiques via
// arrayUnion / arrayRemove.
// ═══════════════════════════════════════════════════════════════════════════

class FavorisService {
  static final _db = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Ajoute ou retire un pagne des favoris. Retourne le nouvel état (true = favori).
  static Future<bool> basculer(String pagneId) async {
    final uid = _uid;
    if (uid == null) return false;

    final ref = _db.collection('utilisateurs').doc(uid);
    final doc = await ref.get();
    final favoris = List<String>.from(doc.data()?['favoris'] ?? []);

    if (favoris.contains(pagneId)) {
      await ref.update({
        'favoris': FieldValue.arrayRemove([pagneId])
      });
      return false;
    } else {
      await ref.update({
        'favoris': FieldValue.arrayUnion([pagneId])
      });
      return true;
    }
  }

  /// Flux temps réel des IDs favoris de l'utilisateur courant.
  static Stream<List<String>> streamFavoris() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db.collection('utilisateurs').doc(uid).snapshots().map(
        (doc) => List<String>.from(doc.data()?['favoris'] ?? []));
  }

  /// Vérifie si un pagne est en favori (lecture ponctuelle).
  static Future<bool> estFavori(String pagneId) async {
    final uid = _uid;
    if (uid == null) return false;
    final doc = await _db.collection('utilisateurs').doc(uid).get();
    final favoris = List<String>.from(doc.data()?['favoris'] ?? []);
    return favoris.contains(pagneId);
  }
}
