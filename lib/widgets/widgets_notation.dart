import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/avis.dart';
import 'package:sami/services/notation_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent  = Color(0xFFFF8F00);

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS DE NOTATION
//
// WidgetSoumettrAvis      → formulaire post-livraison (étoiles + sous-notes + commentaire)
// WidgetAffichageNotes    → étoiles + moyenne + distribution (dans les listes/détails)
// WidgetListeAvis         → liste scrollable des avis publiés
// ═══════════════════════════════════════════════════════════════════════════

// ─── Formulaire de soumission d'avis ─────────────────────────────────────────

class WidgetSoumettreAvis extends StatefulWidget {
  final CibleAvis cible;
  final String cibleId;
  final String cibleNom;         // affiché dans le titre
  final String auteurId;
  final String auteurRole;
  final String auteurNom;
  final String? auteurPhoto;
  final String? sousCommandeId;
  final String? livraisonId;
  final VoidCallback? onAvisSoumis;

  const WidgetSoumettreAvis({
    super.key,
    required this.cible,
    required this.cibleId,
    required this.cibleNom,
    required this.auteurId,
    required this.auteurRole,
    required this.auteurNom,
    this.auteurPhoto,
    this.sousCommandeId,
    this.livraisonId,
    this.onAvisSoumis,
  });

  @override
  State<WidgetSoumettreAvis> createState() => _WidgetSoumettreAvisState();
}

class _WidgetSoumettreAvisState extends State<WidgetSoumettreAvis> {
  double _note = 0;                         // 0 = pas encore noté
  final Map<String, double> _sousNotes = {};
  final _commentCtrl = TextEditingController();
  bool _enCours = false;
  bool _soumis = false;
  String? _erreur;

  List<SousNote> get _sousCriteres =>
      SousNotesConfig.catalogue[widget.cible] ?? [];

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_soumis) return _buildMerci();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Titre
        Row(children: [
          Icon(_icone(widget.cible), color: _kPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(
            Tr.s.evaluer(widget.cibleNom),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          )),
        ]),
        const SizedBox(height: 16),

        // Étoiles principales
        Text(Tr.s.noteGlobale, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ...List.generate(5, (i) => GestureDetector(
            onTap: () => setState(() => _note = i + 1.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                i < _note ? Icons.star : Icons.star_border,
                color: _kAccent,
                size: 36,
              ),
            ),
          )),
        ]),
        if (_note > 0) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(child: Text(
            _labelNote(_note.round()),
            style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600, fontSize: 13),
          )),
        ),

        // Sous-critères
        if (_sousCriteres.isNotEmpty && _note > 0) ...[
          const SizedBox(height: 20),
          Text(Tr.s.detailOptionnel,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 10),
          ..._sousCriteres.map((critere) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(critere.icone, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(child: Text(critere.label,
                  style: const TextStyle(fontSize: 12))),
              Row(children: List.generate(5, (i) => GestureDetector(
                onTap: () => setState(
                    () => _sousNotes[critere.id] = i + 1.0),
                child: Icon(
                  i < (_sousNotes[critere.id] ?? 0)
                      ? Icons.star : Icons.star_border,
                  color: _kAccent, size: 18,
                ),
              ))),
            ]),
          )),
        ],

        // Commentaire
        if (_note > 0) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: _hintCommentaire(widget.cible),
              hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              filled: true, fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
              counterStyle: const TextStyle(fontSize: 10),
            ),
          ),
        ],

        // Erreur
        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],

        const SizedBox(height: 16),

        // Bouton soumettre
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: _note == 0 || _enCours ? null : _soumettre,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              disabledBackgroundColor: Colors.grey.shade200,
            ),
            child: _enCours
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : Text(
                    _note == 0 ? Tr.s.selectionnezNote : Tr.s.publierMonAvis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        if (_note == 0)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Center(child: Text(
              Tr.s.appuyezSurEtoilesPourNoter,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            )),
          ),
      ]),
    );
  }

  Widget _buildMerci() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.green.shade200),
    ),
    child: Column(children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 48),
      const SizedBox(height: 12),
      Text(Tr.s.merciPourVotreAvis,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
      const SizedBox(height: 6),
      Text(Tr.s.ilSeraVisibleApresVerification,
          style: TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
  );

  Future<void> _soumettre() async {
    setState(() { _enCours = true; _erreur = null; });
    try {
      final erreur = await NotationService.soumettre(
        cible: widget.cible,
        cibleId: widget.cibleId,
        auteurId: widget.auteurId,
        auteurRole: widget.auteurRole,
        auteurNom: widget.auteurNom,
        auteurPhoto: widget.auteurPhoto,
        note: _note,
        commentaire: _commentCtrl.text.trim().isEmpty
            ? null : _commentCtrl.text.trim(),
        sousNotes: _sousNotes,
        sousCommandeId: widget.sousCommandeId,
        livraisonId: widget.livraisonId,
      );
      if (erreur != null) {
        if (mounted) setState(() { _erreur = erreur; _enCours = false; });
      } else {
        if (mounted) {
          setState(() { _soumis = true; _enCours = false; });
          widget.onAvisSoumis?.call();
        }
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = 'Erreur : $e'; _enCours = false; });
    }
  }

  IconData _icone(CibleAvis c) => switch (c) {
    CibleAvis.pagne     => Icons.shopping_bag_outlined,
    CibleAvis.boutique  => Icons.store_outlined,
    CibleAvis.couturier => Icons.content_cut,
    CibleAvis.livreur   => Icons.delivery_dining,
    CibleAvis.client    => Icons.person_outline,
  };

  String _hintCommentaire(CibleAvis c) => switch (c) {
    CibleAvis.pagne     => Tr.s.qualiteTissuCouleursCoupe,
    CibleAvis.boutique  => Tr.s.serviceReactiviteProduits,
    CibleAvis.couturier => Tr.s.precisionRespectDelaisResultat,
    CibleAvis.livreur   => Tr.s.rapiditeSoinColisPolitesse,
    CibleAvis.client    => Tr.s.disponibiliteSerieux,
  };

  String _labelNote(int n) => switch (n) {
    1 => Tr.s.tresMauvais,
    2 => Tr.s.mauvais,
    3 => Tr.s.correct,
    4 => Tr.s.bien,
    5 => Tr.s.excellent,
    _ => '',
  };
}

