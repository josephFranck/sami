import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/message_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/pages/couturier/creer_modele_page.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/services/couture_service.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/pages/couturier/saisie_mesures_page.dart';
import 'package:sami/pages/abonnements/abonnements_page.dart';
import 'package:sami/services/abonnement_service.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kTeal    = Color(0xFF1D9E75);
const _kAccent  = Color(0xFFFF8F00);

class DashboardCouturier extends StatefulWidget {
  const DashboardCouturier({super.key});
  @override
  State<DashboardCouturier> createState() => _DashboardCouturierState();
}

class _DashboardCouturierState extends State<DashboardCouturier>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  /// Le couturier soigne SA vitrine : atelier, présentation, spécialités.
  Future<void> _editerProfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final q = await FirebaseFirestore.instance
        .collection('couturiers')
        .where('utilisateurId', isEqualTo: uid)
        .limit(1)
        .get();
    if (q.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil couturier introuvable.')));
      }
      return;
    }
    final doc = q.docs.first;
    final data = doc.data();
    final atelier =
        TextEditingController(text: data['nomAtelier'] as String? ?? '');
    final bio = TextEditingController(text: data['bio'] as String? ?? '');
    final spec = TextEditingController(
        text: (data['specialites'] as List?)?.join(', ') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mon profil couturier'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: atelier,
              decoration: const InputDecoration(
                  labelText: 'Nom de l\'atelier',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: bio,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Présentation (les clients la lisent)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: spec,
              decoration: const InputDecoration(
                  labelText: 'Spécialités (virgules)',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      await doc.reference.update({
        'nomAtelier': atelier.text.trim(),
        'bio': bio.text.trim(),
        'specialites': spec.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil mis à jour ✅'),
            backgroundColor: Colors.green));
      }
    }
    atelier.dispose();
    bio.dispose();
    spec.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon espace couturier'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Modifier mon profil',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editerProfil,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Commandes'),
            Tab(icon: Icon(Icons.style, size: 18), text: 'Mes modèles'),
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'Stats'),
            Tab(icon: Icon(Icons.workspace_premium, size: 18), text: 'Abonnement'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OngletCommandes(uid: _uid),
          _OngletModeles(uid: _uid),
          _OngletStats(uid: _uid),
          _OngletAbonnement(uid: _uid),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 1 — COMMANDES
// ═══════════════════════════════════════════════════════════════════════════

class _OngletCommandes extends StatelessWidget {
  final String uid;
  const _OngletCommandes({required this.uid});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          color: Colors.white,
          child: const TabBar(
            labelColor: _kPrimary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _kPrimary,
            tabs: [
              Tab(text: 'À traiter'),
              Tab(text: 'En cours'),
              Tab(text: 'Terminées'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _ListeCommandesCouturier(uid: uid, statuts: [
            StatutCommandeCouturier.enAttente,
            StatutCommandeCouturier.devisPropose,
            StatutCommandeCouturier.confirmeeCouturier,
          ]),
          _ListeCommandesCouturier(uid: uid, statuts: [
            StatutCommandeCouturier.rdvPlanifie,
            StatutCommandeCouturier.enConfection,
            StatutCommandeCouturier.preteLivraison,
          ]),
          _ListeCommandesCouturier(uid: uid, statuts: [
            StatutCommandeCouturier.livree,
            StatutCommandeCouturier.terminee,
          ]),
        ])),
      ]),
    );
  }
}

class _ListeCommandesCouturier extends StatelessWidget {
  final String uid;
  final List<StatutCommandeCouturier> statuts;
  const _ListeCommandesCouturier({required this.uid, required this.statuts});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommandeCouturier>>(
      // 1 seul where (pas d'index requis) ; filtrage par statut + tri côté client
      stream: CoutureService.streamCommandesCouturier(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator(color: _kPrimary));
        final toutes = snap.data ?? [];
        final filtrees = toutes.where((c) => statuts.contains(c.statut)).toList();

        // OFFLINE-FIRST : précharger les clés QR des livraisons du couturier
        // tant qu'il a du réseau. Trajet 1 : il est la DESTINATION (reçoit le
        // pagne) → rôle client. Trajet 2 : il est l'ORIGINE (remet le vêtement
        // au livreur) → rôle boutique.
        for (final cmd in filtrees) {
          if (cmd.livraisonPagneId != null) {
            QRCryptoService.prechargerDepuisFirestore(
              livraisonId: cmd.livraisonPagneId!,
              role: RoleLivraison.client,
            );
          }
          if (cmd.livraisonRetourId != null) {
            QRCryptoService.prechargerDepuisFirestore(
              livraisonId: cmd.livraisonRetourId!,
              role: RoleLivraison.boutique,
            );
          }
        }
        if (filtrees.isEmpty)
          return const Center(child: Text('Aucune commande ici', style: TextStyle(color: Colors.grey)));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtrees.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _CarteCommandeCouturier(commande: filtrees[i]),
        );
      },
    );
  }
}

