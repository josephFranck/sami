import 'package:flutter/material.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/pages/livraison/qr_boutique_page.dart';
import 'package:sami/pages/commandes/analyse_page.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/services/commande_multi_service.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// Vue boutiquier : toutes ses sous-commandes groupées par statut
class DashboardBoutiquier extends StatefulWidget {
  final String boutiqueId;
  const DashboardBoutiquier({super.key, required this.boutiqueId});
  @override
  State<DashboardBoutiquier> createState() => _DashboardBoutiquierState();
}

class _DashboardBoutiquierState extends State<DashboardBoutiquier>
    with SingleTickerProviderStateMixin, PageProtegee {

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) {
      if (!Droits.estBoutiquier(u)) {
        return Scaffold(
          appBar: AppBar(title: Text(Tr.s.mesCommandes), backgroundColor: _kPrimary, foregroundColor: Colors.white),
          body: Center(child: Text(Tr.s.accesReserveBoutiquiers)));
      }
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(Tr.s.mesCommandes),
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.insights_outlined),
              tooltip: Tr.s.analyse,
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnalysePage(boutiqueId: widget.boutiqueId),
              )),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: Tr.s.traiter),
              Tab(text: Tr.s.livraison),
              Tab(text: Tr.s.terminees),
            ],
          ),
        ),
        body: StreamBuilder<List<SousCommande>>(
          stream: CommandeMultiService.sousCommandesBoutique(widget.boutiqueId),
          builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(Tr.s.impossibleChargerCommandes(snap.error),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            );
          }
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator(color: _kPrimary));
            if (!snap.hasData || snap.data!.isEmpty)
              return Center(child: Text(Tr.s.aucuneCommande, style: TextStyle(color: Colors.grey)));

            final toutes = snap.data!;
            final aTraiter = toutes.where((sc) => [
              StatutSousCommande.enAttente,
              StatutSousCommande.confirmeeBoutique,
              StatutSousCommande.enPreparation,
              StatutSousCommande.prete,
            ].contains(sc.statut)).toList();

            final enLivraison = toutes.where((sc) => [
              StatutSousCommande.enCoursLivraison,
              StatutSousCommande.avecCouturier,
              StatutSousCommande.costurierTermine,
            ].contains(sc.statut)).toList();

            final terminees = toutes.where((sc) =>
              sc.statut == StatutSousCommande.livree ||
              sc.statut == StatutSousCommande.terminee || // legacy
              sc.statut == StatutSousCommande.annulee
            ).toList();

            return TabBarView(
              controller: _tabs,
              children: [
                _ListeSousCommandes(scs: aTraiter, onAction: _traiterAction),
                _ListeSousCommandes(scs: enLivraison, onAction: _traiterAction),
                _ListeSousCommandes(scs: terminees, onAction: null),
              ],
            );
          },
        ),
      );
    },
  );

  Future<void> _traiterAction(SousCommande sc) async {
    switch (sc.statut) {
      case StatutSousCommande.enAttente:
        await _confirmer(sc);
        break;
      case StatutSousCommande.confirmeeBoutique:
      case StatutSousCommande.enPreparation:
        await _marquerPrete(sc);
        break;
      default:
        break;
    }
  }

  Future<void> _confirmer(SousCommande sc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Tr.s.confirmerCommande),
        content: Text(Tr.s.confirmezVousPrendreChargeCommande(sc.articles.length, PrixFCFA.formater(sc.totalClient))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Tr.s.annuler)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
            child: Text(Tr.s.confirmer),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await CommandeMultiService.confirmerParBoutique(sc.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Tr.s.commandeConfirmee), backgroundColor: Colors.green));
  }

  Future<void> _marquerPrete(SousCommande sc) async {
    await CommandeMultiService.marquerPrete(sc.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Tr.s.commandeMarqueePreteLivreurCours), backgroundColor: Colors.blue));
  }
}

class _ListeSousCommandes extends StatelessWidget {
  final List<SousCommande> scs;
  final Future<void> Function(SousCommande)? onAction;
  const _ListeSousCommandes({required this.scs, this.onAction});

