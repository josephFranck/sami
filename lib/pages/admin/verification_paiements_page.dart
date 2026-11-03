import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/services/abonnement_service.dart';
import 'package:sami/services/log_service.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// VÉRIFICATION DES TRANSFERTS DÉCLARÉS : l'agent compare la référence
/// déclarée au SMS reçu sur le téléphone marchand, puis valide — la
/// préparation du colis se débloque à l'instant.
class VerificationPaiementsPage extends StatelessWidget {
  const VerificationPaiementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FA),
        appBar: AppBar(
          title: const Text('Vérification des paiements'),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF8F00),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Commandes', icon: Icon(Icons.shopping_bag_outlined, size: 18)),
              Tab(text: 'Abonnements', icon: Icon(Icons.workspace_premium_outlined, size: 18)),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _OngletCommandes(),
          _OngletAbonnements(),
        ]),
      ),
    );
  }
}

/// Transferts déclarés sur les COMMANDES (sessions momo_declare).
class _OngletCommandes extends StatelessWidget {
  const _OngletCommandes();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sessions_commande')
            .where('methodePaiement', isEqualTo: 'momo_declare')
            .where('paiementVerifie', isEqualTo: false)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'Erreur : ${snap.error}\n(index Firestore requis ? '
                  'le lien de création est dans les logs)',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
                child: Text('✅ Aucun transfert en attente de vérification',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final s = d.data();
              final total = (s['total'] as num?)?.toDouble() ??
                  (s['totalClient'] as num?)?.toDouble() ??
                  0;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Text(PrixFCFA.formater(total),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const Spacer(),
                        Text(
                            (s['dateCreation'] as Timestamp?)
                                    ?.toDate()
                                    .toString()
                                    .substring(0, 16) ??
                                '',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade600)),
                      ]),
                      const SizedBox(height: 6),
                      SelectableText(
                          'Référence déclarée : ${s['refPaiement'] ?? '—'}\n'
                          'Client : ${s['clientId'] ?? '?'}',
                          style: const TextStyle(fontSize: 12, height: 1.4)),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Expanded(
                          child: Text(
                              'Vérifiez le SMS sur le téléphone marchand.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white),
                          onPressed: () async {
                            await LogService.log(
                                'paiement_declare_verifie',
                                details: {'sessionId': d.id});
                            await d.reference.update({
                              'paiementVerifie': true,
                              'paiementVerifieLe':
                                  FieldValue.serverTimestamp(),
                            });
                            // débloquer les boutiquiers de la session
                            final scs = await FirebaseFirestore.instance
                                .collection('sous_commandes')
                                .where('sessionId', isEqualTo: d.id)
                                .get();
                            for (final sc in scs.docs) {
                              final bId =
                                  sc.data()['boutiqueId'] as String?;
                              if (bId == null) continue;
                              final b = await FirebaseFirestore.instance
                                  .collection('boutiques')
                                  .doc(bId)
                                  .get();
                              for (final g in List<String>.from(
                                  b.data()?['gerants'] as List? ?? [])) {
                                await NotificationService.envoyer(
                                  destinataireId: g,
                                  titre: 'Paiement confirmé 💰',
                                  message:
                                      'Le transfert est vérifié — vous pouvez préparer le colis.',
                                  route: '/dashboard_boutiquier',
                                );
                              }
                            }
                            final cId = s['clientId'] as String?;
                            if (cId != null) {
                              await NotificationService.envoyer(
                                destinataireId: cId,
                                titre: 'Paiement vérifié ✅',
                                message:
                                    'Votre transfert est confirmé — la préparation démarre.',
                                route: '/commandes',
                              );
                            }
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Vérifié'),
                        ),
                      ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
    );
  }
}

/// Demandes d'ABONNEMENT par transfert déclaré (AbonnementService).
/// « Valider » active le plan sur la fiche et trace la transaction ;
/// « Refuser » clôt la demande avec un motif envoyé à l'abonné.
class _OngletAbonnements extends StatelessWidget {
  const _OngletAbonnements();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DemandeAbonnement>>(
      stream: AbonnementService.aVerifier(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Erreur : ${snap.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = snap.data!;
        if (l.isEmpty) {
          return const Center(
              child: Text('✅ Aucune demande d\'abonnement en attente',
                  style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: l.length,
          itemBuilder: (_, i) {
            final d = l[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.workspace_premium, color: Color(0xFF6A1B9A), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${d.profil.libelle} · ${d.planNom}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text(d.prix <= 0 ? 'Gratuit' : PrixFCFA.formater(d.prix),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ]),
                    const SizedBox(height: 6),
                    SelectableText(
                        '${d.entiteNom.isNotEmpty ? '${d.entiteNom}\n' : ''}'
                        'Référence déclarée : ${d.refPaiement.isEmpty ? '—' : d.refPaiement}\n'
                        'Numéro utilisé : ${d.numeroPaiement.isEmpty ? '—' : d.numeroPaiement}\n'
                        'Durée : ${d.dureeJours} j · Demandeur : ${d.utilisateurId}'
                        '${d.dateCreation != null ? '\nLe ${d.dateCreation!.toString().substring(0, 16)}' : ''}',
                        style: const TextStyle(fontSize: 12, height: 1.4)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Text(
                            d.prix <= 0
                                ? 'Plan gratuit : aucune vérification de transfert.'
                                : 'Vérifiez le SMS sur le téléphone marchand.',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () => _refuser(context, d),
                        child: const Text('Refuser'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () => _valider(context, d),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Valider'),
                      ),
                    ]),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _valider(BuildContext context, DemandeAbonnement d) async {
    final staff = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await AbonnementService.valider(d, staff);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Abonnement activé ✅'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Activation impossible : $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _refuser(BuildContext context, DemandeAbonnement d) async {
    final ctrl = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser la demande'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Motif (envoyé à l\'abonné)',
              hintText: 'Ex : aucun transfert reçu avec cette référence',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Refuser')),
        ],
      ),
    );
    ctrl.dispose();
    if (motif == null) return;
    final staff = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await AbonnementService.refuser(d, staff, motif);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demande refusée'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Refus impossible : $e'), backgroundColor: Colors.red));
      }
    }
  }
}
