import 'package:flutter/material.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/pages/couturier/commander_couture_page.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kOrange = Colors.deepOrange;

/// CATALOGUE DES MODÈLES — groupés PAR CATÉGORIE (type de vêtement),
/// chaque rangée défile horizontalement, « Voir tout › » ouvre la
/// catégorie complète en grille.
class TousLesModelesPage extends StatelessWidget {
  final TypeVetement? filtreType; // null = toutes les catégories
  const TousLesModelesPage({super.key, this.filtreType});

  String _libelle(TypeVetement t) => switch (t) {
        TypeVetement.boubou => '👘 Boubous',
        TypeVetement.robe => '👗 Robes',
        TypeVetement.chemise => '👔 Chemises',
        TypeVetement.pantalon => '👖 Pantalons',
        TypeVetement.jupe => '🩳 Jupes',
        TypeVetement.ensemble => '🧥 Ensembles',
        _ => '✂️ ${t.name}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(filtreType == null
            ? 'Modèles de couture'
            : _libelle(filtreType!)),
        backgroundColor: _kOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder(
        stream: ModeleCouture.collection
            .where('estActif', isEqualTo: true)
            .limit(120)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Erreur : ${snap.error}',
                    style: const TextStyle(fontSize: 12)));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kOrange));
          }
          final tous = <ModeleCouture>[];
          for (final d in snap.data!.docs) {
            try {
              tous.add(ModeleCouture.fromDoc(d));
            } catch (_) {}
          }
          if (tous.isEmpty) {
            return const Center(
                child: Text('Aucun modèle publié pour le moment',
                    style: TextStyle(color: Colors.grey)));
          }
          // ── VUE CATÉGORIE (Voir tout) : grille simple ──
          if (filtreType != null) {
            final liste =
                tous.where((m) => m.typeVetement == filtreType).toList();
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72),
              itemCount: liste.length,
              itemBuilder: (_, i) => _CarteModele(mo: liste[i]),
            );
          }
          // ── VUE GROUPÉE : une rangée défilable par catégorie ──
          final parType = <TypeVetement, List<ModeleCouture>>{};
          for (final m in tous) {
            parType.putIfAbsent(m.typeVetement, () => []).add(m);
          }
          final types = parType.keys.toList()
            ..sort((a, b) =>
                parType[b]!.length.compareTo(parType[a]!.length));
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: types.map((t) {
              final liste = parType[t]!;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 14, 14, 6),
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                '${_libelle(t)} (${liste.length})',
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold))),
                        GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TousLesModelesPage(
                                      filtreType: t))),
                          child: const Text('Voir tout ›',
                              style: TextStyle(
                                  color: _kOrange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                    SizedBox(
                      height: 172,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: liste.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                              width: 124,
                              child: _CarteModele(mo: liste[i])),
                        ),
                      ),
                    ),
                  ]);
            }).toList(),
          );
        },
      ),
    );
  }
}

class _CarteModele extends StatelessWidget {
  final ModeleCouture mo;
  const _CarteModele({required this.mo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => Scaffold(
                    appBar: AppBar(
                        title: Text(mo.nom),
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white),
                    body: Center(
                        child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'Pour commander ce modèle : choisissez un pagne, puis « Faire coudre ».',
                          textAlign: TextAlign.center),
                    )),
                  ))),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)),
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: double.infinity,
                child: mo.photosExemples.isNotEmpty
                    ? ImageUniverselle(
                        source: mo.photosExemples.first,
                        fit: BoxFit.cover)
                    : Container(
                        color: _kOrange.withOpacity(0.08),
                        child: const Icon(Icons.checkroom,
                            color: _kOrange, size: 30)),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(mo.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          Text(
              mo.surDevis
                  ? 'Sur devis'
                  : PrixFCFA.formater(mo.prixBase),
              style: const TextStyle(
                  fontSize: 11.5,
                  color: _kOrange,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
