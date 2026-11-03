import 'package:cloud_firestore/cloud_firestore.dart';

/// PARAMÈTRES DE LA PLATEFORME — configurables par l'admin (app_config/parametres).
/// Chaque valeur a un défaut sûr : l'app fonctionne même sans configuration.
class ParametresService {
  static Map<String, dynamic> _cache = {};
  static DateTime? _chargeA;

  static Future<Map<String, dynamic>> _charger() async {
    // cache 5 min pour éviter les lectures répétées
    if (_chargeA != null &&
        DateTime.now().difference(_chargeA!).inMinutes < 5) {
      return _cache;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('parametres')
          .get();
      _cache = doc.data() ?? {};
      _chargeA = DateTime.now();
    } catch (_) {}
    return _cache;
  }

  /// Les numéros de téléphone des partenaires sont-ils visibles par défaut ?
  /// false = stratégie anti-désintermédiation (contact via le chat SAMI).
  static Future<bool> contactsVisiblesParDefaut() async =>
      (await _charger())['contactsVisiblesParDefaut'] as bool? ?? false;

  /// Un abonnement PAYANT débloque-t-il l'affichage du numéro ? (premium)
  static Future<bool> abonnementDebloqueContact() async =>
      (await _charger())['abonnementDebloqueContact'] as bool? ?? true;

  /// Plafond d'encours cash par livreur (0 = désactivé).
  static Future<double> plafondCashLivreur() async =>
      ((await _charger())['plafondCashLivreur'] as num?)?.toDouble() ?? 25000;

  /// Supprimer la photo CNI après traitement de la candidature (conformité
  /// loi 2024/017 protection des données) ?
  static Future<bool> supprimerCNIApresTraitement() async =>
      (await _charger())['supprimerCNIApresTraitement'] as bool? ?? true;

  /// Photo du vêtement fini obligatoire avant le trajet retour ?
  static Future<bool> photoFinaleObligatoire() async =>
      (await _charger())['photoFinaleObligatoire'] as bool? ?? true;

  // ── FRAIS FINANCIERS (tous configurables sans republier l'app) ──

  /// Commission plateforme par défaut sur une vente (%, ex: 7.0).
  /// Espèces à la LIVRAISON autorisées ? (pilote : oui — coupable quand
  /// le Mobile Money devient la norme)
  /// Réserver le paiement À LA LIVRAISON aux clients fidèles ?
  /// (le refus à la porte est LE risque des marketplaces — la confiance
  /// se mérite par l'historique d'achats)
  static Future<bool> cashSelonFidelite() async =>
      (await _charger())['cashSelonFidelite'] as bool? ?? false;
  static Future<int> niveauMinCash() async =>
      ((await _charger())['niveauMinCash'] as num?)?.toInt() ?? 2;

  static Future<bool> cashLivraisonActif() async =>
      (await _charger())['cashLivraisonActif'] as bool? ?? true;

  static Future<double> commissionDefautPct() async =>
      ((await _charger())['commissionDefautPct'] as num?)?.toDouble() ?? 8.0;

  /// Frais Mobile Money ENTRANTS (%, encaissement client — répercutés).
  /// Frais d'UNE course de livraison (F CFA) — la couture en facture 2.
  /// Modifiable dans app_config/parametres → fraisLivraisonBase.
  /// Commission plateforme sur la CONFECTION (modèles des couturiers),
  /// pour les couturiers SANS abonnement (les abonnés ont leur taux dégressif).
  /// Critère du carrousel d'accueil :
  /// 'mixte' (équitable, défaut) | 'vedettes' | 'meilleursVentes' | 'recents'
  /// COMPRESSION DES IMAGES (modes R2/Firebase — le mode local garde ses
  /// plafonds serrés à cause de la limite Firestore de 1 Mo/document).
  /// Standard : bon rendu mobile. Abonné (HD) : quasi-original.
  static Future<int> imageQualitePct() async =>
      ((await _charger())['imageQualitePct'] as num?)?.toInt() ?? 60;
  static Future<int> imageLargeurMax() async =>
      ((await _charger())['imageLargeurMax'] as num?)?.toInt() ?? 800;
  static Future<int> imageQualiteAbonnePct() async =>
      ((await _charger())['imageQualiteAbonnePct'] as num?)?.toInt() ?? 82;
  static Future<int> imageLargeurAbonneMax() async =>
      ((await _charger())['imageLargeurAbonneMax'] as num?)?.toInt() ?? 1280;