class _CarteCommandeCouturier extends StatelessWidget {
  final CommandeCouturier commande;
  const _CarteCommandeCouturier({required this.commande});

  @override
  Widget build(BuildContext context) {
    final (couleur, label) = _statutInfo(commande.statut);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: couleur.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(
              'Commande #${commande.id.substring(0, 6).toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: couleur.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          // Mesures snapshot
          Text(
            '${commande.mesuresSnapshot.length} mesures · ${commande.modeRencontre.name}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(
              PrixFCFA.formater(commande.prixConvenu),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 15),
            )),
            if (commande.statut == StatutCommandeCouturier.enAttente)
              ElevatedButton(
                onPressed: () => _confirmer(context, commande),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary, foregroundColor: Colors.white,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Accepter', style: TextStyle(fontSize: 12)),
              ),
            if (commande.statut == StatutCommandeCouturier.devisPropose)
              Text('Devis envoyé : ${PrixFCFA.formater(commande.prixPropose ?? 0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            if (commande.statut == StatutCommandeCouturier.enConfection)
              ElevatedButton(
                onPressed: () => _marquerPrete(context, commande),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal, foregroundColor: Colors.white,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Prête', style: TextStyle(fontSize: 12)),
              ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final u = await FirebaseFirestore.instance
                    .collection('utilisateurs').doc(commande.clientId).get();
                final nom = u.data()?['nom'] as String? ?? 'Client';
                if (!context.mounted) return;
                MessageService.contacter(context,
                    autreUserId: commande.clientId,
                    autreNom: nom,
                    contexte: 'Commande couture',
                    contexteId: commande.id);
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 15),
              label: const Text('Écrire au client',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: _kPrimary),
            ),
          ),
          if (commande.statut == StatutCommandeCouturier.enAttente)
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: CommandeCouturier.collection.doc(commande.id).get(),
              builder: (c2, s2) {
                final cp = (s2.data?.data())?['contrePropositionClient'];
                if (cp == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '💬 Contre-proposition du client : ${PrixFCFA.formater((cp as num? ?? 0).toDouble())}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w600)),
                );
              },
            ),
          // Le couturier peut demander au client de REPRENDRE ses mesures
          // (doute sur une valeur, morphologie particulière…)
          if (commande.statut == StatutCommandeCouturier.enAttente ||
              commande.statut == StatutCommandeCouturier.confirmeeCouturier)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await NotificationService.envoyer(
                    destinataireId: commande.clientId,
                    titre: 'Mesures à vérifier 📏',
                    message:
                        'Votre couturier vous demande de vérifier/reprendre vos mesures pour cette commande.',
                    route: '/mes-coutures',
                    refId: commande.id,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Demande envoyée au client'),
                        backgroundColor: Colors.green));
                  }
                },
                icon: const Icon(Icons.straighten, size: 15),
                label: const Text('Demander de reprendre les mesures',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          // Bouton "Proposer un prix" pour les commandes sur devis en attente
          if (commande.statut == StatutCommandeCouturier.enAttente &&
              commande.surDevis)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _proposerPrix(context, commande),
                icon: const Icon(Icons.request_quote_outlined, size: 16),
                label: const Text('Proposer un prix (devis)',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
              ),
            ),
          // Notes client
          if (commande.notesClient?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '📝 ${commande.notesClient}',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  (Color, String) _statutInfo(StatutCommandeCouturier s) => switch (s) {
    StatutCommandeCouturier.enAttente          => (Colors.orange, 'En attente'),
    StatutCommandeCouturier.devisPropose       => (Colors.deepOrange, 'Devis envoyé'),
    StatutCommandeCouturier.confirmeeCouturier => (Colors.blue, 'Confirmée'),
    StatutCommandeCouturier.rdvPlanifie        => (Colors.indigo, 'RDV planifié'),
    StatutCommandeCouturier.enConfection       => (_kPrimary, 'En confection'),
    StatutCommandeCouturier.preteLivraison     => (_kTeal, 'Prête'),
    StatutCommandeCouturier.livree             => (Colors.green, 'Livrée'),
    StatutCommandeCouturier.terminee           => (Colors.green, 'Terminée ✓'),
    StatutCommandeCouturier.annulee            => (Colors.red, 'Annulée'),
    StatutCommandeCouturier.litige             => (Colors.red, 'Litige'),
  };

  Future<void> _proposerPrix(BuildContext ctx, CommandeCouturier cmd) async {
    final ctrl = TextEditingController(
        text: cmd.prixConvenu > 0 ? cmd.prixConvenu.toStringAsFixed(0) : '');
    final prix = await showDialog<double>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Proposer un prix'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Indiquez le prix de confection pour cette demande. '
                'Le client devra l\'accepter.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  suffixText: 'FCFA', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.pop(c, v);
            },
            child: const Text('Envoyer le devis'),
          ),
        ],
      ),
    );
    if (prix != null) {
      await CoutureService.proposerDevis(
        commandeId: cmd.id,
        couturierId: cmd.couturierId,
        prixPropose: prix,
      );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Devis envoyé au client'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }

  Future<void> _confirmer(BuildContext ctx, CommandeCouturier cmd) async {
    await CommandeCouturier.collection.doc(cmd.id).update({
      'statut': StatutCommandeCouturier.confirmeeCouturier.name,
      'dateConfirmation': FieldValue.serverTimestamp(),
    });
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Commande acceptée'), backgroundColor: Colors.green));
  }

  Future<void> _marquerPrete(BuildContext ctx, CommandeCouturier cmd) async {
    // VALIDATION QUALITÉ : photo du vêtement fini (le client la voit avant
    // la livraison — désamorce les litiges à l'atelier).
    String? photoUrl;
    if (await ParametresService.photoFinaleObligatoire()) {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 70);
      if (x == null) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Photo du vêtement fini requise')));
        }
        return;
      }
      try {
        photoUrl = await StockageService.uploadXFile(
          fichier: x, dossier: 'photos_finales');
      } catch (_) {}
    }

    // La photo d'abord…
    if (photoUrl != null) {
      await CommandeCouturier.collection.doc(cmd.id).update({
        'photoFinale': photoUrl,
      });
    }
    // …puis le statut via le SERVICE : c'est lui qui crée le TRAJET 2
    // (couturier → client) et déclenche l'assignation du livreur.
    await CoutureService.changerStatut(
      commandeId: cmd.id,
      statut: StatutCommandeCouturier.preteLivraison,
    );
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Vêtement marqué prêt pour livraison'), backgroundColor: _kTeal));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 2 — MES MODÈLES
// ═══════════════════════════════════════════════════════════════════════════

