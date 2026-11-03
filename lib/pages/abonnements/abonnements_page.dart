import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/commission_boutique_service.dart';
import 'package:sami/models/abonnements.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/services/credit_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent  = Color(0xFFFF8F00);

// ═══════════════════════════════════════════════════════════════════════════
// PAGES D'ABONNEMENTS ET CRÉDITS
// ─────────────────────────────────────────────────────────────────────────
// PageAbonnements          → routeur selon le rôle de l'utilisateur
// PageAvoirsClient         → client : solde d'avoirs, historique, avoirs en attente
// PageAbonnementBoutique   → boutiquier choisit son abonnement
// PageAbonnementCouturier  → couturier choisit son abonnement
// PageInscriptionLivreur   → livreur choisit son type de véhicule
// PageHistoriqueCredits    → historique commun à tous les rôles
// ═══════════════════════════════════════════════════════════════════════════

// ─── Routeur principal ────────────────────────────────────────────────────────

class PageAbonnements extends StatefulWidget {
  final Utilisateur utilisateur;
  const PageAbonnements({super.key, required this.utilisateur});

  @override
  State<PageAbonnements> createState() => _PageAbonnementsState();
}

class _PageAbonnementsState extends State<PageAbonnements>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    // Nombre d'onglets selon le rôle
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final u = widget.utilisateur;

    // Choisir la vue principale selon le rôle
    return switch (u.role) {
      'boutiquier' => PageAbonnementBoutique(utilisateur: u),
      'couturier'  => PageAbonnementCouturier(utilisateur: u),
      'livreur'    => PageInscriptionLivreur(utilisateur: u),
      _            => PageAvoirsClient(utilisateur: u),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIENT — Mes avoirs (décision 03/11/2026 : les crédits sont des AVOIRS,
// issus des remboursements, du cashback et du parrainage ; jamais achetés)
// ═══════════════════════════════════════════════════════════════════════════

class PageAvoirsClient extends StatelessWidget {
  final Utilisateur utilisateur;
  const PageAvoirsClient({super.key, required this.utilisateur});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mes avoirs'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PageHistoriqueCredits(utilisateurId: utilisateur.id))),
            icon: const Icon(Icons.history, color: Colors.white70, size: 18),
            label: const Text('Historique', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSoldeClient(utilisateur: utilisateur),
          const SizedBox(height: 20),
          _SectionTitre('D\'où viennent mes avoirs ?', Icons.info_outline, Colors.teal),
          const SizedBox(height: 10),
          const _CardAvantagesCredits(),
          const SizedBox(height: 20),
          _SectionTitre('Avoirs en cours de validation', Icons.hourglass_top, _kAccent),
          const SizedBox(height: 10),
          _AvoirsEnAttente(utilisateurId: utilisateur.id),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Entrées de `remboursements_a_faire` du client encore « a_traiter »
/// (remboursement, cashback, parrainage) — validées par le staff.
class _AvoirsEnAttente extends StatelessWidget {
  final String utilisateurId;
  const _AvoirsEnAttente({required this.utilisateurId});

  static String _libelle(String? type, String? motif) => switch (type) {
        'parrainage' => 'Prime de parrainage',
        'cashback' => 'Cashback fidélité',
        'credits' => motif == 'commande_echouee_apres_debit'
            ? 'Commande échouée — avoir restitué'
            : 'Remboursement en avoir',
        'mobile_money' => 'Remboursement Mobile Money',
        _ => 'Avoir',
      };

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('remboursements_a_faire')
            .where('clientId', isEqualTo: utilisateurId)
            .where('statut', isEqualTo: 'a_traiter')
            .snapshots(),
        builder: (_, snap) {
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Text('Aucun avoir en attente.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600));
          }
          return Column(
            children: docs.map((d) {
              final r = d.data();
              final montant = (r['montant'] as num?)?.toDouble() ?? 0;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.hourglass_top, color: _kAccent),
                  title: Text(_libelle(r['type'] as String?, r['motif'] as String?),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: const Text('En attente de validation par PagneShop',
                      style: TextStyle(fontSize: 11)),
                  trailing: Text('+${PrixFCFA.formater(montant)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _kAccent)),
                ),
              );
            }).toList(),
          );
        },
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// BOUTIQUIER — Abonnement mensuel
// ═══════════════════════════════════════════════════════════════════════════

class PageAbonnementBoutique extends StatefulWidget {
  final Utilisateur utilisateur;
  const PageAbonnementBoutique({super.key, required this.utilisateur});
  @override
  State<PageAbonnementBoutique> createState() => _PageAbonnementBoutiqueState();
}

class _PageAbonnementBoutiqueState extends State<PageAbonnementBoutique> {
  TypeAbonnementBoutique? _typeSelectionne;
  String _methode = 'orange';
  final _telCtrl = TextEditingController();
  bool _enCours = false;
  TypeAbonnementBoutique? _abonnementActuel;

  @override
  void initState() {
    super.initState();
    _telCtrl.text = widget.utilisateur.telephone.replaceFirst('+237', '');
    _chargerAbonnementActuel();
  }

  @override
  void dispose() { _telCtrl.dispose(); super.dispose(); }

  Future<void> _chargerAbonnementActuel() async {
    final doc = await ProfilAbonnementBoutique.collection.doc(widget.utilisateur.id).get();
    if (doc.exists && mounted) {
      setState(() => _abonnementActuel = TypeAbonnementBoutique.values.firstWhere((e) => e.name == (doc.data()!['typeAbonnement'] as String? ?? 'gratuit'), orElse: () => TypeAbonnementBoutique.values.first));
    } else {
      setState(() => _abonnementActuel = TypeAbonnementBoutique.gratuit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon abonnement boutique'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PageHistoriqueCredits(utilisateurId: widget.utilisateur.id))),
            icon: const Icon(Icons.history, color: Colors.white70, size: 18),
            label: const Text('Historique', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══ CE QUE VOUS AVEZ : l'abonné doit VOIR sa différence ═══
          FutureBuilder<List<(String, AbonnementBoutique)>>(
            future: () async {
              final q = await FirebaseFirestore.instance
                  .collection('boutiques')
                  .where('gerants', arrayContains: widget.utilisateur.id)
                  .get();
              final res = <(String, AbonnementBoutique)>[];
              for (final d in q.docs) {
                res.add((
                  d.data()['nom'] as String? ?? 'Boutique',
                  await CommissionBoutiqueService.abonnementDe(d.id),
                ));
              }
              return res;
            }(),
            builder: (c2, s2) {
              final liste = s2.data;
              if (liste == null || liste.isEmpty) return const SizedBox.shrink();
              return Column(children: [ for (final (nomB, ab) in liste) Card(
                color: _kPrimary.withOpacity(0.06),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _kPrimary.withOpacity(0.4))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.workspace_premium,
                            color: _kPrimary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('$nomB — abonnement : ${ab.nom}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5))),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                          '• Commission : ${ab.tauxCommission}%\n'
                          '• Pagnes publiables : ${ab.limitePagesPagnes}\n'
                          '• Photos par pagne : ${ab.limitePhotosParPagne}',
                          style: const TextStyle(fontSize: 12.5, height: 1.5)),
                      if (ab.avantages.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...ab.avantages.map((v) => Text('✓ $v',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green))),
                      ],
                      const SizedBox(height: 6),
                      const Text(
                          'Les offres ci-dessous montrent ce que chaque niveau supérieur débloque.',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              )]);
            },
          ),
          const SizedBox(height: 16),
          // Abonnement actuel
          if (_abonnementActuel != null)
            _CardAbonnementActuel(
              nom: AbonnementBoutique.catalogue[_abonnementActuel]!.nom,
              couleur: AbonnementBoutique.catalogue[_abonnementActuel]!.couleur,
              icone: AbonnementBoutique.catalogue[_abonnementActuel]!.icone,
              commission: '${AbonnementBoutique.catalogue[_abonnementActuel]!.tauxCommission}% par vente',
            ),
          const SizedBox(height: 20),

          _SectionTitre('Choisir un abonnement', Icons.workspace_premium, _kPrimary),
          const SizedBox(height: 10),

          ...AbonnementBoutique.catalogue.values.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CarteAbonnement(
              nom: a.nom,
              prix: a.prixFmt,
              commission: '${a.tauxCommission}% de commission',
              avantages: a.avantages,
              couleur: a.couleur,
              icone: a.icone,
              estActuel: _abonnementActuel == a.type,
              selectionne: _typeSelectionne == a.type,
              onTap: a.type == _abonnementActuel
                  ? null
                  : () => setState(() => _typeSelectionne = a.type),
            ),
          )),

          if (_typeSelectionne != null && _typeSelectionne != _abonnementActuel) ...[
            const SizedBox(height: 20),
            _SelecteurMoMo(methode: _methode, telephone: _telCtrl,
                onChange: (m) => setState(() => _methode = m)),
            const SizedBox(height: 16),
            _BoutonPayer(
              label: AbonnementBoutique.catalogue[_typeSelectionne]!.prixMensuel == 0
                  ? 'Activer gratuitement'
                  : 'Souscrire — ${AbonnementBoutique.catalogue[_typeSelectionne]!.prixFmt}',
              enCours: _enCours,
              onTap: _souscrire,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _souscrire() async {
    if (_typeSelectionne == null) return;
    setState(() => _enCours = true);
    try {
      final r = await CreditService.souscrireAbonnementBoutique(
        boutiqueId: widget.utilisateur.id,
        type: _typeSelectionne!,
        methodePaiement: _methode,
        numeroTelephone: '+237${_telCtrl.text}',
      );
      if (!mounted) return;
      if (r.succes) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${r.message}'),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
        setState(() { _abonnementActuel = _typeSelectionne; _typeSelectionne = null; });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ ${r.erreur}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COUTURIER — Abonnement mensuel
// ═══════════════════════════════════════════════════════════════════════════

class PageAbonnementCouturier extends StatefulWidget {
  final Utilisateur utilisateur;
  const PageAbonnementCouturier({super.key, required this.utilisateur});
  @override
  State<PageAbonnementCouturier> createState() => _PageAbonnementCouturierState();
}

class _PageAbonnementCouturierState extends State<PageAbonnementCouturier> {
  TypeAbonnementCouturier? _selectionne;
  TypeAbonnementCouturier _actuel = TypeAbonnementCouturier.gratuit;
  String _methode = 'orange';
  final _telCtrl = TextEditingController();
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _telCtrl.text = widget.utilisateur.telephone.replaceFirst('+237', '');
    _charger();
  }

  @override
  void dispose() { _telCtrl.dispose(); super.dispose(); }

  Future<void> _charger() async {
    final doc = await FirebaseFirestore.instance
        .collection('profils_couturier').doc(widget.utilisateur.id).get();
    if (doc.exists && mounted) {
      setState(() => _actuel = TypeAbonnementCouturier.values.firstWhere((e) => e.name == (doc.data()!['typeAbonnement'] as String? ?? 'gratuit'), orElse: () => TypeAbonnementCouturier.values.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon abonnement couturier'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardAbonnementActuel(
            nom: AbonnementCouturier.catalogue[_actuel]!.nom,
            couleur: Colors.teal,
            icone: Icons.content_cut,
            commission: '${AbonnementCouturier.catalogue[_actuel]!.tauxCommission}% de commission',
          ),
          const SizedBox(height: 20),
          _SectionTitre('Choisir un abonnement', Icons.workspace_premium, _kPrimary),
          const SizedBox(height: 10),
          ...AbonnementCouturier.catalogue.values.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CarteAbonnement(
              nom: a.nom,
              prix: a.prixMensuelFmt,
              commission: '${a.tauxCommission}% de commission',
              avantages: a.avantages,
              couleur: Colors.teal,
              icone: Icons.content_cut,
              estActuel: _actuel == a.type,
              selectionne: _selectionne == a.type,
              onTap: a.type == _actuel ? null : () => setState(() => _selectionne = a.type),
            ),
          )),
          if (_selectionne != null && _selectionne != _actuel) ...[
            const SizedBox(height: 20),
            _SelecteurMoMo(methode: _methode, telephone: _telCtrl,
                onChange: (m) => setState(() => _methode = m)),
            const SizedBox(height: 16),
            _BoutonPayer(
              label: AbonnementCouturier.catalogue[_selectionne]!.prixMensuel == 0
                  ? 'Activer gratuitement'
                  : 'Souscrire — ${AbonnementCouturier.catalogue[_selectionne]!.prixMensuelFmt}',
              enCours: _enCours,
              onTap: () async {
                setState(() => _enCours = true);
                final r = await CreditService.souscrireAbonnementCouturier(
                  couturierId: widget.utilisateur.id,
                  type: _selectionne!,
                  methodePaiement: _methode,
                  numeroTelephone: '+237${_telCtrl.text}',
                );
                if (!mounted) return;
                if (r.succes) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('✅ ${r.message}'), backgroundColor: Colors.green));
                  setState(() { _actuel = _selectionne!; _selectionne = null; });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('❌ ${r.erreur}'), backgroundColor: Colors.red));
                }
                setState(() => _enCours = false);
              },
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVREUR — Inscription et abonnement
// ═══════════════════════════════════════════════════════════════════════════

class PageInscriptionLivreur extends StatefulWidget {
  final Utilisateur utilisateur;
  const PageInscriptionLivreur({super.key, required this.utilisateur});
  @override
  State<PageInscriptionLivreur> createState() => _PageInscriptionLivreurState();
}

class _PageInscriptionLivreurState extends State<PageInscriptionLivreur> {
  TypeAbonnementLivreur? _selectionne;
  String _methode = 'orange';
  final _telCtrl = TextEditingController();
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _telCtrl.text = widget.utilisateur.telephone.replaceFirst('+237', '');
  }

  @override
  void dispose() { _telCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Devenir livreur'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Présentation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(14)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.delivery_dining, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Expanded(child: Text('Rejoindre l\'équipe SAMI',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              ]),
              SizedBox(height: 8),
              Text('Livrez les pagnes de Garoua et gagnez à votre rythme.\nChoisissez votre type de véhicule ci-dessous.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),
          _SectionTitre('Choisir votre véhicule', Icons.directions_bike, _kPrimary),
          const SizedBox(height: 10),
          ...AbonnementLivreur.catalogue.values.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CarteLivreur(
              abonnement: a,
              selectionne: _selectionne == a.type,
              onTap: () => setState(() => _selectionne = a.type),
            ),
          )),
          if (_selectionne != null) ...[
            const SizedBox(height: 20),
            _SelecteurMoMo(methode: _methode, telephone: _telCtrl,
                onChange: (m) => setState(() => _methode = m)),
            const SizedBox(height: 16),
            _BoutonPayer(
              label: () {
                final a = AbonnementLivreur.catalogue[_selectionne]!;
                final total = a.fraisInscription + a.prixMensuel;
                return total == 0
                    ? 'S\'inscrire gratuitement'
                    : 'S\'inscrire — ${PrixFCFA.formater(total)}';
              }(),
              enCours: _enCours,
              onTap: () async {
                setState(() => _enCours = true);
                final r = await CreditService.inscrireLivreur(
                  livreurId: widget.utilisateur.id,
                  type: _selectionne!,
                  methodePaiement: _methode,
                  numeroTelephone: '+237${_telCtrl.text}',
                );
                if (!mounted) return;
                if (r.succes) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('✅ ${r.message}'), backgroundColor: Colors.green));
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('❌ ${r.erreur}'), backgroundColor: Colors.red));
                }
                setState(() => _enCours = false);
              },
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORIQUE DES CRÉDITS
// ═══════════════════════════════════════════════════════════════════════════

class PageHistoriqueCredits extends StatelessWidget {
  final String utilisateurId;
  const PageHistoriqueCredits({super.key, required this.utilisateurId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Historique des crédits'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CreditService.streamHistorique(utilisateurId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return const Center(child: Text('Aucun mouvement', style: TextStyle(color: Colors.grey)));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: snap.data!.docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = snap.data!.docs[i].data();
              final montant = (d['montant'] as num? ?? 0).toDouble();
              final isCredit = montant > 0;
              final date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: isCredit ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCredit ? Icons.add : Icons.remove,
                    color: isCredit ? Colors.green : Colors.red, size: 18,
                  ),
                ),
                title: Text(d['description'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2,'0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                trailing: Text(
                  '${isCredit ? '+' : ''}${PrixFCFA.formater(montant)}',
                  style: TextStyle(
                    color: isCredit ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold, fontSize: 14,
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

// ═══════════════════════════════════════════════════════════════════════════
// COMPOSANTS PARTAGÉS
// ═══════════════════════════════════════════════════════════════════════════

class _CardSoldeClient extends StatelessWidget {
  final Utilisateur utilisateur;
  const _CardSoldeClient({required this.utilisateur});

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('utilisateurs').doc(utilisateur.id).snapshots(),
    builder: (_, snap) {
      final solde = snap.hasData
          ? (snap.data!.data()?['creditBalance'] as num?)?.toDouble() ?? 0
          : utilisateur.creditBalance;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_kPrimary, _kPrimary.withBlue(200)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Avoirs disponibles', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(PrixFCFA.formater(solde),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const Text('Utilisable pour vos commandes', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
          const Icon(Icons.account_balance_wallet, color: Colors.white30, size: 48),
        ]),
      );
    },
  );
}

class _CardAbonnementActuel extends StatelessWidget {
  final String nom;
  final Color couleur;
  final IconData icone;
  final String commission;
  const _CardAbonnementActuel({required this.nom, required this.couleur,
    required this.icone, required this.commission});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: couleur.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: couleur.withOpacity(0.3)),
    ),
    child: Row(children: [
      Container(width: 42, height: 42,
        decoration: BoxDecoration(color: couleur.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icone, color: couleur, size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Abonnement actuel', style: TextStyle(color: couleur.withOpacity(0.7), fontSize: 11)),
        Text(nom, style: TextStyle(fontWeight: FontWeight.bold, color: couleur, fontSize: 16)),
        Text(commission, style: TextStyle(fontSize: 12, color: couleur.withOpacity(0.7))),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(8)),
        child: const Text('Actif', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ]),
  );
}

class _CarteAbonnement extends StatelessWidget {
  final String nom;
  final String prix;
  final String commission;
  final List<String> avantages;
  final Color couleur;
  final IconData icone;
  final bool estActuel;
  final bool selectionne;
  final VoidCallback? onTap;

  const _CarteAbonnement({required this.nom, required this.prix, required this.commission,
    required this.avantages, required this.couleur, required this.icone,
    required this.estActuel, required this.selectionne, this.onTap});

  @override
  Widget build(BuildContext context) {
    final actif = estActuel || selectionne;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: actif ? couleur.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: actif ? couleur : Colors.grey.shade200,
              width: actif ? 2 : 1),
        ),
        child: Column(children: [
          // En-tête
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: actif ? couleur.withOpacity(0.1) : Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              Icon(icone, color: couleur, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: couleur)),
                Text(commission, style: TextStyle(fontSize: 11, color: couleur.withOpacity(0.7))),
              ])),
              Text(prix, style: TextStyle(fontWeight: FontWeight.bold, color: couleur, fontSize: 14)),
              if (estActuel) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Actuel', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ] else if (selectionne) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: couleur, size: 20),
              ],
            ]),
          ),
          // Avantages
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: avantages.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.check, color: couleur, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a, style: const TextStyle(fontSize: 12, color: Colors.black87))),
                ]),
              )).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CarteLivreur extends StatelessWidget {
  final AbonnementLivreur abonnement;
  final bool selectionne;
  final VoidCallback onTap;
  const _CarteLivreur({required this.abonnement, required this.selectionne, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fraisTotal = abonnement.fraisInscription + abonnement.prixMensuel;
    return _CarteAbonnement(
      nom: abonnement.nom,
      prix: fraisTotal == 0 ? 'Gratuit' : PrixFCFA.formater(fraisTotal),
      commission: '${PrixFCFA.formater(abonnement.gainParLivraison)} / livraison',
      avantages: abonnement.avantages,
      couleur: abonnement.couleur,
      icone: abonnement.icone,
      estActuel: false,
      selectionne: selectionne,
      onTap: onTap,
    );
  }
}

class _SelecteurMoMo extends StatelessWidget {
  final String methode;
  final TextEditingController telephone;
  final ValueChanged<String> onChange;
  const _SelecteurMoMo({required this.methode, required this.telephone, required this.onChange});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Mode de paiement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _BoutonOperateur('🟠 Orange Money', 'orange', methode, onChange)),
        const SizedBox(width: 10),
        Expanded(child: _BoutonOperateur('🟡 MTN MoMo', 'mtn', methode, onChange)),
      ]),
      const SizedBox(height: 12),
      TextFormField(
        controller: telephone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Numéro de téléphone',
          prefixText: '+237 ',
          prefixIcon: const Icon(Icons.phone_outlined, size: 18),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
        ),
      ),
    ],
  );
}

