import 'package:sami/utils/droits.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sami/firebase_options.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/pages/legal/mentions_legales_page.dart';
import 'package:sami/pages/accueil_pagneshop.dart';
import 'package:sami/pages/auth/login_page.dart';
import 'package:sami/pages/auth/signup_page.dart';
import 'package:sami/pages/auth/reset_password_page.dart';
import 'package:sami/pages/categoriepage.dart';
import 'package:sami/pages/chat/liste_conversations_page.dart';
import 'package:sami/pages/favoris.dart';
import 'package:sami/pages/mapscreen.dart';
import 'package:sami/pages/moncompte.dart';
import 'package:sami/pages/pagnepage.dart';
import 'package:sami/pages/panierpage.dart';
import 'package:sami/pages/admin/gestion_utilisateurs_page.dart';
import 'package:sami/pages/admin/carte_boutiques_page.dart';
import 'package:sami/pages/admin/config_marketing_page.dart';
import 'package:sami/pages/admin/repartition_paiements_page.dart';
import 'package:sami/pages/admin/gestion_boutiques_page.dart';
import 'package:sami/pages/admin/livraisons_a_verifier_page.dart';
import 'package:sami/pages/couturier/mes_couture_client_page.dart';
import 'package:sami/pages/devenir_partenaire_page.dart';
import 'package:sami/pages/admin/candidatures_admin_page.dart';
import 'package:sami/pages/admin/admin_commandes_page.dart';
import 'package:sami/pages/admin/dashboard_admin_page.dart';
import 'package:sami/pages/admin/evenements_admin_page.dart';
import 'package:sami/pages/boutiques_liste_page.dart';
import 'package:sami/pages/notifications_page.dart';
import 'package:sami/pages/conditions_page.dart';
import 'package:sami/pages/recus_page.dart';
import 'package:sami/pages/mes_boutiques_page.dart';
import 'package:sami/pages/tous_les_pagnes_page.dart';
import 'package:sami/pages/livraison/dashboard_superviseur.dart';
import 'package:sami/pages/admin/promotions_admin_page.dart';
import 'package:sami/pages/admin/remboursements_admin_page.dart';
import 'package:sami/pages/admin/verification_paiements_page.dart';
import 'package:sami/pages/tous_les_modeles_page.dart';
import 'package:sami/pages/admin/parametres_admin_page.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/services/resilience_service.dart';
import 'package:sami/widgets/widgets_resilients.dart';
import 'package:sami/pages/livreur/livreur_list_page.dart';
import 'package:sami/pages/livreur/dashboard_livreur_page.dart';
import 'package:sami/pages/livreur/mes_livraisons_page.dart';
import 'package:sami/pages/retours/retours_page.dart';
import 'package:sami/pages/abonnements/abonnements_page.dart';
import 'package:sami/pages/commandes/mes_commandes_page.dart';
import 'package:sami/pages/commandes/dashboard_boutiquier.dart';
import 'package:sami/pages/couturier/dashboard_couturier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await StockageService.init();
  await initResilienceServices();
  runApp(const SamiApp());
}

class SamiApp extends StatelessWidget {
  const SamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PagneShop — Garoua',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A1B9A),
          primary: const Color(0xFF6A1B9A),
          secondary: const Color(0xFFFF8F00),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A1B9A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      // Point d'entrée : redirige selon l'état Auth
      home: const _AuthGate(),
      onGenerateRoute: _generateRoute,
    );
  }
}

// ─── Auth gate — écoute Firebase Auth ────────────────────────────────────────

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const AccueilPagneShop();
        }
        return const LoginPage();
      },
    );
  }
}

// ─── Routeur central ─────────────────────────────────────────────────────────
// Les routes qui nécessitent Utilisateur le chargent elles-mêmes depuis Firebase.
// Seules les routes simples (sans args obligatoires) sont ici.

