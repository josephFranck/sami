import 'package:flutter/material.dart';
import 'package:sami/services/config_marketing_service.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Page admin : configurer points de fidélité, cashback et promotions.
class ConfigMarketingPage extends StatefulWidget {
  const ConfigMarketingPage({super.key});

  @override
  State<ConfigMarketingPage> createState() => _ConfigMarketingPageState();
}

class _ConfigMarketingPageState extends State<ConfigMarketingPage>
    with PageProtegee {
  ConfigMarketing? _config;
  bool _chargement = true;
  bool _sauvegarde = false;

  // Contrôleurs
  final _fcfaParPointCtrl = TextEditingController();
  final _reductionFlashCtrl = TextEditingController();
  bool _promotionsActives = true;
  late List<PalierConfig> _paliers;

  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    _charger();
  }

  Future<void> _charger() async {
    final config = await ConfigMarketingService.charger();
    if (mounted) setState(() {
      _config = config;
      _fcfaParPointCtrl.text = config.fcfaParPoint.toString();
      _reductionFlashCtrl.text = config.reductionFlashDefaut.toStringAsFixed(0);
      _promotionsActives = config.promotionsActives;
      _paliers = List.from(config.paliers);
      _chargement = false;
    });
  }

  @override
  void dispose() {
    _fcfaParPointCtrl.dispose();
    _reductionFlashCtrl.dispose();
    super.dispose();
  }

  Future<void> _sauvegarder() async {
    setState(() => _sauvegarde = true);
    try {
      final nouvelle = ConfigMarketing(
        fcfaParPoint: int.tryParse(_fcfaParPointCtrl.text) ?? 100,
        reductionFlashDefaut: double.tryParse(_reductionFlashCtrl.text) ?? 20,
        promotionsActives: _promotionsActives,
        paliers: _paliers,
      );
      await ConfigMarketingService.sauvegarder(nouvelle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuration enregistrée'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur d\'enregistrement'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sauvegarde = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.estAdmin(u)) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Configuration marketing'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Promotions & fidélité'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          body: _chargement
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _sectionPoints(),
                    const SizedBox(height: 16),
                    _sectionPromotions(),
                    const SizedBox(height: 16),
                    _sectionPaliers(),
                    const SizedBox(height: 80),
                  ],
                ),
          bottomSheet: _chargement ? null : _barreSauvegarde(),
        );
      },
    );
  }

  // ── Points de fidélité ─────────────────────────────────────────────────────
  Widget _sectionPoints() {
    return _carte(
      titre: 'Points de fidélité',
      icone: Icons.stars_outlined,
      enfants: [
        const Text(
            'Combien faut-il dépenser pour gagner 1 point de fidélité ?',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fcfaParPointCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'FCFA par point',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('FCFA = 1 point', style: TextStyle(fontSize: 13)),
          ],
        ),
      ],
    );
  }

  // ── Promotions ─────────────────────────────────────────────────────────────
  Widget _sectionPromotions() {
    return _carte(
      titre: 'Promotions',
      icone: Icons.local_offer_outlined,
      enfants: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Promotions activées',
              style: TextStyle(fontSize: 14)),
          subtitle: const Text('Active les ventes flash sur la plateforme',
              style: TextStyle(fontSize: 12)),
          value: _promotionsActives,
          activeColor: _kPrimary,
          onChanged: (v) => setState(() => _promotionsActives = v),
        ),
        const Divider(),
        const SizedBox(height: 4),
        const Text('Réduction suggérée par défaut pour une vente flash',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: _reductionFlashCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '% réduction',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Paliers de fidélité ──────────────────────────────────────────────────
  Widget _sectionPaliers() {
    return _carte(
      titre: 'Paliers de fidélité & cashback',
      icone: Icons.workspace_premium_outlined,
      enfants: [
        const Text(
            'Pour chaque palier : points requis, réduction sur livraison et cashback en crédits.',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 12),
        ..._paliers.asMap().entries.map((e) => _editeurPalier(e.key, e.value)),
      ],
    );
  }

  Widget _editeurPalier(int index, PalierConfig p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(p.nom,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniChamp(
                  label: 'Points requis',
                  valeur: p.pointsRequis.toString(),
                  onChanged: (v) => setState(() => _paliers[index] =
                      p.copyWith(pointsRequis: int.tryParse(v) ?? p.pointsRequis)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniChamp(
                  label: 'Réduc. livr. %',
                  valeur: p.reductionLivraison.toStringAsFixed(0),
                  onChanged: (v) => setState(() => _paliers[index] =
                      p.copyWith(
                          reductionLivraison:
                              double.tryParse(v) ?? p.reductionLivraison)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniChamp(
                  label: 'Cashback %',
                  valeur: p.cashback.toStringAsFixed(0),
                  onChanged: (v) => setState(() => _paliers[index] =
                      p.copyWith(cashback: double.tryParse(v) ?? p.cashback)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChamp({
    required String label,
    required String valeur,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: valeur,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onChanged: onChanged,
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              Text(titre,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...enfants,
        ],
      ),
    );
  }

  Widget _barreSauvegarde() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _sauvegarde ? null : _sauvegarder,
          icon: _sauvegarde
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: const Text('Enregistrer la configuration'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
