import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/pages/livraison/code_reception_page.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/models/avis.dart';
import 'package:sami/widgets/widgets_notation.dart';
import 'package:sami/models/retour.dart';
import 'package:sami/services/retours_service.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/pages/map/carte_osm.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/services/commande_multi_service.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/utils/config_paiement.dart';
import 'package:sami/services/fidelite_service.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent  = Color(0xFFFF8F00);

// ─── Page principale : liste des sessions du client ───────────────────────────

class MesCommandesPage extends StatefulWidget {
  const MesCommandesPage({super.key});
  @override
  State<MesCommandesPage> createState() => _MesCommandesPageState();
}

class _MesCommandesPageState extends State<MesCommandesPage> with PageProtegee {
  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    // points de fidélité / parrainage des livraisons non comptées :
    // réclamés par le client (seul autorisé à écrire sur son doc)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) FideliteService.reclamerTout(uid);
  }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) => Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mes commandes'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<SessionCommande>>(
        stream: CommandeMultiService.sessionsClient(u.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.isEmpty)
            return _buildVide();
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: snap.data!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _CarteSession(
              session: snap.data![i],
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DetailSessionPage(sessionId: snap.data![i].id))),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildVide() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.receipt_long_outlined, size: 72, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      const Text('Aucune commande', style: TextStyle(fontSize: 16, color: Colors.grey)),
      const SizedBox(height: 8),
      const Text('Vos commandes apparaîtront ici', style: TextStyle(color: Colors.grey, fontSize: 13)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => Navigator.pushNamed(context, '/pagnepage'),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: const Text('Explorer les pagnes'),
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
      ),
    ]),
  );
}

// ─── Carte de session (résumé) ────────────────────────────────────────────────

class _CarteSession extends StatelessWidget {
  final SessionCommande session;
  final VoidCallback onTap;
  const _CarteSession({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (couleur, label, icone) = _statutInfo(session.statut);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Commande #${session.id.substring(0,6).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: couleur.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icone, size: 12, color: couleur),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            // Indicateur multi-boutiques
            Row(children: [
              Icon(Icons.store_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${session.nombreBoutiques} boutique${session.nombreBoutiques > 1 ? "s" : ""}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(_formatDate(session.dateCreation),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 10),
            // Barre de progression multi-boutiques
            if (session.sousCommandeIds.isNotEmpty)
              _BarreProgression(sousCommandeIds: session.sousCommandeIds),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(
                ConfigPaiement.libelleMethode(session.methodePaiement),
                style: const TextStyle(fontSize: 12, color: Colors.grey))),
              Text(session.totalFmt,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 15)),
            ]),
          ]),
        ),
      ),
    );
  }

  (Color, String, IconData) _statutInfo(StatutSession s) => switch (s) {
    StatutSession.enCours             => (Colors.orange, 'En cours', Icons.hourglass_empty),
    StatutSession.partiellementLivree => (Colors.blue, 'Partielle', Icons.local_shipping),
    StatutSession.touteLivree         => (Colors.green, 'Livrée ✓', Icons.check_circle),
    StatutSession.annulee             => (Colors.red, 'Annulée', Icons.cancel),
  };

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ─── Barre de progression par sous-commandes ─────────────────────────────────

class _BarreProgression extends StatelessWidget {
  final List<String> sousCommandeIds;
  const _BarreProgression({required this.sousCommandeIds});

  @override
  Widget build(BuildContext context) {
    // Barre simplifiée — couleur selon statut chargé
    return StreamBuilder<List<SousCommande>>(
      stream: Stream.fromFuture(Future.wait(
        sousCommandeIds.map((id) => SousCommande.collection.doc(id).get()
            .then((d) => SousCommande.fromDoc(d as DocumentSnapshot<Map<String, dynamic>>))),
      )),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 4);
        final scs = snap.data!;
        final total = scs.length;
        final terminees = scs.where((sc) => sc.estTerminee).length;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : terminees / total,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(terminees == total ? Colors.green : _kPrimary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text('$terminees/$total boutiques livrées',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]);
      },
    );
  }
}

// ─── Page de détail d'une session ─────────────────────────────────────────────

class DetailSessionPage extends StatefulWidget {
  final String sessionId;
  const DetailSessionPage({super.key, required this.sessionId});
  @override
  State<DetailSessionPage> createState() => _DetailSessionPageState();
}

