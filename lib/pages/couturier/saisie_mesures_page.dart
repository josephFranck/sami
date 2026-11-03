import 'package:flutter/material.dart';
import 'package:sami/services/resilience_service.dart';
import 'package:sami/widgets/widgets_resilients.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sami/models/couture.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent = Color(0xFFFF8F00);

/// Page de saisie des mesures avec mannequin illustré interactif
/// Trilingue : Français / English / Fulfulde
class SaisieMesuresPage extends StatefulWidget {
  final ModeleCouture modele;
  final MesuresClient? mesuresExistantes; // pré-remplissage si profil sauvegardé
  final Langue langueInitiale;

  const SaisieMesuresPage({
    super.key,
    required this.modele,
    this.mesuresExistantes,
    this.langueInitiale = Langue.fr,
  });

  @override
  State<SaisieMesuresPage> createState() => _SaisieMesuresPageState();
}

class _SaisieMesuresPageState extends State<SaisieMesuresPage> with AutoSaveMixin {
  @override
  String get autosaveCle => 'mesures_${widget.modele.id}';

  late Langue _langue;
  late Map<String, TextEditingController> _controllers;
  String? _mesureActive;  // ID de la mesure sélectionnée (met la zone en surbrillance)
  final _formKey = GlobalKey<FormState>();
  bool _sauvegarderProfil = true;
  String _nomProfil = 'Mon profil';

  @override
  void initState() {
    super.initState();
    _langue = widget.langueInitiale;
    _controllers = {};
    for (final mesureId in widget.modele.mesuresRequises) {
      final valeur = widget.mesuresExistantes?.valeur(mesureId);
      _controllers[mesureId] = TextEditingController(
        text: valeur != null && valeur > 0 ? valeur.toStringAsFixed(0) : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_texte('Mes mesures', 'My measurements', 'Mesureeji am')),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          // Sélecteur de langue
          PopupMenuButton<Langue>(
            icon: Text(
              _langueEmoji(_langue),
              style: const TextStyle(fontSize: 18),
            ),
            onSelected: (l) => setState(() => _langue = l),
            itemBuilder: (_) => [
              _menuItemLangue(Langue.fr, '🇫🇷', 'Français'),
              _menuItemLangue(Langue.en, '🇬🇧', 'English'),
              // Fulfulde (Langue.ff) : lancement FR/EN uniquement (décision
              // 03/11/2026) — l'enum et ses textes restent, non proposés.
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // En-tête modèle
            _EnteteModele(modele: widget.modele, langue: _langue),

            Expanded(
              child: Row(
                children: [
                  // Mannequin SVG (gauche)
                  Expanded(
                    flex: 2,
                    child: _MannequinInteractif(
                      mesuresRequises: widget.modele.definitionsMesures,
                      mesureActive: _mesureActive,
                      valeurs: _valeursActuelles,
                      onZoneTap: (id) => setState(() {
                        _mesureActive = _mesureActive == id ? null : id;
                        _scrollVers(id);
                      }),
                    ),
                  ),

                  // Formulaire mesures (droite)
                  Expanded(
                    flex: 3,
                    child: _FormulaireMesures(
                      modele: widget.modele,
                      controllers: _controllers,
                      langue: _langue,
                      mesureActive: _mesureActive,
                      onMesureSelect: (id) => setState(() => _mesureActive = id),
                    ),
                  ),
                ],
              ),
            ),

            // Options sauvegarde + bouton valider
            _PiedPage(
              sauvegarder: _sauvegarderProfil,
              nomProfil: _nomProfil,
              langue: _langue,
              onSauvegarderChange: (v) => setState(() => _sauvegarderProfil = v),
              onNomChange: (v) => _nomProfil = v,
              onValider: _valider,
              estComplet: _estComplet,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> get _valeursActuelles {
    final map = <String, double>{};
    for (final entry in _controllers.entries) {
      final val = double.tryParse(entry.value.text);
      if (val != null && val > 0) map[entry.key] = val;
    }
    return map;
  }

  bool get _estComplet {
    for (final mesureId in widget.modele.mesuresRequises) {
      final def = DefinitionMesure.catalogue[mesureId];
      if (def == null || !def.obligatoire) continue;
      final val = double.tryParse(_controllers[mesureId]?.text ?? '');
      if (val == null || val <= 0) return false;
    }
    return true;
  }

  void _scrollVers(String mesureId) {
    // Le formulaire gère le scroll interne
  }

  Future<void> _valider() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_estComplet) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_texte(
          'Remplissez toutes les mesures obligatoires',
          'Fill in all required measurements',
          'Ƴeewton fof mesures ɗe haɗɗiiɗe',
        )),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final mesures = MesuresClient(
      id: '',
      clientId: '',
      nomProfil: _sauvegarderProfil ? _nomProfil : null,
      valeurs: _valeursActuelles,
      dateCreation: DateTime.now(),
    );

    Navigator.pop(context, mesures);
  }

  PopupMenuItem<Langue> _menuItemLangue(Langue l, String emoji, String nom) =>
      PopupMenuItem(
        value: l,
        child: Row(children: [
          Text(emoji),
          const SizedBox(width: 8),
          Text(nom),
          if (_langue == l) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: _kPrimary),
          ],
        ]),
      );

