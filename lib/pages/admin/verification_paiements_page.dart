import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Vérification des paiements'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
      ),
    );
  }
}
