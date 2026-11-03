import 'package:flutter/material.dart';
import 'package:sami/models/avis.dart';
import 'package:sami/widgets/widgets_notation.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/services/couture_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/services/message_service.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/services/recu_service.dart';
import 'package:sami/pages/recus_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Commandes de couture du client : suivi des statuts et acceptation des devis
/// proposés par les couturiers (modèles sur devis).
class MesCoutureClientPage extends StatelessWidget {
  const MesCoutureClientPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(Tr.s.mesCoutures),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<CommandeCouturier>>(
        stream: CoutureService.streamCommandesClient(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final commandes = snap.data!;
          if (commandes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.content_cut,
                      size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(Tr.s.aucuneCommandeCouture,
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: commandes.length,
            itemBuilder: (_, i) => _carte(context, commandes[i]),
          );
        },
      ),
    );
  }

  Widget _carte(BuildContext context, CommandeCouturier cmd) {
    final (couleur, label) = _statutInfo(cmd.statut);
    final devisEnAttente = cmd.statut == StatutCommandeCouturier.devisPropose;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: couleur.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      style: TextStyle(
                          color: couleur,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Text(PrixFCFA.formater(cmd.prixConvenu),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _kPrimary)),
              ],
            ),
            const SizedBox(height: 10),
            if (cmd.statut == StatutCommandeCouturier.livree ||
                cmd.statut == StatutCommandeCouturier.terminee)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom),
                      child: WidgetSoumettreAvis(
                        cible: CibleAvis.couturier,
                        cibleId: cmd.couturierId,
                        cibleNom: 'ce couturier',
                        auteurId: FirebaseAuth.instance.currentUser?.uid ?? '',
                        auteurRole: 'client',
                        auteurNom: FirebaseAuth
                                .instance.currentUser?.displayName ??
                            Tr.s.client,
                        livraisonId: cmd.livraisonRetourId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.star_border,
                      size: 15, color: Colors.amber),
                  label: Text(Tr.s.noterCouturier,
                      style: TextStyle(fontSize: 12)),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.amber),
                ),
              ),
            if (cmd.statut == StatutCommandeCouturier.livree ||
                cmd.statut == StatutCommandeCouturier.terminee)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final recu = await RecuService.creer(
                      type: 'couture', refId: cmd.id,
                      beneficiaireId: uid,
                      beneficiaireNom: 'Client',
                      montant: cmd.prixConvenu + cmd.prixPagne,
                      detail: 'Confection livrée (pagne ${PrixFCFA.formater(cmd.prixPagne)} + couture ${PrixFCFA.formater(cmd.prixConvenu)})',
                    );
                    if (!context.mounted) return;
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => RecuPage(recu: recu)));
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                  label: Text(Tr.s.recuAuthentifie,
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final q = await FirebaseFirestore.instance
                      .collection('couturiers')
                      .where('utilisateurId', isEqualTo: cmd.couturierId)
                      .limit(1).get();
                  final d = q.docs.isNotEmpty ? q.docs.first.data() : null;
                  if (!context.mounted) return;
                  MessageService.contacter(context,
                      autreUserId: cmd.couturierId,
                      autreNom: d != null
                          ? '${d['prenom'] ?? ''} ${d['nom'] ?? 'Couturier'}'.trim()
                          : Tr.s.couturier,
                      contexte: 'Commande couture',
                      contexteId: cmd.id);
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: Text(Tr.s.ecrireCouturier,
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
              ),
            ),

            // PHOTO DU VÊTEMENT FINI (validation qualité avant livraison)
            if (cmd.statut == StatutCommandeCouturier.preteLivraison)
              FutureBuilder(
                future: CommandeCouturier.collection.doc(cmd.id).get(),
                builder: (context, s) {
                  final url = (s.data?.data() as Map<String, dynamic>?)?['photoFinale'] as String?;
                  if (url == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Tr.s.votreVetementEstPret,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ImageUniverselle(
                              source: url,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // Devis proposé : à accepter ou refuser
            if (cmd.statut == StatutCommandeCouturier.devisPropose)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(Tr.s.contreProposition),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: Tr.s.votrePrixFcfa,
                              border: OutlineInputBorder(), isDense: true),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Tr.s.annuler)),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Tr.s.envoyer)),
                        ],
                      ),
                    );
                    final montant = double.tryParse(ctrl.text);
                    if (ok == true && montant != null && montant > 0) {
                      // Repasse en attente : le couturier peut re-proposer
                      await CommandeCouturier.collection.doc(cmd.id).update({
                        'contrePropositionClient': montant,
                        'statut': StatutCommandeCouturier.enAttente.name,
                      });
                      // Le couturier doit le SAVOIR, pas le découvrir
                      await NotificationService.envoyer(
                        destinataireId: cmd.couturierId,
                        titre: (Tr t) => t.contrePropositionRecue,
                        message:
                            (Tr t) => t.clientProposeVousPouvezAccepter(PrixFCFA.formater(montant)),
                        route: '/dashboard_couturier',
                        refId: cmd.id,
                      );
                    }
                  },
                  icon: const Icon(Icons.gavel_outlined, size: 15),
                  label: Text(Tr.s.contreProposer, style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                ),
              ),
            if (devisEnAttente) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Tr.s.couturierProposePrix,
                        style: TextStyle(fontSize: 12, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(PrixFCFA.formater(cmd.prixPropose ?? 0),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _refuser(context, cmd),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red)),
                      child: Text(Tr.s.refuser),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _accepter(context, cmd),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                      child: Text(Tr.s.accepter),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _accepter(BuildContext ctx, CommandeCouturier cmd) async {
    await CoutureService.accepterDevis(cmd.id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(Tr.s.devisAccepteConfectionPeutCommencer),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _refuser(BuildContext ctx, CommandeCouturier cmd) async {
    await CoutureService.refuserDevis(cmd.id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(Tr.s.devisRefuseCommandeAnnulee),
        backgroundColor: Colors.orange,
      ));
    }
  }

  (Color, String) _statutInfo(StatutCommandeCouturier s) => switch (s) {
        StatutCommandeCouturier.enAttente => (Colors.orange, 'En attente'),
        StatutCommandeCouturier.devisPropose =>
          (Colors.deepOrange, 'Devis à valider'),
        StatutCommandeCouturier.confirmeeCouturier =>
          (Colors.blue, 'Confirmée'),
        StatutCommandeCouturier.rdvPlanifie => (Colors.indigo, 'RDV planifié'),
        StatutCommandeCouturier.enConfection => (_kPrimary, 'En confection'),
        StatutCommandeCouturier.preteLivraison => (Colors.teal, 'Prête'),
        StatutCommandeCouturier.livree => (Colors.green, 'Livrée'),
        StatutCommandeCouturier.terminee => (Colors.green, 'Terminée'),
        StatutCommandeCouturier.annulee => (Colors.red, 'Annulée'),
        StatutCommandeCouturier.litige => (Colors.red, 'Litige'),
      };
}
