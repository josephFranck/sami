import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/l10n/tr.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// SCANS VÉRIFIÉS CÔTÉ SERVEUR (lot C) — appels aux Cloud Functions.
///
/// Actif quand `app_config/parametres.scansServeur == true` (le serveur
/// détient la clé HMAC ; l'app n'en génère plus). Sinon l'app garde son
/// flux local (clé partagée) : les deux coexistent, l'interrupteur se
/// bascule depuis la console sans republier.
/// ═══════════════════════════════════════════════════════════════════════
class ResultatScanServeur {
  final bool ok;
  final bool deja; // déjà validé (rejeu) — pas une erreur
  final String message;
  const ResultatScanServeur({required this.ok, this.deja = false, required this.message});
}

class ScanServeurService {
  static const String region = 'europe-west1';
  static FirebaseFunctions get _f => FirebaseFunctions.instanceFor(region: region);

  static Future<bool> actif() => ParametresService.scansServeur();

  /// Scan de départ (boutique) ou d'arrivée (client) par le livreur.
  /// `code` = contenu du QR scanné ; `codeCourt` = 6 chiffres dictés (secours).
  static Future<ResultatScanServeur> validerScan({
    required String livraisonId,
    required TypeQR type,
    String? code,
    String? codeCourt,
    double? lat,
    double? lng,
    String? photoUrl,
    double? montantCash,
  }) async {
    try {
      final r = await _f.httpsCallable('validerScan').call<Map<String, dynamic>>({
        'livraisonId': livraisonId,
        'type': type.name,
        if (code != null && code.isNotEmpty) 'code': code,
        if (codeCourt != null && codeCourt.isNotEmpty) 'codeCourt': codeCourt,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (montantCash != null) 'montantCash': montantCash,
      });
      final d = Map<String, dynamic>.from(r.data);
      return ResultatScanServeur(
        ok: d['ok'] == true,
        deja: d['deja'] == true,
        message: type == TypeQR.depart ? Tr.s.priseChargeConfirmee : Tr.s.livraisonConfirmee2,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) print('[ScanServeur] ${e.code}: ${e.message}');
      return ResultatScanServeur(ok: false, message: e.message ?? Tr.s.validationRefusee(e.code));
    } catch (e) {
      return ResultatScanServeur(ok: false, message: Tr.s.serveurInjoignableVerifiezConnexion(e));
    }
  }

  static Future<String?> ajouterSignature({
    required String livraisonId,
    required String signatureBase64,
  }) async {
    try {
      await _f.httpsCallable('ajouterSignature').call({
        'livraisonId': livraisonId,
        'signatureBase64': signatureBase64,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Serveur injoignable ($e)';
    }
  }

  static Future<Map<String, dynamic>?> creerRecu({
    required String type,
    required String refId,
    required String beneficiaireId,
    required String beneficiaireNom,
    required double montant,
    required String detail,
    String? contrepartie,
  }) async {
    try {
      final r = await _f.httpsCallable('creerRecu').call<Map<String, dynamic>>({
        'type': type,
        'refId': refId,
        'beneficiaireId': beneficiaireId,
        'beneficiaireNom': beneficiaireNom,
        'montant': montant,
        'detail': detail,
        if (contrepartie != null) 'contrepartie': contrepartie,
      });
      return Map<String, dynamic>.from(r.data);
    } catch (e) {
      if (kDebugMode) print('[ScanServeur] creerRecu: $e');
      return null;
    }
  }

  /// (authentique, contenu) — même forme que RecuService.verifier.
  static Future<(bool, Map<String, dynamic>?)> verifierRecu(String qr) async {
    try {
      final r = await _f.httpsCallable('verifierRecu').call<Map<String, dynamic>>({'qr': qr});
      final d = Map<String, dynamic>.from(r.data);
      final contenu = d['contenu'];
      return (d['valide'] == true, contenu is Map ? Map<String, dynamic>.from(contenu) : null);
    } catch (_) {
      return (false, null);
    }
  }
}
