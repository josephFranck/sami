import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';

/// VISIONNEUSE PLEIN ÉCRAN : fond noir, zoom/pincement (InteractiveViewer),
/// balayage image suivante/précédente, compteur, fermeture.
class GaleriePleinEcran extends StatefulWidget {
  final List<String> images;
  final int indexInitial;
  const GaleriePleinEcran(
      {super.key, required this.images, this.indexInitial = 0});

  @override
  State<GaleriePleinEcran> createState() => _GaleriePleinEcranState();
}

class _GaleriePleinEcranState extends State<GaleriePleinEcran> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.indexInitial;
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: ImageUniverselle(
                  source: widget.images[i], fit: BoxFit.contain),
            ),
          ),
        ),
        // Fermer
        Positioned(
          top: 40, right: 12,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        // Compteur + flèches
        if (widget.images.length > 1) ...[
          Positioned(
            bottom: 34, left: 0, right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_index + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          if (_index > 0)
            Positioned(
              left: 4, top: 0, bottom: 0,
              child: IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Colors.white54, size: 36),
                onPressed: () => _ctrl.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
              ),
            ),
          if (_index < widget.images.length - 1)
            Positioned(
              right: 4, top: 0, bottom: 0,
              child: IconButton(
                icon: const Icon(Icons.chevron_right,
                    color: Colors.white54, size: 36),
                onPressed: () => _ctrl.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
              ),
            ),
        ],
      ]),
    );
  }
}
