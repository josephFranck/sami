import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// TRAITEMENT DES REMBOURSEMENTS : la file créée par les annulations.
/// Crédits → un bouton re-crédite le client (écriture staff, permise).
/// Mobile Money → le staff fait le geste MoMo puis marque « traité ».
class RemboursementsAdminPage extends StatelessWidget {
  const RemboursementsAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Remboursements'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('remboursements_a_faire')
            .where('statut', isEqualTo: 'a_traiter')
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
                child: Text('✅ Aucun remboursement en attente',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final r = d.data();
              final montant = (r['montant'] as num?)?.toDouble() ?? 0;
              final type = r['type'] as String? ?? 'mobile_money';
              final estCredits = type == 'credits' || type == 'parrainage';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                      estCredits ? Icons.toll : Icons.phone_android,
                      color: estCredits ? Colors.amber : Colors.green),
                  title: Text(PrixFCFA.formater(montant),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${estCredits ? 'Crédits' : 'Mobile Money'} · '
                      'réf ${r['refPaiement'] ?? '?'}\n'
                      'client ${r['clientId'] ?? '?'}',
                      style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            estCredits ? Colors.amber.shade700 : Colors.green,
                        foregroundColor: Colors.white),
                    onPressed: () async {
                      if (estCredits) {
                        // re-crédite le client (écriture STAFF : permise)
                        await FirebaseFirestore.instance
                            .collection('utilisateurs')
                            .doc(r['clientId'] as String? ?? '')
                            .update({
                          'creditBalance': FieldValue.increment(montant)
                        });
                      }
                      // MoMo : le staff a fait le transfert à la main
                      await d.reference.update({
                        'statut': 'traite',
                        'traiteLe': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(estCredits
                                ? 'Crédits rendus au client ✅'
                                : 'Marqué remboursé (MoMo manuel) ✅'),
                            backgroundColor: Colors.green));
                      }
                    },
                    child: Text(estCredits ? 'Rendre' : 'Fait ✓',
                        style: const TextStyle(fontSize: 12)),
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
