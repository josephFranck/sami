import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MISE À JOUR FORCÉE
//
// L'admin règle une version MINIMALE dans Firestore (app_config/version,
// éditable depuis le Tableau de bord admin). Au démarrage, l'app compare sa
// version locale : si elle est plus ancienne, un dialogue BLOQUANT invite à
// mettre à jour (lien Play Store / APK).
//
// ⚠️ À CHAQUE RELEASE : incrémenter `versionApp` ci-dessous ET la version
//    dans pubspec.yaml. C'est ce numéro qui est comparé.
// ═══════════════════════════════════════════════════════════════════════════

class VersionService {
  /// Version de CETTE build de l'app (à incrémenter à chaque release).
  static const String versionApp = '1.0.0';

  /// Compare deux versions "x.y.z". Retourne true si a < b.
  static bool _plusAncienne(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va < vb;
    }
    return false;
  }

  /// Vérifie la version au démarrage. Si trop ancienne → dialogue BLOQUANT
  /// (non fermable) avec le lien de mise à jour.
  static Future<void> verifierAuDemarrage(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();
      final min = doc.data()?['versionMin'] as String?;
      final url = doc.data()?['urlMiseAJour'] as String? ?? '';
      if (min == null || min.isEmpty) return;
      if (!_plusAncienne(versionApp, min)) return; // à jour

      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false, // BLOQUANT
        builder: (ctx) => PopScope(
          canPop: false, // impossible de fermer avec "retour"
          child: AlertDialog(
            title: const Text('Mise à jour requise'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Une nouvelle version de SAMI est disponible et '
                    'obligatoire pour continuer.'),
                const SizedBox(height: 8),
                Text('Votre version : $versionApp\nVersion requise : $min',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                if (url.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(url,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6A1B9A))),
                  const SizedBox(height: 4),
                  const Text(
                      'Copiez ce lien dans votre navigateur pour télécharger '
                      'la mise à jour.',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      // Pas de réseau / pas de config → on laisse passer (ne jamais bloquer
      // l'app à cause d'une erreur de lecture).
    }
  }
}