class _DetailSessionPageState extends State<DetailSessionPage> {
  SessionCommande? _session;
  bool _chargement = true;

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    final session = await CommandeMultiService.chargerSession(widget.sessionId);
    if (mounted) setState(() { _session = session; _chargement = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Commande #${widget.sessionId.substring(0,6).toUpperCase()}'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _session == null
              ? const Center(child: Text('Commande introuvable'))
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      // Résumé session
                      _ResumePaiement(session: _session!),
                      const SizedBox(height: 16),
                      // Chaque sous-commande
                      ..._session!.sousCommandes.map((sc) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CarteSousCommande(
                          sc: sc,
                          onConfirmerReception: () => _confirmerReception(sc),
                        ),
                      )),
                    ],
                  ),
                ),
    );
  }

  Future<void> _confirmerReception(SousCommande sc) async {
    // ARCHI MODERNE : la réception se confirme quand LE LIVREUR scanne
    // le QR du client (preuve HMAC) — le client montre son code, il ne
    // « déclare » pas. Ce bouton ouvre donc SON code de remise.
    final ql = await FirebaseFirestore.instance
        .collection('livraisons')
        .where('commandeId', isEqualTo: sc.id)
        .limit(1)
        .get();
    if (!mounted) return;
    if (ql.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Livraison introuvable — réessayez dans un instant.')));
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CodeReceptionPage(
                  livraisonId: ql.docs.first.id,
                )));
  }

}

// ─── Résumé paiement de la session ───────────────────────────────────────────

