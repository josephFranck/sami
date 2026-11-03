import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFICATIONS
//
// IN-APP (opérationnel tout de suite) : chaque notification est un document
// de la collection 'notifications' ; la cloche de l'accueil affiche le badge
// des non-lues et la page /notifications les liste.
//
// PUSH (FCM, hors app) : nécessite firebase_messaging + une Cloud Function
// qui écoute cette même collection et envoie le push (voir GUIDE_PAIEMENT.md
// § infrastructure). Les documents créés ici sont DÉJÀ au bon format : quand
// la Cloud Function sera déployée, le push marchera sans changer l'app.
// ═══════════════════════════════════════════════════════════════════════════

class NotificationService {
  static final _db = FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Crée une notification pour un utilisateur (in-app + future base du push).
  static Future<void> envoyer({
    required String destinataireId,
    required String titre,
    required String message,
    String? route,     // route à ouvrir au tap (ex: '/mes-coutures')
    String? refId,     // ID de l'objet concerné
  }) async {
    if (destinataireId.isEmpty) return;
    try {
      await _db.collection('notifications').add({
        'destinataireId': destinataireId,
        'titre': titre,
        'message': message,
        'route': route,
        'refId': refId,
        'lue': false,
        'date': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Badge : nombre de notifications non lues de l'utilisateur courant.
  static Stream<int> nonLues() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('notifications')
        .where('destinataireId', isEqualTo: uid)
        .where('lue', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Liste des notifications de l'utilisateur courant (tri client).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> mesNotifs() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('notifications')
        .where('destinataireId', isEqualTo: uid)
        .snapshots()
        .map((s) {
      final docs = s.docs.toList()
        ..sort((a, b) {
          final da = a.data()['date'], db2 = b.data()['date'];
          if (da is Timestamp && db2 is Timestamp) return db2.compareTo(da);
          return 0;
        });
      return docs;
    });
  }

  static Future<void> marquerLue(String id) =>
      _db.collection('notifications').doc(id).update({'lue': true});

  static Future<void> toutMarquerLues() async {
    final uid = _uid;
    if (uid == null) return;
    final q = await _db
        .collection('notifications')
        .where('destinataireId', isEqualTo: uid)
        .where('lue', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'lue': true});
    }
    await batch.commit();
  }
}
