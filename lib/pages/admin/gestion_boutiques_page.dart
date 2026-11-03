import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/boutique.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Page admin : gérer le modèle de facturation des boutiques et accorder
/// des périodes gratuites (franchise) pour attirer de nouvelles boutiques.
class GestionBoutiquesPage extends StatefulWidget {
  const GestionBoutiquesPage({super.key});

  @override
  State<GestionBoutiquesPage> createState() => _GestionBoutiquesPageState();
}

class _GestionBoutiquesPageState extends State<GestionBoutiquesPage>
    with PageProtegee {
  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.peut(u, 'boutiques')) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Gestion des boutiques'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Gestion des boutiques'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('boutiques')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final boutiques = snap.data!.docs
                  .map((d) => Boutique.fromFirebaseDocument(d))
                  .toList();
              if (boutiques.isEmpty) {
                return const Center(child: Text('Aucune boutique'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: boutiques.length,
                itemBuilder: (_, i) => _carteBoutique(boutiques[i]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _carteBoutique(Boutique b) {
    final gratuitActif = b.franchiseGratuiteJusqu != null &&
        b.franchiseGratuiteJusqu!.isAfter(DateTime.now());
    final estPrepaye = b.billingModel == 'prepaid';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ImageUniverselle(
                    source: b.logo.isNotEmpty ? b.logo : null,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.nom,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(b.quartier ?? b.ville ?? 'Garoua',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Text('${b.creditBalance.toStringAsFixed(0)} F',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: b.creditBalance < 0
                            ? Colors.red
                            : Colors.green.shade700)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _puce(
                    estPrepaye ? 'Prépayé' : 'Commission/vente',
                    estPrepaye ? Colors.deepPurple : Colors.blueGrey),
                if (gratuitActif)
                  _puce(
                      'Gratuit jusqu\'au ${_fmtDate(b.franchiseGratuiteJusqu!)}',
                      Colors.green),
                _puce(b.estActif ? 'Active' : 'Inactive',
                    b.estActif ? Colors.teal : Colors.grey),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _basculerMode(b),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: Text(estPrepaye ? '→ Commission' : '→ Prépayé',
                        style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimary,
                        side: const BorderSide(color: _kPrimary)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _accorderGratuite(b),
                    icon: const Icon(Icons.card_giftcard, size: 16),
                    label: const Text('Période gratuite',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _puce(String texte, Color couleur) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: couleur.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6)),
        child: Text(texte,
            style: TextStyle(
                color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _basculerMode(Boutique b) async {
    final nouveau = b.billingModel == 'prepaid' ? 'per_commission' : 'prepaid';
    await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(b.id)
        .update({'billingModel': nouveau});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nouveau == 'prepaid'
            ? 'Boutique passée en mode prépayé'
            : 'Boutique passée en commission-sur-vente'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _accorderGratuite(Boutique b) async {
    int jours = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Période gratuite — ${b.nom}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Pendant cette période : aucune commission, publication libre.',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Text('Durée : $jours jours',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: jours.toDouble(),
                min: 7,
                max: 180,
                divisions: 173,
                activeColor: _kPrimary,
                label: '$jours jours',
                onChanged: (v) => setLocal(() => jours = v.round()),
              ),
              Wrap(
                spacing: 6,
                children: [7, 30, 60, 90].map((j) {
                  return ActionChip(
                    label: Text('$j j'),
                    onPressed: () => setLocal(() => jours = j),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accorder'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final jusqu = DateTime.now().add(Duration(days: jours));
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(b.id)
          .update({'franchiseGratuiteJusqu': Timestamp.fromDate(jusqu)});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Période gratuite de $jours jours accordée'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }
}
