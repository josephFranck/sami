import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/chat/conversation_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE MESSAGERIE — Optimisé coûts Firestore
//
// Stratégie anti-coût :
// ─────────────────────
// ❌ NE PAS FAIRE : stream sur toute la collection messages
//    → chaque nouveau message = 1 lecture par utilisateur connecté
//    → 100 users × 1000 messages = 100 000 lectures/jour
//
// ✅ CE QU'ON FAIT :
//    → 1 document "conversation" par paire d'utilisateurs
//    → messages sous-collection de la conversation (pas collection racine)
//    → limite à 50 derniers messages au chargement
//    → pagination manuelle pour charger plus
//    → lastMessage stocké dans le doc conversation (1 lecture pour la liste)
//    → index composé : conversationId + timestamp
// ═══════════════════════════════════════════════════════════════════════════

class MessageService {

  static final _db = FirebaseFirestore.instance;
  static String get _moi => FirebaseAuth.instance.currentUser!.uid;

  // ── Collections ───────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _convCol =>
      _db.collection('conversations');

  static CollectionReference<Map<String, dynamic>> _msgCol(String convId) =>
      _convCol.doc(convId).collection('messages');

  // ── ID conversation déterministe ─────────────────────────────────────────
  // Toujours le même ID pour les deux utilisateurs, quel que soit l'ordre
  static String convId(String autreUserId) {
    final ids = [_moi, autreUserId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  // ── Créer/récupérer une conversation ─────────────────────────────────────
  static Future<void> initierConversation({
    required String autreUserId,
    required String autreNom,
    String? autrePhoto,
    String? contexte,      // ex: "Pagne Bazin #123" ou "Commande #ABC"
    String? contexteId,    // ID de la commande/pagne si applicable
  }) async {
    final id = convId(autreUserId);
    final ref = _convCol.doc(id);
    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'id': id,
        'participants': [_moi, autreUserId],
        'participantNoms': {_moi: '', autreUserId: autreNom},
        'participantPhotos': {_moi: '', autreUserId: autrePhoto ?? ''},
        'dateCreation': FieldValue.serverTimestamp(),
        'dateModif': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageDate': FieldValue.serverTimestamp(),
        'lastMessageSender': '',
        'nonLus': {_moi: 0, autreUserId: 0},
        'contexte': contexte,
        'contexteId': contexteId,
        'archive': false,
      });
    }
  }

  /// Initie (si besoin) puis OUVRE la conversation avec un autre utilisateur.
  /// À utiliser depuis les boutons « Contacter » liés à une commande,
  /// une couture ou une livraison (le contexte s'affiche dans le fil).
  static Future<void> contacter(
    BuildContext context, {
    required String autreUserId,
    required String autreNom,
    String? contexte,
    String? contexteId,
  }) async {
    if (autreUserId.isEmpty || autreUserId == _moi) return;
    await initierConversation(
      autreUserId: autreUserId,
      autreNom: autreNom,
      contexte: contexte,
      contexteId: contexteId,
    );
    final doc = await _convCol.doc(convId(autreUserId)).get();
    if (!context.mounted || !doc.exists) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationPage(conv: ConversationLocale.fromDoc(doc)),
      ),
    );
  }

  // ── Stream conversations (liste) — 1 lecture par doc ─────────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamConversations() =>
      _convCol
          .where('participants', arrayContains: _moi)
          .where('archive', isEqualTo: false)
          .orderBy('dateModif', descending: true)
          .limit(30)           // max 30 conversations chargées
          .snapshots();

  // ── Stream messages d'une conversation — limité à 50 ─────────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(
      String convId, {int limite = 50}) =>
      _msgCol(convId)
          .orderBy('timestamp', descending: true)
          .limit(limite)
          .snapshots();

  // ── Charger messages plus anciens (pagination) ────────────────────────────
  static Future<QuerySnapshot<Map<String, dynamic>>> chargerPlus(
      String convId, DocumentSnapshot dernierDoc) =>
      _msgCol(convId)
          .orderBy('timestamp', descending: true)
          .startAfterDocument(dernierDoc)
          .limit(30)
          .get();

  // ── Envoyer un message ────────────────────────────────────────────────────
  static Future<void> envoyer({
    required String autreUserId,
    required String texte,
    String type = 'texte',     // 'texte' | 'image' | 'commande' | 'pagne'
    Map<String, dynamic>? meta, // données annexes (lien commande, etc.)
  }) async {
    if (texte.trim().isEmpty) return;

    final id = convId(autreUserId);
    final now = FieldValue.serverTimestamp();

    final batch = _db.batch();

    // 1. Ajouter le message dans la sous-collection
    final msgRef = _msgCol(id).doc();
    batch.set(msgRef, {
      'id': msgRef.id,
      'senderId': _moi,
      'texte': texte.trim(),
      'type': type,
      'timestamp': now,
      'lu': false,
      if (meta != null) 'meta': meta,
    });

    // 2. Mettre à jour la conversation (lastMessage)
    // → 1 seule écriture supplémentaire, évite de relire tous les messages
    batch.update(_convCol.doc(id), {
      'lastMessage': texte.length > 60 ? '${texte.substring(0, 60)}...' : texte,
      'lastMessageDate': now,
      'lastMessageSender': _moi,
      'dateModif': now,
      'nonLus.$autreUserId': FieldValue.increment(1),
    });

    await batch.commit();
  }

  // ── Marquer comme lus ─────────────────────────────────────────────────────
  static Future<void> marquerLu(String convId) async {
    await _convCol.doc(convId).update({'nonLus.$_moi': 0});
  }

  // ── Archiver une conversation ─────────────────────────────────────────────
  static Future<void> archiver(String convId) async {
    await _convCol.doc(convId).update({'archive': true});
  }

  // ── Supprimer un message (soft delete) ───────────────────────────────────
  static Future<void> supprimerMessage(String convId, String msgId) async {
    await _msgCol(convId).doc(msgId).update({
      'texte': 'Message supprimé',
      'supprime': true,
    });
  }

  // ── Message contextuel lié à une commande/pagne ───────────────────────────
  static Future<void> envoyerContexte({
    required String autreUserId,
    required String texte,
    required String type,       // 'commande' | 'pagne' | 'livraison'
    required String contexteId,
    required String contexteTitre,
    String? contexteImage,
  }) => envoyer(
    autreUserId: autreUserId,
    texte: texte,
    type: type,
    meta: {
      'contexteId': contexteId,
      'contexteTitre': contexteTitre,
      'contexteImage': contexteImage,
    },
  );
}

