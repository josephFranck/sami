import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/categorie.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/pages/addcategorie.dart';
import 'package:sami/pages/editcategorie.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);

class CategorieListPage extends StatefulWidget {
  const CategorieListPage({super.key});
  @override
  State<CategorieListPage> createState() => _CategorieListPageState();
}

class _CategorieListPageState extends State<CategorieListPage> with PageProtegee {
  @override
  void initState() { super.initState(); chargerUtilisateur(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) => Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Catégories'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: Droits.fab(
        condition: Droits.peutGererCategories(u),
        tooltip: 'Ajouter une catégorie',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCategoriePage())),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('categories').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return const Center(child: Text('Aucune catégorie', style: TextStyle(color: Colors.grey)));
          final cats = snap.data!.docs.map(Categorie.fromFirebaseDocument).toList();
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.2),
            itemCount: cats.length,
            itemBuilder: (_, i) => _CarteCat(
              categorie: cats[i],
              peutGerer: Droits.peutGererCategories(u),
              onModifier: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EditCategoriePage(categorie: cats[i]))),
              onSupprimer: () => _supprimer(cats[i]),
            ),
          );
        },
      ),
    ),
  );

  Future<void> _supprimer(Categorie c) async {
    final ok = await Droits.confirmerSuppression(context, nom: c.nom);
    if (!ok) return;
    // GARDE : une catégorie utilisée par des pagnes ne peut pas disparaître
    // (les pagnes pointeraient vers un fantôme). Déplacer les pagnes d'abord.
    final utilises = await FirebaseFirestore.instance
        .collection('pagnes')
        .where('categories', arrayContains: c.id)
        .limit(1)
        .get();
    if (utilises.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Impossible : des pagnes utilisent cette catégorie. Changez d\'abord leur catégorie.'),
            backgroundColor: Colors.red));
      }
      return;
    }
    await Categorie.categorieCollection.doc(c.id).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${c.nom}" supprimée'), backgroundColor: Colors.red));
  }
}

class _CarteCat extends StatelessWidget {
  final Categorie categorie;
  final bool peutGerer;
  final VoidCallback onModifier;
  final VoidCallback onSupprimer;

  const _CarteCat({required this.categorie, required this.peutGerer,
    required this.onModifier, required this.onSupprimer});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200)),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PagnesParCategoriePage(nomCategorie: categorie.nom))),
      child: Stack(children: [
      Column(children: [
        Expanded(child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: categorie.image.isNotEmpty
              ? ImageUniverselle(source: categorie.image, fit: BoxFit.cover, width: double.infinity)
              : Container(color: Colors.purple.shade50,
                  child: const Icon(Icons.category, color: _kPrimary, size: 40)),
        )),
        Padding(padding: const EdgeInsets.all(8), child: Column(children: [
          Text(categorie.nom, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (categorie.description.isNotEmpty)
            Text(categorie.description, style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
      if (peutGerer) Positioned(top: 4, right: 4,
        child: PopupMenuButton<String>(
          icon: Container(padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.more_vert, color: Colors.white, size: 16)),
          onSelected: (v) { if (v == 'edit') onModifier(); else onSupprimer(); },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Row(children: [
              Icon(Icons.edit_outlined, size: 16, color: _kPrimary), SizedBox(width: 8), Text('Modifier')])),
            const PopupMenuItem(value: 'del', child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8),
              Text('Supprimer', style: TextStyle(color: Colors.red))])),
          ],
        ),
      ),
    ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Liste des pagnes d'une catégorie donnée
// ═══════════════════════════════════════════════════════════════════════════
class PagnesParCategoriePage extends StatelessWidget {
  final String nomCategorie;
  const PagnesParCategoriePage({super.key, required this.nomCategorie});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: Text(nomCategorie),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('pagnes')
            .where('disponible', isEqualTo: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          }
          // Filtre côté client : pagnes contenant cette catégorie
          final pagnes = snap.data!.docs
              .map(Pagne.fromFirebaseDocument)
              .where((p) => p.categories.contains(nomCategorie))
              .toList();

          if (pagnes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun pagne dans "$nomCategorie"',
                      style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: pagnes.length,
            itemBuilder: (_, i) {
              final p = pagnes[i];
              return InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PagneDetailPage(pagne: p))),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ImageUniverselle(
                          source: p.images.isNotEmpty ? p.images.first : null,
                          fit: BoxFit.cover,
                          width: double.infinity,
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
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(PrixFCFA.formater(p.prixParBoutique),
                                style: const TextStyle(
                                    color: _kPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
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
    );
  }
}