class _ResumePaiement extends StatelessWidget {
  final SessionCommande session;
  const _ResumePaiement({required this.session});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kPrimary,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Récapitulatif', style: TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 8),
      _ligne('Articles', PrixFCFA.formater(session.totalArticles)),
      _ligne('Livraisons', PrixFCFA.formater(session.totalLivraisons)),
      const Divider(color: Colors.white24, height: 16),
      _ligne('Total payé', PrixFCFA.formater(session.totalPayeClient), bold: true),
      const SizedBox(height: 6),
      Row(children: [
        Icon(
          session.paiementConfirme ? Icons.check_circle : Icons.pending,
          color: session.paiementConfirme ? Colors.greenAccent : Colors.orangeAccent,
          size: 14,
        ),
        const SizedBox(width: 6),
        Text(
          session.paiementConfirme ? 'Paiement confirmé' : 'En attente de confirmation paiement',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ]),
    ]),
  );

  Widget _ligne(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(l, style: TextStyle(color: Colors.white70, fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
      Text(v, style: TextStyle(color: Colors.white, fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]),
  );
}

// ─── Carte d'une sous-commande ────────────────────────────────────────────────

class _CarteSousCommande extends StatelessWidget {
  final SousCommande sc;
  final VoidCallback onConfirmerReception;
  const _CarteSousCommande({required this.sc, required this.onConfirmerReception});

  @override
  Widget build(BuildContext context) {
    final (couleur, label) = _statutInfo(sc.statut);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête boutique
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: couleur.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Icon(Icons.store_outlined, size: 16, color: couleur),
            const SizedBox(width: 8),
            Expanded(child: Text(sc.boutiqueNom,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: couleur))),
            Text(quandFr(sc.dateCreation, prefixe: 'Commandée le '),
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: couleur.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        // Articles
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sc.articles.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    width: 52, height: 52,
                    child: item.pagneImage != null
                        ? ImageUniverselle(
                            source: item.pagneImage!, fit: BoxFit.cover)
                        : Container(
                            color: Colors.purple.shade50,
                            child: const Icon(Icons.checkroom,
                                size: 14, color: Colors.purple)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(child: Text('${item.pagneNom} × ${item.quantite}',
                    style: const TextStyle(fontSize: 13))),
                Text(PrixFCFA.formater(item.sousTotal),
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                if (item.avecCouture) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('✂️ couture', style: TextStyle(fontSize: 10, color: Colors.teal)),
                  ),
                ],
              ]),
            )).toList(),
          ),
        ),

        // Livraisons — condition par STATUT (sc.livraisons n'est jamais
        // chargée : l'ancien test cachait le bouton Suivre à jamais)
        if (sc.statut == StatutSousCommande.prete ||
            sc.statut == StatutSousCommande.enCoursLivraison ||
            sc.statut == StatutSousCommande.livree) ...[
          const Divider(height: 16, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _EtapesDepuisRacine(sousCommandeId: sc.id),
          ),
          // Bouton suivi GPS temps réel
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _suivreLivraison(context, sc.id),
                icon: const Icon(Icons.location_on_outlined, size: 18),
                label: const Text('Suivre ma livraison'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                ),
              ),
            ),
          ),
        ],

        // Total + action
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${PrixFCFA.formater(sc.sousTotal)} articles',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(PrixFCFA.formater(sc.totalClient),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 15)),
            ])),
            // AVIS : un vrai acheteur note son pagne (crédibilité du catalogue)
            if (sc.statut == StatutSousCommande.livree ||
                sc.statut == StatutSousCommande.terminee)
              IconButton(
                tooltip: 'Noter cet achat',
                icon: const Icon(Icons.star_border, color: Colors.amber),
                onPressed: () {
                  if (sc.articles.isEmpty) return;
                  final art = sc.articles.first;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom),
                      child: WidgetSoumettreAvis(
                        cible: CibleAvis.pagne,
                        cibleId: art.pagneId,
                        cibleNom: art.pagneNom,
                        auteurId:
                            FirebaseAuth.instance.currentUser?.uid ?? '',
                        auteurRole: 'client',
                        auteurNom: FirebaseAuth
                                .instance.currentUser?.displayName ??
                            'Client',
                        sousCommandeId: sc.id,
                        livraisonId: sc.livraisonId,
                      ),
                    ),
                  );
                },
              ),
            // RETOUR : possible après livraison (le moteur retours prend le relais)
            if (sc.statut == StatutSousCommande.livree ||
                sc.statut == StatutSousCommande.terminee)
              IconButton(
                tooltip: 'Demander un retour',
                icon: const Icon(Icons.assignment_return_outlined,
                    color: Colors.orange),
                onPressed: () async {
                  final motif = await showDialog<MotifRetour>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Motif du retour',
                          style: TextStyle(fontSize: 16)),
                      children: [
                        for (final (m, l) in [
                          (MotifRetour.pagneDefectueux, 'Article défectueux / non conforme'),
                          (MotifRetour.mauvaiseTaille, 'Mauvaise taille livrée'),
                          (MotifRetour.retardLivraison, 'Retard de livraison trop long'),
                          (MotifRetour.changementAvis, "J'ai changé d'avis"),
                        ])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, m),
                            child: Text(l, style: const TextStyle(fontSize: 13.5)),
                          ),
                      ],
                    ),
                  );
                  if (motif == null) return;
                  await RetoursService.initierRetourClient(
                    clientId: sc.clientId,
                    livraisonId: sc.livraisonId ?? '',
                    commandeId: sc.id,
                    boutiqueId: sc.boutiqueId,
                    pagneId: sc.articles.isNotEmpty
                        ? (sc.articles.first.pagneId)
                        : '',
                    motif: motif,
                    montantPaye: sc.totalClient,
                    fraisLivraisonPaye: 0,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Demande envoyée — un agent va analyser votre dossier'),
                        backgroundColor: Colors.orange));
                  }
                },
              ),
            // ADRESSE MODIFIABLE tant que le colis n'est pas en route.
            if (sc.statut == StatutSousCommande.enAttente ||
                sc.statut == StatutSousCommande.confirmeeBoutique ||
                sc.statut == StatutSousCommande.enPreparation ||
                sc.statut == StatutSousCommande.prete)
              IconButton(
                tooltip: "Modifier l'adresse de livraison",
                icon: const Icon(Icons.edit_location_alt_outlined,
                    color: Colors.teal),
                onPressed: () => _modifierAdresseSc(context, sc),
              ),
            // SUIVI : dès qu'une livraison existe, le client peut la suivre
            if (sc.livraisonId != null &&
                sc.statut != StatutSousCommande.livree &&
                sc.statut != StatutSousCommande.annulee)
              IconButton(
                tooltip: 'Suivre la livraison',
                icon: const Icon(Icons.local_shipping_outlined,
                    color: _kPrimary),
                onPressed: () async {
                  final d = await FirebaseFirestore.instance
                      .collection('livraisons')
                      .doc(sc.livraisonId!)
                      .get();
                  if (!context.mounted || !d.exists) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PageSuiviLivraison(
                          livraison: Livraison.fromFirebaseDocument(d)),
                    ),
                  );
                },
              ),
            if (sc.statut == StatutSousCommande.enCoursLivraison)
              ElevatedButton(
                onPressed: onConfirmerReception,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('📱 Mon code de réception', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }

  (Color, String) _statutInfo(StatutSousCommande s) => switch (s) {
    StatutSousCommande.enAttente          => (Colors.orange, 'En attente'),
    StatutSousCommande.confirmeeBoutique  => (Colors.blue, 'Confirmée'),
    StatutSousCommande.enPreparation      => (Colors.blue, 'En préparation'),
    StatutSousCommande.prete              => (Colors.indigo, 'Prête'),
    StatutSousCommande.enCoursLivraison   => (Colors.teal, 'En livraison'),
    StatutSousCommande.livree             => (Colors.green, 'Livrée'),
    StatutSousCommande.avecCouturier      => (Colors.teal, 'Chez couturier'),
    StatutSousCommande.costurierTermine   => (Colors.indigo, 'Couture terminée'),
    StatutSousCommande.terminee           => (Colors.green, '✓ Terminée'),
    StatutSousCommande.annulee            => (Colors.red, 'Annulée'),
    StatutSousCommande.litige             => (Colors.red, 'Litige'),
  };
}