  String _langueEmoji(Langue l) => switch (l) {
    Langue.fr => '🇫🇷',
    Langue.en => '🇬🇧',
    Langue.ff => '🟡',
  };

  String _texte(String fr, String en, String ff) => switch (_langue) {
    Langue.fr => fr,
    Langue.en => en,
    Langue.ff => ff,
  };
}

// ─── En-tête modèle ───────────────────────────────────────────────────────────

class _EnteteModele extends StatelessWidget {
  final ModeleCouture modele;
  final Langue langue;
  const _EnteteModele({required this.modele, required this.langue});

  @override
  Widget build(BuildContext context) => Container(
    color: _kPrimary.withOpacity(0.06),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.content_cut, color: _kPrimary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modele.nom(langue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                '${modele.mesuresRequises.length} ${langue == Langue.fr ? "mesures requises" : langue == Langue.en ? "measurements required" : "mesure keɗɗiiɗe"}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        Text(modele.prixBaseFmt, style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 14)),
      ],
    ),
  );
}

// ─── Mannequin SVG interactif ─────────────────────────────────────────────────

class _MannequinInteractif extends StatelessWidget {
  final List<DefinitionMesure> mesuresRequises;
  final String? mesureActive;
  final Map<String, double> valeurs;
  final ValueChanged<String> onZoneTap;

