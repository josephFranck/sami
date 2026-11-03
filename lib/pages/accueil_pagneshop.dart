import 'package:sami/pages/moncompte.dart';
import 'package:sami/pages/commandes/mes_commandes_page.dart';
import 'package:sami/pages/categoriepage.dart';
import 'package:sami/pages/favoris.dart';
import 'package:sami/services/parametres_service.dart';
import 'dart:math';
import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/couturier/choisir_pagne_pour_modele.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/version_service.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/favoris_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/models/strategies_marketing.dart';
import 'package:sami/pages/auth/login_page.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ─── Couleurs de l'app ────────────────────────────────────────────────────────
/// Prix barré à afficher : celui du boutiquier s'il existe, sinon le
/// barré AUTO (+X % paramétré, arrondi au 50) — null si désactivé.
double? _prixBarreAffiche(Map<String, dynamic> p, num prix) {
  final manuel = (p['prixBarre'] as num?)?.toDouble();
  if (manuel != null && manuel > prix) return manuel;
  final pct = ParametresService.prixBarreAutoCache;
  if (pct <= 0) return null;
  return PrixFCFA.arrondirAu50(prix * (1 + pct / 100));
}

const _kPrimary = Color(0xFF6A1B9A);       // violet profond
const _kAccent = Color(0xFFFF8F00);        // ambre chaud (couleur Garoua)
const _kBg = Color(0xFFF8F5FF);           // fond très légèrement violet

class AccueilPagneShop extends StatefulWidget {
  const AccueilPagneShop({super.key});
  @override
  State<AccueilPagneShop> createState() => _AccueilPagneShopState();
}

class _AccueilPagneShopState extends State<AccueilPagneShop> {
  int _tabIndex = 0;
  final Set<int> _ongletsVisites = {0}; // lazy : pages montées à la 1re visite
  bool _showIntro = false;
  Utilisateur? _utilisateur;
  String _recherche = '';
  String? _categorieSelectee;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Données Firestore
  List<Map<String, dynamic>> _pagnesFlash = [];
  List<Map<String, dynamic>> _pagnesVedettes = [];
  String _modeCarousel = 'mixte'; // préchargé (le listener est synchrone)
  List<Map<String, dynamic>> _tousLesPagnes = [];
  List<Map<String, dynamic>> _categories = [];
  EventSaisonnier? _eventActuel;
  List<EventSaisonnier> _events = [];
  bool _chargement = true;
  final List<StreamSubscription> _abonnements = [];