Route<dynamic>? _generateRoute(RouteSettings settings) {
  final name = settings.name;

  // LIENS PROFONDS (partage WhatsApp) : sami-c564c.web.app/p/{id} → fiche
  // pagne ; /b/{id} → boutique. L'app s'ouvre directement sur le produit.
  if (name != null && name.startsWith('/p/')) {
    final id = name.substring(3);
    return _slide(_ChargeurPagne(pagneId: id));
  }
  if (name != null && name.startsWith('/b/')) {
    final id = name.substring(3);
    return _slide(_ChargeurBoutique(boutiqueId: id));
  }
  final args = settings.arguments;

  switch (name) {
    // ── Auth ──────────────────────────────────────────────────────────────
    case '/login':
      return _fade(const LoginPage());
    case '/signup':
      return _fade(const SignupPage());
    case '/reset':
      return _fade(const ResetPasswordPage());

    // ── Accueil ───────────────────────────────────────────────────────────
    case '/':
    case '/accueil':
      return _fade(const AccueilPagneShop());

    // ── Catalogue ─────────────────────────────────────────────────────────
    case '/pagnepage':
      return _slide(const PagneListPage());
    case '/categorie':
      return _slide(const CategorieListPage());
    // ── Compte (charge Utilisateur en interne) ────────────────────────────
    case '/moncompte':
      return _slide(const ProfilePage());

    // ── Panier & commandes (nécessitent Utilisateur) ──────────────────────
    case '/panier':
      return _slide(const _PanierGate());
    case '/commandes':
      return _slide(const MesCommandesPage());
    case '/dashboard_couturier':
      return _slide(const DashboardCouturier());
    case '/dashboard_boutiquier':
      return _slide(const _DashboardBoutiquierGate());

    // ── Favoris (nécessite Utilisateur) ───────────────────────────────────
    case '/favoris':
      return _slide(const _FavorisGate());

    // ── Messagerie ────────────────────────────────────────────────────────
    case '/chatpage':
      return _slide(const ListeConversationsPage());

    // ── Carte & position ──────────────────────────────────────────────────
    // ── Admin & outils ────────────────────────────────────────────────────
    case '/listuser':
    case '/utilisateurs':
      return _slide(const GestionUtilisateursPage());
    case '/carte-boutiques':
      return _slide(const CarteBoutiquesPage());
    case '/config-marketing':
      return _slide(const ConfigMarketingPage());
    case '/repartition-paiements':
      return _slide(const RepartitionPaiementsPage());
    case '/gestion-boutiques':
      return _slide(const GestionBoutiquesPage());
    case '/livraisons-a-verifier':
      return _slide(const LivraisonsAVerifierPage());
    case '/mes-coutures':
      return _slide(const MesCoutureClientPage());
    case '/devenir-partenaire':
      return _slide(const DevenirPartenairePage());
    case '/candidatures':
      return _slide(const CandidaturesAdminPage());
    case '/dashboard-admin':
      return _slide(const DashboardAdminPage());
    case '/evenements':
      return _slide(const EvenementsAdminPage());
    case '/boutiques':
      return _slide(const BoutiquesListePage());
    case '/notifications':
      return _slide(const NotificationsPage());
    case '/conditions':
      return _slide(const ConditionsPage());
    case '/mes-recus':
      return _slide(const MesRecusPage());
    case '/mes-boutiques':
      return _slide(const MesBoutiquesPage());
    case '/verification-paiements':
      return _slide(const VerificationPaiementsPage());
    case '/admin-remboursements':
      return _slide(const RemboursementsAdminPage());
    case '/admin-promotions':
      return _slide(const PromotionsAdminPage());
    case '/supervision':
      return _slide(const DashboardSuperviseur());
    case '/tous-les-pagnes':
      return _slide(const TousLesPagnesPage());
    case '/tous-les-modeles':
      return _slide(const TousLesModelesPage());
    case '/parametres':
      return _slide(const ParametresAdminPage());

    // ── Livreurs & retours ───────────────────────────────────────────────
    // ── Crédits & abonnements ──────────────────────────────────────────────
    case '/abonnements':
      return _slide(const _AbonnementGate());

    case '/livreurs':
      return _slide(const LivreurListPage());
    case '/dashboard-livreur':
      return _slide(const DashboardLivreurPage());
    case '/mes-livraisons':
      return _slide(const MesLivraisonsPage());
    case '/mentions-legales':
      return _slide(const MentionsLegalesPage());
    case '/cgu':
      return _slide(const MentionsLegalesPage(ongletInitial: 1));
    case '/confidentialite':
      return _slide(const MentionsLegalesPage(ongletInitial: 2));
    case '/admin-commandes':
      return MaterialPageRoute(builder: (_) => const AdminCommandesPage());
    case '/retours':
      return _slide(const RetoursPage());

    // ── Redirections legacy vers nouveaux équivalents ────────────────────
    case '/home':
    case '/home1':
    case '/homeb':
    case '/homee':
    case '/home2':

    // /conversation → nouvelle liste conversations
    case '/conversation':
      return _slide(const ListeConversationsPage());


    default:
      return _fade(const _RouteInconnue());
  }
}

