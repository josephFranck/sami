import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/services/promotions_service.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/pages/addpagne_v2.dart';
import 'package:sami/pages/addpagne_v2.dart';
import 'package:sami/services/stock_service.dart';
import 'package:sami/pages/pagnedetail.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/connectivity_widgets.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent = Color(0xFFFF8F00);

class PagneListPage extends StatefulWidget {
  /// Si fourni : gestion des pagnes de CETTE boutique uniquement
  /// (sinon : toutes les boutiques du gérant connecté).
  final String? boutiqueId;
  final String? boutiqueNom;
  const PagneListPage({super.key, this.boutiqueId, this.boutiqueNom});
  @override
  State<PagneListPage> createState() => _PagneListPageState();
}

class _PagneListPageState extends State<PagneListPage> with PageProtegee {
  // PÉRIMÈTRE : un gérant ne gère QUE les pagnes de SES boutiques.
  // (admin/staff : accès complet)
  List<String>? _idsMesBoutiques; // null = pas encore chargé OU accès complet
  bool _perimetreCharge = false;
  String _recherche = '';

  Future<void> _chargerPerimetre() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final me = await FirebaseFirestore.instance
        .collection('utilisateurs').doc(u.uid).get();
    final role = me.data()?['role'] as String?;
    if (role == 'admin' || role == 'agent') {
      setState(() => _perimetreCharge = true); // accès complet
      return;
    }
    final q = await FirebaseFirestore.instance
        .collection('boutiques')
        .where('gerants', arrayContains: u.uid)
        .get();
    if (!mounted) return;
    setState(() {
      _idsMesBoutiques = q.docs.map((d) => d.id).toList();
      _perimetreCharge = true;
    });
  }

  String? _categorieFiltre;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); chargerUtilisateur(); _chargerPerimetre(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) => Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.boutiqueNom != null ? 'Pagnes — ${widget.boutiqueNom}' : 'Pagnes'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: Droits.fab(
        condition: Droits.peutAjouterPagne(u),
        tooltip: 'Ajouter un pagne',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AddPagnePage())),
      ),
      body: Column(children: [
        // Bannière offline
        const BanniereConnectivite(),
        // Barre de recherche
        Padding(padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _recherche = v),
            decoration: InputDecoration(
              hintText: 'Rechercher un pagne...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _recherche.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _searchCtrl.clear(); setState(() => _recherche = ''); })
                  : null,
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
            ),
          ),
        ),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // GESTION : on voit AUSSI les pagnes désactivés (sinon impossible
          // de les réactiver) — le catalogue client, lui, reste filtré.
          // FILTRE SERVEUR : on ne lit QUE les pagnes du périmètre.
          // (avant : toute la collection → à 5 000 pagnes, 5 000 lectures
          // facturées à chaque ouverture !) Admin/staff : accès complet.
          stream: widget.boutiqueId != null
              ? FirebaseFirestore.instance
                  .collection('pagnes')
                  .where('boutiqueId', isEqualTo: widget.boutiqueId)
                  .snapshots()
              : (_idsMesBoutiques != null && _idsMesBoutiques!.isNotEmpty)
                  ? FirebaseFirestore.instance
                      .collection('pagnes')
                      .where('boutiqueId',
                          whereIn: _idsMesBoutiques!.take(10).toList())
                      .snapshots()
                  : FirebaseFirestore.instance
                      .collection('pagnes')
                      .snapshots(), // admin/staff uniquement
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator(color: _kPrimary));
            if (!snap.hasData || snap.data!.docs.isEmpty)
              return _buildVide(u);
            var pagnes = snap.data!.docs.map(Pagne.fromFirebaseDocument).toList();
            // Tri par date d'ajout décroissante (côté client → pas d'index requis)
            pagnes.sort((a, b) {
              final da = a.dateAjout, db = b.dateAjout;
              if (da != null && db != null) return db.compareTo(da);
              return 0;
            });
            // Filtrer par recherche
            if (_recherche.isNotEmpty) {
              final q = _recherche.toLowerCase();
              if (widget.boutiqueId != null) {
                // Vue MONO-boutique (ouverte depuis la fiche boutique)
                pagnes = pagnes
                    .where((p) => p.boutiqueId == widget.boutiqueId)
                    .toList();
              } else if (_idsMesBoutiques != null) {
                pagnes = pagnes
                    .where((p) => _idsMesBoutiques!.contains(p.boutiqueId))
                    .toList();
              }
              pagnes = pagnes.where((p) =>
                p.nom.toLowerCase().contains(q) ||
                p.matiere.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q)).toList();
            }
            if (pagnes.isEmpty)
              return const Center(child: Text('Aucun résultat', style: TextStyle(color: Colors.grey)));
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72),
              itemCount: pagnes.length,
              itemBuilder: (_, i) => _CartePagne(
                estGerant: widget.boutiqueId != null
                    ? true // vue mono-boutique : ouverte par un gérant vérifié
                    : (_idsMesBoutiques?.contains(pagnes[i].boutiqueId) ??
                        false),
                pagne: pagnes[i], utilisateur: u,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PagneDetailPage(pagne: pagnes[i]))),
                onModifier: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AddPagnePage(aModifier: pagnes[i]))),
                onSupprimer: () => _supprimer(pagnes[i], u),
              ),
            );
          },
        )),
      ]),
    ),
  );

  Widget _buildVide(utilisateur) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      const Text('Aucun pagne disponible', style: TextStyle(color: Colors.grey, fontSize: 16)),
      if (Droits.peutAjouterPagne(utilisateur)) ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddPagnePage())),
          icon: const Icon(Icons.add), label: const Text('Ajouter le premier pagne'),
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
        ),
      ],
    ]),
  );

  Future<void> _supprimer(Pagne p, u) async {
    final proprio = Droits.estAdmin(u) ||
        (_idsMesBoutiques?.contains(p.boutiqueId) ?? false);
    if (!proprio) { Droits.accesRefuse(context); return; }
    final ok = await Droits.confirmerSuppression(context, nom: p.nom,
        message: 'Le pagne sera masqué du catalogue.');
    if (!ok) return;
    await Pagne.pagneCollection.doc(p.id).update({'disponible': false});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${p.nom}" retiré du catalogue'), backgroundColor: Colors.orange));
  }
}

