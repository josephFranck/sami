import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/message_service.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);

// ═══════════════════════════════════════════════════════════════════════════
// GESTION DES UTILISATEURS (Admin)
// Remplace les anciennes userlist_page.dart et userslistes.dart
// ═══════════════════════════════════════════════════════════════════════════

class GestionUtilisateursPage extends StatefulWidget {
  const GestionUtilisateursPage({super.key});
  @override
  State<GestionUtilisateursPage> createState() => _GestionUtilisateursPageState();
}

// Permissions attribuables aux agents (mini-admins)
const kPermissionsAgent = {
  'candidatures': 'Valider les candidatures',
  'litiges': 'Livraisons à vérifier / litiges',
  'evenements': 'Événements & promotions',
  'boutiques': 'Gestion des boutiques',
  'reversements': 'Répartition des paiements',
  'paiements': 'Vérification des transferts déclarés',
  'utilisateurs': 'Gestion des utilisateurs',
  'parametres': 'Paramètres de la plateforme',
};

class _GestionUtilisateursPageState extends State<GestionUtilisateursPage>
    with PageProtegee {
  String _filtreRole = 'tous';
  String _recherche = '';

  final _roles = const ['tous', 'client', 'boutiquier', 'couturier', 'livreur', 'agent', 'admin', 'superadmin'];

  @override
  void initState() {
    super.initState();
    chargerUtilisateur(); // fourni par le mixin PageProtegee
  }

  @override
  Widget build(BuildContext context) {
    // Pendant le chargement de l'utilisateur
    if (chargementUtilisateur) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }
    // Réservé aux admins — le mixin expose 'utilisateur', pas 'utilisateurCourant'
    if (utilisateur?.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Accès refusé'), backgroundColor: _kPrimary),
        body: const Center(child: Text('Réservé aux administrateurs')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Gestion des utilisateurs'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        // Recherche
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _recherche = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom ou email...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
            ),
          ),
        ),
        // Filtre par rôle
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _roles.map((r) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(r == 'tous' ? 'Tous' : r),
                selected: _filtreRole == r,
                onSelected: (_) => setState(() => _filtreRole = r),
                selectedColor: _kPrimary.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: _filtreRole == r ? _kPrimary : Colors.grey,
                  fontWeight: _filtreRole == r ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Liste
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('utilisateurs').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _kPrimary));
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Text('Aucun utilisateur'));
              }

              var users = snap.data!.docs;
              // Filtre rôle
              if (_filtreRole != 'tous') {
                users = users.where((d) => d.data()['role'] == _filtreRole).toList();
              }
              // Filtre recherche
              if (_recherche.isNotEmpty) {
                users = users.where((d) {
                  final data = d.data();
                  final nom = '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'.toLowerCase();
                  final email = (data['email'] as String? ?? '').toLowerCase();
                  return nom.contains(_recherche) || email.contains(_recherche);
                }).toList();
              }

              if (users.isEmpty) {
                return const Center(child: Text('Aucun résultat'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CarteUtilisateur(
                  doc: users[i],
                  onRoleChange: _changerRole,
                  onPermissions: _editerPermissions,
                  onContact: _basculerContactVisible,
                  onToggleActif: _toggleActif,
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _editerPermissions(String uid, List<String> actuelles) async {
    final sel = Set<String>.from(actuelles);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Droits de l\'agent'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: kPermissionsAgent.entries
                  .map((e) => CheckboxListTile(
                        dense: true,
                        title: Text(e.value,
                            style: const TextStyle(fontSize: 13)),
                        value: sel.contains(e.key),
                        activeColor: const Color(0xFF6A1B9A),
                        onChanged: (v) => setLocal(() =>
                            v == true ? sel.add(e.key) : sel.remove(e.key)),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(uid)
          .update({'permissions': sel.toList()});
    }
  }

  /// Active/désactive l'affichage public du numéro du partenaire lié à cet
  /// utilisateur (boutique via gerants, couturier/livreur via utilisateurId).
  Future<void> _basculerContactVisible(String uid, String role) async {
    final db = FirebaseFirestore.instance;
    DocumentReference<Map<String, dynamic>>? ref;
    if (role == 'boutiquier') {
      final q = await db
          .collection('boutiques')
          .where('gerants', arrayContains: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) ref = q.docs.first.reference;
    } else if (role == 'couturier' || role == 'livreur') {
      final q = await db
          .collection(role == 'couturier' ? 'couturiers' : 'livreurs')
          .where('utilisateurId', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) ref = q.docs.first.reference;
    }
    if (ref == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aucune fiche partenaire liée à ce compte')));
      }
      return;
    }
    final doc = await ref.get();
    final actuel = doc.data()?['contactVisible'] as bool? ?? false;
    await ref.update({'contactVisible': !actuel});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!actuel
              ? 'Numéro rendu VISIBLE publiquement'
              : 'Numéro masqué (contact via chat SAMI)')));
    }
  }

  Future<void> _changerRole(String userId, String nouveauRole) async {
    // GARDE DE SURVIE : on ne change JAMAIS son propre rôle — sinon un
    // faux geste et la plateforme n'a plus d'admin (irréversible côté app).
    // HIÉRARCHIE : toucher un admin, ou nommer un admin → superadmin seul
    final moi = await FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .get();
    final monRole = moi.data()?['role'] as String? ?? '';
    final cible = await FirebaseFirestore.instance
        .collection('utilisateurs').doc(userId).get();
    final roleCible = cible.data()?['role'] as String? ?? '';
    final toucheAdmin = ['admin', 'superadmin'].contains(roleCible) ||
        ['admin', 'superadmin'].contains(nouveauRole);
    if (toucheAdmin && monRole != 'superadmin') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Réservé au SUPER-ADMIN : gérer les admins ou en nommer.'),
            backgroundColor: Colors.orange));
      }
      return;
    }
    if (userId == FirebaseAuth.instance.currentUser?.uid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Impossible de modifier son PROPRE rôle (protection anti-décapitation). Demandez à un autre admin.'),
          backgroundColor: Colors.orange));
      return;
    }
    await FirebaseFirestore.instance.collection('utilisateurs')
        .doc(userId).update({
      'role': nouveauRole,
      if (['livreur', 'boutiquier', 'couturier'].contains(nouveauRole)) ...{
        'origineRole': 'admin',
        'origineRoleLe': FieldValue.serverTimestamp(),
      },
    });
    // Un LIVREUR a besoin de sa fiche (position, dispo) — créée si
    // absente, sinon son tracker GPS spamme NOT_FOUND.
    if (nouveauRole == 'livreur') {
      final fiche = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(userId).get();
      final fd = fiche.data() ?? {};
      await FirebaseFirestore.instance
          .collection('livreurs')
          .doc(userId)
          .set({
        'utilisateurId': userId,
        'nom': fd['nom'] ?? '',
        'prenom': fd['prenom'] ?? '',
        'telephone': fd['telephone'] ?? '',
        'origine': 'admin',
        'disponible': true,
        'creeLe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // COUTURIER : même principe — la fiche métier naît à la promotion
    // (sinon « Faire coudre » ne trouve jamais le couturier).
    if (nouveauRole == 'couturier') {
      final fiche = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(userId).get();
      final fd = fiche.data() ?? {};
      await FirebaseFirestore.instance
          .collection('couturiers')
          .doc(userId)
          .set({
        'utilisateurId': userId,
        'nom': fd['nom'] ?? '',
        'prenom': fd['prenom'] ?? '',
        'telephone': fd['telephone'] ?? '',
        'origine': 'admin',
        'actif': true,
        'creeLe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rôle changé en $nouveauRole'), backgroundColor: Colors.green));
    }
  }

  Future<void> _toggleActif(String userId, bool actif) async {
    await FirebaseFirestore.instance.collection('utilisateurs')
        .doc(userId).update({'estActif': actif});
  }
}