  /// Prix barré AUTOMATIQUE quand le boutiquier n'en a pas mis :
  /// +X % fictif affiché barré (0 = désactivé). Marketing d'ancrage —
  /// à utiliser avec mesure : les clients comparent les prix au marché.
  static Future<double> prixBarreAutoPct() async =>
      ((await _charger())['prixBarreAutoPct'] as num?)?.toDouble() ?? 0;
  static double prixBarreAutoCache = 0; // lu au chargement accueil

  static Future<String> carouselMode() async =>
      (await _charger())['carouselMode'] as String? ?? 'mixte';

  static Future<double> commissionCouturePct() async =>
      ((await _charger())['commissionCouturePct'] as num?)?.toDouble() ?? 10.0;

  /// Part du LIVREUR sur chaque course (%) — l'étude commissions
  /// suggère 75 % au recrutement des premiers livreurs, 70 % en régime.
  /// Serveur d'itinéraires : OSRM public (démo) par défaut ; à
  /// remplacer par le vôtre (app_config/parametres → osrmUrl) à l'échelle.
  /// PARRAINAGE : désactivé par défaut — à allumer quand le pilote roule.
  /// PAIEMENT PAR TRANSFERT DÉCLARÉ : le client transfère sur VOS
  /// numéros MoMo/OM puis déclare la référence ; un agent vérifie
  /// contre le SMS avant que le boutiquier prépare. 0 % de frais,
  /// aucune approbation externe requise.
  static Future<bool> momoDeclareActif() async =>
      (await _charger())['momoDeclareActif'] as bool? ?? false;
  static Future<String> numeroMoMoMTN() async =>
      (await _charger())['numeroMoMoMTN'] as String? ?? '';
  static Future<String> numeroOM() async =>
      (await _charger())['numeroOM'] as String? ?? '';
  static Future<String> titulaireMoMo() async =>
      (await _charger())['titulaireMoMo'] as String? ?? '';

  static Future<bool> parrainageActif() async =>
      (await _charger())['parrainageActif'] as bool? ?? false;
  static Future<double> recompenseParrainF() async =>
      ((await _charger())['recompenseParrainF'] as num?)?.toDouble() ?? 1000;
  static Future<double> recompenseFilleulF() async =>
      ((await _charger())['recompenseFilleulF'] as num?)?.toDouble() ?? 500;

  static Future<String> osrmUrl() async =>
      (await _charger())['osrmUrl'] as String? ??
      'https://router.project-osrm.org';

  static Future<double> gainLivreurPct() async =>
      ((await _charger())['gainLivreurPct'] as num?)?.toDouble() ?? 70;

  /// PART LIVREUR ÉVOLUTIVE : base (admin) + fidélité-livreur (paliers
  /// de bonnes livraisons) + abonnement livreur — plafonnée.
  /// TOUT est paramétrable (seuils, bonus, plafond) depuis l'admin.
  /// Le détail est retourné pour l'AFFICHER (la motivation se voit).
  static Future<({double pct, double base, double bonusFidelite,
      double bonusAbo, int nbLivrees})> partLivreurEffective(
      String? livreurId) async {
    final p = await _charger();
    final base = (p['gainLivreurPct'] as num?)?.toDouble() ?? 70;
    final seuil1 = (p['livreurPalier1Seuil'] as num?)?.toInt() ?? 20;
    final bonus1 = (p['livreurPalier1Bonus'] as num?)?.toDouble() ?? 2;
    final seuil2 = (p['livreurPalier2Seuil'] as num?)?.toInt() ?? 100;
    final bonus2 = (p['livreurPalier2Bonus'] as num?)?.toDouble() ?? 5;
    final bonusAboParam =
        (p['livreurBonusAbo'] as num?)?.toDouble() ?? 5;
    final plafond = (p['livreurPartMax'] as num?)?.toDouble() ?? 90;
    double bonusFid = 0, bonusAbo = 0;
    int nb = 0;
    if (livreurId != null && livreurId.isNotEmpty) {
      try {
        final f = await FirebaseFirestore.instance
            .collection('livreurs').doc(livreurId).get();
        final d = f.data() ?? {};
        // COMPTEUR INFALSIFIABLE : on compte les livraisons réellement
        // « livree » (validées par le code HMAC du client) au lieu de lire
        // un champ que l'appareil du livreur pourrait écrire lui-même.
        final q = await FirebaseFirestore.instance
            .collection('livraisons')
            .where('livreurId', isEqualTo: livreurId)
            .limit(1000)
            .get();
        nb = q.docs
            .where((x) => ['livree', 'livre'].contains(x.data()['statut']))
            .length;
        // Paliers fidélité-livreur (le plus haut atteint s'applique)
        if (nb >= seuil2) {
          bonusFid = bonus2;
        } else if (nb >= seuil1) {
          bonusFid = bonus1;
        }
        // Abonnement livreur (optionnel, expirable)
        final abo = d['abonnementLivreur'];
        final finLe = d['abonnementFinLe'];
        final aboActif = (abo == true ||
                (abo is String && abo.isNotEmpty && abo != 'aucun')) &&
            !(finLe is Timestamp &&
                finLe.toDate().isBefore(DateTime.now()));
        if (aboActif) bonusAbo = bonusAboParam;
      } catch (_) {}
    }
    final pct = (base + bonusFid + bonusAbo).clamp(0, plafond).toDouble();
    return (pct: pct, base: base, bonusFidelite: bonusFid,
        bonusAbo: bonusAbo, nbLivrees: nb);
  }