// ─── Carte étape de livraison ─────────────────────────────────────────────────

/// Étapes de livraison lues depuis LA source : /livraisons (commandeId).
class _EtapesDepuisRacine extends StatelessWidget {
  final String sousCommandeId;
  const _EtapesDepuisRacine({required this.sousCommandeId});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('livraisons')
            .where('commandeId', isEqualTo: sousCommandeId)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const SizedBox(height: 4);
          final livs = docs.map((d) => d.data()).toList()
            ..sort((a, b) {
              final ta = (a['dateCreation'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              final tb = (b['dateCreation'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              return ta.compareTo(tb);
            });
          return Column(
            children: livs.asMap().entries.map((e) {
              final d = e.value;
              final st = d['statut'] as String? ?? '';
              final livree = st == 'livre' || st == 'livree';
              final type = d['typeLivraison'] as String? ?? '';
              final label = livs.length > 1
                  ? (e.key == 0 ? 'Tissu → atelier' : 'Livraison finale → client')
                  : (type == 'confection' ? 'Livraison du vêtement' : 'Livraison → client');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: livree ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(livree ? Icons.check : Icons.local_shipping_outlined,
                        size: 14, color: livree ? Colors.green : Colors.grey),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(d['destinationAdresse'] as String? ?? d['adresseArrivee'] as String? ?? '',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  if (livree)
                    const Text('✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                  else
                    Text(_libelleStatutLivraison(st),
                        style: const TextStyle(fontSize: 11, color: _kAccent)),
                ]),
              );
            }).toList(),
          );
        },
      );

  static String _libelleStatutLivraison(String st) => switch (st) {
        'enAttente' || 'rechercheLibreur' => 'Recherche livreur',
        'livreurAssigne' || 'enRouteOrigine' => 'Livreur en route',
        'articleRecupere' || 'enLivraison' => 'En livraison',
        'pretRetrait' => 'Prêt au retrait',
        'echec' => 'Échec',
        'annule' || 'annulee' => 'Annulée',
        _ => 'En cours',
      };
}

// Charge la Livraison liée à une sous-commande et ouvre la carte de suivi
Future<void> _suivreLivraison(BuildContext context, String sousCommandeId) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('livraisons')
        .where('commandeId', isEqualTo: sousCommandeId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Livraison pas encore disponible'),
        ));
      }
      return;
    }
    final livraison = Livraison.fromFirebaseDocument(snap.docs.first);
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PageSuiviLivraison(livraison: livraison),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur de chargement du suivi'),
      ));
    }
  }
}

Future<void> _modifierAdresseSc(BuildContext context, SousCommande sc) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nouvelle adresse de livraison'),
      content: TextField(
        controller: ctrl,
        maxLines: 2,
        decoration: const InputDecoration(
            hintText: 'Quartier, repère, précisions…',
            border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mettre à jour')),
      ],
    ),
  );
  if (ok != true || ctrl.text.trim().length < 5) return;
  final adresse = ctrl.text.trim();
  // Livraisons de cette sous-commande PAS ENCORE récupérées :
  final livs = await FirebaseFirestore.instance
      .collection('livraisons')
      .where('commandeId', isEqualTo: sc.id)
      .get();
  var maj = 0;
  for (final l in livs.docs) {
    final st = l.data()['statut'] as String? ?? '';
    if (['recuperee', 'enRoute', 'livree'].contains(st)) continue;
    await l.reference.update({
      'adresseArrivee': adresse,
      'adresseModifieeLe': FieldValue.serverTimestamp(),
    });
    maj++;
    final livreurId = l.data()['livreurId'] as String?;
    if (livreurId != null && livreurId.isNotEmpty) {
      await NotificationService.envoyer(
        destinataireId: livreurId,
        titre: 'Adresse modifiée 📍',
        message: 'Nouvelle destination : ' + adresse,
        route: '/mes-livraisons',
      );
    }
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(maj > 0
        ? 'Adresse mise à jour ✅ (le livreur est prévenu)'
        : 'Trop tard : le colis est déjà en route — contactez le livreur.'),
    backgroundColor: maj > 0 ? Colors.green : Colors.orange,
  ));
}

