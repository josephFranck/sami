import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// JOURNAL APPLICATIF : trace les événements-clés du métier dans
/// `app_logs` (lisible par le staff). Complète les logs de l'agent IA.
/// Léger, jamais bloquant : un log qui échoue ne casse rien.
class LogService {
  static Future<void> log(String evenement,
      {Map<String, dynamic>? details}) async {
    try {
      await FirebaseFirestore.instance.collection('app_logs').add({
        'evenement': evenement,
        'details': details ?? {},
        'utilisateurId': FirebaseAuth.instance.currentUser?.uid,
        'date': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('[Log] échec: $e');
    }
  }
}
