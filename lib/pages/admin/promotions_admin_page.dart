import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/promotions_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// VALIDATION DES PROMOTIONS : chaque proposition arrive avec son analyse
/// d'impact — avertissement ROUGE quand un pagne serait vendu À PERTE.
class PromotionsAdminPage extends StatelessWidget {
  const PromotionsAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    // restauration paresseuse des promos expirées à chaque visite
    PromotionsService.restaurerExpirees();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Promotions'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PromotionsService.collection
            .orderBy('dateCreation', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Erreur : ${snap.error}',
                    style:
                        const TextStyle(color: Colors.red, fontSize: 12)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
                child: Text('Aucune promotion proposée pour le moment',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final p = d.data();
              final statut = p['statut'] as String? ?? '?';
              final pertes = (p['pertes'] as num?)?.toInt() ?? 0;
              final impact =
                  List<Map<String, dynamic>>.from(p['impact'] ?? []);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                            '🏷️ -${(p['reductionPct'] as num?)?.toStringAsFixed(0)} % '
                            '· ${(p['pagneIds'] as List?)?.length ?? 0} pagne(s) '
                            '· ${(p['dureeHeures'] as num?)?.toInt() ?? 0} h',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: switch (statut) {
                                'proposee' => Colors.orange.shade100,
                                'active' => Colors.green.shade100,
                                _ => Colors.grey.shade200,
                              },
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(statut,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ]),
                      // ═══ L'AVERTISSEMENT ANTI-PERTE ═══
                      if (pertes > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.red.shade200)),
                          child: Text(
                              '⚠️ PERTE : $pertes pagne(s) seraient vendus '
                              'SOUS leur coût d\'achat !',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 6),
                      ...impact.take(4).map((it) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                                '• ${it['nom']} : '
                                '${PrixFCFA.formater((it['prix'] as num? ?? 0).toDouble())} → '
                                '${PrixFCFA.formater((it['prixReduit'] as num? ?? 0).toDouble())}'
                                '${it['perte'] == true ? '  🔴 À PERTE' : it['sousPlancher'] == true ? '  ⛔ sous plancher' : ''}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: it['perte'] == true
                                        ? Colors.red
                                        : Colors.grey.shade700))),
                          ),
                      if (impact.length > 4)
                        Text('… et ${impact.length - 4} autres',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      if (statut == 'proposee')
                        Row(children: [
                          const Spacer(),
                          TextButton(
                            onPressed: () async {
                              await PromotionsService.refuser(d.id,
                                  'Refusée par l\'administrateur.');
                            },
                            child: const Text('Refuser',
                                style: TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: pertes > 0
                                    ? Colors.orange
                                    : Colors.green,
                                foregroundColor: Colors.white),
                            onPressed: () async {
                              if (pertes > 0) {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title:
                                        const Text('Valider malgré la PERTE ?'),
                                    content: Text(
                                        '$pertes pagne(s) seront vendus sous leur coût d\'achat.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Annuler')),
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child:
                                              const Text('Valider quand même')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                              }
                              await PromotionsService.valider(d.id);
                            },
                            child: Text(pertes > 0
                                ? 'Valider (⚠️ perte)'
                                : 'Valider'),
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
