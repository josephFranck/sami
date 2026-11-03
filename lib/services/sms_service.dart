import 'package:flutter/foundation.dart';
import 'package:sami/utils/config_paiement.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE SMS (secours)
//
// Envoie un code court (6 chiffres) au client par SMS, en SECOURS du QR affiché
// dans l'app. Le SMS a un COÛT réel (~15-40 FCFA/envoi) → il ne doit PAS être
// le canal principal :
//   - Le code est D'ABORD visible dans l'app (gratuit).
//   - Le SMS n'est envoyé que sur demande explicite (bouton "Recevoir par SMS")
//     ou si configuré pour les cas critiques.
//
// ⚠️ DÉSACTIVÉ PAR DÉFAUT (smsActif = false) : en dev, les SMS sont SIMULÉS
//    (loggés, pas envoyés) → zéro frais. Pour activer : créer un compte chez un
//    fournisseur SMS (Twilio, ou agrégateur local Cameroun), renseigner les
//    clés et passer smsActif à true.
// ═══════════════════════════════════════════════════════════════════════════

class SmsConfig {
  // Interrupteur : false = simulé (aucun SMS réel, aucun frais)
  static const bool smsActif = false;

  // Fournisseur SMS — à renseigner en production
  // Ex Twilio : accountSid + authToken + numéro expéditeur
  static const String fournisseur = 'A_RENSEIGNER'; // 'twilio' | 'autre'
  static const String apiKey = 'A_RENSEIGNER';
  static const String expediteur = 'SAMI';

  // Endpoint de la Cloud Function qui envoie réellement le SMS (sécurité :
  // ne jamais mettre les clés SMS dans l'app — passer par le serveur).
  static const String webhookEnvoiSms =
      'https://A-RENSEIGNER.cloudfunctions.net/envoyerSms';
}

class SmsService {
  /// Envoie un code de livraison par SMS (ou le simule si désactivé).
  /// Retourne true si "envoyé" (ou simulé avec succès).
  static Future<bool> envoyerCodeLivraison({
    required String telephone,
    required String code,
    String? nomBoutique,
  }) async {
    final message =
        'SAMI : votre code de réception est $code. Présentez-le au livreur '
        '${nomBoutique != null ? "pour votre commande $nomBoutique" : ""}.';

    // MODE SIMULÉ (dev) : on logge, aucun frais
    if (!SmsConfig.smsActif) {
      if (kDebugMode) {
        print('[SMS SIMULÉ] → $telephone : $message');
      }
      return true;
    }

    // MODE RÉEL : appeler la Cloud Function d'envoi (qui détient les clés SMS)
    try {
      // Implémentation réelle à brancher selon le fournisseur retenu.
      // Recommandé : POST vers SmsConfig.webhookEnvoiSms avec {telephone, message}
      // La Cloud Function appelle Twilio/agrégateur et facture l'envoi.
      //
      // final res = await http.post(Uri.parse(SmsConfig.webhookEnvoiSms),
      //     body: jsonEncode({'telephone': telephone, 'message': message}));
      // return res.statusCode == 200;
      if (kDebugMode) {
        print('[SMS] Envoi réel non encore branché — voir SmsConfig');
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('[SMS] Erreur envoi: $e');
      return false;
    }
  }

  /// Le SMS est-il disponible (configuré et activé) ?
  static bool get disponible =>
      SmsConfig.smsActif && SmsConfig.apiKey != 'A_RENSEIGNER';
}
