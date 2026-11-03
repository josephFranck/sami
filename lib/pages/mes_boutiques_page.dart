import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/addboutique.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/pages/editboutique.dart';
import 'package:sami/pages/pagnepage.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// GÉRER MES BOUTIQUES — l'espace du boutiquier : modifier sa boutique
/// (logo, description, activation) et gérer les pagnes de chacune.
class MesBoutiquesPage extends StatelessWidget {
  const MesBoutiquesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddBoutiquePage())),
        icon: const Icon(Icons.add_business),
        label: const Text('Créer une boutique'),
      ),
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Mes boutiques'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: uid == null
          ? const Center(child: Text('Connectez-vous'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('boutiques')
                  .where('gerants', arrayContains: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text('Erreur : ${snap.error}',
                          style: const TextStyle(color: Colors.red)));
                }
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _kPrimary));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucune boutique à votre nom.\nDéposez une candidature « Devenir partenaire » : sa validation crée votre boutique.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final b = Boutique.fromFirebaseDocument(docs[i]);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: (b.logo ?? '').isNotEmpty
                                      ? ImageUniverselle(
                                          source: b.logo, fit: BoxFit.cover)
                                      : Container(
                                          color: _kPrimary.withOpacity(0.1),
                                          child: const Icon(Icons.storefront,
                                              color: _kPrimary)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.nom,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    Text(
                                        b.estActif
                                            ? '🟢 Active (visible des clients)'
                                            : '⛔ Désactivée',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: b.estActif
                                                ? Colors.green
                                                : Colors.red)),
                                  ],
                                ),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              EditBoutiquePage(boutique: b))),
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 16),
                                  label: const Text('Modifier',
                                      style: TextStyle(fontSize: 12.5)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => PagneListPage(
                                              boutiqueId: b.id,
                                              boutiqueNom: b.nom))),
                                  icon: const Icon(Icons.inventory_2_outlined,
                                      size: 16),
                                  label: const Text('Ses pagnes',
                                      style: TextStyle(fontSize: 12.5)),
                                ),
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