// ─── Gates — chargent l'utilisateur puis rendent la page ─────────────────────

class _PanierGate extends StatefulWidget {
  const _PanierGate();
  @override
  State<_PanierGate> createState() => _PanierGateState();
}
class _PanierGateState extends State<_PanierGate> {
  Utilisateur? _u;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final u = await Utilisateur.fromUid(user.uid);
      if (mounted) setState(() => _u = u);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_u == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
    return PanierPage(utilisateur: _u!);
  }
}

class _CommandesGate extends StatefulWidget {
  const _CommandesGate();
  @override
  State<_CommandesGate> createState() => _CommandesGateState();
}
class _CommandesGateState extends State<_CommandesGate> {
  Utilisateur? _u;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final u = await Utilisateur.fromUid(user.uid);
      if (mounted) setState(() => _u = u);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_u == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
    return MesCommandesPage();
  }
}

class _FavorisGate extends StatefulWidget {
  const _FavorisGate();
  @override
  State<_FavorisGate> createState() => _FavorisGateState();
}
class _FavorisGateState extends State<_FavorisGate> {
  Utilisateur? _u;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final u = await Utilisateur.fromUid(user.uid);
      if (mounted) setState(() => _u = u);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_u == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
    return FavorisPage(utilisateur: _u!);
  }
}

// Passerelle : trouve la boutique du boutiquier connecté et ouvre son dashboard
class _DashboardBoutiquierGate extends StatefulWidget {
  const _DashboardBoutiquierGate();
  @override
  State<_DashboardBoutiquierGate> createState() => _DashboardBoutiquierGateState();
}
class _DashboardBoutiquierGateState extends State<_DashboardBoutiquierGate> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _boutiques = [];
  bool _chargement = true;

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('boutiques')
            .where('gerants', arrayContains: user.uid)
            .limit(10)
            .get();
        _boutiques = snap.docs;
      } catch (_) {}
    }
    if (mounted) setState(() => _chargement = false);
  }

  @override
  Widget build(BuildContext context) {
    const kP = Color(0xFF6A1B9A);
    if (_chargement) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kP)));
    }
    // AUCUNE : expliquer ET donner la sortie (pas un cul-de-sac).
    if (_boutiques.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Commandes reçues'),
            backgroundColor: kP, foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                      "Aucune boutique n'est rattachée à votre compte.\n"
                      "Votre compte doit figurer parmi les GÉRANTS de la boutique.",
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/mes-boutiques'),
                    icon: const Icon(Icons.storefront, size: 16),
                    label: const Text('Gérer mes boutiques'),
                  ),
                ]),
          ),
        ),
      );
    }
    // UNE SEULE : directement au tableau de bord.
    if (_boutiques.length == 1) {
      return DashboardBoutiquier(boutiqueId: _boutiques.first.id);
    }
    // PLUSIEURS : choisir laquelle.
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir la boutique'),
          backgroundColor: kP, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: _boutiques
            .map((b) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront, color: kP),
                    title: Text(b.data()['nom'] as String? ?? b.id),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                DashboardBoutiquier(boutiqueId: b.id))),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ─── Route inconnue ───────────────────────────────────────────────────────────

