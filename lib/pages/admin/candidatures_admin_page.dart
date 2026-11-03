import 'package:flutter/material.dart';
import 'package:sami/services/candidature_service.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/widgets/image_universelle.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Admin : candidatures partenaires en attente. La validation change le rôle
/// de l'utilisateur ET crée automatiquement sa fiche métier.
class CandidaturesAdminPage extends StatefulWidget {
  const CandidaturesAdminPage({super.key});

  @override
  State<CandidaturesAdminPage> createState() => _CandidaturesAdminPageState();
}

class _CandidaturesAdminPageState extends State<CandidaturesAdminPage>
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
        if (!Droits.peut(u, 'candidatures')) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Candidatures'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Candidatures partenaires'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<List<Candidature>>(
            stream: CandidatureService.streamEnAttente(),
            builder: (context, snap) {
              if (snap.hasError) {
                // Erreur VISIBLE (règles, réseau…) plutôt qu'une liste vide muette
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'Impossible de charger les candidatures :\n${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.how_to_reg_outlined,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('Aucune candidature en attente',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) => _carte(list[i]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _carte(Candidature c) {
    final (icone, label) = switch (c.type) {
      'boutiquier' => (Icons.storefront, 'Boutiquier'),
      'couturier' => (Icons.content_cut, 'Couturier'),
      _ => (Icons.delivery_dining, 'Livreur'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icone, color: _kPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              if (c.dateDepot != null)
                Text(
                    '${c.dateDepot!.day}/${c.dateDepot!.month}/${c.dateDepot!.year}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 10),
            // PIÈCE D'IDENTITÉ (vérification visuelle par l'admin)
            if (c.infos['pieceIdentite'] != null) ...[
              const Text('Pièce d\'identité :',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageUniverselle(
                  source: c.infos['pieceIdentite'] as String? ?? '',
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (c.infos['latitude'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.place, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  const Text('Position GPS capturée sur place ✓',
                      style: TextStyle(fontSize: 12, color: Colors.green)),
                ]),
              ),
            // Les infos du dossier (texte)
            ...c.infos.entries
                .where((e) => !['pieceIdentite', 'latitude', 'longitude']
                    .contains(e.key))
                .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 110,
                          child: Text(_champLabel(e.key),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600))),
                      Expanded(
                          child: Text('${e.value}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500))),
                    ],
                  ),
                )),
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _refuser(c),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red)),
                  child: const Text('Refuser'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _valider(c),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  child: const Text('Valider'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _valider(Candidature c) async {
    try {
      await CandidatureService.valider(c);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Candidature validée — compte partenaire activé'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _refuser(Candidature c) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser la candidature'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Motif (optionnel)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CandidatureService.refuser(c, motif: ctrl.text.trim());
    }
  }

  String _champLabel(String k) => switch (k) {
        'nomBoutique' => 'Boutique',
        'quartier' => 'Quartier',
        'telephone' => 'Téléphone',
        'description' => 'Description',
        'nom' => 'Nom',
        'prenom' => 'Prénom',
        'numeroCNI' => 'CNI',
        'typeVehicule' => 'Véhicule',
        _ => k,
      };
}
