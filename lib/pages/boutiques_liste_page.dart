import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/pages/pagnepage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/services/message_service.dart';
import 'package:sami/services/partage_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Liste PUBLIQUE des boutiques : tout utilisateur peut parcourir les
/// boutiques actives et entrer dans chacune pour voir ses pagnes disponibles.
class BoutiquesListePage extends StatelessWidget {
  const BoutiquesListePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(Tr.s.boutiques2),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('boutiques')
            .where('estActif', isEqualTo: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final boutiques = snap.data!.docs
              .map((d) => Boutique.fromFirebaseDocument(d))
              .toList()
            ..sort((a, b) => a.nom.compareTo(b.nom));
          if (boutiques.isEmpty) {
            return Center(child: Text(Tr.s.aucuneBoutiquePourMoment));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: boutiques.length,
            itemBuilder: (_, i) {
              final b = boutiques[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ImageUniverselle(
                      source: b.logo.isNotEmpty ? b.logo : null,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(b.nom,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(b.quartier ?? b.ville ?? 'Garoua',
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BoutiqueDetailPage(boutique: b)),
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

/// Détail d'une boutique : ses infos et TOUS SES PAGNES DISPONIBLES.
class BoutiqueDetailPage extends StatelessWidget {
  final Boutique boutique;
  const BoutiqueDetailPage({super.key, required this.boutique});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(boutique.nom),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Tr.s.partagerBoutique,
            icon: const Icon(Icons.share_outlined),
            onPressed: () => PartageService.partagerBoutique(
                id: boutique.id, nom: boutique.nom, logo: boutique.logo),
          ),
        ],
      ),
      body: Column(
        children: [
          // GESTION CONTEXTUELLE : visible seulement pour un gérant de
          // CETTE boutique (ou le staff) — les clients ne le voient pas.
          Builder(builder: (ctx) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            final estGerant =
                uid != null && boutique.gerants.contains(uid);
            if (!estGerant) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => PagneListPage(
                        boutiqueId: boutique.id, boutiqueNom: boutique.nom),
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text(Tr.s.gererPagnesCetteBoutique),
              ),
            );
          }),
          // Bandeau infos boutique
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ImageUniverselle(
                    source: boutique.logo.isNotEmpty ? boutique.logo : null,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(boutique.nom,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(boutique.quartier ?? boutique.adresse,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      // CONTACT : numéro si autorisé (premium/admin),
                      // sinon bouton chat SAMI (anti-désintermédiation).
                      FutureBuilder<bool>(
                        future: ContactPolicy.peutAfficher({
                          'contactVisible':
                              (boutique.contactVisible ?? false),
                          'abonnement': boutique.abonnement,
                        }),
                        builder: (context, s) {
                          final visible = s.data ?? false;
                          if (visible && boutique.telephone.isNotEmpty) {
                            return Text('📞 ${boutique.telephone}',
                                style: const TextStyle(
                                    fontSize: 12, color: _kPrimary,
                                    fontWeight: FontWeight.w600));
                          }
                          return GestureDetector(
                            onTap: () => MessageService.contacter(context,
                                autreUserId: boutique.gerants.isNotEmpty
                                    ? boutique.gerants.first
                                    : '',
                                autreNom: boutique.nom,
                                contexte: 'Boutique ${boutique.nom}'),
                            child: Text(Tr.s.contacterViaSami,
                                style: TextStyle(
                                    fontSize: 12, color: _kPrimary,
                                    fontWeight: FontWeight.w600)),
                          );
                        },
                      ),
                      if (boutique.description.isNotEmpty)
                        Text(boutique.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Les pagnes DISPONIBLES de la boutique
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('pagnes')
                  .where('boutiqueId', isEqualTo: boutique.id)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _kPrimary));
                }
                // Filtre client : disponibles ET pas en rupture
                final pagnes = snap.data!.docs
                    .map((d) => Pagne.fromMap({'id': d.id, ...d.data()}))
                    .where((p) {
                  final enVente = p.disponible;
                  final rupture =
                      p.quantiteStock > 0 && p.quantiteDisponible <= 0;
                  return enVente && !rupture;
                }).toList();

                if (pagnes.isEmpty) {
                  return Center(
                      child: Text(Tr.s.aucunPagneDisponibleDansCette,
                          style: TextStyle(color: Colors.grey)));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: pagnes.length,
                  itemBuilder: (_, i) {
                    final p = pagnes[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PagneDetailPage(pagne: p)),
                      ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ImagesBalayables(
                                images: p.images,
                                fallback: Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image,
                                        color: Colors.grey)),
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
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if (p.prixBarre != null &&
                                      p.prixBarre! > p.prixParBoutique)
                                    Text(PrixFCFA.formater(p.prixBarre!),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            decoration:
                                                TextDecoration.lineThrough)),
                                  Text(
                                      PrixFCFA.formater(p.prixParBoutique),
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
          ),
        ],
      ),
    );
  }
}
