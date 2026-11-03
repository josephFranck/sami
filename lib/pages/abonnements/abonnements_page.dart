import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/services/abonnement_service.dart';
import 'package:sami/services/credit_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent  = Color(0xFFFF8F00);

// ═══════════════════════════════════════════════════════════════════════════
// PAGES D'ABONNEMENTS ET AVOIRS
// ─────────────────────────────────────────────────────────────────────────
// PageAbonnements      → un onglet par profil de l'utilisateur (multi-rôles)
// PageSouscription     → plans d'UN profil, demande par transfert MoMo déclaré
// PageAvoirsClient     → client : solde d'avoirs, historique, avoirs en attente
// PageHistoriqueCredits → historique commun à tous les rôles
// ═══════════════════════════════════════════════════════════════════════════

// ─── Routeur principal ────────────────────────────────────────────────────────

class PageAbonnements extends StatelessWidget {
  final Utilisateur utilisateur;
  const PageAbonnements({super.key, required this.utilisateur});

  @override
  Widget build(BuildContext context) {
    final u = utilisateur;
    // Tout pro est aussi client (décision 03/11/2026) : un onglet par profil.
    final profils = <ProfilAbonnement>[
      if (u.aRole('boutiquier') || u.aRole('admin') || u.aRole('superadmin'))
        ProfilAbonnement.boutique,
      if (u.aRole('couturier')) ProfilAbonnement.couturier,
      if (u.aRole('livreur')) ProfilAbonnement.livreur,
      ProfilAbonnement.client,
    ];
    if (profils.length == 1) {
      return PageSouscription(utilisateur: u, profil: profils.first);
    }
    return DefaultTabController(
      length: profils.length,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(Tr.s.abonnements),
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: _kAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [for (final p in profils) Tab(text: p.libelle)],
          ),
        ),
        body: TabBarView(children: [
          for (final p in profils)
            PageSouscription(utilisateur: u, profil: p, integree: true),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SOUSCRIPTION — un profil : plan actuel, plans, demande MoMo déclaré,
// demandes en cours. Aucune écriture du plan ici : le staff active après
// vérification (AbonnementService.valider).
// ═══════════════════════════════════════════════════════════════════════════

class PageSouscription extends StatefulWidget {
  final Utilisateur utilisateur;
  final ProfilAbonnement profil;
  final bool integree; // dans un TabBarView : pas d'AppBar
  const PageSouscription(
      {super.key, required this.utilisateur, required this.profil, this.integree = false});
  @override
  State<PageSouscription> createState() => _PageSouscriptionState();
}

class _PageSouscriptionState extends State<PageSouscription> {
  List<PlanAbonnement> _plans = const [];
  List<(String, String)> _fiches = const [];
  String? _ficheId;
  AbonnementActuel _actuel = const AbonnementActuel(planId: 'aucun');
  PlanAbonnement? _choisi;
  final _refCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  bool _charge = false, _envoi = false, _momoOk = false;
  String _numMtn = '', _numOm = '', _titulaire = '';

  @override
  void initState() {
    super.initState();
    _numCtrl.text = widget.utilisateur.telephone.replaceFirst('+237', '');
    _charger();
  }

  @override
  void dispose() { _refCtrl.dispose(); _numCtrl.dispose(); super.dispose(); }

  Future<void> _charger() async {
    final plans = await AbonnementService.plans(widget.profil);
    final fiches = await AbonnementService.fiches(widget.profil, widget.utilisateur.id);
    final declActif = await ParametresService.momoDeclareActif();
    final nMtn = await ParametresService.numeroMoMoMTN();
    final nOm = await ParametresService.numeroOM();
    final tit = await ParametresService.titulaireMoMo();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _fiches = fiches;
      _ficheId = fiches.isNotEmpty ? fiches.first.$1 : null;
      _momoOk = declActif && (nMtn.isNotEmpty || nOm.isNotEmpty);
      _numMtn = nMtn; _numOm = nOm; _titulaire = tit;
      _charge = true;
    });
    await _chargerActuel();
  }

  Future<void> _chargerActuel() async {
    final id = _ficheId;
    if (id == null) return;
    final a = await AbonnementService.actuel(widget.profil, id);
    if (mounted) setState(() => _actuel = a);
  }

  String get _ficheNom =>
      _fiches.where((f) => f.$1 == _ficheId).map((f) => f.$2).firstOrNull ?? '';

  @override
  Widget build(BuildContext context) {
    final corps = !_charge
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_fiches.isEmpty)
                _Info(
                  couleur: Colors.orange,
                  icone: Icons.info_outline,
                  texte: switch (widget.profil) {
                    ProfilAbonnement.boutique =>
                      Tr.s.aucuneBoutiqueDontVousEtes,
                    ProfilAbonnement.couturier =>
                      Tr.s.aucuneFicheCouturierValideeDeposez,
                    ProfilAbonnement.livreur =>
                      Tr.s.aucuneFicheLivreurValideeDeposez,
                    ProfilAbonnement.client => Tr.s.compteIntrouvable,
                  },
                )
              else ...[
                if (_fiches.length > 1) ...[
                  DropdownButtonFormField<String>(
                    value: _ficheId,
                    decoration: InputDecoration(
                        labelText: Tr.s.boutique, isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (final f in _fiches)
                        DropdownMenuItem(value: f.$1, child: Text(f.$2, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) { setState(() { _ficheId = v; _choisi = null; }); _chargerActuel(); },
                  ),
                  const SizedBox(height: 12),
                ],
                _CardPlanActuel(profil: widget.profil, actuel: _actuel, plans: _plans),
                const SizedBox(height: 18),
                if (_plans.isEmpty)
                  _Info(
                    couleur: Colors.grey,
                    icone: Icons.hourglass_empty,
                    texte: Tr.s.aucuneOffreAbonnementPourMoment(widget.profil.libelle.toLowerCase()),
                  )
                else ...[
                  _SectionTitre(Tr.s.choisirPlan, Icons.workspace_premium, _kPrimary),
                  const SizedBox(height: 10),
                  for (final p in _plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CarteAbonnement(
                        nom: p.nom,
                        prix: p.prixFmt,
                        commission: p.gratuit ? Tr.s.sansEngagement : Tr.s.jours(p.dureeJours),
                        avantages: p.avantages,
                        couleur: p.couleur,
                        icone: p.icone,
                        estActuel: _actuel.actif
                            ? _actuel.planId == p.id
                            : (p.gratuit && !_actuel.actif),
                        selectionne: _choisi?.id == p.id,
                        // le plan actif reste sélectionnable : renouvellement
                        onTap: () => setState(() => _choisi = p),
                      ),
                    ),
                  if (_choisi != null) _buildDemande(_choisi!),
                ],
                const SizedBox(height: 18),
                _SectionTitre(Tr.s.mesDemandes, Icons.receipt_long, _kAccent),
                const SizedBox(height: 8),
                _MesDemandes(utilisateurId: widget.utilisateur.id, profil: widget.profil),
              ],
              const SizedBox(height: 32),
            ],
          );
    if (widget.integree) return corps;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(Tr.s.abonnement(widget.profil.libelle.toLowerCase())),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: corps,
    );
  }

  /// Bloc « transférez puis déclarez » — même mécanique que le panier
  /// (momo_declare) : numéros de la plateforme, référence du SMS.
  Widget _buildDemande(PlanAbonnement p) {
    final renouvellement = _actuel.actif && _actuel.planId == p.id;
    if (!p.gratuit && !_momoOk) {
      return _Info(
        couleur: Colors.orange,
        icone: Icons.info_outline,
        texte: Tr.s.paiementParTransfertDeclareN,
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          p.gratuit
              ? Tr.s.planDemandeEstValideePar(p.nom)
              : '${renouvellement ? "Renouvellement" : "Souscription"} ${p.nom} — ${p.prixFmt}'
                  '${renouvellement ? "\nLa nouvelle période s\'ajoute à la fin de l\'actuelle (${_actuel.finFmt})." : ""}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        if (!p.gratuit) ...[
          const SizedBox(height: 8),
          Text(
              Tr.s.k1Transferez2CollezReference(PrixFCFA.formater(p.prix), _numMtn.isNotEmpty ? Tr.s.mtnMomo(_numMtn) : '', _numOm.isNotEmpty ? Tr.s.orangeMoney(_numOm) : '', _titulaire.isNotEmpty ? Tr.s.titulaire(_titulaire) : ''),
              style: const TextStyle(fontSize: 12, height: 1.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _refCtrl,
            decoration: InputDecoration(
              labelText: Tr.s.referenceTransaction,
              hintText: Tr.s.ex8123456789,
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _numCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: Tr.s.numeroMomoOmUtilise,
              prefixText: '+237 ',
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(Tr.s.notreEquipeVerifieSmsRecu,
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: _envoi ? null : () => _envoyer(p),
            icon: _envoi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 16),
            label: Text(p.gratuit ? Tr.s.demanderCePlan : Tr.s.jAiTransfereEnvoyerMa),
          ),
        ),
      ]),
    );
  }

  Future<void> _envoyer(PlanAbonnement p) async {
    final id = _ficheId;
    if (id == null) return;
    if (!p.gratuit) {
      if (_refCtrl.text.trim().length < 4) { _snack(Tr.s.entrezReferenceSmsTransfert, Colors.red); return; }
      if (_numCtrl.text.trim().length < 9) { _snack(Tr.s.entrezNumeroUtilisePourTransfert, Colors.red); return; }
    }
    setState(() => _envoi = true);
    try {
      await AbonnementService.demander(
        plan: p,
        entiteId: id,
        entiteNom: _ficheNom,
        utilisateurId: widget.utilisateur.id,
        refPaiement: _refCtrl.text,
        numeroPaiement: '+237${_numCtrl.text.trim()}',
      );
      if (!mounted) return;
      _refCtrl.clear();
      setState(() => _choisi = null);
      _snack(Tr.s.demandeEnvoyeeActivationApresVerification, Colors.green);
    } catch (e) {
      if (mounted) _snack(Tr.s.envoiImpossible(e), Colors.red);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _snack(String msg, Color c) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating));
}

