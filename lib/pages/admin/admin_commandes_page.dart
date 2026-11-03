import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// VUE ADMIN : TOUTES les commandes de la plateforme, filtrables par
/// statut — le pouls de l'activité d'un seul écran.
class AdminCommandesPage extends StatefulWidget {
  const AdminCommandesPage({super.key});
  @override
  State<AdminCommandesPage> createState() => _AdminCommandesPageState();
}

class _AdminCommandesPageState extends State<AdminCommandesPage> {
  String? _filtre; // null = toutes

  static const _statuts = <(String?, String, Color)>[
    (null, 'Toutes', Colors.blueGrey),
    ('enAttente', 'En attente', Colors.orange),
    ('confirmeeBoutique', 'Confirmées', Colors.blue),
    ('enPreparation', 'En préparation', Colors.indigo),
    ('prete', 'Prêtes', Colors.teal),
    ('enCoursLivraison', 'En livraison', Colors.purple),
    ('livree', 'Livrées', Colors.green),
    ('annulee', 'Annulées', Colors.red),
  ];

  Query<Map<String, dynamic>> get _query {
    final base = FirebaseFirestore.instance.collection('sous_commandes');
    if (_filtre == null) {
      return base.orderBy('dateCreation', descending: true).limit(80);
    }
    return base
        .where('statut', isEqualTo: _filtre)
        .orderBy('dateCreation', descending: true)
        .limit(80);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Toutes les commandes'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Retours',
            icon: const Icon(Icons.assignment_return_outlined),
            onPressed: () => Navigator.pushNamed(context, '/retours'),
          ),
        ],
      ),
      body: Column(children: [
        // Filtres statut
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            children: _statuts.map((s) {
              final actif = _filtre == s.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(s.$2, style: const TextStyle(fontSize: 12)),
                  selected: actif,
                  selectedColor: s.$3.withOpacity(0.18),
                  labelStyle: TextStyle(
                      color: actif ? s.$3 : Colors.black87,
                      fontWeight: actif ? FontWeight.bold : FontWeight.normal),
                  onSelected: (_) => setState(() => _filtre = s.$1),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                    child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erreur : ${snap.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ));
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Text('Aucune commande dans ce statut',
                        style: TextStyle(color: Colors.grey)));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final sc = SousCommande.fromDoc(docs[i]);
                  final coul = _statuts
                      .firstWhere((s) => s.$1 == sc.statut.name,
                          orElse: () => _statuts.first)
                      .$3;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(sc.boutiqueNom,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5))),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: coul.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(sc.statut.name,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: coul,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ]),
                          Text(
                              quandFr(sc.dateCreation,
                                  prefixe: 'Commandée le '),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          ...sc.articles.take(3).map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: a.pagneImage != null
                                          ? ImageUniverselle(
                                              source: a.pagneImage!,
                                              fit: BoxFit.cover)
                                          : Container(
                                              color: Colors.purple.shade50,
                                              child: const Icon(
                                                  Icons.checkroom,
                                                  size: 15)),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                      child: Text(
                                          '${a.pagneNom} × ${a.quantite}',
                                          style: const TextStyle(
                                              fontSize: 12))),
                                ]),
                              )),
                          if (sc.articles.length > 3)
                            Text('… +${sc.articles.length - 3} article(s)',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade500)),
                          const SizedBox(height: 4),
                          Text(PrixFCFA.formater(sc.sousTotal),
                              style: const TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
