import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/pages/addboutique.dart';
import 'package:sami/pages/editboutique.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);

class BoutiqueListPage extends StatefulWidget {
  const BoutiqueListPage({super.key});
  @override
  State<BoutiqueListPage> createState() => _BoutiqueListPageState();
}

class _BoutiqueListPageState extends State<BoutiqueListPage> with PageProtegee {
  @override
  void initState() { super.initState(); chargerUtilisateur(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) => Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Boutiques'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (Droits.estAdmin(u))
            IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
        ],
      ),
      floatingActionButton: Droits.fab(
        condition: Droits.peutAjouterBoutique(u),
        tooltip: 'Ajouter une boutique',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBoutiquePage())),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('boutiques')
            .where('estActif', isEqualTo: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return _buildVide(u);
          final boutiques = snap.data!.docs.map(Boutique.fromFirebaseDocument).toList();
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: boutiques.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CarteBoutique(
              boutique: boutiques[i],
              utilisateur: u,
              onModifier: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditBoutiquePage(boutique: boutiques[i]))),
              onSupprimer: () => _supprimer(boutiques[i], u),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildVide(Utilisateur u) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      const Text('Aucune boutique', style: TextStyle(color: Colors.grey, fontSize: 16)),
      if (Droits.peutAjouterBoutique(u)) ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBoutiquePage())),
          icon: const Icon(Icons.add), label: const Text('Ajouter la première boutique'),
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
        ),
      ],
    ]),
  );

  Future<void> _supprimer(Boutique b, Utilisateur u) async {
    if (!Droits.peutSupprimerBoutique(u)) { Droits.accesRefuse(context); return; }
    final ok = await Droits.confirmerSuppression(context, nom: b.nom,
        message: 'La boutique et tous ses pagnes seront désactivés.');
    if (!ok) return;
    await Boutique.boutiqueCollection.doc(b.id).update({'estActif': false});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${b.nom}" désactivée'), backgroundColor: Colors.orange));
  }
}

class _CarteBoutique extends StatelessWidget {
  final Boutique boutique;
  final Utilisateur utilisateur;
  final VoidCallback onModifier;
  final VoidCallback onSupprimer;

  const _CarteBoutique({required this.boutique, required this.utilisateur,
    required this.onModifier, required this.onSupprimer});

  @override
  Widget build(BuildContext context) {
    final peutModifier = Droits.peutModifierBoutique(utilisateur, boutique.gerants);
    final peutSupprimer = Droits.peutSupprimerBoutique(utilisateur);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 52, height: 52,
            child: boutique.logo.isNotEmpty
                ? ImageUniverselle(source: boutique.logo, fit: BoxFit.cover)
                : _iconPlaceholder(),
          ),
        ),
        title: Text(boutique.nom, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(boutique.adresse, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: boutique.methodesPaiement
              .map((m) => _Chip(m)).toList()),
        ]),
        trailing: peutModifier || peutSupprimer ? PopupMenuButton<String>(
          onSelected: (v) { if (v == 'edit') onModifier(); else onSupprimer(); },
          itemBuilder: (_) => [
            if (peutModifier) const PopupMenuItem(value: 'edit', child: Row(children: [
              Icon(Icons.edit_outlined, size: 16, color: Color(0xFF6A1B9A)), SizedBox(width: 8), Text('Modifier')])),
            if (peutSupprimer) const PopupMenuItem(value: 'del', child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Désactiver', style: TextStyle(color: Colors.red))])),
          ],
        ) : null,
        onTap: () {},
      ),
    );
  }

  Widget _iconPlaceholder() => Container(color: Colors.purple.shade50,
      child: const Icon(Icons.store, color: _kPrimary, size: 28));
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  );
}
