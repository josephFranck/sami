import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sami/services/recu_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// MES REÇUS : chaque vente complétée, confection livrée et paiement reçu
/// génère un reçu numéroté et signé — imprimable (capture/partage) et
/// vérifiable par scan « pour servir ce que de droit ».
class MesRecusPage extends StatelessWidget {
  const MesRecusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: Text(Tr.s.mesRecus),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Tr.s.verifierRecuScan,
            icon: const Icon(Icons.verified_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VerifierRecuPage())),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: RecuService.mesRecus(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final recus = snap.data!;
          if (recus.isEmpty) {
            return Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  Tr.s.aucunRecuPourMomentIls,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: recus.length,
            itemBuilder: (_, i) {
              final r = recus[i];
              final (ic, lb) = switch (r['type']) {
                'vente' => (Icons.shopping_bag_outlined, 'Vente'),
                'couture' => (Icons.content_cut, 'Confection'),
                _ => (Icons.payments_outlined, 'Paiement reçu'),
              };
              return Card(
                child: ListTile(
                  leading: Icon(ic, color: _kPrimary),
                  title: Text(r['numero'] as String? ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(
                      '$lb · ${(r['dateISO'] as String? ?? '').split('T').first}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                      PrixFCFA.formater((r['montant'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(
                          color: _kPrimary, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => RecuPage(recu: r))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// LE REÇU imprimable : en-tête, parties, montant, mention légale et QR signé.
class RecuPage extends StatelessWidget {
  final Map<String, dynamic> recu;
  const RecuPage({super.key, required this.recu});

  @override
  Widget build(BuildContext context) {
    final r = recu;
    final montant = PrixFCFA.formater((r['montant'] as num?)?.toDouble() ?? 0);
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: Text(Tr.s.recu),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Tr.s.partager,
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share(
                'REÇU ${r['numero']}\n${r['detail']}\nMontant : $montant\n'
                'Bénéficiaire : ${r['beneficiaireNom']}\nDate : '
                '${(r['dateISO'] as String? ?? '').split('T').first}\n'
                'Authentifié SAMI — vérifiable par scan du QR.'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 12)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('SAMI',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: _kPrimary)),
                  const Spacer(),
                  Text(Tr.s.recu2,
                      style: TextStyle(
                          fontSize: 16,
                          letterSpacing: 3,
                          color: Colors.grey.shade600)),
                ]),
                const Divider(height: 24),
                _l(Tr.s.n, r['numero'] as String? ?? ''),
                _l(Tr.s.date, (r['dateISO'] as String? ?? '').replaceFirst('T', '  ').split('.').first),
                _l(Tr.s.beneficiaire, r['beneficiaireNom'] as String? ?? ''),
                _l(Tr.s.emetteur, r['contrepartie'] as String? ?? 'SAMI'),
                _l(Tr.s.objet, r['detail'] as String? ?? ''),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: _kPrimary.withOpacity(0.07),
                  child: Row(children: [
                    const Text('MONTANT',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(montant,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _kPrimary)),
                  ]),
                ),
                const SizedBox(height: 18),
                Center(
                  child: QrImageView(
                      data: RecuService.qrDeRecu(r),
                      size: 150,
                      backgroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                      Tr.s.recuElectroniqueSigneHmacSha256,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _l(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 95,
              child: Text(a,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(
              child: Text(b,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// VÉRIFICATEUR : scanne le QR d'un reçu → AUTHENTIQUE ou FALSIFIÉ.
class VerifierRecuPage extends StatefulWidget {
  const VerifierRecuPage({super.key});
  @override
  State<VerifierRecuPage> createState() => _VerifierRecuPageState();
}

class _VerifierRecuPageState extends State<VerifierRecuPage> {
  bool _traite = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(Tr.s.verifierRecu),
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white),
      body: MobileScanner(onDetect: (cap) async {
        if (_traite) return;
        final code = cap.barcodes.firstOrNull?.rawValue;
        if (code == null) return;
        _traite = true;
        final (ok, contenu) = await RecuService.verifier(code);
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(ok ? Icons.verified : Icons.gpp_bad,
                color: ok ? Colors.green : Colors.red, size: 42),
            title: Text(ok ? Tr.s.recuAuthentique : Tr.s.recuNonValide,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ok ? Colors.green : Colors.red, fontSize: 16)),
            content: Text(
                ok
                    ? Tr.s.montantBeneficiaire(contenu?['numero'], contenu?['detail'], PrixFCFA.formater((contenu?['montant'] as num?)?.toDouble() ?? 0), contenu?['beneficiaireNom'])
                    : Tr.s.signatureNeCorrespondPasCe,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _traite = false;
                  },
                  child: Text(Tr.s.scannerAutre)),
              ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: Text(Tr.s.fermer)),
            ],
          ),
        );
      }),
    );
  }
}
