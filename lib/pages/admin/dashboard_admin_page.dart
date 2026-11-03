import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/utils/droits.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// TABLEAU DE BORD ADMIN : vue d'ensemble de la plateforme.
/// Compteurs (utilisateurs, boutiques, ventes, GMV, commission), alertes
/// (candidatures, livraisons à vérifier, soldes négatifs) et réglages
/// (version minimale de l'app).
class DashboardAdminPage extends StatefulWidget {
  const DashboardAdminPage({super.key});

  @override
  State<DashboardAdminPage> createState() => _DashboardAdminPageState();
}

class _DashboardAdminPageState extends State<DashboardAdminPage>
    with PageProtegee {
  final _db = FirebaseFirestore.instance;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final users = await _db.collection('utilisateurs').get();
      final boutiques = await _db.collection('boutiques').get();
      final pagnes = await _db.collection('pagnes').get();
      final sousCmd = await _db.collection('sous_commandes').get();
      final coutures = await _db.collection('commandes_couturier').get();
      final candid = await _db
          .collection('candidatures')
          .where('statut', isEqualTo: 'enAttente')
          .get();
      final aVerif = await _db
          .collection('livraisons')
          .where('aVerifier', isEqualTo: true)
          .get();

      final parRole = <String, int>{};
      for (final d in users.docs) {
        final r = d.data()['role'] as String? ?? 'client';
        parRole[r] = (parRole[r] ?? 0) + 1;
      }

      double gmv = 0, commission = 0;
      int ventes = 0;
      for (final d in sousCmd.docs) {
        final data = d.data();
        if (data['statut'] == 'annulee') continue;
        ventes++;
        gmv += (data['sousTotal'] as num?)?.toDouble() ?? 0;
        commission +=
            (data['commissionPlateforme'] as num?)?.toDouble() ?? 0;
      }
      for (final d in coutures.docs) {
        final data = d.data();
        if (data['statut'] == 'annulee') continue;
        gmv += ((data['prixConvenu'] as num?)?.toDouble() ?? 0) +
            ((data['prixPagne'] as num?)?.toDouble() ?? 0);
        commission +=
            (data['commissionPlateforme'] as num?)?.toDouble() ?? 0;
      }

      final negatifs = boutiques.docs
          .where((d) =>
              ((d.data()['creditBalance'] as num?)?.toDouble() ?? 0) < 0)
          .length;

      if (mounted) {
        setState(() => _stats = {
              'utilisateurs': users.docs.length,
              'parRole': parRole,
              'boutiques': boutiques.docs.length,
              'pagnes': pagnes.docs.length,
              'ventes': ventes,
              'coutures': coutures.docs.length,
              'gmv': gmv,
              'commission': commission,
              'candidatures': candid.docs.length,
              'aVerifier': aVerif.docs.length,
              'soldesNegatifs': negatifs,
            });
      }
    } catch (_) {
      if (mounted) setState(() => _stats = {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.estAdmin(u)) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Tableau de bord'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        final s = _stats;
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Tableau de bord SAMI'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                  onPressed: _charger, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: s == null
              ? const Center(
                  child: CircularProgressIndicator(color: _kPrimary))
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      // ── ALERTES (à traiter) ──
                      if ((s['candidatures'] ?? 0) > 0 ||
                          (s['aVerifier'] ?? 0) > 0 ||
                          (s['soldesNegatifs'] ?? 0) > 0) ...[
                        _titre('À traiter'),
                        if ((s['candidatures'] ?? 0) > 0)
                          _alerte(
                              Icons.how_to_reg_outlined,
                              '${s['candidatures']} candidature(s) en attente',
                              '/candidatures'),
                        if ((s['aVerifier'] ?? 0) > 0)
                          _alerte(
                              Icons.flag_outlined,
                              '${s['aVerifier']} livraison(s) à vérifier',
                              '/livraisons-a-verifier'),
                        if ((s['soldesNegatifs'] ?? 0) > 0)
                          _alerte(
                              Icons.warning_amber_outlined,
                              '${s['soldesNegatifs']} boutique(s) en solde négatif (dette)',
                              '/gestion-boutiques'),
                        const SizedBox(height: 12),
                      ],

                      // ── ACTIVITÉ ──
                      _titre('Activité'),
                      Row(children: [
                        _tuile('Utilisateurs', '${s['utilisateurs']}',
                            Icons.people_outline),
                        const SizedBox(width: 10),
                        _tuile('Boutiques', '${s['boutiques']}',
                            Icons.storefront),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _tuile('Pagnes en ligne', '${s['pagnes']}',
                            Icons.checkroom),
                        const SizedBox(width: 10),
                        _tuile('Ventes', '${s['ventes']}',
                            Icons.shopping_bag_outlined),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _tuile('Coutures', '${s['coutures']}',
                            Icons.content_cut),
                        const SizedBox(width: 10),
                        _tuile(
                            'Comptes créés',
                            '${s['utilisateurs']}',
                            Icons.download_outlined,
                            note:
                                'proxy des téléchargements — le vrai chiffre est dans Play Console'),
                      ]),
                      const SizedBox(height: 14),

                      // ── FINANCES ──
                      _titre('Finances'),
                      _tuileLarge(
                          'Volume d\'affaires (GMV)',
                          PrixFCFA.formater((s['gmv'] as double?) ?? 0),
                          Icons.stacked_line_chart),
                      const SizedBox(height: 10),
                      _tuileLarge(
                          'Commission plateforme (ton CA)',
                          PrixFCFA.formater(
                              (s['commission'] as double?) ?? 0),
                          Icons.account_balance_wallet_outlined),
                      const SizedBox(height: 14),

                      // ── RÉPARTITION DES RÔLES ──
                      _titre('Utilisateurs par rôle'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: (s['parRole'] as Map<String, int>)
                                .entries
                                .map((e) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      child: Row(children: [
                                        Text(_roleLabel(e.key),
                                            style: const TextStyle(
                                                fontSize: 13)),
                                        const Spacer(),
                                        Text('${e.value}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ]),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── RÉGLAGES ──
                      _titre('Réglages'),
                      _lien(Icons.celebration_outlined,
                          'Événements & promotions (Tabaski…)', '/evenements'),
                      _lien(Icons.tune, 'Paramètres de la plateforme',
                          '/parametres'),
                      _lien(Icons.system_update_alt,
                          'Version minimale de l\'app', null,
                          onTap: _dialogVersion),
                    ],
                  ),
                ),
        );
      },
    );
  }

  // ── Version minimale (mise à jour forcée) ──
  Future<void> _dialogVersion() async {
    final doc =
        await _db.collection('app_config').doc('version').get();
    final ctrl = TextEditingController(
        text: doc.data()?['versionMin'] as String? ?? '1.0.0');
    final urlCtrl = TextEditingController(
        text: doc.data()?['urlMiseAJour'] as String? ?? '');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Version minimale requise'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Les utilisateurs avec une version plus ancienne seront '
                'BLOQUÉS et invités à mettre à jour.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    labelText: 'Version minimale (ex: 1.2.0)',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                    labelText: 'Lien de mise à jour (Play Store / APK)',
                    border: OutlineInputBorder(),
                    isDense: true)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.collection('app_config').doc('version').set({
        'versionMin': ctrl.text.trim(),
        'urlMiseAJour': urlCtrl.text.trim(),
      }, SetOptions(merge: true));
    }
  }

  // ── Helpers UI ──
  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: _kPrimary)),
      );

  Widget _tuile(String label, String valeur, IconData icone, {String? note}) =>
      Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: _kPrimary, size: 20),
                const SizedBox(height: 6),
                Text(valeur,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
                if (note != null)
                  Text(note,
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey.shade400)),
              ],
            ),
          ),
        ),
      );

  Widget _tuileLarge(String label, String valeur, IconData icone) => Card(
        child: ListTile(
          leading: Icon(icone, color: _kPrimary),
          title: Text(valeur,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          subtitle: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  Widget _alerte(IconData icone, String texte, String route) => Card(
        color: Colors.orange.withOpacity(0.08),
        child: ListTile(
          dense: true,
          leading: Icon(icone, color: Colors.orange),
          title: Text(texte, style: const TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.pushNamed(context, route),
        ),
      );

  Widget _lien(IconData icone, String texte, String? route,
          {VoidCallback? onTap}) =>
      Card(
        child: ListTile(
          dense: true,
          leading: Icon(icone, color: _kPrimary),
          title: Text(texte, style: const TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: onTap ??
              () => Navigator.pushNamed(context, route!),
        ),
      );

  String _roleLabel(String r) => switch (r) {
        'client' => 'Clients',
        'boutiquier' => 'Boutiquiers',
        'couturier' => 'Couturiers',
        'livreur' => 'Livreurs',
        'admin' => 'Admins',
        _ => r,
      };
}
