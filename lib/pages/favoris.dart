import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/services/favoris_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

class FavorisPage extends StatelessWidget {
  final Utilisateur? utilisateur; // conservé pour compatibilité (non requis)
  const FavorisPage({super.key, this.utilisateur});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(Tr.s.mesFavoris),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<String>>(
        stream: FavorisService.streamFavoris(),
        builder: (context, favSnap) {
          if (!favSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final favorisIds = favSnap.data!;
          if (favorisIds.isEmpty) {
            return _vide();
          }
          // Charger les pagnes correspondants (stream global filtré côté client)
          return FutureBuilder<List<Pagne>>(
            // LECTURE CIBLÉE : on ne demande QUE les favoris (par ID,
            // paquets de 10) — avant : toute la collection était lue.
            future: () async {
              final res = <Pagne>[];
              final ids = favorisIds.toList();
              for (var i = 0; i < ids.length; i += 10) {
                final chunk = ids.sublist(
                    i, i + 10 > ids.length ? ids.length : i + 10);
                final snap = await FirebaseFirestore.instance
                    .collection('pagnes')
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();
                for (final d in snap.docs) {
                  try {
                    res.add(Pagne.fromFirebaseDocument(d));
                  } catch (_) {}
                }
              }
              return res;
            }(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final pagnes = snap.data!
                  // un pagne retiré de la vente sort aussi des favoris
                  .where((p) => p.disponible)
                  .toList();

              if (pagnes.isEmpty) {
                return _vide();
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: pagnes.length,
                itemBuilder: (_, i) => _carteFavori(context, pagnes[i]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _carteFavori(BuildContext context, Pagne pagne) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PagneDetailPage(pagne: pagne)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageUniverselle(
                  source: pagne.images.isNotEmpty ? pagne.images.first : null,
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pagne.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(PrixFCFA.formater(pagne.prixParBoutique),
                        style: const TextStyle(
                            color: _kPrimary, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        pagne.quantiteDisponible > 0
                            ? Tr.s.stock
                            : Tr.s.rupture,
                        style: TextStyle(
                            fontSize: 12,
                            color: pagne.quantiteDisponible > 0
                                ? Colors.green
                                : Colors.red)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () => FavorisService.basculer(pagne.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(Tr.s.aucunFavoriPourMoment,
              style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(Tr.s.touchezCUrSurPagne,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }
}