// ─── Affichage des étoiles + résumé ──────────────────────────────────────────

class WidgetAffichageNotes extends StatelessWidget {
  final CibleAvis cible;
  final String cibleId;
  final bool afficherDistribution;
  final bool compact;            // mode compact pour les listes

  const WidgetAffichageNotes({
    super.key,
    required this.cible,
    required this.cibleId,
    this.afficherDistribution = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResumeNotes>(
      future: NotationService.getResume(cible, cibleId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 20,
            child: Center(child: LinearProgressIndicator(color: _kPrimary)));

        final resume = snap.data!;
        if (!resume.aDesAvis) {
          return compact ? const SizedBox.shrink()
              : Text(Tr.s.aucunAvisPourMoment,
                  style: TextStyle(color: Colors.grey, fontSize: 12));
        }

        if (compact) {
          return Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, color: _kAccent, size: 14),
            const SizedBox(width: 3),
            Text(resume.moyenne.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 3),
            Text('(${resume.nombre})',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]);
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Moyenne + étoiles
          Row(children: [
            Text(resume.moyenne.toStringAsFixed(1),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _EtoilesRow(note: resume.moyenne),
              Text(Tr.s.avis(resume.nombre),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ]),

          // Distribution (optionnel)
          if (afficherDistribution) ...[
            const SizedBox(height: 12),
            ...List.generate(5, (i) => _BarreDistribution(
              etoiles: 5 - i,
              pct: resume.pct(5 - i),
              nombre: resume.distribution[5 - i] ?? 0,
            )),
          ],
        ]);
      },
    );
  }
}

class _EtoilesRow extends StatelessWidget {
  final double note;
  final double taille;
  const _EtoilesRow({required this.note, this.taille = 18});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) {
      if (i < note.floor()) {
        return Icon(Icons.star, color: _kAccent, size: taille);
      } else if (i < note) {
        return Icon(Icons.star_half, color: _kAccent, size: taille);
      } else {
        return Icon(Icons.star_border, color: Colors.grey.shade300, size: taille);
      }
    }),
  );
}