/// DÉFINITIF : autorisé seulement si AUCUNE commande ne référence ce pagne
/// (sinon l'historique/reçus pointeraient vers un fantôme). Les images
/// (base64 dans le document) partent avec lui.
/// PROMOTION : le boutiquier choisit le %, la durée — le service bloque
/// net si le prix passerait sous SON plancher, puis l'admin valide.
Future<void> _proposerPromotion(BuildContext context, dynamic pagne) async {
  double pct = 10;
  double heures = 48;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Promotion sur « ${pagne.nom} »'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Réduction'),
            Expanded(
              child: Slider(
                value: pct, min: 5, max: 50, divisions: 9,
                label: '-${pct.toStringAsFixed(0)} %',
                onChanged: (v) => setD(() => pct = v),
              ),
            ),
            Text('-${pct.toStringAsFixed(0)} %',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          Row(children: [
            const Text('Durée'),
            Expanded(
              child: Slider(
                value: heures, min: 6, max: 168, divisions: 27,
                label: heures >= 24
                    ? '${(heures / 24).round()} j'
                    : '${heures.round()} h',
                onChanged: (v) => setD(() => heures = v),
              ),
            ),
            Text(heures >= 24
                ? '${(heures / 24).round()} j'
                : '${heures.round()} h'),
          ]),
          Text(
              'Nouveau prix : ${PrixFCFA.formater(PrixFCFA.arrondirAu50(pagne.prixParBoutique * (1 - pct / 100)))}'
              '${pagne.prixPlancher != null ? '  (votre plancher : ${PrixFCFA.formater(pagne.prixPlancher)})' : '  (plancher auto : seuil de rentabilité)'}',
              style: const TextStyle(fontSize: 12.5)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proposer à l\'admin')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await PromotionsService.proposer(
      boutiqueId: pagne.boutiqueId ?? '',
      proposePar: FirebaseAuth.instance.currentUser?.uid ?? '',
      pagneIds: [pagne.id],
      reductionPct: pct,
      duree: Duration(hours: heures.round()),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Promotion proposée — en attente de validation admin'),
          backgroundColor: Colors.green));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8)));
    }
  }
}

