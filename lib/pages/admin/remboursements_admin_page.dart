import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/credit_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

/// FILE DES AVOIRS ET REMBOURSEMENTS (`remboursements_a_faire`) : annulations,
/// retours, cashback fidélité, primes de parrainage, avoirs à restituer.
/// Avoir → « Créditer » : CreditService.crediterClient (solde + mouvement).
/// Mobile Money → le staff fait le geste MoMo puis marque « Fait ».
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
              // tout ce qui n'est pas un remboursement MoMo manuel devient
              // un AVOIR sur le compte du client
              final estCredits = type != 'mobile_money';
              final libelle = switch (type) {
                'parrainage' => 'Prime de parrainage',
                'cashback' => 'Cashback fidélité',
                'credits' => r['motif'] == 'commande_echouee_apres_debit'
                    ? 'Avoir à restituer (commande échouée)'
                    : 'Remboursement en avoir',
                _ => 'Remboursement Mobile Money',
              };
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
                      '$libelle · réf ${r['refPaiement'] ?? '?'}\n'
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
                        // crédite l'AVOIR (écriture STAFF) ET trace le
                        // mouvement — visible dans l'historique du client.
                        // Avant : incrément nu, absent de l'historique.
                        try {
                          await CreditService.crediterClient(
                            clientId: r['clientId'] as String? ?? '',
                            montant: montant,
                            type: switch (type) {
                              'parrainage' => TypeMouvementCredit.parrainage,
                              'cashback' => TypeMouvementCredit.cashback,
                              _ => TypeMouvementCredit.remboursement,
                            },
                            description: libelle,
                            referenceTransaction: r['refPaiement'] as String?,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Échec du crédit : $e'),
                                backgroundColor: Colors.red));
                          }
                          return;
                        }
                      }
                      // MoMo : le staff a fait le transfert à la main
                      await d.reference.update({
                        'statut': 'traite',
                        'traiteLe': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(estCredits
                                ? 'Avoir crédité au client ✅'
                                : 'Marqué remboursé (MoMo manuel) ✅'),
                            backgroundColor: Colors.green));
                      }
                    },
                    child: Text(estCredits ? 'Créditer' : 'Fait ✓',
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