  @override
  void initState() {
    super.initState();
    // Mise à jour forcée : bloque si la version est trop ancienne
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => VersionService.verifierAuDemarrage(context));
    _initApp();
  }

  Future<void> _initApp() async {
    await Future.wait([
      _checkIntro(),
      _chargerUtilisateur(),
      _chargerDonnees(),
    ]);
    _eventActuel = await EventSaisonnier.evenementProchainFirestore();
    _events = await EventSaisonnier.evenementsActifsFirestore();
    if (mounted) setState(() => _chargement = false);
  }

  Future<void> _checkIntro() async {
    final prefs = await SharedPreferences.getInstance();
    final vu = prefs.getBool('pagneshop_intro_seen') ?? false;
    if (mounted) setState(() => _showIntro = !vu);
  }

  Future<void> _chargerUtilisateur() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _utilisateur = await Utilisateur.fromUid(user.uid);
      }
    } catch (e) {
      if (kDebugMode) print('[Accueil] Erreur chargement utilisateur: $e');
    }
  }

  Future<void> _chargerDonnees() async {
    _modeCarousel = await ParametresService.carouselMode();
    ParametresService.prixBarreAutoCache =
        await ParametresService.prixBarreAutoPct();
    // UN SEUL stream simple (where disponible uniquement) → AUCUN index composite requis.
    // Le filtrage (vedettes, flash) et le tri (par date) se font côté client en Dart.
    _abonnements.forEach((s) => s.cancel());
    _abonnements.clear();

    _abonnements.add(FirebaseFirestore.instance
        .collection('pagnes')
        .where('disponible', isEqualTo: true)
        .limit(40) // boot léger : 40 suffisent à l'écran initial
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          // Convertir tous les docs
          // Ne jamais afficher un pagne en RUPTURE à l'accueil :
          // stock suivi (quantiteStock>0) ET plus rien de disponible → masqué.
          final tous = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .where((p) {
                final stock = (p['quantiteStock'] as num?)?.toInt() ?? 0;
                final dispo = (p['quantiteDisponible'] as num?)?.toInt() ?? 0;
                return stock == 0 || dispo > 0; // stock non suivi OU dispo
              })
              .toList();

          // Tri par date d'ajout décroissante (côté client)
          tous.sort((a, b) {
            final da = a['dateAjout'];
            final db = b['dateAjout'];
            if (da is Timestamp && db is Timestamp) return db.compareTo(da);
            return 0;
          });

          // Vedettes : mention différente de aucun / ruptureDeStock
          // ═══ CARROUSEL CONFIGURABLE (admin → Critère du carrousel) ═══
          // 'mixte' (défaut) = équitable : vedettes + meilleures ventes +
          // ROTATION QUOTIDIENNE aléatoire — personne n'est lésé, chaque
          // jour d'autres pagnes ont leur chance en vitrine.
          final mode = _modeCarousel;
          List<Map<String, dynamic>> avecMention() => tous.where((p) {
                final m = p['mention'] as String?;
                return m != null &&
                    m != Mention.aucun.name &&
                    m != Mention.ruptureDeStock.name;
              }).toList();
          List<Map<String, dynamic>> parVentes() {
            final l = List<Map<String, dynamic>>.from(tous);
            l.sort((x, y) => ((y['nombreVentes'] as num?) ?? 0)
                .compareTo((x['nombreVentes'] as num?) ?? 0));
            return l;
          }
          List<Map<String, dynamic>> vedettes;
          switch (mode) {
            case 'vedettes':
              vedettes = avecMention().take(10).toList();
              break;
            case 'meilleursVentes':
              vedettes = parVentes().take(10).toList();
              break;
            case 'recents':
              vedettes = tous.take(10).toList();
              break;
            default: // mixte équitable
              final ids = <String>{};
              vedettes = [];
              void ajoute(Iterable<Map<String, dynamic>> src, int n) {
                for (final p in src) {
                  if (vedettes.length >= 10) return;
                  final id = p['id'] as String? ?? '';
                  if (ids.add(id)) {
                    vedettes.add(p);
                    if (--n <= 0) return;
                  }
                }
              }
              ajoute(avecMention(), 4); // les mises en avant payées/choisies
              ajoute(parVentes(), 3); // les meilleures ventes réelles
              // rotation du jour : graine = jour de l'année → change chaque
              // jour, identique pour tous les clients (équitable et stable)
              final reste = tous
                  .where((p) => !ids.contains(p['id'] as String? ?? ''))
                  .toList()
                ..shuffle(Random(DateTime.now().difference(
                        DateTime(DateTime.now().year))
                    .inDays));
              ajoute(reste, 10 - vedettes.length);
          }

          // Flash : mention == enPromotion
          final flash = tous.where((p) =>
              p['mention'] == Mention.enPromotion.name).take(6).toList();

          setState(() {
            _tousLesPagnes = tous; // catalogue COMPLET (défilement vertical)
            _pagnesVedettes = vedettes;
            _pagnesFlash = flash;
            _chargement = false;
          });
        }, onError: (e) {
          if (kDebugMode) print('[Accueil] Erreur stream pagnes: $e');
          if (mounted) setState(() {
            _tousLesPagnes = [];
            _pagnesVedettes = [];
            _pagnesFlash = [];
            _chargement = false;
          });
        }));

    // Catégories (une seule fois suffit, pas de stream)
    try {
      final catSnap = await FirebaseFirestore.instance.collection('categories').get();
      if (mounted) setState(() => _categories = catSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    } catch (e) {
      if (kDebugMode) print('[Accueil] Erreur chargement catégories: $e');
    }
  }

  @override
  void dispose() {
    for (final s in _abonnements) s.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }


  // ── Drawer (menu latéral) ────────────────────────────────────────────────
  Widget _buildDrawer() {
    final role = _utilisateur?.role ?? 'client';
    final perms = _utilisateur?.permissions ?? const <String>[];
    // Un AGENT voit les portes de SES fonctionnalités (même logique que
    // les règles serveur estStaff) — l'admin voit tout.
    bool peut(String p) =>
        role == 'admin' ||
        role == 'superadmin' ||
        (role == 'agent' && perms.contains(p));
    final nom = _utilisateur != null
        ? '${_utilisateur!.prenom} ${_utilisateur!.nom}'.trim()
        : 'Invité';
    final email = _utilisateur?.email ?? '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // En-tête profil
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: _kPrimary),
            accountName: Text(nom.isEmpty ? 'Invité' : nom,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(email),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                style: const TextStyle(color: _kPrimary, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Navigation commune à tous
          _drawerItem(Icons.home_outlined, 'Accueil', () => Navigator.pop(context)),
          _drawerItem(Icons.shopping_bag_outlined, 'Catalogue', () => _navProtege('/pagnepage')),
          _drawerItem(Icons.store_outlined, 'Boutiques', () => Navigator.pushNamed(context, '/boutiques')),
          _drawerItem(Icons.category_outlined, 'Catégories', () => _navProtege('/categorie')),
          _drawerItem(Icons.favorite_border, 'Favoris', () => _navProtege('/favoris')),
          _drawerItem(Icons.shopping_cart_outlined, 'Mon panier', () => _navProtege('/panier')),
          _drawerItem(Icons.receipt_long_outlined, 'Mes commandes', () => _navProtege('/commandes')),
          _drawerItem(Icons.content_cut, 'Mes coutures', () => _navProtege('/mes-coutures')),
          _drawerItem(Icons.receipt_long_outlined, 'Mes reçus', () => _navProtege('/mes-recus')),
          if (role == 'client')
            _drawerItem(Icons.handshake_outlined, 'Devenir partenaire', () => _navProtege('/devenir-partenaire')),
          _drawerItem(Icons.chat_bubble_outline, 'Messages', () => _navProtege('/chatpage')),
          _drawerItem(Icons.gavel_outlined, 'Conditions & confidentialité', () => Navigator.pushNamed(context, '/conditions')),

          const Divider(),

          // Navigation selon le rôle
          if (role == 'couturier')
            _drawerItem(Icons.content_cut, 'Espace couturier', () => _navProtege('/dashboard_couturier')),
          if (role == 'boutiquier' || role == 'admin')
            _drawerItem(Icons.dashboard_outlined, 'Tableau de bord', () => _navProtege('/dashboard_boutiquier')),
            _drawerItem(Icons.inbox_outlined, 'Commandes reçues 📦', () => _navProtege('/dashboard_boutiquier')),
          if (role == 'boutiquier' || role == 'admin') ...[
            _drawerItem(Icons.storefront_outlined, 'Gérer mes boutiques', () => _navProtege('/mes-boutiques')),
            _drawerItem(Icons.add_business_outlined, 'Gérer mes pagnes', () => _navProtege('/pagnepage')),
          ],
          if (role == 'livreur')
            _drawerItem(Icons.insights, 'Mes gains 💰', () => _navProtege('/dashboard-livreur')),
            _drawerItem(Icons.delivery_dining, 'Mes livraisons', () => _navProtege('/mes-livraisons')),
          if (peut('livraisons'))
            _drawerItem(Icons.support_agent, 'Supervision Agent IA',
                () => _navProtege('/supervision')),
          if (peut('pagnes'))
            _drawerItem(Icons.local_offer_outlined, 'Promotions',
                () => _navProtege('/admin-promotions')),
          if (peut('paiements'))
            _drawerItem(Icons.price_check, 'Vérification paiements',
                () => _navProtege('/verification-paiements')),
          if (peut('reversements'))
            _drawerItem(Icons.replay_circle_filled_outlined, 'Remboursements',
                () => _navProtege('/admin-remboursements')),
          if (peut('parametres'))
            _drawerItem(Icons.settings_outlined, 'Paramètres plateforme',
                () => _navProtege('/parametres')),
          if (peut('utilisateurs'))
            _drawerItem(Icons.group_outlined, 'Utilisateurs',
                () => _navProtege('/listuser')),
          if (peut('evenements'))
            _drawerItem(Icons.event_outlined, 'Événements & bandeaux',
                () => _navProtege('/evenements')),
          if (peut('livraisons'))
            _drawerItem(Icons.delivery_dining, 'Livreurs', () => _navProtege('/livreurs')),
          if (role == 'admin' || Droits.estStaff(_utilisateur)) ...[
            _drawerItem(Icons.people_outline, 'Utilisateurs', () => _navProtege('/utilisateurs')),
            _drawerItem(Icons.dashboard_outlined, 'Tableau de bord admin', () => _navProtege('/dashboard-admin')),
            _drawerItem(Icons.map_outlined, 'Carte des boutiques', () => _navProtege('/carte-boutiques')),
            _drawerItem(Icons.storefront_outlined, 'Gestion des boutiques', () => _navProtege('/gestion-boutiques')),
            _drawerItem(Icons.local_offer_outlined, 'Promotions & fidélité', () => _navProtege('/config-marketing')),
            _drawerItem(Icons.account_balance_wallet_outlined, 'Répartition des paiements', () => _navProtege('/repartition-paiements')),
            if (Droits.peut(_utilisateur, 'litiges'))
              _drawerItem(Icons.flag_outlined, 'Livraisons à vérifier', () => _navProtege('/livraisons-a-verifier')),
            if (Droits.peut(_utilisateur, 'candidatures'))
              _drawerItem(Icons.how_to_reg_outlined, 'Candidatures', () => _navProtege('/candidatures')),
            _drawerItem(Icons.receipt_long, 'Toutes les commandes', () => _navProtege('/admin-commandes')),
            _drawerItem(Icons.assignment_return_outlined, 'Retours', () => _navProtege('/retours')),
          ],

          _drawerItem(Icons.card_membership_outlined, 'Abonnements & crédits', () => _navProtege('/abonnements')),

          const Divider(),

          _drawerItem(Icons.person_outline, 'Mon compte', () => _navProtege('/moncompte')),
          _drawerItem(Icons.logout, 'Déconnexion', _deconnexion, couleur: Colors.red),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icone, String titre, VoidCallback onTap, {Color? couleur}) {
    return ListTile(
      leading: Icon(icone, color: couleur ?? _kPrimary, size: 22),
      title: Text(titre, style: TextStyle(color: couleur, fontSize: 14)),
      onTap: onTap,
      dense: true,
    );
  }

  void _navProtege(String route) {
    Navigator.pop(context); // ferme le drawer
    Navigator.pushNamed(context, route);
  }

  Future<void> _deconnexion() async {
    Navigator.pop(context);
    await FirebaseAuth.instance.signOut();
    // _AuthGate détectera la déconnexion et affichera LoginPage
  }

  // ── Build principal ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showIntro) return _buildIntro();
    return Scaffold(
      backgroundColor: _kBg,
      drawer: _buildDrawer(),
      // VRAIS ONGLETS : les 5 pages vivent SOUS la barre (IndexedStack)
      // — taper Favoris ne cache plus la barre de navigation.
      // LAZY : un onglet jamais visité = un simple espace vide — ses
      // streams (favoris, commandes…) ne coûtent RIEN tant qu'on n'y va pas.
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildBody(),
          _ongletsVisites.contains(1)
              ? FavorisPage(utilisateur: _utilisateur)
              : const SizedBox.shrink(),
          _ongletsVisites.contains(2)
              ? const CategorieListPage()
              : const SizedBox.shrink(),
          _ongletsVisites.contains(3)
              ? const MesCommandesPage()
              : const SizedBox.shrink(),
          _ongletsVisites.contains(4)
              ? const ProfilePage()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Intro screen ─────────────────────────────────────────────────────────

  Widget _buildIntro() {
    return IntroductionScreen(
      globalBackgroundColor: _kPrimary,
      pages: [
        PageViewModel(
          title: 'Bienvenue sur PagneShop',
          body: 'Trouvez les plus beaux pagnes, bazins et gandouras du Grand Marché de Garoua. Livraison à domicile.',
          image: Center(
            child: Image.asset('lib/assets/images/pagne_back.jpg',
                height: 200, fit: BoxFit.cover),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            bodyTextStyle: TextStyle(fontSize: 16, color: Colors.white70),
            imagePadding: EdgeInsets.only(top: 40),
          ),
        ),
        PageViewModel(
          title: 'Paiement Mobile Money',
          body: 'Payez facilement par Orange Money ou MTN MoMo. Livraison en moto-taxi dans tout Garoua.',
          image: const Center(child: Icon(Icons.phone_android, size: 120, color: Colors.white70)),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            bodyTextStyle: TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ),
        PageViewModel(
          title: 'Couturiers partenaires',
          body: 'Achetez votre tissu et faites-le coudre par nos artisans certifiés de Lopéré et Yelwa.',
          image: const Center(child: Icon(Icons.content_cut, size: 120, color: Colors.white70)),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            bodyTextStyle: TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ),
      ],
      onDone: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pagneshop_intro_seen', true);
        if (mounted) setState(() => _showIntro = false);
      },
      showSkipButton: true,
      skip: const Text('Passer', style: TextStyle(color: Colors.white70)),
      next: const Icon(Icons.arrow_forward, color: Colors.white),
      done: const Text("C'est parti !", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      dotsDecorator: DotsDecorator(
        activeColor: _kAccent,
        color: Colors.white38,
        size: const Size(8, 8),
        activeSize: const Size(20, 8),
        activeShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  // ── Body principal ───────────────────────────────────────────────────────

  Widget _buildBody() {
    return NestedScrollView(
      controller: _scrollCtrl,
      headerSliverBuilder: (context, innerBoxScrolled) => [
        _buildSliverAppBar(innerBoxScrolled),
      ],
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              onRefresh: _chargerDonnees,
              color: _kPrimary,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Bannière événement saisonnier
                  // CARROUSEL d'événements : ils défilent SEULS (5 s) —
                  // plusieurs campagnes actives = toutes vues, avec points.
                  if (_events.length > 1)
                    _CarrouselEvents(events: _events)
                  else if (_eventActuel != null)
                    _BanniereEvent(event: _eventActuel!),

                  // Barre de recherche
                  _BarreRecherche(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _recherche = v),
                  ),

                  // Filtre catégories
                  if (_categories.isNotEmpty)
                    _FiltreCat(
                      categories: _categories,
                      selected: _categorieSelectee,
                      onSelect: (id) => setState(() =>
                          _categorieSelectee = _categorieSelectee == id ? null : id),
                    ),

                  // Si recherche active → résultats filtrés
                  if (_recherche.isNotEmpty || _categorieSelectee != null)
                    Column(children: [
                      _GrillePagnes(
                        titre: 'Résultats',
                        pagnes: _pagnesFiltres,
                        onTap: _ouvrirPagne,
                      ),
                      // La recherche couvre AUSSI les modèles de couture
                      if (_recherche.trim().length >= 2)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream:
                              ModeleCouture.collection.limit(40).snapshots(),
                          builder: (c2, s2) {
                            final q = _recherche.toLowerCase().trim();
                            final modeles = <ModeleCouture>[];
                            for (final d in (s2.data?.docs ?? [])) {
                              try {
                                final mo = ModeleCouture.fromDoc(d);
                                if (mo.nom.toLowerCase().contains(q)) {
                                  modeles.add(mo);
                                }
                              } catch (_) {}
                            }
                            if (modeles.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding:
                                      EdgeInsets.fromLTRB(14, 10, 14, 6),
                                  child: Text('✂️ Modèles correspondants',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.deepOrange)),
                                ),
                                SizedBox(
                                  height: 168,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    itemCount: modeles.length,
                                    itemBuilder: (_, i) {
                                      final mo = modeles[i];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                            right: 10),
                                        child: GestureDetector(
                                          onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      ChoisirPagnePourModelePage(
                                                          modele: mo))),
                                          child: SizedBox(
                                            width: 118,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10),
                                                  child: SizedBox(
                                                    width: 118,
                                                    height: 106,
                                                    child: ImagesBalayables(
                                                        images: mo
                                                            .photosExemples,
                                                        fallback: Container(
                                                            color: Colors
                                                                .deepOrange
                                                                .withOpacity(
                                                                    0.1),
                                                            child: const Icon(
                                                                Icons
                                                                    .checkroom,
                                                                color: Colors
                                                                    .deepOrange))),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(mo.nom,
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600)),
                                                Text(
                                                    mo.surDevis
                                                        ? 'Sur devis'
                                                        : PrixFCFA.formater(
                                                            mo.prixBase),
                                                    style: const TextStyle(
                                                        fontSize: 11.5,
                                                        color: Colors
                                                            .deepOrange,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ])
                  else ...[
                    // Carousel vedettes
                    if (_pagnesVedettes.isNotEmpty)
                      _CarouselVedettes(
                        pagnes: _pagnesVedettes,
                        onTap: _ouvrirPagne,
                      ),

                    // Section ventes flash
                    if (_pagnesFlash.isNotEmpty) ...[
                      const SizedBox(height: 18), // ── espacement de section
                      _TitreSection(
                        titre: 'Ventes flash',
                        icone: Icons.flash_on,
                        couleur: Colors.orange,
                        action: 'Voir tout',
                        onAction: () {},
                      ),
                      _ListeHorizontale(
                        pagnes: _pagnesFlash,
                        onTap: _ouvrirPagne,
                        estFlash: true,
                      ),
                    ],

                    // Bandeau fidélité
                    const SizedBox(height: 18),
                    if (_utilisateur != null)
                      _BandeauFidelite(utilisateur: _utilisateur!),

                    // Catalogue complet
                    const SizedBox(height: 18), // ── espacement de section
                    _TitreSection(
                      titre: 'Tous les pagnes',
                      action: 'Voir tout ›',
                      onAction: () =>
                          Navigator.pushNamed(context, '/tous-les-pagnes'),
                      icone: Icons.grid_view,
                      couleur: _kPrimary,
                    ),
                    _GrillePagnes(
                      titre: '',
                      pagnes: _tousLesPagnes,
                      onTap: _ouvrirPagne,
                      // GRILLE VERTICALE : le catalogue complet défile avec
                      // la page — la priorité de l'accueil, ce sont les pagnes.
                      horizontal: false,
                    ),

                    // ═══ MODÈLES DE COUTURE : le parcours inversé ═══
                    // (après les pagnes — la priorité d'affichage)
                    const SizedBox(height: 18), // ── espacement de section
                    _TitreSection(
                      titre: 'Modèles de couture',
                      icone: Icons.content_cut,
                      couleur: Colors.deepOrange,
                      action: 'Voir tout ›',
                      onAction: () =>
                          Navigator.pushNamed(context, '/tous-les-modeles'),
                    ),
                    SizedBox(
                      height: 172,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: ModeleCouture.collection.limit(12).snapshots(),
                        builder: (c2, s2) {
                          // DÉFENSIF : un doc modèle incomplet (données de
                          // test) est ignoré au lieu de faire planter l'accueil.
                          final modeles = <ModeleCouture>[];
                          for (final d in (s2.data?.docs ?? [])) {
                            try {
                              modeles.add(ModeleCouture.fromDoc(d));
                            } catch (_) {}
                          }
                          if (modeles.isEmpty) {
                            return const Center(
                                child: Text('Les modèles des couturiers arrivent bientôt…',
                                    style: TextStyle(color: Colors.grey, fontSize: 12)));
                          }
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: modeles.length,
                            itemBuilder: (_, i) {
                              final mo = modeles[i];
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: GestureDetector(
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              ChoisirPagnePourModelePage(modele: mo))),
                                  child: SizedBox(
                                    width: 120,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: SizedBox(
                                            width: 120, height: 110,
                                            child: ImagesBalayables(
                                                images: mo.photosExemples,
                                                fallback: Container(
                                                    color: Colors.deepOrange.withOpacity(0.1),
                                                    child: const Icon(Icons.checkroom,
                                                        color: Colors.deepOrange))),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(mo.nom, maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w600)),
                                        Text(
                                            mo.surDevis
                                                ? 'Sur devis'
                                                : PrixFCFA.formater(mo.prixBase),
                                            style: const TextStyle(
                                                fontSize: 11.5, color: Colors.deepOrange,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                  ],

                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  List<Map<String, dynamic>> get _pagnesFiltres {
    return _tousLesPagnes.where((p) {
      final nom = (p['nom'] as String? ?? '').toLowerCase();
      final desc = (p['description'] as String? ?? '').toLowerCase();
      final matiere = (p['matiere'] as String? ?? '').toLowerCase();
      final q = _recherche.toLowerCase();
      final matchRecherche = q.isEmpty ||
          nom.contains(q) || desc.contains(q) || matiere.contains(q);
      final cats = List<String>.from(p['categories'] ?? []);
      final matchCat = _categorieSelectee == null ||
          cats.contains(_categorieSelectee);
      return matchRecherche && matchCat;
    }).toList();
  }

  void _ouvrirPagne(Map<String, dynamic> data) {
    final pagne = Pagne.fromMap({'id': data['id'], ...data});
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PagneDetailPage(pagne: pagne)),
    );
  }

  // ── SliverAppBar ─────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(bool innerBoxScrolled) {
    final niveauFid = NiveauFidelite.fromPoints(
      _utilisateur != null ? (_utilisateur!.niveau * 500) : 0,
    );
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      snap: true,
      pinned: true,
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: _kPrimary,
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
          child: Row(
            children: [
              // Logo PagneShop (assets/logo.png)
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.store,
                          color: _kPrimary, size: 22)),
                ),
              ),
              const SizedBox(width: 10),
              // Titre + sous-titre
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PagneShop',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    Text(
                      _utilisateur != null
                          ? '${niveauFid.emoji} ${_utilisateur!.nom} · ${niveauFid.nom}'
                          : 'Grand Marché de Garoua',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Panier + notifs
                            IconButton(
                icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                onPressed: () => Navigator.pushNamed(context, '/panier'),
              ),
            ],
          ),
        ),
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        StreamBuilder<int>(
          stream: NotificationService.nonLues(),
          builder: (context, s) {
            final n = s.data ?? 0;
            return Stack(children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
              ),
              if (n > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text('$n',
                        style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
            ]);
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: _handleMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'compte', child: Text('Mon compte')),
            const PopupMenuItem(value: 'commandes', child: Text('Mes commandes')),
            const PopupMenuItem(value: 'messages', child: Text('Messages')),
            const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: Container(),
      ),
    );
  }

  // ── Drawer ───────────────────────────────────────────────────────────────


  // ── Bottom nav ───────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: _onTabTap,
        selectedItemColor: _kPrimary,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), activeIcon: Icon(Icons.favorite), label: 'Favoris'),
          BottomNavigationBarItem(icon: Icon(Icons.category_outlined), activeIcon: Icon(Icons.category), label: 'Catégories'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Commandes'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  Future<void> _onTabTap(int index) async {
    // Simple bascule : la page se monte à sa PREMIÈRE visite (lazy).
    setState(() {
      _ongletsVisites.add(index);
      _tabIndex = index;
    });
  }

  void _handleMenu(String val) async {
    switch (val) {
      case 'compte':
        Navigator.pushNamed(context, '/moncompte');
        break;
      case 'commandes':
        Navigator.pushNamed(context, '/commandes');
        break;
      case 'messages':
        Navigator.pushNamed(context, '/chatpage');
        break;
      case 'logout':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Déconnexion'),
            content: const Text('Voulez-vous vraiment vous déconnecter ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Déconnecter', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
          }
        }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPOSANTS DE LA PAGE D'ACCUEIL
// ═══════════════════════════════════════════════════════════════════════════

// ─── Bannière événement saisonnier ───────────────────────────────────────────

class _BanniereEvent extends StatelessWidget {
  final EventSaisonnier event;
  const _BanniereEvent({required this.event});

  @override
  Widget build(BuildContext context) {
    // AFFICHAGE HUMAIN : « 3 jours », « 5 h », « 40 min » — plus jamais
    // « 0 jours » pour un événement imminent.
    final delta = event.dateDebut.difference(DateTime.now());
    final compte = delta.inDays >= 1
        ? '${delta.inDays} jour${delta.inDays > 1 ? 's' : ''}'
        : delta.inHours >= 1
            ? '${delta.inHours} h'
            : '${delta.inMinutes.clamp(1, 59)} min';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(event.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.nom} dans $compte !',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5),
                ),
                Text(
                  event.messageMarketing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '-${event.reductionSuggeree.round()}%',
              style: const TextStyle(
                  color: _kAccent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Barre de recherche ──────────────────────────────────────────────────────

class _BarreRecherche extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _BarreRecherche({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher un pagne, une matière...',
          hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kPrimary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─── Filtre catégories ───────────────────────────────────────────────────────

class _FiltreCat extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _FiltreCat({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final id = cat['id'] as String? ?? '';
          final nom = cat['nom'] as String? ?? id;
          final actif = selected == id;
          return GestureDetector(
            onTap: () => onSelect(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: actif ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: actif ? _kPrimary : Colors.grey.shade300),
              ),
              child: Text(
                nom,
                style: TextStyle(
                  fontSize: 13,
                  color: actif ? Colors.white : Colors.black87,
                  fontWeight: actif ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Carousel vedettes ───────────────────────────────────────────────────────

class _CarouselVedettes extends StatefulWidget {
  final List<Map<String, dynamic>> pagnes;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _CarouselVedettes({required this.pagnes, required this.onTap});

  @override
  State<_CarouselVedettes> createState() => _CarouselVedettesState();
}

class _CarouselVedettesState extends State<_CarouselVedettes> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        CarouselSlider.builder(
          itemCount: widget.pagnes.length,
          itemBuilder: (_, i, __) => _CarteVedette(
            pagne: widget.pagnes[i],
            onTap: () => widget.onTap(widget.pagnes[i]),
          ),
          options: CarouselOptions(
            height: 200,
            autoPlay: true,
            enlargeCenterPage: true,
            viewportFraction: 0.62,   // ~1,6 éléments visibles à la fois
            autoPlayInterval: const Duration(seconds: 4),
            onPageChanged: (i, _) => setState(() => _current = i),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.pagnes.asMap().entries.map((e) {
            return Container(
              width: _current == e.key ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: _current == e.key ? _kPrimary : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CarteVedette extends StatelessWidget {
  final Map<String, dynamic> pagne;
  final VoidCallback onTap;

  const _CarteVedette({required this.pagne, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(pagne['images'] ?? []);
    final mention = pagne['mention'] as String? ?? '';
    final prix = (pagne['prixParBoutique'] as num?)?.toDouble() ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image (balayable si plusieurs photos)
              ImagesBalayables(
                  images: images,
                  fallback: Container(
                      color: Colors.purple.shade50,
                      child: const Icon(Icons.shopping_bag,
                          color: _kPrimary, size: 60))),

              // Overlay dégradé
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),

              // Contenu bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pagne['nom'] as String? ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              pagne['matiere'] as String? ?? '',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_prixBarreAffiche(p, prix) != null)
                              Text(
                                PrixFCFA.formaterCompact(
                                    _prixBarreAffiche(p, prix)!),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    decoration:
                                        TextDecoration.lineThrough),
                              ),
                            Text(
                              PrixFCFA.formaterCompact(prix),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Badge mention
              if (mention.isNotEmpty && mention != 'aucun')
                Positioned(
                  top: 10,
                  left: 10,
                  child: _BadgeMention(mention: mention),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Titre de section ─────────────────────────────────────────────────────────

class _TitreSection extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Color couleur;
  final String? action;
  final VoidCallback? onAction;

  const _TitreSection({
    required this.titre,
    required this.icone,
    required this.couleur,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icone, color: couleur, size: 20),
          const SizedBox(width: 6),
          Text(
            titre,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: couleur),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(fontSize: 13, color: _kPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Liste horizontale (ventes flash) ────────────────────────────────────────

class _ListeHorizontale extends StatelessWidget {
  final List<Map<String, dynamic>> pagnes;
  final ValueChanged<Map<String, dynamic>> onTap;
  final bool estFlash;

  const _ListeHorizontale({
    required this.pagnes,
    required this.onTap,
    this.estFlash = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: estFlash ? 152 : 200, // promotions : zone COMPACTE
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: pagnes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _CartePagneFlash(
          pagne: pagnes[i],
          onTap: () => onTap(pagnes[i]),
          estFlash: estFlash,
        ),
      ),
    );
  }
}

class _CartePagneFlash extends StatelessWidget {
  final Map<String, dynamic> pagne;
  final VoidCallback onTap;
  final bool estFlash;

  const _CartePagneFlash({
    required this.pagne,
    required this.onTap,
    this.estFlash = false,
  });

  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(pagne['images'] ?? []);
    final prix = (pagne['prixParBoutique'] as num?)?.toDouble() ?? 0;
    final note = (pagne['noteMoyenne'] as num?)?.toDouble() ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: estFlash
              ? Border.all(color: Colors.orange.shade200, width: 1.5)
              : Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 110,
                width: double.infinity,
                child: ImagesBalayables(
                    images: images,
                    fallback: Container(
                        color: Colors.purple.shade50,
                        child: const Icon(Icons.shopping_bag,
                            color: _kPrimary, size: 40))),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pagne['nom'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (_prixBarreAffiche(p, prix) != null)
                      Text(PrixFCFA.formater(_prixBarreAffiche(p, prix)!),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough)),
                    Text(
                    PrixFCFA.formater(prix),
                    style: const TextStyle(
                        color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (note > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          note.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grille principale des pagnes ────────────────────────────────────────────

class _GrillePagnes extends StatelessWidget {
  final String titre;
  final List<Map<String, dynamic>> pagnes;
  final ValueChanged<Map<String, dynamic>> onTap;
  final bool horizontal;   // true = liste horizontale (2,5 cards), false = grille verticale

  const _GrillePagnes({
    required this.titre,
    required this.pagnes,
    required this.onTap,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (pagnes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Aucun pagne trouvé',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    // Mode horizontal : ~2,5 cards visibles, défilement latéral
    if (horizontal) {
      final largeurCard = MediaQuery.of(context).size.width / 2.5;
      return SizedBox(
        height: largeurCard * 1.5,   // ratio card ≈ 0.66
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          itemCount: pagnes.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: largeurCard,
              child: _CartePagneGrille(
                pagne: pagnes[i],
                onTap: () => onTap(pagnes[i]),
                compact: true,
              ),
            ),
          ),
        ),
      );
    }

    // Mode grille verticale (résultats de recherche)
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: pagnes.length,
      itemBuilder: (_, i) => _CartePagneGrille(
        pagne: pagnes[i],
        onTap: () => onTap(pagnes[i]),
      ),
    );
  }
}

class _CartePagneGrille extends StatefulWidget {
  final Map<String, dynamic> pagne;
  final VoidCallback onTap;
  final bool compact;

  const _CartePagneGrille({
    required this.pagne,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_CartePagneGrille> createState() => _CartePagneGrilleState();
}

class _CartePagneGrilleState extends State<_CartePagneGrille> {
  final PageController _imgCtrl = PageController();
  int _imgActive = 0;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _demarrerAutoDefilement();
  }

  void _demarrerAutoDefilement() {
    final images = List<String>.from(widget.pagne['images'] ?? []);
    if (images.length <= 1) return; // rien à faire défiler
    // Délai différent par card pour éviter que toutes défilent en même temps
    final delaiInitial = (widget.pagne['id']?.hashCode ?? 0) % 2000;
    Future.delayed(Duration(milliseconds: delaiInitial), () {
      if (!mounted) return;
      _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || !_imgCtrl.hasClients) return;
        final suivant = (_imgActive + 1) % images.length;
        _imgCtrl.animateToPage(
          suivant,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _imgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pagne = widget.pagne;
    final onTap = widget.onTap;
    final images = List<String>.from(pagne['images'] ?? []);
    final prix = (pagne['prixParBoutique'] as num?)?.toDouble() ?? 0;
    final note = (pagne['noteMoyenne'] as num?)?.toDouble() ?? 0;
    final mention = pagne['mention'] as String? ?? 'aucun';
    final origine = pagne['origine'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image(s) — mini-carrousel défilant si plusieurs images
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (images.isEmpty)
                      Container(
                        color: Colors.purple.shade50,
                        child: const Icon(Icons.shopping_bag,
                            color: _kPrimary, size: 40),
                      )
                    else
                      PageView.builder(
                        controller: _imgCtrl,
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _imgActive = i),
                        itemBuilder: (_, i) =>
                            ImageUniverselle(source: images[i], fit: BoxFit.cover),
                      ),
                    // Indicateur de position (points) si plusieurs images
                    if (images.length > 1)
                      Positioned(
                        bottom: 6,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(images.length, (i) {
                            final actif = i == _imgActive;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: actif ? 12 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: actif
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ),
                    if (mention != 'aucun')
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _BadgeMention(mention: mention, mini: true),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: StreamBuilder<List<String>>(
                        stream: FavorisService.streamFavoris(),
                        builder: (context, snap) {
                          final estFav =
                              snap.data?.contains(pagne['id']) ?? false;
                          return GestureDetector(
                            onTap: () async {
                              await FavorisService.basculer(pagne['id'] as String? ?? '');
                            },
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: Icon(
                                estFav
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 15,
                                color: Colors.red,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Infos
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pagne['nom'] as String? ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (origine.isNotEmpty)
                    Text(origine,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  if (_prixBarreAffiche(pagne, prix) != null)
                    Text(
                        PrixFCFA.formater(_prixBarreAffiche(pagne, prix)!),
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.lineThrough)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          PrixFCFA.formater(prix),
                          style: const TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      if (note > 0) ...[
                        const Icon(Icons.star, color: Colors.amber, size: 12),
                        Text(note.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bandeau fidélité ────────────────────────────────────────────────────────

class _BandeauFidelite extends StatelessWidget {
  final Utilisateur utilisateur;
  const _BandeauFidelite({required this.utilisateur});

  @override
  Widget build(BuildContext context) {
    // VERSION COMPACTE : le header (à côté du logo) porte déjà le niveau ;
    // ici, un simple rappel discret — le détail complet vit dans Mon compte.
    final points = utilisateur.niveau * 500;
    final niveau = NiveauFidelite.fromPoints(points);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(children: [
        Icon(Icons.stars, size: 15, color: Colors.amber.shade700),
        const SizedBox(width: 6),
        Text('${niveau.nom} · $points pts',
            style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/moncompte'),
          child: Text('détails ›',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ),
      ]),
    );
  }
}

// ─── Badge mention ────────────────────────────────────────────────────────────

class _BadgeMention extends StatelessWidget {
  final String mention;
  final bool mini;
  const _BadgeMention({required this.mention, this.mini = false});

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (mention) {
      'coupDeCoeur' => ('❤️ Coup de cœur', const Color(0xFFD4537E)),
      'meilleureVente' => ('🏆 Meilleure vente', const Color(0xFFBA7517)),
      'nouveaute' => ('🆕 Nouveauté', const Color(0xFF1D9E75)),
      'exclusivite' => ('⭐ Exclusif', const Color(0xFF534AB7)),
      'premium' => ('💎 Premium', const Color(0xFF534AB7)),
      'artisanatLocal' => ('🤝 Local', const Color(0xFF3B6D11)),
      'editionLimitee' => ('🔥 Limité', const Color(0xFFD85A30)),
      'enPromotion' => ('🏷️ Promo', const Color(0xFFD85A30)),
      _ => ('', Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mini ? 6 : 8, vertical: mini ? 2 : 4),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: Colors.white,
            fontSize: mini ? 10 : 11,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Carrousel auto-défilant des événements actifs : chaque bannière
/// réutilise _BanniereEvent ; points indicateurs ; boucle infinie douce.
class _CarrouselEvents extends StatefulWidget {
  final List<EventSaisonnier> events;
  const _CarrouselEvents({required this.events});

  @override
  State<_CarrouselEvents> createState() => _CarrouselEventsState();
}

class _CarrouselEventsState extends State<_CarrouselEvents> {
  final _ctrl = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.events.length < 2) return;
      final suivant = (_page + 1) % widget.events.length;
      _ctrl.animateToPage(suivant,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 53, // demandé : bandeau ultra-compact
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.events.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _BanniereEvent(event: widget.events[i]),
        ),
      ),
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.events.length,
          (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _page == i ? 16 : 6,
            height: 2,
            decoration: BoxDecoration(
              color: _page == i ? _kPrimary : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    ]);
  }
}
