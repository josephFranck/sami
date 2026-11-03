import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/message_service.dart';
import 'package:sami/pages/chat/conversation_page.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

class ListeConversationsPage extends StatelessWidget {
  const ListeConversationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(Tr.s.messages),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: MessageService.streamConversations(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // ERREUR VISIBLE : sinon le cache s'affiche puis le refus du
            // serveur (index en construction, règles) vide l'écran en silence.
            final msg = snapshot.error.toString();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  msg.contains('index')
                      ? 'Index Firestore en cours de création — réessayez dans quelques minutes.\n(firebase deploy --only firestore:indexes)'
                      : Tr.s.impossibleChargerMessages(msg),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildVide();
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, i) {
              final conv = ConversationLocale.fromDoc(docs[i]);
              return _CarteConversation(
                conv: conv,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConversationPage(conv: conv),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildVide() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(Tr.s.aucuneConversation, style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          Tr.s.demarrezDiscussionDepuisBoutiqueOu,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ],
    ),
  );
}

class _CarteConversation extends StatelessWidget {
  final ConversationLocale conv;
  final VoidCallback onTap;

  const _CarteConversation({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final heure = _formatHeure(conv.lastMessageDate);
    final estMoi = conv.lastMessageSender == FirebaseAuth.instance.currentUser?.uid;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _kPrimary.withOpacity(0.15),
                  backgroundImage: providerUniversel(conv.autrePhoto),
                  child: conv.autrePhoto.isEmpty
                      ? Text(
                          conv.autreNom.isNotEmpty ? conv.autreNom[0].toUpperCase() : '?',
                          style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 20),
                        )
                      : null,
                ),
                if (conv.aMessageNonLu)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${conv.nonLusMoi > 9 ? '9+' : conv.nonLusMoi}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.autreNom,
                          style: TextStyle(
                            fontWeight: conv.aMessageNonLu ? FontWeight.bold : FontWeight.w500,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        heure,
                        style: TextStyle(
                          fontSize: 12,
                          color: conv.aMessageNonLu ? _kPrimary : Colors.grey,
                          fontWeight: conv.aMessageNonLu ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Contexte si présent (pagne/commande)
                  if (conv.contexte != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          conv.contexte!,
                          style: const TextStyle(fontSize: 10, color: _kPrimary),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      if (estMoi)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.done_all, size: 14, color: Colors.grey),
                        ),
                      Expanded(
                        child: Text(
                          conv.lastMessage.isEmpty ? Tr.s.conversationDemarree : conv.lastMessage,
                          style: TextStyle(
                            fontSize: 13,
                            color: conv.aMessageNonLu ? Colors.black87 : Colors.grey,
                            fontWeight: conv.aMessageNonLu ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatHeure(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) {
      return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } else if (diff.inDays == 1) {
      return 'Hier';
    } else if (diff.inDays < 7) {
      const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return jours[d.weekday - 1];
    } else {
      return '${d.day}/${d.month}';
    }
  }
}