class _BoutonOperateur extends StatelessWidget {
  final String label;
  final String valeur;
  final String actuel;
  final ValueChanged<String> onSelect;
  const _BoutonOperateur(this.label, this.valeur, this.actuel, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final actif = actuel == valeur;
    return GestureDetector(
      onTap: () => onSelect(valeur),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: actif ? _kPrimary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: actif ? _kPrimary : Colors.grey.shade300,
              width: actif ? 2 : 1),
        ),
        child: Center(child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: actif ? FontWeight.bold : FontWeight.normal,
                color: actif ? _kPrimary : Colors.black87))),
      ),
    );
  }
}

class _BoutonPayer extends StatelessWidget {
  final String label;
  final bool enCours;
  final VoidCallback onTap;
  const _BoutonPayer({required this.label, required this.enCours, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 56,
    child: ElevatedButton(
      onPressed: enCours ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimary, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
      child: enCours
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(label, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
    ),
  );
}

class _SectionTitre extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Color couleur;
  const _SectionTitre(this.titre, this.icone, this.couleur);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icone, color: couleur, size: 18),
    const SizedBox(width: 8),
    Text(titre, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: couleur)),
  ]);
}

class _CardAvantagesCredits extends StatelessWidget {
  const _CardAvantagesCredits();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.teal.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.teal.shade200),
    ),
    child: Column(children: [
      _Avantage(Icons.replay, 'Remboursement d\'une commande annulée ou d\'un retour accepté', Colors.teal),
      _Avantage(Icons.card_giftcard, 'Prime de parrainage (à la première livraison du filleul)', Colors.teal),
      _Avantage(Icons.stars, 'Cashback selon votre palier de fidélité', Colors.teal),
      _Avantage(Icons.shopping_bag_outlined, 'Se dépensent au panier, sans frais Mobile Money', Colors.teal),
      _Avantage(Icons.block, 'Ni rechargeables en argent, ni retirables', Colors.teal),
    ]),
  );
}

class _Avantage extends StatelessWidget {
  final IconData icone;
  final String texte;
  final Color couleur;
  const _Avantage(this.icone, this.texte, this.couleur);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icone, color: couleur, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(texte, style: TextStyle(fontSize: 12, color: couleur.withOpacity(0.8)))),
    ]),
  );
}
