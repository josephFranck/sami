import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/livreur/ajout_livreur_page.dart';
import 'package:sami/models/livreur.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);

class LivreurListPage extends StatefulWidget {
  const LivreurListPage({super.key});
  @override
  State<LivreurListPage> createState() => _LivreurListPageState();
}

class _LivreurListPageState extends State<LivreurListPage> with PageProtegee {
  @override
  void initState() { super.initState(); chargerUtilisateur(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) {
      if (!Droits.peutVoirUtilisateurs(u)) {
        return Scaffold(appBar: AppBar(title: const Text('Livreurs'), backgroundColor: _kPrimary, foregroundColor: Colors.white),
          body: const Center(child: Text('Accès réservé aux administrateurs', style: TextStyle(color: Colors.grey))));
      }
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(title: const Text('Livreurs'), backgroundColor: _kPrimary, foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.person_add_outlined), tooltip: 'Ajouter un livreur',
              onPressed: () => _ajouterLivreur()),
          ]),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('livreurs').snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator(color: _kPrimary));
            if (!snap.hasData || snap.data!.docs.isEmpty)
              return const Center(child: Text('Aucun livreur enregistré', style: TextStyle(color: Colors.grey)));
            final livreurs = snap.data!.docs.map(Livreur.fromFirebaseDocument).toList();
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: livreurs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _CarteLivreur(livreur: livreurs[i],
                onToggleActif: () => _toggleActif(livreurs[i]),
                onSupprimer: () => _supprimer(livreurs[i]),
              ),
            );
          },
        ),
      );
    },
  );

  void _ajouterLivreur() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const AjoutLivreurPage(),
    ));
  }

  Future<void> _toggleActif(Livreur l) async {
    // Basculer le statut entre disponible et indisponible
    final estDispo = l.statut == StatutLivreur.disponible;
    await FirebaseFirestore.instance.collection('livreurs').doc(l.id)
        .set({'statut': estDispo
            ? StatutLivreur.inactif.name
            : StatutLivreur.disponible.name}, SetOptions(merge: true));
  }

  Future<void> _supprimer(Livreur l) async {
    final ok = await Droits.confirmerSuppression(context, nom: '${l.prenom} ${l.nom}');
    if (!ok) return;
    await FirebaseFirestore.instance.collection('livreurs').doc(l.id).delete();
  }
}

class _CarteLivreur extends StatelessWidget {
  final Livreur livreur;
  final VoidCallback onToggleActif;
  final VoidCallback onSupprimer;

  const _CarteLivreur({required this.livreur, required this.onToggleActif, required this.onSupprimer});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: livreur.statut == StatutLivreur.disponible ? Colors.green.shade50 : Colors.grey.shade100,
        child: Icon(Icons.delivery_dining,
            color: livreur.statut == StatutLivreur.disponible ? Colors.green : Colors.grey),
      ),
      title: Text(
          '${livreur.prenom} ${livreur.nom}'.trim().isEmpty
              ? 'Livreur (fiche à compléter)'
              : '${livreur.prenom} ${livreur.nom}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(livreur.telephone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (livreur.origine != null)
          Text(
              livreur.origine == 'admin'
                  ? '👤 Ajouté par l\'équipe'
                  : '📝 A candidaté',
              style: TextStyle(
                  fontSize: 10.5,
                  color: livreur.origine == 'admin'
                      ? Colors.blueGrey
                      : Colors.teal)),
        Row(children: [
          Icon(Icons.star, color: Colors.amber, size: 12),
          Text(' ${livreur.noteMoyenne.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 8),
          Text('${livreur.nombreLivraisons} livraisons',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Switch(value: livreur.statut == StatutLivreur.disponible, onChanged: (_) => onToggleActif(),
            activeColor: Colors.green, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
            onPressed: onSupprimer),
      ]),
    ),
  );
}
