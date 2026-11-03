import 'package:cloud_firestore/cloud_firestore.dart';
// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION DES PAIEMENTS — SAMI
//
// ⚠️  C'EST LE SEUL ENDROIT où renseigner les clés de paiement.
//
// ⚠️  SÉCURITÉ : en production, ces clés ne devraient PAS être dans l'app
//     mobile (elles sont visibles par décompilation). L'idéal est de faire
//     transiter l'initiation du paiement par une Cloud Function / serveur
//     qui détient les clés. Voir GUIDE_PAIEMENT.md.
//     Pour le développement et les tests, les mettre ici est acceptable.
//
// ÉTAPES POUR ACTIVER LES VRAIS PAIEMENTS :
//   1. Choisir un fournisseur (Monetbil recommandé pour le Cameroun, ou CinetPay)
//   2. Créer un compte marchand et obtenir les clés (voir GUIDE_PAIEMENT.md)
//   3. Renseigner les clés ci-dessous
//   4. Déployer la Cloud Function webhook (voir GUIDE_PAIEMENT.md)
//   5. Mettre webhookUrlXXX sur l'URL de votre Cloud Function déployée
//   6. Passer `modeTest` à false
//   7. Mettre `paiementsActifs` à true
// ═══════════════════════════════════════════════════════════════════════════

class ConfigPaiement {
  // ══════════════════════════════════════════════════════════════════════
  // ACTIVATION SIMPLE (sans republier l'app) :
  // Paramètres admin → section PAIEMENT → interrupteur + clés.
  // Tout est lu depuis Firestore `app_config/paiement` ; les constantes
  // ci-dessous ne servent que de valeurs de repli.
  // ══════════════════════════════════════════════════════════════════════
  static Map<String, dynamic> _dyn = {};
  static DateTime? _chargeA;

  static Future<void> chargerDepuisFirestore() async {
    if (_chargeA != null &&
        DateTime.now().difference(_chargeA!).inMinutes < 5) return;
    try {
      final d = await FirebaseFirestore.instance
          .collection('app_config').doc('paiement').get();
      _dyn = d.data() ?? {};
      _chargeA = DateTime.now();
    } catch (_) {}
  }

  static void invaliderCache() => _chargeA = null;

  /// Paiements Mobile Money RÉELS actifs ? (l'interrupteur de l'admin)
  static Future<bool> actifs() async {
    await chargerDepuisFirestore();
    return (_dyn['actif'] as bool? ?? false)
        // GARDE : sans webhook déployé, la confirmation n'arriverait
        // JAMAIS (le client paierait dans le vide). Le système reste
        // en mode pilote tant que l'URL du worker n'est pas renseignée.
        && ((_dyn['monetbilWebhookUrl'] as String?) ?? '').startsWith('http');
  }

  static Future<String> fournisseur() async {
    await chargerDepuisFirestore();
    return _dyn['fournisseur'] as String? ?? fournisseurParDefaut;
  }

  static Future<String> cleMonetbil() async {
    await chargerDepuisFirestore();
    final v = _dyn['monetbilServiceKey'] as String? ?? '';
    return v.isNotEmpty ? v : monetbilServiceKey;
  }

  static Future<String> cleCinetPayApi() async {
    await chargerDepuisFirestore();
    final v = _dyn['cinetpayApiKey'] as String? ?? '';
    return v.isNotEmpty ? v : cinetpayApiKey;
  }

  static Future<String> cinetPaySiteIdDyn() async {
    await chargerDepuisFirestore();
    final v = _dyn['cinetpaySiteId'] as String? ?? '';
    return v.isNotEmpty ? v : cinetpaySiteId;
  }

  // ── INTERRUPTEUR GLOBAL ──────────────────────────────────────────────────
  // false = paiements SIMULÉS (dev/test, aucun argent réel ne circule)
  // true  = paiements RÉELS (nécessite clés + webhook configurés)
  static const bool paiementsActifs = false;

  // Mode test (sandbox) des fournisseurs. true tant qu'on n'est pas en prod.
  static const bool modeTest = true;

  // Fournisseur par défaut : 'monetbil' ou 'cinetpay'
  static const String fournisseurParDefaut = 'monetbil';

  // ── MONETBIL (recommandé Cameroun) ───────────────────────────────────────
  // Compte : https://www.monetbil.com → Dashboard → Service Key
  static const String monetbilServiceKey = 'A_RENSEIGNER';
  static const String monetbilWebhookUrl =
      'https://A-RENSEIGNER.cloudfunctions.net/webhookMonetbil';

  // ── CINETPAY ─────────────────────────────────────────────────────────────
  // Compte : https://cinetpay.com → Back-office → menu Intégration
  static const String cinetpayApiKey = 'A_RENSEIGNER';
  static const String cinetpaySiteId = 'A_RENSEIGNER';
  static const String cinetpayWebhookUrl =
      'https://A-RENSEIGNER.cloudfunctions.net/webhookCinetPay';

  // ── URLs DE RETOUR (deep links / pages de l'app) ─────────────────────────
  static const String returnUrl = 'https://sami.app/paiement/retour';
  static const String cancelUrl = 'https://sami.app/paiement/annule';

  // ── Devise & pays (Cameroun) ─────────────────────────────────────────────
  static const String devise = 'XAF';        // Franc CFA Afrique centrale
  static const String paysIso = 'CM';

  // ── Frais de transaction Mobile Money (à VÉRIFIER avec le fournisseur) ───
  // Sert au calcul du prix dans PrixFCFA. Mettre le VRAI taux du contrat.
  static const double tauxFraisMobileMoney = 2.5; // %

  // Helper : les paiements réels sont-ils prêts à l'emploi ?
  static bool get pretPourProduction =>
      paiementsActifs &&
      monetbilServiceKey != 'A_RENSEIGNER' &&
      !monetbilWebhookUrl.contains('A-RENSEIGNER');

  // ── Les 4 valeurs de `methodePaiement` écrites dans `sessions_commande`
  //    (panierpage.dart) et leur libellé client. 'interne' = écritures
  //    comptables (remboursements, commissions), jamais choisi par un client.
  static String libelleMethode(String? methode) => switch (methode) {
        'cash' => 'Espèces à la livraison',
        'mobile_money' => 'Mobile Money',
        'momo_declare' => 'Transfert MoMo/OM déclaré',
        'credits' => 'Avoirs (crédits)',
        'interne' => 'Écriture interne',
        _ => methode ?? '—',
      };
}