class _CarteUtilisateur extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function(String, String) onRoleChange;
  final Future<void> Function(String, List<String>)? onPermissions;
  final Future<void> Function(String, String)? onContact;
  final Future<void> Function(String, bool) onToggleActif;

  const _CarteUtilisateur({
    required this.doc,
    required this.onRoleChange,
    this.onPermissions,
    this.onContact,
    required this.onToggleActif,
  });

  void _dialogMessage(BuildContext context, String userId, String nom, String photo) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Message à ${nom.isEmpty ? "l'utilisateur" : nom}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Votre message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () async {
              final texte = ctrl.text.trim();
              if (texte.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await MessageService.initierConversation(
                  autreUserId: userId,
                  autreNom: nom.isEmpty ? 'Utilisateur' : nom,
                  autrePhoto: photo,
                );
                await MessageService.envoyer(autreUserId: userId, texte: texte);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Message envoyé'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Erreur d\'envoi'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final nom = '${d['prenom'] ?? ''} ${d['nom'] ?? ''}'.trim();
    final email = d['email'] as String? ?? '';
    final role = d['role'] as String? ?? 'client';
    final photo = d['image'] as String? ?? '';
    final actif = d['estActif'] as bool? ?? true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: _kPrimary.withOpacity(0.1),
          backgroundImage: providerUniversel(photo),
          child: photo.isEmpty
              ? Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold))
              : null,
        ),
        title: Text(nom.isEmpty ? 'Sans nom' : nom,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (['livreur', 'boutiquier', 'couturier']
                  .contains(role) &&
              d['origineRole'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: d['origineRole'] == 'admin'
                      ? Colors.blueGrey.shade50
                      : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  d['origineRole'] == 'admin'
                      ? '👤 Ajouté par l\'équipe'
                      : '📝 A candidaté',
                  style: TextStyle(
                      fontSize: 10,
                      color: d['origineRole'] == 'admin'
                          ? Colors.blueGrey.shade700
                          : Colors.teal.shade700),
                ),
              ),
            ),
          Text(email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Droits.badgeRole(role),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) {
            if (value.startsWith('role_')) {
              onRoleChange(doc.id, value.substring(5));
            } else if (value == 'permissions') {
              final perms = List<String>.from(
                  (doc.data() as Map<String, dynamic>)['permissions']
                          as List? ??
                      const []);
              onPermissions?.call(doc.id, perms);
            } else if (value == 'contact') {
              onContact?.call(doc.id,
                  (doc.data() as Map<String, dynamic>)['role'] as String? ??
                      'client');
            } else if (value == 'toggle') {
              onToggleActif(doc.id, !actif);
            } else if (value == 'message') {
              _dialogMessage(context, doc.id, nom, photo);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'message', child: Row(children: [
              Icon(Icons.send_outlined, size: 16, color: _kPrimary),
              SizedBox(width: 8), Text('Envoyer un message')])),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'role_client', child: Text('→ Client')),
            const PopupMenuItem(value: 'role_boutiquier', child: Text('→ Boutiquier')),
            const PopupMenuItem(value: 'role_couturier', child: Text('→ Couturier')),
            const PopupMenuItem(value: 'role_livreur', child: Text('→ Livreur')),
            const PopupMenuItem(value: 'role_agent', child: Text('→ Agent (mini-admin)')),
            const PopupMenuItem(value: 'role_admin', child: Text('→ Admin')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'permissions', child: Row(children: [
              Icon(Icons.rule, size: 16, color: _kPrimary),
              SizedBox(width: 8), Text('Droits de l\'agent…')])),
            const PopupMenuItem(value: 'contact', child: Row(children: [
              Icon(Icons.phone_enabled_outlined, size: 16, color: _kPrimary),
              SizedBox(width: 8), Text('Numéro visible on/off')])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'toggle',
                child: Text(actif ? '🔴 Désactiver' : '🟢 Activer')),
          ],
        ),
      ),
    );
  }
}
