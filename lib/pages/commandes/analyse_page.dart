import 'package:flutter/material.dart';
import 'package:sami/services/analyse_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

class AnalysePage extends StatefulWidget {
  final String boutiqueId;
  final String boutiqueNom;
  const AnalysePage({
    super.key,
    required this.boutiqueId,
    this.boutiqueNom = '',
  });

  @override
  State<AnalysePage> createState() => _AnalysePageState();
}

class _AnalysePageState extends State<AnalysePage> {
  int _periode = 30; // jours
  late Future<IndicateursBoutique> _future;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  void _recharger() {
    _future = AnalyseService.indicateurs(widget.boutiqueId, jours: _periode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Analyse de ma boutique'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _selecteurPeriode(),
          Expanded(
            child: FutureBuilder<IndicateursBoutique>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _kPrimary));
                }
                if (!snap.hasData) {
                  return const Center(child: Text('Erreur de chargement'));
                }
                final ind = snap.data!;
                if (ind.nbCommandesTotal == 0) {
                  return _vide();
                }
                return RefreshIndicator(
                  color: _kPrimary,
                  onRefresh: () async => setState(_recharger),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _grilleKPI(ind),
                      const SizedBox(height: 16),
                      _sectionArgent(ind),
                      const SizedBox(height: 16),
                      _sectionEvolution(ind),
                      const SizedBox(height: 16),
                      _sectionTopProduits(ind),
                      const SizedBox(height: 16),
                      _sectionRecommandations(ind),
                      const SizedBox(height: 30),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _selecteurPeriode() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [7, 30, 90].map((j) {
          final actif = _periode == j;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(j == 7
                  ? '7 jours'
                  : j == 30
                      ? '30 jours'
                      : '3 mois'),
              selected: actif,
              onSelected: (_) => setState(() {
                _periode = j;
                _recharger();
              }),
              selectedColor: _kPrimary.withOpacity(0.15),
              labelStyle: TextStyle(
                color: actif ? _kPrimary : Colors.grey,
                fontWeight: actif ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Grille des indicateurs clés ───────────────────────────────────────────
  Widget _grilleKPI(IndicateursBoutique ind) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _carteKPI('Ventes', '${ind.nbVentes}', Icons.shopping_bag_outlined,
            Colors.blue),
        _carteKPI('Panier moyen', PrixFCFA.formater(ind.panierMoyen),
            Icons.receipt_outlined, Colors.teal),
        _carteKPI('Commandes', '${ind.nbCommandesTotal}',
            Icons.list_alt_outlined, Colors.indigo),
        _carteKPI('Taux annulation', '${ind.tauxAnnulation.toStringAsFixed(0)}%',
            Icons.cancel_outlined,
            ind.tauxAnnulation > 20 ? Colors.red : Colors.orange),
      ],
    );
  }

  Widget _carteKPI(String label, String valeur, IconData icone, Color couleur) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, color: couleur, size: 22),
          const SizedBox(height: 8),
          Text(valeur,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ── Section argent ─────────────────────────────────────────────────────────
  Widget _sectionArgent(IndicateursBoutique ind) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimary, Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chiffre d\'affaires',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(PrixFCFA.formater(ind.chiffreAffaires),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24, height: 24),
          _ligneArgent('Net encaissé (vous)', ind.netEncaisse, Colors.white),
          const SizedBox(height: 8),
          _ligneArgent('Commissions plateforme', ind.commissionsVersees,
              Colors.white70),
        ],
      ),
    );
  }

  Widget _ligneArgent(String label, double montant, Color couleur) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: couleur, fontSize: 13)),
        Text(PrixFCFA.formater(montant),
            style: TextStyle(
                color: couleur, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Graphique d'évolution (barres maison) ───────────────────────────────────
  Widget _sectionEvolution(IndicateursBoutique ind) {
    if (ind.evolution.isEmpty) return const SizedBox.shrink();
    final maxMontant = ind.evolution
        .map((p) => p.montant)
        .reduce((a, b) => a > b ? a : b);

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
          const Text('Évolution des ventes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: ind.evolution.map((p) {
                final hauteur =
                    maxMontant > 0 ? (p.montant / maxMontant) * 100 : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: hauteur + 4,
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${p.jour.day}/${p.jour.month}',
                            style: const TextStyle(
                                fontSize: 8, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top produits ─────────────────────────────────────────────────────────
  Widget _sectionTopProduits(IndicateursBoutique ind) {
    if (ind.topProduits.isEmpty) return const SizedBox.shrink();
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
          const Text('Pagnes les plus vendus',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...ind.topProduits.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: _kPrimary.withOpacity(0.12),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: _kPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text('${p.quantite} vendus',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(width: 10),
                  Text(PrixFCFA.formater(p.montant),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kPrimary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Recommandations ────────────────────────────────────────────────────────
  Widget _sectionRecommandations(IndicateursBoutique ind) {
    if (ind.recommandations.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              const Text('Conseils pour votre boutique',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ...ind.recommandations.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 14)),
                    Expanded(
                        child: Text(r,
                            style: const TextStyle(
                                fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _vide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Aucune donnée sur cette période',
              style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Vos statistiques apparaîtront après vos premières ventes',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
