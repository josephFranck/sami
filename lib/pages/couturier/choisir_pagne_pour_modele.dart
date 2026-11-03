import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/pages/couturier/commander_couture_page.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/l10n/tr.dart';

const _kOrange = Colors.deepOrange;

/// PARCOURS INVERSÉ : le client a choisi un MODÈLE (depuis l'accueil) ;
/// il choisit maintenant le PAGNE à faire coudre, puis commande.
class ChoisirPagnePourModelePage extends StatelessWidget {
  final ModeleCouture modele;
  const ChoisirPagnePourModelePage({super.key, required this.modele});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      appBar: AppBar(
        title: Text(Tr.s.tissuPour(modele.nom),
            style: const TextStyle(fontSize: 16)),
        backgroundColor: _kOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        // Rappel du modèle choisi
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kOrange.withOpacity(0.3)),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46, height: 46,
                child: modele.photosExemples.isNotEmpty
                    ? ImageUniverselle(
                        source: modele.photosExemples.first,
                        fit: BoxFit.cover)
                    : const Icon(Icons.checkroom, color: _kOrange),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Tr.s.choisissezPagneCoudre(modele.nom, modele.surDevis ? Tr.s.prixSurDevis : PrixFCFA.formater(modele.prixBase)),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('pagnes')
                .where('disponible', isEqualTo: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kOrange));
              }
              final pagnes =
                  snap.data!.docs.map(Pagne.fromFirebaseDocument).toList();
              if (pagnes.isEmpty) {
                return Center(
                    child: Text(Tr.s.aucunPagneDisponiblePourMoment,
                        style: TextStyle(color: Colors.grey)));
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.74),
                itemCount: pagnes.length,
                itemBuilder: (_, i) {
                  final p = pagnes[i];
                  return GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommanderCouturePage(
                            pagne: p, modeleInitialId: modele.id),
                      ),
                    ),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              // Photos BALAYABLES : le client feuillette le
                              // tissu du doigt sans quitter la grille.
                              child: p.images.isEmpty
                                  ? Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image,
                                          color: Colors.grey))
                                  : PageView.builder(
                                      itemCount: p.images.length,
                                      itemBuilder: (_, j) =>
                                          ImageUniverselle(
                                              source: p.images[j],
                                              fit: BoxFit.cover),
                                    ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.nom,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                Text(PrixFCFA.formater(p.prixParBoutique),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: _kOrange,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