Future<void> _supprimerDefinitivement(BuildContext context, dynamic pagne) async {
  final snap = await FirebaseFirestore.instance
      .collection('sous_commandes')
      .where('boutiqueId', isEqualTo: pagne.boutiqueId)
      .get();
  final commande = snap.docs.any((d) =>
      (d.data()['articles'] as List? ?? [])
          .any((a) => (a as Map)['pagneId'] == pagne.id));
  if (!context.mounted) return;
  if (commande) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Impossible : ce pagne a déjà été commandé (historique et reçus). Utilisez la désactivation.'),
        backgroundColor: Colors.red));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer définitivement ?'),
      content: Text(
          '« ${pagne.nom} » et ses images seront effacés pour toujours.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer')),
      ],
    ),
  );
  if (ok == true) {
    await FirebaseFirestore.instance
        .collection('pagnes').doc(pagne.id).delete();
  }
}

Future<void> _voirCommandesPagne(BuildContext context, dynamic pagne) async {
  final snap = await FirebaseFirestore.instance
      .collection('sous_commandes')
      .where('boutiqueId', isEqualTo: pagne.boutiqueId)
      .get();
  final lignes = <String>[];
  for (final d in snap.docs) {
    final arts = List<Map<String, dynamic>>.from(
        (d.data()['articles'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    for (final a in arts) {
      if (a['pagneId'] == pagne.id) {
        final t = (d.data()['dateCreation'] as Timestamp?)?.toDate();
        lignes.add(
            '${t != null ? "${t.day}/${t.month}/${t.year}" : "—"}  ·  x${a['quantite'] ?? 1}  ·  ${d.data()['statut'] ?? ''}');
      }
    }
  }
  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Commandes — ${pagne.nom}',
          style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: lignes.isEmpty
            ? const Text('Aucune commande pour ce pagne pour le moment.',
                style: TextStyle(color: Colors.grey))
            : ListView(
                shrinkWrap: true,
                children: lignes
                    .map((l) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child:
                              Text(l, style: const TextStyle(fontSize: 12.5)),
                        ))
                    .toList()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))
      ],
    ),
  );
}

class _CartePagne extends StatelessWidget {
  final Pagne pagne;
  final dynamic utilisateur;
  final VoidCallback onTap;
  final VoidCallback onModifier;
  final VoidCallback onSupprimer;

  final bool estGerant; // ce user gère-t-il LA boutique de ce pagne ?
  const _CartePagne({required this.pagne, required this.utilisateur, required this.estGerant,
    required this.onTap, required this.onModifier, required this.onSupprimer});