class _AbonnementGate extends StatefulWidget {
  const _AbonnementGate();
  @override
  State<_AbonnementGate> createState() => _AbonnementGateState();
}
class _AbonnementGateState extends State<_AbonnementGate> {
  Utilisateur? _u;
  @override
  void initState() { super.initState(); _charger(); }
  Future<void> _charger() async {
    final u = await Droits.utilisateurCourant();
    if (mounted) setState(() => _u = u);
  }
  @override
  Widget build(BuildContext context) {
    if (_u == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
    return PageAbonnements(utilisateur: _u!);
  }
}

class _CreditsGate extends StatefulWidget {
  const _CreditsGate();
  @override
  State<_CreditsGate> createState() => _CreditsGateState();
}
class _CreditsGateState extends State<_CreditsGate> {
  Utilisateur? _u;
  @override
  void initState() { super.initState(); _charger(); }
  Future<void> _charger() async {
    final u = await Droits.utilisateurCourant();
    if (mounted) setState(() => _u = u);
  }
  @override
  Widget build(BuildContext context) {
    if (_u == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
    return PageAchatCreditsClient(utilisateur: _u!);
  }
}

class _HistoriqueGate extends StatefulWidget {
  const _HistoriqueGate();
  @override
  State<_HistoriqueGate> createState() => _HistoriqueGateState();
}
class _HistoriqueGateState extends State<_HistoriqueGate> {
  String? _uid;
  @override
  void initState() { super.initState(); _uid = FirebaseAuth.instance.currentUser?.uid; }
  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const Scaffold(body: Center(child: Text('Non connecté')));
    return PageHistoriqueCredits(utilisateurId: _uid!);
  }
}

class _RouteInconnue extends StatelessWidget {
  const _RouteInconnue();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Page introuvable')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('Cette page n\'existe pas', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/accueil', (_) => false),
            child: const Text('Retour à l\'accueil'),
          ),
        ],
      ),
    ),
  );
}

// ─── Helpers transitions ──────────────────────────────────────────────────────

PageRoute<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 200),
);

PageRoute<T> _slide<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 250),
);


/// Charge un pagne depuis un lien partagé et ouvre sa fiche.
class _ChargeurPagne extends StatelessWidget {
  final String pagneId;
  const _ChargeurPagne({required this.pagneId});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('pagnes').doc(pagneId).get(),
      builder: (context, s) {
        if (!s.hasData) {
          return const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
        }
        final data = s.data!.data();
        if (data == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('SAMI')),
              body: const Center(child: Text('Ce pagne n\'existe plus')));
        }
        return PagneDetailPage(
            pagne: Pagne.fromMap({'id': s.data!.id, ...data}));
      },
    );
  }
}

/// Charge une boutique depuis un lien partagé et ouvre sa vitrine.
class _ChargeurBoutique extends StatelessWidget {
  final String boutiqueId;
  const _ChargeurBoutique({required this.boutiqueId});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('boutiques').doc(boutiqueId).get(),
      builder: (context, s) {
        if (!s.hasData) {
          return const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6A1B9A))));
        }
        if (s.data!.data() == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('SAMI')),
              body: const Center(child: Text('Boutique introuvable')));
        }
        return BoutiqueDetailPage(
            boutique: Boutique.fromFirebaseDocument(s.data!));
      },
    );
  }
}