class _BarreDistribution extends StatelessWidget {
  final int etoiles;
  final double pct;
  final int nombre;
  const _BarreDistribution({required this.etoiles, required this.pct, required this.nombre});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$etoiles', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const Icon(Icons.star, color: _kAccent, size: 11),
      const SizedBox(width: 6),
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: Colors.grey.shade100,
          valueColor: const AlwaysStoppedAnimation(_kAccent),
          minHeight: 6,
        ),
      )),
      const SizedBox(width: 6),
      SizedBox(width: 20, child: Text('$nombre',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.right)),
    ]),
  );
}

// ─── Liste des avis publiés ───────────────────────────────────────────────────

class WidgetListeAvis extends StatelessWidget {
  final CibleAvis cible;
  final String cibleId;
  final String? auteurIdCourant;   // pour permettre le signalement

  const WidgetListeAvis({
    super.key,
    required this.cible,
    required this.cibleId,
    this.auteurIdCourant,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Avis>>(
      stream: Avis.streamPourCible(cible, cibleId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator(color: _kPrimary));
        if (!snap.hasData || snap.data!.isEmpty)
          return Padding(
            padding: EdgeInsets.all(16),
            child: Text(Tr.s.aucunAvisPubliePourMoment,
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: snap.data!.map((avis) => _CarteAvis(
            avis: avis,
            auteurIdCourant: auteurIdCourant,
          )).toList(),
        );
      },
    );
  }
}

class _CarteAvis extends StatelessWidget {
  final Avis avis;
  final String? auteurIdCourant;
  const _CarteAvis({required this.avis, this.auteurIdCourant});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: _kPrimary.withOpacity(0.12),
          backgroundImage: providerUniversel(avis.auteurPhoto),
          child: avis.auteurPhoto == null
              ? Text(avis.auteurNom[0].toUpperCase(),
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(avis.auteurNom,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (avis.achatVerifie) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(Tr.s.achatVerifie,
                    style: TextStyle(fontSize: 9, color: Colors.green.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          Text(_formatDate(avis.dateCreation),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ])),
        // Étoiles + note
        Row(mainAxisSize: MainAxisSize.min, children: [
          _EtoilesRow(note: avis.note, taille: 14),
          const SizedBox(width: 4),
          Text(avis.note.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ]),

      // Commentaire
      if (avis.commentaire?.isNotEmpty == true) ...[
        const SizedBox(height: 8),
        Text(avis.commentaire!,
            style: const TextStyle(fontSize: 13, height: 1.4)),
      ],

      // Sous-notes si présentes
      if (avis.sousNotes.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 4,
          children: avis.sousNotes.entries.map((e) {
            final label = SousNotesConfig.catalogue[avis.cible]
                ?.firstWhere((s) => s.id == e.key, orElse: () => SousNote(e.key, e.key, Icons.star))
                .label ?? e.key;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text('$label: ${e.value.toStringAsFixed(0)}⭐',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            );
          }).toList(),
        ),
      ],

      // Bouton signaler (seulement si ce n'est pas son propre avis)
      if (auteurIdCourant != null && auteurIdCourant != avis.auteurId) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _signaler(context),
            icon: const Icon(Icons.flag_outlined, size: 12, color: Colors.grey),
            label: Text(Tr.s.signaler, style: TextStyle(fontSize: 11, color: Colors.grey)),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    ]),
  );

  void _signaler(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Tr.s.signalerCetAvis),
        content: Text(Tr.s.cetAvisVousSembleFaux),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Tr.s.annuler),
          ),
          ElevatedButton(
            onPressed: () async {
              await NotationService.signalerAvis(
                avis.id,
                auteurIdCourant!,
                'Avis inapproprié signalé par un utilisateur',
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(Tr.s.signalementEnvoyeMerci),
                  backgroundColor: Colors.orange,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: Text(Tr.s.signaler),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Aujourd\'hui';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 30) return 'Il y a ${diff.inDays} jours';
    if (diff.inDays < 365) return 'Il y a ${(diff.inDays / 30).round()} mois';
    return 'Il y a ${(diff.inDays / 365).round()} an(s)';
  }
}
