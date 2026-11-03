import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/widgets/galerie_plein_ecran.dart';
import 'package:sami/pages/boutiques_liste_page.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/services/partage_service.dart';
import 'package:sami/models/avis.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/favoris_service.dart';
import 'package:sami/pages/couturier/commander_couture_page.dart';
import 'package:sami/widgets/widgets_notation.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

class PagneDetailPage extends StatefulWidget {
  final Pagne pagne;
  const PagneDetailPage({super.key, required this.pagne});

  @override
  State<PagneDetailPage> createState() => _PagneDetailPageState();
}

class _PagneDetailPageState extends State<PagneDetailPage> {
  int _imageActive = 0;
  int _quantite = 1;
  final _pageCtrl = PageController();

  Pagne get pagne => widget.pagne;

  // Prix client réel (frais inclus) via le moteur PrixFCFA
  double get _prixClient {
    if (pagne.coutAchat != null && pagne.coutAchat! > 0) {
      final d = PrixFCFA.decomposer(
        coutAchat: pagne.coutAchat!,
        beneficeSouhaite: pagne.beneficeSouhaite ?? 0,
        tauxCommission: ParametresService.commissionDefautPctSync,
        fraisLivraison: ParametresService.fraisLivraisonBaseSync,
        tauxGainLivreur: ParametresService.gainLivreurPctSync / 100,
      );
      return d.prixFinalClient;
    }
    return pagne.prixParBoutique;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(pagne.nom, style: const TextStyle(fontSize: 16)),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Partager (WhatsApp…)',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => PartageService.partagerPagne(widget.pagne),
          ),
          StreamBuilder<List<String>>(
            stream: FavorisService.streamFavoris(),
            builder: (context, snap) {
              final estFav = snap.data?.contains(pagne.id) ?? false;
              return IconButton(
                icon: Icon(estFav ? Icons.favorite : Icons.favorite_border),
                onPressed: () => FavorisService.basculer(pagne.id),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCarrousel(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(pagne.nom,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                      if (pagne.mention != Mention.aucun) _badgeMention(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  WidgetAffichageNotes(
                    cible: CibleAvis.pagne,
                    cibleId: pagne.id,
                    compact: true,
                  ),
                  const SizedBox(height: 12),
                  if ((widget.pagne.prixBarre ??
                          (ParametresService.prixBarreAutoCache > 0
                              ? PrixFCFA.arrondirAu50(_prixClient *
                                  (1 +
                                      ParametresService.prixBarreAutoCache /
                                          100))
                              : null)) !=
                      null)
                    Text(PrixFCFA.formater(widget.pagne.prixBarre ??
                            PrixFCFA.arrondirAu50(_prixClient *
                                (1 +
                                    ParametresService.prixBarreAutoCache /
                                        100))),
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.lineThrough)),
                  Text(PrixFCFA.formater(_prixClient),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _kPrimary)),
                  // Provenance : le client sait chez QUI il achète
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .collection('boutiques')
                        .doc(widget.pagne.boutiqueId)
                        .get(),
                    builder: (c2, s2) {
                      final nom = s2.data?.data()?['nom'] as String?;
                      if (nom == null) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () {
                          if (!s2.data!.exists) return;
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => BoutiqueDetailPage(
                                boutique: Boutique.fromFirebaseDocument(s2.data!)),
                          ));
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('🏬 Vendu par $nom  ›',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('Prix tout compris · livraison en sus',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  Text(pagne.description,
                      style: const TextStyle(fontSize: 15, height: 1.4)),
                  const SizedBox(height: 16),
                  _ligneStock(),
                  const Divider(height: 28),
                  if (pagne.categories.isNotEmpty)
                    _infoRow('Catégories', pagne.categories.join(', ')),
                  if (pagne.tailles.isNotEmpty)
                    _infoRow('Tailles', pagne.tailles.join(', ')),
                  if (pagne.couleurs.isNotEmpty)
                    _infoRow('Couleurs', pagne.couleurs.join(', ')),
                  if (pagne.matiere.isNotEmpty)
                    _infoRow('Matière', pagne.matiere),
                  if (pagne.origine.isNotEmpty)
                    _infoRow('Origine', pagne.origine),
                  if (pagne.nomArtisan != null && pagne.nomArtisan!.isNotEmpty)
                    _infoRow('Artisan', pagne.nomArtisan!),
                  const SizedBox(height: 20),
                  _selecteurQuantite(),
                  const SizedBox(height: 16),
                  _boutonPanier(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Avis clients',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  WidgetListeAvis(cible: CibleAvis.pagne, cibleId: pagne.id),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSimilaires(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCarrousel() {
    if (pagne.images.isEmpty) {
      return Container(
        height: 300,
        color: Colors.purple.shade50,
        child: const Center(
            child: Icon(Icons.shopping_bag, color: _kPrimary, size: 80)),
      );
    }
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: pagne.images.length,
            onPageChanged: (i) => setState(() => _imageActive = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GaleriePleinEcran(
                      images: pagne.images, indexInitial: i),
                ),
              ),
              child: ImageUniverselle(
                  source: pagne.images[i], fit: BoxFit.cover, width: double.infinity),
            ),
          ),
        ),
        if (pagne.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pagne.images.length, (i) {
                final actif = i == _imageActive;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: actif ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: actif ? _kPrimary : Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _badgeMention() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(pagne.mention.name,
          style: const TextStyle(
              color: _kPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _ligneStock() {
    final enStock = pagne.quantiteDisponible > 0;
    return Row(children: [
      Icon(enStock ? Icons.check_circle : Icons.cancel,
          size: 16, color: enStock ? Colors.green : Colors.red),
      const SizedBox(width: 6),
      Text(
        enStock
            ? 'En stock (${pagne.quantiteDisponible} disponibles)'
            : 'Rupture de stock',
        style: TextStyle(
            fontSize: 13,
            color: enStock ? Colors.green.shade700 : Colors.red),
      ),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13))),
        Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _selecteurQuantite() {
    return Row(children: [
      const Text('Quantité', style: TextStyle(fontWeight: FontWeight.w600)),
      const Spacer(),
      IconButton(
        onPressed: _quantite > 1 ? () => setState(() => _quantite--) : null,
        icon: const Icon(Icons.remove_circle_outline),
        color: _kPrimary,
      ),
      Text('$_quantite',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      IconButton(
        onPressed: _quantite < pagne.quantiteDisponible
            ? () => setState(() => _quantite++)
            : null,
        icon: const Icon(Icons.add_circle_outline),
        color: _kPrimary,
      ),
    ]);
  }

  Widget _boutonPanier() {
    final indisponible = pagne.quantiteDisponible <= 0;
    return Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: indisponible ? null : _ajouterAuPanier,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: Text(indisponible ? 'Indisponible' : 'Ajouter au panier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: indisponible
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommanderCouturePage(pagne: pagne),
                        ),
                      ),
              icon: const Icon(Icons.content_cut),
              label: const Text('Faire coudre ce pagne'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterAuPanier() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    try {
      final panier = await Panier.charger(user.uid);
      panier.ajouter(PanierItem(
        pagneId: pagne.id,
        pagneNom: pagne.nom,
        pagneImage: pagne.images.isNotEmpty ? pagne.images.first : null,
        quantite: _quantite,
        prixUnitaire: _prixClient,
        boutiqueId: pagne.boutiqueId,
      ));
      await panier.sauvegarder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$_quantite × ${pagne.nom} ajouté au panier'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Voir',
          textColor: Colors.white,
          onPressed: () => Navigator.pushNamed(context, '/panier'),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur lors de l\'ajout au panier'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Widget _buildSimilaires() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Pagnes similaires',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('pagnes')
                .where('disponible', isEqualTo: true)
                .limit(20)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final similaires = snap.data!.docs
                  .map((d) => Pagne.fromFirebaseDocument(d))
                  .where((p) =>
                      p.id != pagne.id &&
                      p.categories.any((c) => pagne.categories.contains(c)))
                  .take(8)
                  .toList();
              if (similaires.isEmpty) {
                return Center(
                    child: Text('Aucun pagne similaire',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13)));
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: similaires.length,
                itemBuilder: (_, i) => _carteSimilaire(similaires[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _carteSimilaire(Pagne p) {
    return GestureDetector(
      onTap: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PagneDetailPage(pagne: p)),
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: ImageUniverselle(
              source: p.images.isNotEmpty ? p.images.first : null,
              width: 140,
              height: 120,
              fit: BoxFit.cover,
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
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(PrixFCFA.formater(p.prixParBoutique),
                      style: const TextStyle(fontSize: 13, color: _kPrimary)),
                ]),
          ),
        ]),
      ),
    );
  }
}