  static Future<double> fraisLivraisonBase() async =>
      ((await _charger())['fraisLivraisonBase'] as num?)?.toDouble() ?? 600;

  /// ZONE DE LIVRAISON : au-delà de ce rayon (km, à vol d'oiseau depuis la
  /// boutique), un supplément s'ajoute au forfait. Décision du 03/11/2026 :
  /// forfait + supplément hors zone.
  static Future<double> rayonZoneKm() async =>
      ((await _charger())['rayonZoneKm'] as num?)?.toDouble() ?? 5;
  static Future<double> supplementHorsZone() async =>
      ((await _charger())['supplementHorsZone'] as num?)?.toDouble() ?? 300;

  // ── ACCÈS SYNCHRONES (valeur en cache, sinon défaut) ──
  // Pour les calculs d'affichage qui ne peuvent pas attendre (getters,
  // setState) : la fiche pagne et l'ajout de pagne lisent LE MÊME
  // paramètre que la facturation, au lieu de constantes codées en dur.
  static Future<void> precharger() => _charger();
  static double get commissionDefautPctSync =>
      (_cache['commissionDefautPct'] as num?)?.toDouble() ?? 8.0;
  static double get gainLivreurPctSync =>
      (_cache['gainLivreurPct'] as num?)?.toDouble() ?? 70;
  static double get fraisLivraisonBaseSync =>
      (_cache['fraisLivraisonBase'] as num?)?.toDouble() ?? 600;

  static Future<double> fraisMoMoPct() async =>
      ((await _charger())['fraisMoMoPct'] as num?)?.toDouble() ?? 2.5;

  /// Frais de RETRAIT/transfert SORTANT (%, payout vers partenaires).
  static Future<double> fraisRetraitPct() async =>
      ((await _charger())['fraisRetraitPct'] as num?)?.toDouble() ?? 1.0;

  /// Marge plateforme sur chaque livraison (FCFA).
  static Future<double> margeLivraison() async =>
      ((await _charger())['margeLivraison'] as num?)?.toDouble() ?? 150;

  static void invaliderCache() => _chargeA = null;
}

/// POLITIQUE D'AFFICHAGE DES CONTACTS (anti-désintermédiation + premium).
/// Un numéro s'affiche si : le paramètre global l'autorise, OU l'admin a
/// activé `contactVisible` sur l'entité, OU (option) l'entité a un
/// abonnement payant. Sinon → bouton « Contacter via SAMI » (chat interne).
class ContactPolicy {
  /// [entite] = data d'une boutique ou d'un couturier.
  static Future<bool> peutAfficher(Map<String, dynamic> entite) async {
    if (await ParametresService.contactsVisiblesParDefaut()) return true;
    if (entite['contactVisible'] == true) return true; // activé par l'admin
    if (await ParametresService.abonnementDebloqueContact()) {
      final abo = (entite['abonnement'] ?? entite['typeAbonnement']) as String?;
      if (abo != null && abo != 'gratuit') return true; // avantage premium
    }
    return false;
  }
}
