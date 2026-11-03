import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Tableau admin : livraisons signalées 'à vérifier' par les contrôles
/// anti-fraude (GPS incohérent, validation par code/signature de secours).
/// L'admin les contrôle avant de débloquer le paiement.
class LivraisonsAVerifierPage extends StatefulWidget {
  const LivraisonsAVerifierPage({super.key});

  @override
  State<LivraisonsAVerifierPage> createState() =>
      _LivraisonsAVerifierPageState();
}

class _LivraisonsAVerifierPageState extends State<LivraisonsAVerifierPage>
    with PageProtegee {
  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.peut(u, 'litiges')) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Livraisons à vérifier'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Livraisons à vérifier'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // 1 seul filtre (pas d'index composite) ; tri côté client.
            stream: FirebaseFirestore.instance
                .collection('livraisons')
                .where('aVerifier', isEqualTo: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final livraisons = snap.data!.docs
                  .map((d) => Livraison.fromFirebaseDocument(d))
                  .toList()
                ..sort((a, b) => b.dateCreation.compareTo(a.dateCreation));

              if (livraisons.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_outlined,
                          size: 56, color: Colors.green.shade300),
                      const SizedBox(height: 12),
                      const Text('Aucune livraison à vérifier',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: livraisons.length,
                itemBuilder: (_, i) => _carte(livraisons[i]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _carte(Livraison l) {
    final secours = switch (l.validationSecours) {
      'code_court' => 'Validé par code de secours',
      'signature' => 'Validé par signature',
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.flag_outlined,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Livraison ${l.id.substring(0, l.id.length.clamp(0, 8))}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Statut : ${l.statut.name}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (l.motifVerification != null)
              _ligneInfo(Icons.warning_amber_outlined, 'Motif',
                  l.motifVerification!, Colors.orange),
            if (secours != null)
              _ligneInfo(Icons.vpn_key_outlined, 'Méthode', secours,
                  Colors.blueGrey),
            _ligneInfo(Icons.place_outlined, 'Destination',
                l.destinationAdresse, Colors.grey),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _traiter(l, litige: true),
                    icon: const Icon(Icons.report_gmailerrorred_outlined,
                        size: 16),
                    label: const Text('Litige', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _traiter(l, litige: false),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Valider',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(IconData icone, String label, String valeur, Color c) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 15, color: c),
            const SizedBox(width: 8),
            SizedBox(
                width: 80,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600))),
            Expanded(
                child: Text(valeur,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Future<void> _traiter(Livraison l, {required bool litige}) async {
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(l.id)
        .update({
      'aVerifier': false,
      'verificationAdmin': litige ? 'litige' : 'validee',
      'dateVerificationAdmin': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(litige
            ? 'Livraison marquée en litige'
            : 'Livraison validée'),
        backgroundColor: litige ? Colors.red : Colors.green,
      ));
    }
  }
}
