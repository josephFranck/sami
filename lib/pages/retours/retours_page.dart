import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/retour.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

class RetoursPage extends StatefulWidget {
  const RetoursPage({super.key});
  @override
  State<RetoursPage> createState() => _RetoursPageState();
}

class _RetoursPageState extends State<RetoursPage> with PageProtegee {
  @override
  void initState() { super.initState(); chargerUtilisateur(); }

  @override
  Widget build(BuildContext context) => buildAvecDroits(
    builder: (u) => Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text(Tr.s.retoursLitiges),
          backgroundColor: _kPrimary, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('retours')
            .where(Droits.estAdmin(u) ? 'statut' : 'clientId',
                   isEqualTo: Droits.estAdmin(u) ? null : u.id)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator(color: _kPrimary));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return Center(child: Text(Tr.s.aucunRetour, style: TextStyle(color: Colors.grey)));
          final retours = snap.data!.docs.map(DossierRetour.fromFirebaseDocument).toList();
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: retours.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CarteRetour(retour: retours[i], estAdmin: Droits.estAdmin(u)),
          );
        },
      ),
    ),
  );
}

class _CarteRetour extends StatelessWidget {
  final DossierRetour retour;
  final bool estAdmin;
  const _CarteRetour({required this.retour, required this.estAdmin});

  @override
  Widget build(BuildContext context) {
    final (couleur, label) = switch (retour.statut) {
      StatutRetour.soumis        => (Colors.orange, 'Soumis'),
      StatutRetour.enExamen      => (Colors.blue, 'En examen'),
      StatutRetour.accepte       => (Colors.green, 'Accepté'),
      StatutRetour.rejete        => (Colors.red, 'Rejeté'),
      StatutRetour.enCoursDRetour => (Colors.indigo, 'Retour en cours'),
      StatutRetour.articleRecu   => (Colors.teal, 'Article reçu'),
      StatutRetour.rembourse     => (Colors.teal, 'Remboursé'),
      StatutRetour.clos          => (Colors.grey, 'Clos'),
    };
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(Tr.s.retour(retour.id.substring(0, 6).toUpperCase()),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: couleur.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        Text(Tr.s.motif(_motifLabel(retour.motif)),
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
        Text(Tr.s.montant(PrixFCFA.formater(retour.montantRemboursable)),
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(retour.preuve?.description ?? '',
            style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (estAdmin && retour.statut == StatutRetour.soumis) ...[
          const SizedBox(height: 10),
          Row(children: [
            ElevatedButton(onPressed: () => _approuver(context, retour),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white,
                  minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text(Tr.s.approuver, style: TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _rejeter(context, retour),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text(Tr.s.rejeter, style: TextStyle(fontSize: 12))),
          ]),
        ],
      ])),
    );
  }

  String _motifLabel(MotifRetour m) => switch (m) {
    MotifRetour.changementAvis   => Tr.s.changementAvis,
    MotifRetour.mauvaiseTaille   => Tr.s.mauvaiseTaille,
    MotifRetour.pagneDefectueux  => Tr.s.pagneDefectueux,
    MotifRetour.retardLivraison  => Tr.s.retardLivraison,
    _                            => m.name,
  };

  Future<void> _approuver(BuildContext ctx, DossierRetour r) async {
    await FirebaseFirestore.instance.collection('retours').doc(r.id)
        .update({'statut': StatutRetour.accepte.name});
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(Tr.s.retourApprouve), backgroundColor: Colors.green));
  }

  Future<void> _rejeter(BuildContext ctx, DossierRetour r) async {
    await FirebaseFirestore.instance.collection('retours').doc(r.id)
        .update({'statut': StatutRetour.rejete.name});
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(Tr.s.retourRejete), backgroundColor: Colors.red));
  }
}