  const _MannequinInteractif({
    required this.mesuresRequises,
    required this.mesureActive,
    required this.valeurs,
    required this.onZoneTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // Mannequin SVG de base (silhouette neutre)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildMannequinSVG(),
            ),
          ),
          // Légende des zones colorées
          Positioned(
            bottom: 8,
            left: 4,
            right: 4,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: mesuresRequises.take(6).map((m) => GestureDetector(
                onTap: () => onZoneTap(m.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(int.parse(m.couleurZone.replaceFirst('#', '0xFF'))).withOpacity(
                      mesureActive == m.id ? 1.0 : 0.6,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    border: mesureActive == m.id
                        ? Border.all(color: Colors.black38, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    m.id.substring(0, 2).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMannequinSVG() {
    // Zones à mettre en surbrillance selon les mesures requises
    final zonesActives = mesuresRequises.map((m) => m.zone).toSet();

    // SVG simplifié d'un mannequin avec zones colorées
    return CustomPaint(
      size: const Size(120, 280),
      painter: _MannequinPainter(
        mesuresRequises: mesuresRequises,
        mesureActive: mesureActive,
        valeursSaisies: valeurs,
        onZoneTap: onZoneTap,
      ),
    );
  }
}

// Painter du mannequin avec zones colorées
class _MannequinPainter extends CustomPainter {
  final List<DefinitionMesure> mesuresRequises;
  final String? mesureActive;
  final Map<String, double> valeursSaisies;
  final ValueChanged<String> onZoneTap;

  _MannequinPainter({
    required this.mesuresRequises,
    required this.mesureActive,
    required this.valeursSaisies,
    required this.onZoneTap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paintBase = Paint()..color = const Color(0xFFE8D5C4)..style = PaintingStyle.fill;
    final paintContour = Paint()..color = const Color(0xFFB8956A)..style = PaintingStyle.stroke..strokeWidth = 1.5;

    // Tête
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.07), width: w * 0.22, height: h * 0.12), paintBase);
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.07), width: w * 0.22, height: h * 0.12), paintContour);

    // Cou
    final neckPath = Path()
      ..addRect(Rect.fromCenter(center: Offset(w / 2, h * 0.14), width: w * 0.10, height: h * 0.04));
    canvas.drawPath(neckPath, paintBase);
    canvas.drawPath(neckPath, paintContour);

    // Torse
    final torsePath = Path()
      ..moveTo(w * 0.25, h * 0.16)
      ..lineTo(w * 0.75, h * 0.16)
      ..lineTo(w * 0.72, h * 0.42)
      ..lineTo(w * 0.28, h * 0.42)
      ..close();
    canvas.drawPath(torsePath, paintBase);
    canvas.drawPath(torsePath, paintContour);

    // Hanches
    final hanchesPath = Path()
      ..moveTo(w * 0.28, h * 0.42)
      ..lineTo(w * 0.72, h * 0.42)
      ..lineTo(w * 0.76, h * 0.58)
      ..lineTo(w * 0.24, h * 0.58)
      ..close();
    canvas.drawPath(hanchesPath, paintBase);
    canvas.drawPath(hanchesPath, paintContour);

    // Jambes
    final jambeGPath = Path()
      ..moveTo(w * 0.28, h * 0.58)
      ..lineTo(w * 0.50, h * 0.58)
      ..lineTo(w * 0.48, h * 0.95)
      ..lineTo(w * 0.26, h * 0.95)
      ..close();
    final jambeDPath = Path()
      ..moveTo(w * 0.50, h * 0.58)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w * 0.74, h * 0.95)
      ..lineTo(w * 0.52, h * 0.95)
      ..close();
    canvas.drawPath(jambeGPath, paintBase);
    canvas.drawPath(jambeGPath, paintContour);
    canvas.drawPath(jambeDPath, paintBase);
    canvas.drawPath(jambeDPath, paintContour);

    // Bras gauche
    final brasGPath = Path()
      ..moveTo(w * 0.25, h * 0.16)
      ..lineTo(w * 0.12, h * 0.20)
      ..lineTo(w * 0.08, h * 0.40)
      ..lineTo(w * 0.18, h * 0.42)
      ..lineTo(w * 0.24, h * 0.22)
      ..close();
    final brasDPath = Path()
      ..moveTo(w * 0.75, h * 0.16)
      ..lineTo(w * 0.88, h * 0.20)
      ..lineTo(w * 0.92, h * 0.40)
      ..lineTo(w * 0.82, h * 0.42)
      ..lineTo(w * 0.76, h * 0.22)
      ..close();
    canvas.drawPath(brasGPath, paintBase);
    canvas.drawPath(brasGPath, paintContour);
    canvas.drawPath(brasDPath, paintBase);
    canvas.drawPath(brasDPath, paintContour);

    // Superposer les zones colorées selon les mesures
    for (final mesure in mesuresRequises) {
      final couleur = Color(int.parse(mesure.couleurZone.replaceFirst('#', '0xFF')));
      final isActive = mesureActive == mesure.id;
      final hasSaisie = valeursSaisies.containsKey(mesure.id);
      final opacity = isActive ? 0.55 : (hasSaisie ? 0.25 : 0.15);
      final paintZone = Paint()
        ..color = couleur.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      switch (mesure.zone) {
        case 'poitrine':
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.28, h * 0.16)
              ..lineTo(w * 0.72, h * 0.16)
              ..lineTo(w * 0.70, h * 0.30)
              ..lineTo(w * 0.30, h * 0.30)
              ..close(),
            paintZone,
          );
        case 'taille':
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.29, h * 0.30)
              ..lineTo(w * 0.71, h * 0.30)
              ..lineTo(w * 0.72, h * 0.38)
              ..lineTo(w * 0.28, h * 0.38)
              ..close(),
            paintZone,
          );
        case 'hanches':
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.28, h * 0.38)
              ..lineTo(w * 0.72, h * 0.38)
              ..lineTo(w * 0.75, h * 0.52)
              ..lineTo(w * 0.25, h * 0.52)
              ..close(),
            paintZone,
          );
        case 'bras':
          canvas.drawPath(brasGPath, paintZone);
          canvas.drawPath(brasDPath, paintZone);
        case 'epaules':
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.22, h * 0.16)
              ..lineTo(w * 0.78, h * 0.16)
              ..lineTo(w * 0.76, h * 0.20)
              ..lineTo(w * 0.24, h * 0.20)
              ..close(),
            paintZone,
          );
        case 'cou':
          canvas.drawOval(
            Rect.fromCenter(center: Offset(w / 2, h * 0.14), width: w * 0.12, height: h * 0.05),
            paintZone,
          );
        case 'jambes':
          canvas.drawPath(jambeGPath, paintZone);
          canvas.drawPath(jambeDPath, paintZone);
        case 'dos':
        case 'corps':
          canvas.drawPath(torsePath, paintZone);
      }

      // Point indicateur si mesure saisie
      if (hasSaisie) {
        final checkPaint = Paint()..color = couleur..style = PaintingStyle.fill;
        final (cx, cy) = _centreZone(mesure.zone, w, h);
        canvas.drawCircle(Offset(cx, cy), 5, checkPaint);
        final checkMark = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5;
        final path = Path()
          ..moveTo(cx - 2.5, cy)
          ..lineTo(cx - 0.5, cy + 2)
          ..lineTo(cx + 2.5, cy - 2);
        canvas.drawPath(path, checkMark);
      }
    }
  }

  (double, double) _centreZone(String zone, double w, double h) => switch (zone) {
    'poitrine' => (w / 2, h * 0.22),
    'taille' => (w / 2, h * 0.34),
    'hanches' => (w / 2, h * 0.46),
    'bras' => (w * 0.12, h * 0.30),
    'epaules' => (w / 2, h * 0.18),
    'cou' => (w / 2, h * 0.14),
    'jambes' => (w / 2, h * 0.76),
    _ => (w / 2, h * 0.50),
  };

  @override
  bool shouldRepaint(_MannequinPainter old) =>
      old.mesureActive != mesureActive || old.valeursSaisies != valeursSaisies;
}

