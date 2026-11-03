import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// IMAGE UNIVERSELLE
//
// Affiche correctement une image qu'elle soit :
//   - un data URI base64  ("data:image/jpeg;base64,...")  → mode local temporaire
//   - une URL réseau       ("https://...")                 → Firebase Storage / R2
//   - vide ou nulle                                        → placeholder
//
// Ainsi, quand on migrera du mode local (base64) vers Cloudflare R2,
// aucun widget d'affichage n'aura besoin d'être modifié.
// ═══════════════════════════════════════════════════════════════════════════

class ImageUniverselle extends StatelessWidget {
  final String? source;       // data URI base64, URL réseau, ou null
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final BorderRadius? borderRadius;

  const ImageUniverselle({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.borderRadius,
  });

  bool get _estBase64 => source != null && source!.startsWith('data:');
  bool get _estReseau => source != null &&
      (source!.startsWith('http://') || source!.startsWith('https://'));

  @override
  Widget build(BuildContext context) {
    Widget image;

    if (_estBase64) {
      // Décoder le data URI : "data:image/jpeg;base64,XXXX"
      try {
        final base64Part = source!.substring(source!.indexOf(',') + 1);
        final bytes = base64Decode(base64Part);
        image = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      } catch (_) {
        image = _buildPlaceholder();
      }
    } else if (_estReseau) {
      image = CachedNetworkImage(
        imageUrl: source!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _buildLoading(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    } else {
      image = _buildPlaceholder();
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _buildPlaceholder() =>
      placeholder ??
      Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_outlined,
            color: Colors.grey.shade400,
            size: (width != null && width! < 60) ? 20 : 40),
      );

  Widget _buildLoading() => Container(
        width: width,
        height: height,
        color: Colors.grey.shade100,
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6A1B9A)),
          ),
        ),
      );
}

/// Retourne un ImageProvider adapté (base64 ou réseau) pour les cas
/// où on a besoin d'un provider et non d'un widget :
///   - CircleAvatar(backgroundImage: ...)
///   - DecorationImage(image: ...)
/// Retourne null si la source est vide → l'appelant affiche un fallback.
ImageProvider? providerUniversel(String? source) {
  if (source == null || source.isEmpty) return null;
  if (source.startsWith('data:')) {
    try {
      final base64Part = source.substring(source.indexOf(',') + 1);
      return MemoryImage(base64Decode(base64Part));
    } catch (_) {
      return null;
    }
  }
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return CachedNetworkImageProvider(source);
  }
  return null;
}


/// Images BALAYABLES au doigt (mini-carrousel de carte).
/// Le tap traverse vers le parent (ouverture de la fiche) ; seul le
/// glissement horizontal feuillette les photos.
class ImagesBalayables extends StatelessWidget {
  final List<String> images;
  final Widget fallback;
  const ImagesBalayables(
      {super.key, required this.images, required this.fallback});

  @override
  Widget build(BuildContext context) => images.isEmpty
      ? fallback
      : images.length == 1
          ? ImageUniverselle(source: images.first, fit: BoxFit.cover)
          : PageView.builder(
              itemCount: images.length,
              itemBuilder: (_, i) => ImageUniverselle(
                  source: images[i], fit: BoxFit.cover),
            );
}