class _CardPlanActuel extends StatelessWidget {
  final ProfilAbonnement profil;
  final AbonnementActuel actuel;
  final List<PlanAbonnement> plans;
  const _CardPlanActuel({required this.profil, required this.actuel, required this.plans});

  @override
  Widget build(BuildContext context) {
    final plan = plans.where((p) => p.id == actuel.planId).firstOrNull;
    final nom = actuel.actif
        ? (plan?.nom ?? actuel.planId)
        : (profil == ProfilAbonnement.client || profil == ProfilAbonnement.livreur
            ? Tr.s.aucunAbonnement
            : (plans.where((p) => p.gratuit).firstOrNull?.nom ?? Tr.s.gratuit));
    final couleur = actuel.actif ? (plan?.couleur ?? _kPrimary) : Colors.grey.shade700;
    final expire = actuel.planId != 'gratuit' && actuel.planId != 'aucun' &&
        actuel.finLe != null && !actuel.actif;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(color: couleur.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(plan?.icone ?? Icons.workspace_premium_outlined, color: couleur, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Tr.s.planActuel(profil.libelle.toLowerCase()), style: TextStyle(color: couleur.withOpacity(0.8), fontSize: 11)),
          Text(nom, style: TextStyle(fontWeight: FontWeight.bold, color: couleur, fontSize: 16)),
          if (actuel.actif && actuel.finLe != null)
            Text(Tr.s.jusqu(actuel.finFmt), style: TextStyle(fontSize: 12, color: couleur.withOpacity(0.8))),
          if (expire)
            Text(Tr.s.expireRetourPlanBase(actuel.finFmt), style: const TextStyle(fontSize: 12, color: Colors.red)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(8)),
          child: Text(actuel.actif ? Tr.s.actif : Tr.s.planBase, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _MesDemandes extends StatelessWidget {
  final String utilisateurId;
  final ProfilAbonnement profil;
  const _MesDemandes({required this.utilisateurId, required this.profil});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DemandeAbonnement>>(
        stream: AbonnementService.mesDemandes(utilisateurId),
        builder: (_, snap) {
          final l = (snap.data ?? const <DemandeAbonnement>[])
              .where((d) => d.profil == profil)
              .take(10)
              .toList();
          if (l.isEmpty) {
            return Text(Tr.s.aucuneDemande, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600));
          }
          return Column(children: [
            for (final d in l)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    switch (d.statut) {
                      'validee' => Icons.check_circle,
                      'refusee' => Icons.cancel,
                      _ => Icons.hourglass_top,
                    },
                    color: switch (d.statut) {
                      'validee' => Colors.green,
                      'refusee' => Colors.red,
                      _ => _kAccent,
                    },
                  ),
                  title: Text('${d.planNom} — ${d.prix <= 0 ? "gratuit" : PrixFCFA.formater(d.prix)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    switch (d.statut) {
                      'validee' => Tr.s.active,
                      'refusee' => 'Refusé${(d.motifRefus ?? '').isNotEmpty ? " : ${d.motifRefus}" : ""}',
                      _ => Tr.s.attenteVerificationTransfertRef(d.refPaiement),
                    },
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: d.dateCreation == null
                      ? null
                      : Text('${d.dateCreation!.day.toString().padLeft(2, '0')}/${d.dateCreation!.month.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ),
              ),
          ]);
        },
      );
}

class _Info extends StatelessWidget {
  final Color couleur;
  final IconData icone;
  final String texte;
  const _Info({required this.couleur, required this.icone, required this.texte});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: couleur.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: couleur.withOpacity(0.3))),
        child: Row(children: [
          Icon(icone, color: couleur, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
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
        title: Text(Tr.s.mesAvoirs),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PageHistoriqueCredits(utilisateurId: utilisateur.id))),
            icon: const Icon(Icons.history, color: Colors.white70, size: 18),
            label: Text(Tr.s.historique, style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSoldeClient(utilisateur: utilisateur),
          const SizedBox(height: 20),
          _SectionTitre(Tr.s.ouViennentMesAvoirs, Icons.info_outline, Colors.teal),
          const SizedBox(height: 10),
          const _CardAvantagesCredits(),
          const SizedBox(height: 20),
          _SectionTitre(Tr.s.avoirsCoursValidation, Icons.hourglass_top, _kAccent),
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
        'parrainage' => Tr.s.primeParrainage,
        'cashback' => Tr.s.cashbackFidelite,
        'credits' => motif == 'commande_echouee_apres_debit'
            ? Tr.s.commandeEchoueeAvoirRestitue
            : Tr.s.remboursementAvoir,
        'mobile_money' => Tr.s.remboursementMobileMoney,
        _ => Tr.s.avoir,
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
            return Text(Tr.s.aucunAvoirAttente,
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
                  subtitle: Text(Tr.s.attenteValidationParPagneshop,
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
        title: Text(Tr.s.historiqueCredits),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CreditService.streamHistorique(utilisateurId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return Center(child: Text(Tr.s.aucunMouvement, style: TextStyle(color: Colors.grey)));

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
            Text(Tr.s.avoirsDisponibles, style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(PrixFCFA.formater(solde),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            Text(Tr.s.utilisablePourVosCommandes, style: TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
          const Icon(Icons.account_balance_wallet, color: Colors.white30, size: 48),
        ]),
      );
    },
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
                  child: Text(Tr.s.actuel, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
      _Avantage(Icons.replay, Tr.s.remboursementCommandeAnnuleeOuRetour, Colors.teal),
      _Avantage(Icons.card_giftcard, Tr.s.primeParrainagePremiereLivraisonFilleul, Colors.teal),
      _Avantage(Icons.stars, Tr.s.cashbackSelonVotrePalierFidelite, Colors.teal),
      _Avantage(Icons.shopping_bag_outlined, Tr.s.seDepensentPanierSansFrais, Colors.teal),
      _Avantage(Icons.block, Tr.s.niRechargeablesArgentNiRetirables, Colors.teal),
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
