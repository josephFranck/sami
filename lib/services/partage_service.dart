import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTAGE VIRAL — « WhatsApp fait le marketing, SAMI capte la transaction »
//
// Chaque fiche (pagne, boutique, modèle) se partage en un tap : image + texte
// vendeur + lien qui OUVRE L'APP sur la fiche (ou la page de téléchargement
// si l'app n'est pas installée). Le boutiquier diffuse dans ses groupes
// WhatsApp — mais l'achat, la garantie et la livraison passent par SAMI.
//
// ⚠️ Lien profond : le domaine ci-dessous doit être servi (Firebase Hosting
// du projet) et déclaré dans AndroidManifest (voir INSTALLATION.md §liens).
// ═══════════════════════════════════════════════════════════════════════════

class PartageService {
  /// Domaine public des liens partagés (Firebase Hosting du projet).
  static const String domaine = 'https://sami-c564c.web.app';

  static String lienPagne(String id) => '$domaine/p/$id';
  static String lienBoutique(String id) => '$domaine/b/$id';
  static String lienModele(String id) => '$domaine/m/$id';

  /// Partage un pagne : image + accroche + prix (barré si promo) + lien.
  static Future<void> partagerPagne(Pagne p) async {
    final promo = p.prixBarre != null && p.prixBarre! > p.prixParBoutique;
    final texte = StringBuffer()
      ..writeln('🧵 ${p.nom}')
      ..writeln(promo
          ? '💥 ${PrixFCFA.formater(p.prixParBoutique)} au lieu de '
              '${PrixFCFA.formater(p.prixBarre!)} !'
          : '💰 ${PrixFCFA.formater(p.prixParBoutique)}')
      ..writeln('✅ Authentique · 🚚 Livraison à Garoua · 💳 Payez à la réception')
      ..writeln('')
      ..writeln('👉 Commandez sur SAMI : ${lienPagne(p.id)}');

    final image = p.images.isNotEmpty ? await _versFichier(p.images.first) : null;
    if (image != null) {
      await Share.shareXFiles([XFile(image.path)], text: texte.toString());
    } else {
      await Share.share(texte.toString());
    }
  }

  /// Partage une boutique (catalogue complet).
  static Future<void> partagerBoutique({
    required String id,
    required String nom,
    String? logo,
  }) async {
    final texte = '🏬 Découvrez la boutique $nom sur SAMI\n'
        '🧵 Pagnes authentiques · 🚚 Livraison · ✂️ Couture sur mesure\n\n'
        '👉 ${lienBoutique(id)}';
    final image = logo != null && logo.isNotEmpty ? await _versFichier(logo) : null;
    if (image != null) {
      await Share.shareXFiles([XFile(image.path)], text: texte);
    } else {
      await Share.share(texte);
    }
  }

  /// Convertit une source d'image (data URI base64 ou URL) en fichier
  /// temporaire partageable. Retourne null si impossible (on partage le
  /// texte seul — le lien fera l'aperçu).
  static Future<File?> _versFichier(String source) async {
    if (kIsWeb) return null; // web : partage texte+lien (aperçu via le lien)
    try {
      if (source.startsWith('data:image')) {
        final b64 = source.substring(source.indexOf(',') + 1);
        final bytes = base64Decode(b64);
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/partage_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(bytes);
        return f;
      }
      // URL réseau (Cloudflare R2, Firebase Storage…) : on TÉLÉCHARGE
      // l'image pour la joindre — sinon le partage part sans photo.
      if (source.startsWith('http')) {
        final rep = await http.get(Uri.parse(source));
        if (rep.statusCode == 200) {
          final dir = await getTemporaryDirectory();
          final f = File(
              '${dir.path}/partage_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await f.writeAsBytes(rep.bodyBytes);
          return f;
        }
      }
    } catch (_) {}
    return null;
  }
}
