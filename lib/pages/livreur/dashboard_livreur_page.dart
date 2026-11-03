import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kP = Color(0xFF6A1B9A);

/// TABLEAU DE BORD LIVREUR — ses gains (jour / semaine / total),
/// ses courses, et l'historique de ce qu'il a livré.
class DashboardLivreurPage extends StatefulWidget {
  const DashboardLivreurPage({super.key});
  @override
  State<DashboardLivreurPage> createState() => _DashboardLivreurPageState();
}

class _DashboardLivreurPageState extends State<DashboardLivreurPage> {
  double _pct = 70; // part EFFECTIVE (base + fidélité + abonnement)
  String _detailPart = '';

  @override
  void initState() {
    super.initState();
    ParametresService.partLivreurEffective(
            FirebaseAuth.instance.currentUser?.uid)
        .then((r) {
      if (mounted) {
        setState(() {
          _pct = r.pct;
          _detailPart = r.bonusFidelite + r.bonusAbo > 0
              ? '(base ${r.base.toStringAsFixed(0)} + fidélité +${r.bonusFidelite.toStringAsFixed(0)} + abo +${r.bonusAbo.toStringAsFixed(0)})'
              : '';
        });
      }
    }).catchError((_) {});
  }

  double _gain(Map<String, dynamic> d, double pct) {
    final frais = (d['fraisLivraison'] as num?)?.toDouble() ??
        (d['montantCourse'] as num?)?.toDouble() ??
        0;
    return frais * pct / 100;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
          title: const Text('Mon tableau de bord'),
          backgroundColor: _kP,
          foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('livraisons')
            .where('livreurId', isEqualTo: uid)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Erreur : ${snap.error}',
                    style: const TextStyle(fontSize: 12)));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kP));
          }
          final docs = snap.data!.docs;
          final maintenant = DateTime.now();
          final debutJour =
              DateTime(maintenant.year, maintenant.month, maintenant.day);
          final debutSemaine =
              debutJour.subtract(Duration(days: maintenant.weekday - 1));

          double gJour = 0, gSemaine = 0, gTotal = 0;
          int nLivrees = 0, nEnCours = 0;
          final livrees = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (final doc in docs) {
            final d = doc.data();
            final st = d['statut'] as String? ?? '';
            if (['livree', 'livre'].contains(st)) {
              nLivrees++;
              livrees.add(doc);
              final g = _gain(d, _pct);
              gTotal += g;
              final quand = (d['dateLivraison'] as Timestamp?)?.toDate() ??
                  (d['dateCreation'] as Timestamp?)?.toDate();
              if (quand != null) {
                if (!quand.isBefore(debutJour)) gJour += g;
                if (!quand.isBefore(debutSemaine)) gSemaine += g;
              }
            } else if (!['annule', 'annulee'].contains(st)) {
              nEnCours++;
            }
          }
          livrees.sort((a, b) {
            final ta = (a.data()['dateLivraison'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final tb = (b.data()['dateLivraison'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return tb.compareTo(ta);
          });

          Widget carte(String v, String l, IconData i, Color c) =>
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(i, color: c, size: 20),
                        const SizedBox(height: 6),
                        Text(v,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        Text(l,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade600)),
                      ]),
                ),
              );

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── LE GAIN, en grand ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_kP, Color(0xFF8E24AA)]),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Aujourd'hui",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      Text(PrixFCFA.formater(gJour),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: Text(
                                'Semaine : ${PrixFCFA.formater(gSemaine)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5))),
                        Text('Total : ${PrixFCFA.formater(gTotal)}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Votre part : ${_pct.toStringAsFixed(0)} % des frais $_detailPart',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10.5)),
                    ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                carte('$nLivrees', 'Courses livrées',
                    Icons.check_circle_outline, Colors.green),
                const SizedBox(width: 10),
                carte('$nEnCours', 'En cours',
                    Icons.delivery_dining, Colors.orange),
              ]),
              const SizedBox(height: 18),
              const Text('  Dernières livraisons',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              if (livrees.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text(
                          'Aucune livraison terminée pour le moment.\nVos gains apparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey))),
                ),
              ...livrees.take(20).map((doc) {
                final d = doc.data();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Row(children: [
                    const Icon(Icons.route, color: _kP, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                d['adresseArrivee'] as String? ??
                                    d['destinationQuartier']
                                        as String? ??
                                    'Livraison',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                quandFr(d['dateLivraison'],
                                    prefixe: 'Livrée le '),
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade600)),
                          ]),
                    ),
                    Text('+${PrixFCFA.formater(_gain(d, _pct))}',
                        style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ]),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