  @override
  Widget build(BuildContext context) {
    if (scs.isEmpty) return Center(
        child: Text(Tr.s.aucuneCommandeDansCetteCategorie, style: TextStyle(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: scs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _CarteSCBoutique(sc: scs[i], onAction: onAction),
    );
  }
}

class _CarteSCBoutique extends StatelessWidget {
  final SousCommande sc;
  final Future<void> Function(SousCommande)? onAction;
  const _CarteSCBoutique({required this.sc, this.onAction});

  @override
  Widget build(BuildContext context) {
    final (couleur, label, boutonLabel) = _statutInfo(sc.statut);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: couleur.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(Tr.s.commande(sc.id.substring(0,6).toUpperCase()),
                style: const TextStyle(fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: couleur.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          // COUTURE : le pagne part chez le couturier, pas chez le client
          if (sc.commandeCoutureId != null)
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200)),
              child: Row(children: [
                const Icon(Icons.content_cut, size: 15, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        sc.notesClient ??
                            Tr.s.coutureLivrerChezCouturier,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.teal.shade900))),
              ]),
            ),
          Text(quandFr(sc.dateCreation, prefixe: 'Commandée le '),
              style: TextStyle(
                  fontSize: 10.5, color: Colors.grey.shade600)),
          if (sc.articles.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                  Tr.s.aucunArticleLisibleCommandeTest,
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          ...sc.articles.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              GestureDetector(
                onTap: item.pagneImage == null
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: const EdgeInsets.all(10),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InteractiveViewer(
                                    maxScale: 5,
                                    child: ImageUniverselle(
                                        source: item.pagneImage!,
                                        fit: BoxFit.contain),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                        '${item.pagneNom} × ${item.quantite}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight.bold)),
                                  ),
                                ]),
                          ),
                        ),
                child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 72, height: 72,
                  child: item.pagneImage != null
                      ? ImageUniverselle(
                          source: item.pagneImage!, fit: BoxFit.cover)
                      : Container(
                          color: Colors.purple.shade50,
                          child: const Icon(Icons.checkroom,
                              size: 16, color: _kPrimary)),
                ),
              ),
              ), // ferme GestureDetector (tap-zoom)
              const SizedBox(width: 8),
              Expanded(child: Text('${item.pagneNom} × ${item.quantite}',
                  style: const TextStyle(fontSize: 13))),
              Text(PrixFCFA.formater(item.sousTotal),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          )),
          const Divider(height: 16),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Tr.s.netBoutiquier(PrixFCFA.formater(sc.netBoutique)),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 14)),
              // QR DE REMISE : toujours proposé dès « Prête » — la
              // livraison réelle est cherchée AU TAP dans sa collection
              // (l'ancienne condition lisait une liste jamais chargée :
              // le bouton n'apparaissait JAMAIS).
              if (sc.statut == StatutSousCommande.prete ||
                  sc.statut == StatutSousCommande.enCoursLivraison)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final q = await FirebaseFirestore.instance
                          .collection('livraisons')
                          .where('commandeId', isEqualTo: sc.id) // clé canonique du doc livraison
                          .limit(1)
                          .get();
                      if (!context.mounted) return;
                      if (q.docs.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    Tr.s.agentAssigneLivreurQrSera),
                                backgroundColor: Colors.orange));
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrBoutiquePage(
                            livraisonId: q.docs.first.id,
                            referenceCommande: sc.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_2, size: 15),
                    label: Text(Tr.s.qrRemiseLivreur,
                        style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ),
            ])),
            if (boutonLabel != null && onAction != null)
              ElevatedButton(
                onPressed: () => onAction!(sc),
                style: ElevatedButton.styleFrom(
                  backgroundColor: couleur,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: Text(boutonLabel, style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ]),
      ),
    );
  }

  (Color, String, String?) _statutInfo(StatutSousCommande s) => switch (s) {
    StatutSousCommande.enAttente          => (Colors.orange, 'En attente', 'Confirmer'),
    StatutSousCommande.confirmeeBoutique  => (Colors.blue, 'Confirmée', 'Marquer prête'),
    StatutSousCommande.enPreparation      => (Colors.blue, 'En préparation', 'Marquer prête'),
    StatutSousCommande.prete              => (Colors.indigo, 'Prête', null),
    StatutSousCommande.enCoursLivraison   => (Colors.teal, 'En livraison', null),
    StatutSousCommande.avecCouturier      => (Colors.teal, 'Chez couturier', null),
    StatutSousCommande.terminee           => (Colors.green, 'Terminée ✓', null),
    StatutSousCommande.annulee            => (Colors.red, 'Annulée', null),
    _                                     => (Colors.grey, s.name, null),
  };
}
