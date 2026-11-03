import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:flutter/services.dart';
import 'package:sami/services/message_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

class ConversationPage extends StatefulWidget {
  final ConversationLocale conv;

  const ConversationPage({super.key, required this.conv});

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _enEnvoi = false;
  // Pour pagination
  DocumentSnapshot? _dernierDoc;
  bool _peutChargerPlus = true;

  ConversationLocale get _conv => widget.conv;

  @override
  void initState() {
    super.initState();
    // Marquer comme lu dès l'ouverture
    MessageService.marquerLu(_conv.id);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EBF8), // fond légèrement violacé
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Fil des messages
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: MessageService.streamMessages(_conv.id),
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
                if (docs.isNotEmpty) _dernierDoc = docs.last;

                final messages = docs
                    .map((d) => MessageLocal.fromDoc(d))
                    .toList();

                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length + (_peutChargerPlus ? 1 : 0),
                  itemBuilder: (context, i) {
                    // Bouton "charger plus" en haut
                    if (i == messages.length) {
                      return _BoutonChargerPlus(onTap: _chargerPlus);
                    }
                    final msg = messages[i];
                    final suivant = i < messages.length - 1 ? messages[i + 1] : null;
                    final memeExpOrdr = suivant != null && suivant.senderId == msg.senderId;
                    final memeJour = suivant != null &&
                        _memeJour(msg.timestamp, suivant.timestamp);

                    return Column(
                      children: [
                        // Séparateur de jour
                        if (!memeJour && suivant != null)
                          _SeparateurJour(date: suivant.timestamp),
                        _BullMessage(
                          message: msg,
                          dernierDuGroupe: !memeExpOrdr,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Zone de saisie
          _ZoneSaisie(
            controller: _textCtrl,
            enEnvoi: _enEnvoi,
            onEnvoyer: _envoyer,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: _kPrimary,
    foregroundColor: Colors.white,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.pop(context),
    ),
    title: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white24,
          backgroundImage: providerUniversel(_conv.autrePhoto),
          child: _conv.autrePhoto.isEmpty
              ? Text(
                  _conv.autreNom.isNotEmpty ? _conv.autreNom[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_conv.autreNom,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (_conv.contexte != null)
                Text(_conv.contexte!,
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ),
      ],
    ),
    actions: [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) async {
          if (v == 'archiver') {
            await MessageService.archiver(_conv.id);
            if (mounted) Navigator.pop(context);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'archiver', child: Text(Tr.s.archiverConversation)),
        ],
      ),
    ],
  );

  Widget _buildVide() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.waving_hand, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          Tr.s.ditesBonjour(_conv.autreNom),
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    ),
  );

  Future<void> _envoyer() async {
    final texte = _textCtrl.text.trim();
    if (texte.isEmpty || _enEnvoi) return;

    setState(() => _enEnvoi = true);
    _textCtrl.clear();

    try {
      await MessageService.envoyer(
        autreUserId: _conv.autreUserId,
        texte: texte,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Tr.s.erreur2(e)), backgroundColor: Colors.red),
        );
        _textCtrl.text = texte; // restaurer le texte
      }
    } finally {
      if (mounted) setState(() => _enEnvoi = false);
    }
  }

  Future<void> _chargerPlus() async {
    if (_dernierDoc == null) return;
    final snap = await MessageService.chargerPlus(_conv.id, _dernierDoc!);
    if (snap.docs.isEmpty && mounted) setState(() => _peutChargerPlus = false);
  }

  bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Bulle de message ─────────────────────────────────────────────────────────

class _BullMessage extends StatelessWidget {
  final MessageLocal message;
  final bool dernierDuGroupe;

  const _BullMessage({required this.message, required this.dernierDuGroupe});

  @override
  Widget build(BuildContext context) {
    final estMoi = message.estMoi;

    return GestureDetector(
      onLongPress: () => _menuContextuel(context),
      child: Align(
        alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: EdgeInsets.only(
            top: 2,
            bottom: dernierDuGroupe ? 8 : 2,
            left: estMoi ? 48 : 0,
            right: estMoi ? 0 : 48,
          ),
          decoration: BoxDecoration(
            color: message.supprime
                ? Colors.grey.shade200
                : estMoi
                    ? _kPrimary
                    : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: estMoi
                  ? const Radius.circular(16)
                  : Radius.circular(dernierDuGroupe ? 4 : 16),
              bottomRight: estMoi
                  ? Radius.circular(dernierDuGroupe ? 4 : 16)
                  : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: _buildContenu(estMoi),
        ),
      ),
    );
  }

  Widget _buildContenu(bool estMoi) {
    if (message.supprime) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          Tr.s.messageSupprime,
          style: TextStyle(
              color: Colors.grey.shade500, fontSize: 13, fontStyle: FontStyle.italic),
        ),
      );
    }

    // Message contextuel (pagne/commande)
    if (message.type != 'texte' && message.meta != null) {
      return _BulleContextuelle(message: message, estMoi: estMoi);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.texte,
            style: TextStyle(
              color: estMoi ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatHeure(message.timestamp),
            style: TextStyle(
              fontSize: 10,
              color: estMoi ? Colors.white60 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  void _menuContextuel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(Tr.s.copier),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.texte));
                Navigator.pop(context);
              },
            ),
            if (message.estMoi && !message.supprime)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(Tr.s.supprimer, style: TextStyle(color: Colors.red)),
                onTap: () {
                  // messageService.supprimerMessage appelé depuis le parent
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatHeure(DateTime d) =>
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
}

// ─── Bulle contextuelle (lien pagne/commande) ─────────────────────────────────

class _BulleContextuelle extends StatelessWidget {
  final MessageLocal message;
  final bool estMoi;

  const _BulleContextuelle({required this.message, required this.estMoi});

  @override
  Widget build(BuildContext context) {
    final meta = message.meta!;
    final titre = meta['contexteTitre'] as String? ?? '';
    final image = meta['contexteImage'] as String?;
    final icone = switch (message.type) {
      'commande' => Icons.receipt_long,
      'pagne' => Icons.shopping_bag,
      'livraison' => Icons.local_shipping,
      _ => Icons.link,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête contexte
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: estMoi ? Colors.white10 : Colors.grey.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 14, color: estMoi ? Colors.white70 : Colors.grey),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: estMoi ? Colors.white70 : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Texte du message
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Text(
            message.texte,
            style: TextStyle(
              color: estMoi ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Séparateur de jour ───────────────────────────────────────────────────────

class _SeparateurJour extends StatelessWidget {
  final DateTime date;
  const _SeparateurJour({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      label = "Aujourd'hui";
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      label = 'Hier';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ),
      ),
    );
  }
}

// ─── Bouton charger plus ──────────────────────────────────────────────────────

class _BoutonChargerPlus extends StatelessWidget {
  final VoidCallback onTap;
  const _BoutonChargerPlus({required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    child: Text(Tr.s.chargerMessagesPrecedents,
        style: TextStyle(color: _kPrimary, fontSize: 12)),
  );
}

// ─── Zone de saisie ───────────────────────────────────────────────────────────

class _ZoneSaisie extends StatelessWidget {
  final TextEditingController controller;
  final bool enEnvoi;
  final VoidCallback onEnvoyer;

  const _ZoneSaisie({
    required this.controller,
    required this.enEnvoi,
    required this.onEnvoyer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          // Champ texte
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: Tr.s.ecrireMessage,
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onEnvoyer(),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Bouton envoyer
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final hasText = controller.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText && !enEnvoi ? onEnvoyer : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasText ? _kPrimary : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: enEnvoi
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
