import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// CATALOGUE COMPLET, PAGINÉ : 30 pagnes par page, « Charger plus »
/// tant qu'il en reste — tient à 100 000 pagnes sans effort.
class TousLesPagnesPage extends StatefulWidget {
  const TousLesPagnesPage({super.key});

  @override
  State<TousLesPagnesPage> createState() => _TousLesPagnesPageState();
}

class _TousLesPagnesPageState extends State<TousLesPagnesPage> {
  static const _parPage = 30;
  final List<Pagne> _pagnes = [];
  DocumentSnapshot<Map<String, dynamic>>? _dernier;
  bool _chargement = false;
  bool _finAtteinte = false;

  @override
  void initState() {
    super.initState();
    _chargerPlus();
  }

  Future<void> _chargerPlus() async {
    if (_chargement || _finAtteinte) return;
    setState(() => _chargement = true);
    var q = FirebaseFirestore.instance
        .collection('pagnes')
        .where('disponible', isEqualTo: true)
        .limit(_parPage);
    if (_dernier != null) q = q.startAfterDocument(_dernier!);
    final snap = await q.get();
    if (!mounted) return;
    setState(() {
      for (final d in snap.docs) {
        try {
          _pagnes.add(Pagne.fromFirebaseDocument(d));
        } catch (_) {}
      }
      if (snap.docs.isNotEmpty) _dernier = snap.docs.last;
      _finAtteinte = snap.docs.length < _parPage;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Tous les pagnes'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: _pagnes.isEmpty && _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.72),
              itemCount: _pagnes.length + (_finAtteinte ? 0 : 1),
              itemBuilder: (_, i) {
                if (i >= _pagnes.length) {
                  // Dernière tuile = bouton « Charger plus »
                  return Center(
                    child: _chargement
                        ? const CircularProgressIndicator(color: _kPrimary)
                        : OutlinedButton.icon(
                            onPressed: _chargerPlus,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Charger plus'),
                          ),
                  );
                }
                final p = _pagnes[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PagneDetailPage(pagne: p))),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            width: double.infinity,
                            child: ImagesBalayables(
                                images: p.images,
                                fallback: Container(
                                    color: Colors.purple.shade50,
                                    child: const Icon(Icons.shopping_bag,
                                        color: _kPrimary))),
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
                                      color: _kPrimary,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