  void _dialogReappro(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Réapprovisionner « ${pagne.nom} »'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock actuel : ${pagne.quantiteDisponible} unité(s)',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Unités à ajouter',
                hintText: 'ex: 10',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () async {
              final ajout = int.tryParse(ctrl.text) ?? 0;
              if (ajout <= 0) return;
              final ok = await StockService.reapprovisionner(
                  pagneId: pagne.id, quantiteAjoutee: ajout);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? '+$ajout ajouté(s) — nouveau stock : ${pagne.quantiteDisponible + ajout}'
                      : 'Échec du réapprovisionnement'),
                  backgroundColor: ok ? Colors.green : Colors.red,
                ));
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Propriété RÉELLE : admin/staff, ou gérant de la boutique de CE pagne.
    final peutModifier = Droits.estAdmin(utilisateur) || estGerant;
    final peutSupprimer = peutModifier;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Stack(fit: StackFit.expand, children: [
              ImagesBalayables(
                  images: pagne.images,
                  fallback: Container(color: Colors.purple.shade50,
                      child: const Icon(Icons.shopping_bag,
                          color: _kPrimary, size: 40))),
              // Badge mention
              if (pagne.mention != Mention.aucun) Positioned(top: 6, left: 6,
                child: _BadgeMention(mention: pagne.mention.name)),
              // Menu actions (visible seulement si droits)
              if (peutModifier || peutSupprimer) Positioned(top: 4, right: 4,
                child: PopupMenuButton<String>(
                  icon: Container(padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.more_vert, color: Colors.white, size: 14)),
                  onSelected: (v) {
                if (v == 'reactiver') {
                  FirebaseFirestore.instance.collection('pagnes')
                      .doc(pagne.id).update({'disponible': true});
                  return;
                }
                if (v == 'promo') {
                  _proposerPromotion(context, pagne);
                  return;
                }
                if (v == 'delFor') {
                  _supprimerDefinitivement(context, pagne);
                  return;
                }
                if (v == 'commandes') {
                  _voirCommandesPagne(context, pagne);
                  return;
                } if (v == 'edit') onModifier(); else if (v == 'restock') _dialogReappro(context); else onSupprimer(); },
                  itemBuilder: (_) => [
                    if (!pagne.disponible)
                      const PopupMenuItem(value: 'reactiver', child: Row(children: [
                        Icon(Icons.visibility_outlined, size: 16, color: Colors.green), SizedBox(width: 8), Text('Réactiver (remettre en vente)')])),
                    const PopupMenuItem(value: 'promo', child: Row(children: [
                      Icon(Icons.local_offer, size: 16, color: Colors.deepOrange), SizedBox(width: 8), Text('Proposer une promotion')])),
                    const PopupMenuItem(value: 'delFor', child: Row(children: [
                      Icon(Icons.delete_forever, size: 16, color: Colors.red), SizedBox(width: 8), Text('Supprimer DÉFINITIVEMENT')])),
                    const PopupMenuItem(value: 'commandes', child: Row(children: [
                      Icon(Icons.receipt_long_outlined, size: 16, color: _kPrimary), SizedBox(width: 8), Text('Commandes de ce pagne')])),
                    if (peutModifier) const PopupMenuItem(value: 'edit', child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16, color: _kPrimary), SizedBox(width: 8), Text('Modifier')])),
                    if (peutModifier) const PopupMenuItem(value: 'restock', child: Row(children: [
                      Icon(Icons.add_box_outlined, size: 16, color: Colors.green), SizedBox(width: 8), Text('Réapprovisionner')])),
                    if (peutSupprimer) const PopupMenuItem(value: 'del', child: Row(children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8),
                      Text('Retirer', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ),
            ]),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pagne.disponible ? pagne.nom : '${pagne.nom}  ·  ⛔ Désactivé', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (pagne.matiere.isNotEmpty)
              Text(pagne.matiere, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(PrixFCFA.formater(pagne.prixParBoutique),
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13))),
              if (pagne.noteMoyenne > 0) Row(children: [
                const Icon(Icons.star, color: Colors.amber, size: 12),
                Text(pagne.noteMoyenne.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ]),
          ])),
        ]),
      ),
    );
  }
}

class _BadgeMention extends StatelessWidget {
  final String mention;
  const _BadgeMention({required this.mention});
  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (mention) {
      'coupDeCoeur'    => ('❤️', const Color(0xFFD4537E)),
      'meilleureVente' => ('🏆', const Color(0xFFBA7517)),
      'nouveaute'      => ('🆕', const Color(0xFF1D9E75)),
      'enPromotion'    => ('🏷️', const Color(0xFFD85A30)),
      'editionLimitee' => ('🔥', const Color(0xFFD85A30)),
      'premium'        => ('💎', const Color(0xFF534AB7)),
      _               => ('', Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}
