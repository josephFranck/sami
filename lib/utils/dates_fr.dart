import 'package:cloud_firestore/cloud_firestore.dart';

/// Dates humaines FR partout : « le 12/07 à 14h05 » — un seul format,
/// tolérant (Timestamp, DateTime, null).
String quandFr(dynamic v, {String prefixe = ''}) {
  DateTime? d;
  if (v is Timestamp) d = v.toDate();
  if (v is DateTime) d = v;
  if (d == null) return '';
  String deux(int n) => n.toString().padLeft(2, '0');
  return '$prefixe${deux(d.day)}/${deux(d.month)} à ${deux(d.hour)}h${deux(d.minute)}';
}