// ─── Modèle message ───────────────────────────────────────────────────────────

class MessageLocal {
  final String id;
  final String senderId;
  final String texte;
  final String type;
  final DateTime timestamp;
  final bool lu;
  final bool supprime;
  final Map<String, dynamic>? meta;

  MessageLocal({
    required this.id,
    required this.senderId,
    required this.texte,
    required this.type,
    required this.timestamp,
    required this.lu,
    this.supprime = false,
    this.meta,
  });

  bool get estMoi => senderId == FirebaseAuth.instance.currentUser?.uid;

  factory MessageLocal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return MessageLocal(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      texte: d['texte'] as String? ?? '',
      type: d['type'] as String? ?? 'texte',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lu: d['lu'] as bool? ?? false,
      supprime: d['supprime'] as bool? ?? false,
      meta: d['meta'] as Map<String, dynamic>?,
    );
  }
}

// ─── Modèle conversation ──────────────────────────────────────────────────────

class ConversationLocale {
  final String id;
  final List<String> participants;
  final Map<String, String> participantNoms;
  final Map<String, String> participantPhotos;
  final String lastMessage;
  final DateTime lastMessageDate;
  final String lastMessageSender;
  final Map<String, int> nonLus;
  final String? contexte;
  final String? contexteId;

  ConversationLocale({
    required this.id,
    required this.participants,
    required this.participantNoms,
    required this.participantPhotos,
    required this.lastMessage,
    required this.lastMessageDate,
    required this.lastMessageSender,
    required this.nonLus,
    this.contexte,
    this.contexteId,
  });

  String get moi => FirebaseAuth.instance.currentUser!.uid;
  String get autreUserId => participants.firstWhere((p) => p != moi, orElse: () => '');
  String get autreNom => participantNoms[autreUserId] ?? 'Utilisateur';
  String get autrePhoto => participantPhotos[autreUserId] ?? '';
  int get nonLusMoi => nonLus[moi] ?? 0;
  bool get aMessageNonLu => nonLusMoi > 0;

  factory ConversationLocale.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ConversationLocale(
      id: doc.id,
      participants: List<String>.from(d['participants'] ?? []),
      participantNoms: Map<String, String>.from(d['participantNoms'] ?? {}),
      participantPhotos: Map<String, String>.from(d['participantPhotos'] ?? {}),
      lastMessage: d['lastMessage'] as String? ?? '',
      lastMessageDate: (d['lastMessageDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageSender: d['lastMessageSender'] as String? ?? '',
      nonLus: Map<String, int>.from((d['nonLus'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num? ?? 0).toInt())) ?? {}),
      contexte: d['contexte'] as String?,
      contexteId: d['contexteId'] as String?,
    );
  }
}