// ─── Formulaire de mesures ────────────────────────────────────────────────────

class _FormulaireMesures extends StatefulWidget {
  final ModeleCouture modele;
  final Map<String, TextEditingController> controllers;
  final Langue langue;
  final String? mesureActive;
  final ValueChanged<String> onMesureSelect;

  const _FormulaireMesures({
    required this.modele,
    required this.controllers,
    required this.langue,
    required this.mesureActive,
    required this.onMesureSelect,
  });

  @override
  State<_FormulaireMesures> createState() => _FormulaireMesuresState();
}

class _FormulaireMesuresState extends State<_FormulaireMesures> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definitions = widget.modele.definitionsMesures;

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(10),
      itemCount: definitions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final def = definitions[i];
        final isActive = widget.mesureActive == def.id;
        final ctrl = widget.controllers[def.id];
        if (ctrl == null) return const SizedBox.shrink();

        return _ChampMesure(
          definition: def,
          controller: ctrl,
          langue: widget.langue,
          isActive: isActive,
          onFocus: () => widget.onMesureSelect(def.id),
        );
      },
    );
  }
}

class _ChampMesure extends StatelessWidget {
  final DefinitionMesure definition;
  final TextEditingController controller;
  final Langue langue;
  final bool isActive;
  final VoidCallback onFocus;

  const _ChampMesure({
    required this.definition,
    required this.controller,
    required this.langue,
    required this.isActive,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = Color(int.parse(definition.couleurZone.replaceFirst('#', '0xFF')));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isActive ? couleur.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? couleur : Colors.grey.shade200,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête de la mesure
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    definition.label(langue),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive ? couleur : Colors.black87,
                    ),
                  ),
                ),
                if (definition.obligatoire)
                  Text('*', style: TextStyle(color: couleur, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // Instruction (si mesure active)
          if (isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 10, 6),
              child: Text(
                definition.instruction(langue),
                style: TextStyle(fontSize: 11, color: couleur.withOpacity(0.8), fontStyle: FontStyle.italic),
              ),
            ),

          // Champ de saisie
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onTap: onFocus,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '${definition.min.round()}–${definition.max.round()} cm',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                suffixText: 'cm',
                suffixStyle: TextStyle(color: couleur, fontWeight: FontWeight.w500),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: couleur, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
              ),
              validator: (v) {
                if (!definition.obligatoire) return null;
                final val = double.tryParse(v ?? '');
                if (val == null || val <= 0) return langue == Langue.fr ? 'Requis' : langue == Langue.en ? 'Required' : 'Haɗɗiiɗo';
                if (val < definition.min || val > definition.max) {
                  return '${definition.min.round()}–${definition.max.round()} cm';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pied de page ─────────────────────────────────────────────────────────────

class _PiedPage extends StatelessWidget {
  final bool sauvegarder;
  final String nomProfil;
  final Langue langue;
  final ValueChanged<bool> onSauvegarderChange;
  final ValueChanged<String> onNomChange;
  final VoidCallback onValider;
  final bool estComplet;

  const _PiedPage({
    required this.sauvegarder,
    required this.nomProfil,
    required this.langue,
    required this.onSauvegarderChange,
    required this.onNomChange,
    required this.onValider,
    required this.estComplet,
  });

  @override
  Widget build(BuildContext context) {
    final lblSauvegarder = langue == Langue.fr
        ? 'Sauvegarder ce profil de mesures'
        : langue == Langue.en
            ? 'Save this measurement profile'
            : 'Waɗ ko mum huunde mesure';

    final lblValider = langue == Langue.fr
        ? 'Confirmer les mesures'
        : langue == Langue.en
            ? 'Confirm measurements'
            : 'Jaɓɓo mesure';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Option sauvegarder profil
          Row(
            children: [
              Switch(value: sauvegarder, onChanged: onSauvegarderChange, activeColor: _kPrimary),
              Expanded(child: Text(lblSauvegarder, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ],
          ),
          if (sauvegarder) ...[
            const SizedBox(height: 6),
            TextField(
              decoration: InputDecoration(
                hintText: langue == Langue.fr ? 'Nom du profil (ex: Mon profil)' : 'Profile name',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: onNomChange,
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: estComplet ? onValider : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                lblValider,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