class _OngletModeles extends StatelessWidget {
  final String uid;
  const _OngletModeles({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreerModelePage(couturierId: uid),
          ),
        ),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau modèle'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ModeleCouture.collection
            .where('couturierId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.style_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Aucun modèle publié', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Créez votre premier modèle pour recevoir des commandes',
                  style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
            ]));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: snap.data!.docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final modele = ModeleCouture.fromDoc(snap.data!.docs[i]);
              return _CarteModele(modele: modele);
            },
          );
        },
      ),
    );
  }
}

class _CarteModele extends StatelessWidget {
  final ModeleCouture modele;
  const _CarteModele({required this.modele});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreerModelePage(
              couturierId: modele.couturierId,
              modeleExistant: modele,
            ),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.content_cut, color: _kPrimary, size: 22),
        ),
        title: Text(
          modele.nom(Langue.fr),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${modele.typeVetement.name} · ${modele.mesuresRequises.length} mesures',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Row(children: [
            const Icon(Icons.star, color: Colors.amber, size: 12),
            Text(
              ' ${modele.noteMoyenne.toStringAsFixed(1)} · ${modele.nombreRealisations} réalisations',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ]),
        ]),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              modele.surDevis
                  ? 'Sur devis'
                  : PrixFCFA.formater(modele.prixBase),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary),
            ),
            Switch(
              value: modele.estActif,
              onChanged: (v) => ModeleCouture.collection.doc(modele.id).update({'estActif': v}),
              activeColor: _kTeal,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 3 — STATISTIQUES
// ═══════════════════════════════════════════════════════════════════════════

class _OngletStats extends StatelessWidget {
  final String uid;
  const _OngletStats({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('profils_couturier').doc(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final gains = (d['gainsTotalMois'] as num?)?.toDouble() ?? 0;
        final commissions = (d['commissionPayeeMois'] as num?)?.toDouble() ?? 0;
        final nbMois = d['commandesMois'] as int? ?? 0;
        final nbTotal = d['commandesTotal'] as int? ?? 0;
        final netMois = gains - commissions;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Gains du mois
            _CardStat(
              titre: 'Ce mois-ci',
              items: [
                _StatItem('Commandes', '$nbMois', Icons.receipt_long, Colors.blue),
                _StatItem('Gains bruts', PrixFCFA.formater(gains), Icons.trending_up, _kTeal),
                _StatItem('Commission', '-${PrixFCFA.formater(commissions)}', Icons.percent, Colors.orange),
                _StatItem('Net perçu', PrixFCFA.formater(netMois), Icons.account_balance_wallet, _kPrimary),
              ],
            ),
            const SizedBox(height: 14),
            // Totaux
            _CardStat(
              titre: 'Depuis le début',
              items: [
                _StatItem('Total commandes', '$nbTotal', Icons.all_inclusive, Colors.grey),
                _StatItem('Gains totaux', PrixFCFA.formater((d['gainsTotal'] as num?)?.toDouble() ?? 0), Icons.savings, _kTeal),
              ],
            ),
            const SizedBox(height: 14),
            // Abonnement actuel — lu sur la fiche `couturiers` (la source que
            // la commission et la limite de modèles utilisent), plus sur
            // `profils_couturier` (stats seulement).
            FutureBuilder<List<(String, String)>>(
              future: AbonnementService.fiches(ProfilAbonnement.couturier, uid),
              builder: (_, sf) {
                final ficheId = sf.data?.firstOrNull?.$1;
                if (ficheId == null) return const SizedBox.shrink();
                return FutureBuilder<AbonnementActuel>(
                  future: AbonnementService.actuel(ProfilAbonnement.couturier, ficheId),
                  builder: (_, sa) {
                    final a = sa.data;
                    final plan = a == null
                        ? null
                        : AbonnementCouturier.catalogue[TypeAbonnementCouturier.values
                            .firstWhere((e) => e.name == (a.actif ? a.planId : 'gratuit'),
                                orElse: () => TypeAbonnementCouturier.gratuit)];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Abonnement actuel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.workspace_premium, color: Colors.teal, size: 20),
                          const SizedBox(width: 8),
                          Text(plan?.nom ?? '…', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          if (a != null && a.actif && a.finLe != null)
                            Text('jusqu\'au ${a.finFmt}',
                                style: const TextStyle(color: Colors.teal, fontSize: 12)),
                        ]),
                      ]),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            // SERVICE : numérisation du catalogue (source de revenu plateforme)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [
                    Icon(Icons.auto_awesome, color: _kPrimary, size: 20),
                    SizedBox(width: 8),
                    Text('Numérisation de votre catalogue',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      'Vous n\'avez pas le temps de saisir vos modèles ? '
                      'Notre équipe vient photographier et mettre en ligne '
                      'votre catalogue pour vous.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _demanderNumerisation(context, uid),
                    icon: const Icon(Icons.support_agent, size: 16),
                    label: const Text('Demander ce service'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 42)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _demanderNumerisation(BuildContext ctx, String uid) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Numérisation du catalogue'),
        content: const Text(
            'Notre équipe vous contactera pour convenir d\'un rendez-vous. '
            'Ce service est payant et facturé selon le nombre de modèles. '
            'Confirmer la demande ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('demandes_numerisation').add({
        'couturierId': uid,
        'statut': 'nouvelle',
        'dateCreation': FieldValue.serverTimestamp(),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Demande envoyée — nous vous contacterons'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }
}

class _CardStat extends StatelessWidget {
  final String titre;
  final List<_StatItem> items;
  const _CardStat({required this.titre, required this.items});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.4,
        children: items.map((item) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: item.couleur.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(item.icone, color: item.couleur, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(item.valeur, style: TextStyle(fontWeight: FontWeight.bold, color: item.couleur, fontSize: 13)),
              Text(item.label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ])),
          ]),
        )).toList(),
      ),
    ]),
  );
}

class _StatItem {
  final String label, valeur;
  final IconData icone;
  final Color couleur;
  const _StatItem(this.label, this.valeur, this.icone, this.couleur);
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 4 — ABONNEMENT
// ═══════════════════════════════════════════════════════════════════════════

class _OngletAbonnement extends StatelessWidget {
  final String uid;
  const _OngletAbonnement({required this.uid});

  @override
  Widget build(BuildContext context) {
    // UN seul écran de souscription (PageSouscription) : flux MoMo déclaré
    // → vérification staff → activation sur la fiche `couturiers`. L'ancien
    // écran embarqué activait un plan payant en écrivant `profils_couturier`
    // sans aucun paiement (et le reste de l'app ne le lisait pas).
    return FutureBuilder<Utilisateur?>(
      future: Utilisateur.fromUid(uid),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: _kPrimary));
        }
        final u = snap.data;
        if (u == null) return const Center(child: Text('Compte introuvable'));
        return PageSouscription(
            utilisateur: u, profil: ProfilAbonnement.couturier, integree: true);
      },
    );
  }
}

