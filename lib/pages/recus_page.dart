import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sami/services/recu_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

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
        title: const Text('Mes reçus'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Vérifier un reçu (scan)',
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
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Aucun reçu pour le moment.\nIls apparaissent après une '
                  'vente complétée, une couture livrée ou un paiement reçu.',
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
        title: const Text('Reçu'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Partager',
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
                  Text('REÇU',
                      style: TextStyle(
                          fontSize: 16,
                          letterSpacing: 3,
                          color: Colors.grey.shade600)),
                ]),
                const Divider(height: 24),
                _l('N°', r['numero'] as String? ?? ''),
                _l('Date', (r['dateISO'] as String? ?? '').replaceFirst('T', '  ').split('.').first),
                _l('Bénéficiaire', r['beneficiaireNom'] as String? ?? ''),
                _l('Émetteur', r['contrepartie'] as String? ?? 'SAMI'),
                _l('Objet', r['detail'] as String? ?? ''),
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
                      'Reçu électronique signé (HMAC-SHA256).\n'
                      'Toute modification invalide la signature — '
                      'authenticité vérifiable par scan dans l\'app SAMI.\n'
                      'Pour servir et valoir ce que de droit.',
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
          title: const Text('Vérifier un reçu'),
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
            title: Text(ok ? 'REÇU AUTHENTIQUE' : 'REÇU NON VALIDE',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ok ? Colors.green : Colors.red, fontSize: 16)),
            content: Text(
                ok
                    ? '${contenu?['numero']}\n${contenu?['detail']}\n'
                        'Montant : ${PrixFCFA.formater((contenu?['montant'] as num?)?.toDouble() ?? 0)}\n'
                        'Bénéficiaire : ${contenu?['beneficiaireNom']}'
                    : 'La signature ne correspond pas : ce reçu a été modifié '
                        'ou ne provient pas de SAMI.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _traite = false;
                  },
                  child: const Text('Scanner un autre')),
              ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: const Text('Fermer')),
            ],
          ),
        );
      }),
    );
  }
}
