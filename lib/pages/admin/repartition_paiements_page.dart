import 'package:flutter/material.dart';
import 'package:sami/services/reversement_service.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Page admin : voir la répartition de chaque paiement et reverser les parts.
class RepartitionPaiementsPage extends StatefulWidget {
  const RepartitionPaiementsPage({super.key});

  @override
  State<RepartitionPaiementsPage> createState() =>
      _RepartitionPaiementsPageState();
}

class _RepartitionPaiementsPageState extends State<RepartitionPaiementsPage>
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
        if (!Droits.estAdmin(u)) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Répartition des paiements'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Répartition des paiements'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<List<RepartitionPaiement>>(
            stream: ReversementService.streamARepartir(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final ventes = snap.data!;
              // Second flux : les CONFECTIONS (couture) à reverser
              return StreamBuilder<List<RepartitionCouture>>(
                stream: ReversementService.streamCouturesAReverser(),
                builder: (context, snapC) {
                  final coutures = snapC.data ?? [];
                  if (ventes.isEmpty && coutures.isEmpty) return _vide();
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ...ventes.map(
                          (r) => _CarteRepartition(repartition: r)),
                      if (coutures.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text('CONFECTIONS (couture)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _kPrimary)),
                        ),
                        ...coutures.map((r) => _CarteCouture(r: r)),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _vide() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Aucun paiement à répartir',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Les commandes terminées apparaîtront ici',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
}

class _CarteRepartition extends StatelessWidget {
  final RepartitionPaiement repartition;
  const _CarteRepartition({required this.repartition});

  @override
  Widget build(BuildContext context) {
    final r = repartition;
    final avecCouture = r.couturierId != null && (r.netCouturier ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Expanded(
                  child: Text(r.boutiqueNom,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text(PrixFCFA.formater(r.totalClient),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _kPrimary)),
              ],
            ),
            Text('Payé par le client', style: TextStyle(
                fontSize: 11, color: Colors.grey.shade600)),
            const Divider(height: 20),

            // Répartition
            _ligneRepartition(
              context,
              icone: Icons.store,
              label: 'Boutiquier',
              montant: r.netBoutique,
              reverse: r.boutiqueReversee,
              actif: r.boutiqueId != null && r.netBoutique > 0,
              onReverser: () => _reverser(context, r, Beneficiaire.boutique),
            ),
            _ligneRepartition(
              context,
              icone: Icons.delivery_dining,
              label: 'Livreur',
              montant: r.gainLivreur,
              reverse: r.livreurReverse,
              actif: r.livreurId != null && r.gainLivreur > 0,
              onReverser: () => _reverser(context, r, Beneficiaire.livreur),
            ),
            if (avecCouture)
              _ligneRepartition(
                context,
                icone: Icons.content_cut,
                label: 'Couturier',
                montant: r.netCouturier ?? 0,
                reverse: r.couturierReverse,
                actif: true,
                onReverser: () =>
                    _reverser(context, r, Beneficiaire.couturier),
              ),
            const Divider(height: 20),

            // Parts plateforme (revenus, pas de reversement)
            _ligneInfo('Commission plateforme', r.commissionPlateforme,
                Colors.green.shade700),
            _ligneInfo('Frais de livraison (brut)', r.fraisLivraison,
                Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _ligneRepartition(
    BuildContext context, {
    required IconData icone,
    required String label,
    required double montant,
    required bool reverse,
    required bool actif,
    required VoidCallback onReverser,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icone, size: 18, color: _kPrimary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(PrixFCFA.formater(montant),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (!actif)
            const SizedBox(
                width: 90,
                child: Text('—',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)))
          else if (reverse)
            Container(
              width: 90,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 13, color: Colors.green),
                  SizedBox(width: 3),
                  Text('Reversé',
                      style: TextStyle(color: Colors.green, fontSize: 11)),
                ],
              ),
            )
          else
            SizedBox(
              width: 90,
              height: 30,
              child: ElevatedButton(
                onPressed: onReverser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Reverser'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ligneInfo(String label, double montant, Color couleur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: couleur)),
          Text(PrixFCFA.formater(montant),
              style: TextStyle(
                  fontSize: 12, color: couleur, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _reverser(
      BuildContext context, RepartitionPaiement r, Beneficiaire b) async {
    final labels = {
      Beneficiaire.boutique: 'au boutiquier',
      Beneficiaire.livreur: 'au livreur',
      Beneficiaire.couturier: 'au couturier',
    };
    final montant = switch (b) {
      Beneficiaire.boutique => r.netBoutique,
      Beneficiaire.livreur => r.gainLivreur,
      Beneficiaire.couturier => r.netCouturier ?? 0,
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer le reversement'),
        content: Text(
            'Reverser ${PrixFCFA.formater(montant)} ${labels[b]} ?\n\n'
            'Cela crédite son solde dans l\'application.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final succes =
          await ReversementService.reverser(r: r, beneficiaire: b);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(succes
              ? 'Reversement effectué'
              : 'Échec du reversement'),
          backgroundColor: succes ? Colors.green : Colors.red,
        ));
      }
    }
  }
}

class _CarteCouture extends StatelessWidget {
  final RepartitionCouture r;
  const _CarteCouture({required this.r});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.content_cut, size: 18, color: _kPrimary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Confection ${r.commandeId.substring(0, r.commandeId.length.clamp(0, 8))}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13))),
            ]),
            const SizedBox(height: 10),
            // Part couturier
            Row(children: [
              Expanded(
                  child: Text(
                      'Couturier : ${PrixFCFA.formater(r.netCouturier)}',
                      style: const TextStyle(fontSize: 12))),
              r.couturierReverse
                  ? const Text('✓ Reversé',
                      style: TextStyle(color: Colors.green, fontSize: 12))
                  : ElevatedButton(
                      onPressed: () => ReversementService.reverserCouture(
                          r: r, beneficiaire: Beneficiaire.couturier),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 30),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12)),
                      child: const Text('Reverser',
                          style: TextStyle(fontSize: 11)),
                    ),
            ]),
            // Part boutique (pagne) si applicable
            if (r.netBoutique > 0) ...[
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(
                        'Boutique (pagne) : ${PrixFCFA.formater(r.netBoutique)}',
                        style: const TextStyle(fontSize: 12))),
                r.boutiqueReversee
                    ? const Text('✓ Reversé',
                        style: TextStyle(color: Colors.green, fontSize: 12))
                    : ElevatedButton(
                        onPressed: () => ReversementService.reverserCouture(
                            r: r, beneficiaire: Beneficiaire.boutique),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 30),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12)),
                        child: const Text('Reverser',
                            style: TextStyle(fontSize: 11)),
                      ),
              ]),
            ],
            const SizedBox(height: 4),
            Text(
                'Commission plateforme : ${PrixFCFA.formater(r.commissionPlateforme)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
