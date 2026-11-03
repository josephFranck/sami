import 'package:flutter/material.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// SILHOUETTE DE MESURE : mannequin 2D animé qui MONTRE OÙ prendre la mesure
/// sélectionnée (ligne pulsante sur la zone du corps). S'affiche au-dessus du
/// formulaire de saisie ; la zone change quand le client passe d'un champ à
/// l'autre.
class SilhouetteMesure extends StatefulWidget {
  final String? mesureId; // ex: 'tourPoitrine' — null = aucune surbrillance
  const SilhouetteMesure({super.key, this.mesureId});

  @override
  State<SilhouetteMesure> createState() => _SilhouetteMesureState();
}

class _SilhouetteMesureState extends State<SilhouetteMesure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: const Size(110, 200),
        painter: _SilhouettePainter(
          mesureId: widget.mesureId,
          pulse: 0.5 + _anim.value * 0.5, // opacité 0.5 → 1.0
        ),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  final String? mesureId;
  final double pulse;
  _SilhouettePainter({this.mesureId, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double x(double v) => v / 110 * w;
    double y(double v) => v / 200 * h;

    final corps = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // ── Silhouette simple ──
    // Tête
    canvas.drawCircle(Offset(x(55), y(18)), x(11), corps);
    // Cou
    canvas.drawLine(Offset(x(55), y(29)), Offset(x(55), y(38)), corps);
    // Épaules
    canvas.drawLine(Offset(x(32), y(42)), Offset(x(78), y(42)), corps);
    // Tronc (léger cintrage taille)
    final tronc = Path()
      ..moveTo(x(36), y(42))
      ..quadraticBezierTo(x(33), y(70), x(40), y(88)) // flanc gauche
      ..quadraticBezierTo(x(36), y(100), x(38), y(112))
      ..moveTo(x(74), y(42))
      ..quadraticBezierTo(x(77), y(70), x(70), y(88)) // flanc droit
      ..quadraticBezierTo(x(74), y(100), x(72), y(112));
    canvas.drawPath(tronc, corps);
    // Bras
    canvas.drawLine(Offset(x(32), y(42)), Offset(x(22), y(92)), corps);
    canvas.drawLine(Offset(x(78), y(42)), Offset(x(88), y(92)), corps);
    // Jambes
    canvas.drawLine(Offset(x(46), y(112)), Offset(x(44), y(190)), corps);
    canvas.drawLine(Offset(x(64), y(112)), Offset(x(66), y(190)), corps);

    // ── Ligne de mesure surlignée (pulsante) ──
    if (mesureId == null) return;
    final marque = Paint()
      ..color = _kPrimary.withOpacity(pulse)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void ellipse(double cy, double rx) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x(55), y(cy)), width: x(rx * 2), height: y(9)),
          marque);
    }

    switch (mesureId) {
      case 'tourCou':
        ellipse(33, 10);
        break;
      case 'largeurEpaule':
        canvas.drawLine(
            Offset(x(32), y(40)), Offset(x(78), y(40)), marque);
        break;
      case 'tourPoitrine':
        ellipse(58, 22);
        break;
      case 'tourTaille':
        ellipse(88, 17);
        break;
      case 'tourHanches':
        ellipse(106, 20);
        break;
      case 'tourBras':
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(x(27), y(58)),
                width: x(13),
                height: y(7)),
            marque);
        break;
      case 'longueurManche':
        canvas.drawLine(
            Offset(x(32), y(42)), Offset(x(22), y(92)), marque);
        break;
      case 'longueurDos':
        canvas.drawLine(
            Offset(x(55), y(42)), Offset(x(55), y(88)), marque);
        break;
      case 'hauteurTotal':
        canvas.drawLine(Offset(x(12), y(8)), Offset(x(12), y(190)), marque);
        break;
      case 'couCheville':
        canvas.drawLine(
            Offset(x(120), y(38)), Offset(x(120), y(178)), marque);
        break;
      case 'longueurJupe':
        canvas.drawLine(
            Offset(x(96), y(88)), Offset(x(96), y(165)), marque);
        break;
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.mesureId != mesureId || old.pulse != pulse;
}
