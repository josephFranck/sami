import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/services/log_service.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/paiement_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/services/livraison_service.dart';
import 'package:sami/services/stock_service.dart';
import 'package:sami/models/strategies_marketing.dart';
import 'package:sami/services/commission_boutique_service.dart';
import 'package:sami/services/config_marketing_service.dart';
import 'package:sami/agents/agent_livraison.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE COMMANDES MULTI-BOUTIQUES
//
// Orchestrateur principal : transforme un panier multi-boutiques
// en sessions + sous-commandes + livraisons + transactions
// ═══════════════════════════════════════════════════════════════════════════

const _kCommissionDefault  = 6.0;    // %
const _kFraisLivraison     = 500.0;  // FCFA par livraison
const _kGainLivreur        = 350.0;  // FCFA par livraison
const _kFraisMMoney        = 2.5;    // % frais passerelle paiement

class CommandeMultiService {

  static final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // PASSER UNE COMMANDE MULTI-BOUTIQUES
  // ══════════════════════════════════════════════════════════════════════════

  /// Point d'entrée principal — transforme le panier en commandes
  static Future<SessionCommande> passerCommande({
    required Panier panier,
    required String clientId,
    required String adresseLivraison,
    required String methodePaiement,
    // Config livraison par boutique (le client choisit pour chaque boutique)
    required Map<String, ConfigLivraisonBoutique> configParBoutique,
    String? notesGenerales,
    String? numeroPaiement, // MoMo : le numéro qui paiera
    String? refPaiement,    // transaction Mobile Money confirmée (traçabilité)
    double? gpsClientLat,   // point posé sur la carte par le client
    double? gpsClientLng,
  }) async {
    // ═══ MONDE FIGÉ ═══ Copie défensive : le panier VIVANT peut être
    // vidé/modifié pendant nos await — itérer la référence partagée =
    // « Concurrent modification ». La commande travaille sur SA photo.
    final items = List<PanierItem>.of(panier.items);

    if (panier.estVide) throw Exception('Le panier est vide');

    // 1. Grouper les articles par boutique
    // COPIE DÉFENSIVE : items est la liste VIVANTE du singleton —
    // pendant les await qui suivent, ses listeners peuvent la modifier
    // → « Concurrent modification during iteration ». Instantané figé :
    final itemsSnapshot = List<PanierItem>.of(items);
    final groupes = _grouperParBoutique(itemsSnapshot);
    // ═══ GROUPES FIGÉS ═══ chaque sous-liste devient une COPIE
    // indépendante : plus aucune structure partagée/lazy dans le flux.
    final groupesFiges = <String, List<PanierItem>>{
      for (final e in groupesFiges.entries) e.key: List<PanierItem>.of(e.value)
    };
    if (kDebugMode) print('[CommandeMulti] ${groupesFiges.length} boutiques détectées');

    // 1bis. DÉCRÉMENT DU STOCK (atomique) — bloque si stock insuffisant
    final articlesStock = itemsSnapshot
        .map((it) => (pagneId: it.pagneId, quantite: it.quantite))
        .toList();
    final resultatStock = await StockService.confirmerStock(articles: articlesStock);
    if (!resultatStock.succes) {
      throw Exception(resultatStock.erreurs.join('\n'));
    }

    // 2. Déterminer le mode de facturation + franchise gratuite de chaque boutique
    final Map<String, bool> prepayeParBoutique = {};
    final Map<String, bool> gratuitParBoutique = {};
    for (final boutiqueId in groupesFiges.keys) {
      gratuitParBoutique[boutiqueId] =
          await CommissionBoutiqueService.enFranchiseGratuite(boutiqueId);
      // En franchise gratuite, on traite comme commission-sur-vente à 0%.
      prepayeParBoutique[boutiqueId] = gratuitParBoutique[boutiqueId]!
          ? false
          : await CommissionBoutiqueService.estPrepaye(boutiqueId);
    }

    // 3. Calculer les totaux (le net boutiquier dépend du mode)
    final decompositions = groupesFiges.map((boutiqueId, items) => MapEntry(
      boutiqueId,
      _calculerSousCommande(
        items: items,
        config: configParBoutique[boutiqueId] ?? ConfigLivraisonBoutique.defaut(adresseLivraison),
        methodePaiement: methodePaiement,
        prepaye: prepayeParBoutique[boutiqueId] ?? false,
        gratuit: gratuitParBoutique[boutiqueId] ?? false,
      ),
    ));

    final totalArticles = decompositions.values.fold<double>(0, (s, d) => s + d.sousTotal);
    final totalLivraisonsBrut = decompositions.values.fold<double>(0, (s, d) => s + d.fraisLivraison);
    final totalCommissions = decompositions.values.fold<double>(0, (s, d) => s + d.commission);

    // RÉDUCTION DE LIVRAISON SELON LE PALIER DE FIDÉLITÉ DU CLIENT
    // Le palier (configuré par l'admin) peut réduire les frais de livraison (0-100%).
    double reductionLivraisonPct = 0;
    try {
      final clientDoc = await _db.collection('utilisateurs').doc(clientId).get();
      final pointsClient = (clientDoc.data()?['pointsFidelite'] as num?)?.toInt() ?? 0;
      final config = await ConfigMarketingService.charger();
      PalierConfig palier = config.paliers.first;
      for (final p in config.paliers) {
        if (pointsClient >= p.pointsRequis) palier = p;
      }
      reductionLivraisonPct = palier.reductionLivraison.clamp(0, 100);
    } catch (_) {}

    final totalLivraisons = PrixFCFA.arrondirAu50(
        totalLivraisonsBrut * (1 - reductionLivraisonPct / 100));
    final totalFraisPaiement = methodePaiement == 'cash' ? 0.0
        : PrixFCFA.arrondirAu50((totalArticles + totalLivraisons) * _kFraisMMoney / 100);
    final totalPaye = PrixFCFA.arrondirSuperieur50(
        totalArticles + totalLivraisons + totalFraisPaiement);

    // 3. Écriture atomique Firestore (batch)
    final batch = _db.batch();

    // Session principale
    final sessionRef = SessionCommande.collection.doc();
    final sousCommandeIds = <String>[];

    // Créer chaque sous-commande
    final sousCommandes = <SousCommande>[];
    for (final entry in groupesFiges.entries) {
      final boutiqueId = entry.key;
      final items = entry.value;
      final decomp = decompositions[boutiqueId]!;
      final config = configParBoutique[boutiqueId] ?? ConfigLivraisonBoutique.defaut(adresseLivraison);

      final scRef = SousCommande.collection.doc();
      sousCommandeIds.add(scRef.id);

      // Générer les QR codes
      final qrDepart = _genererQR('DEP', scRef.id);
      final qrArrivee = _genererQR('ARR', scRef.id);

      // Récupérer nom de la boutique (depuis le 1er item)
      final boutiqueNom = items.first.boutiqueId ?? boutiqueId;

      // Créer les étapes de livraison selon la config
      final livraisons = _creerEtapesLivraison(
        sousCommandeId: scRef.id,
        config: config,
        adresseLivraison: adresseLivraison,
        avecCouture: items.any((i) => i.avecCouture),
        qrDepart: qrDepart,
        qrArrivee: qrArrivee,
        fraisLivraison: decomp.fraisLivraison,
      );

      final sc = SousCommande(
        id: scRef.id,
        sessionId: sessionRef.id,
        clientId: clientId,
        boutiqueId: boutiqueId,
        boutiqueNom: boutiqueNom,
        articles: items,
        couturierId: items.any((i) => i.couturierId != null)
            ? items.firstWhere((i) => i.couturierId != null).couturierId
            : null,
        statut: StatutSousCommande.enAttente,
        dateCreation: DateTime.now(),
        sousTotal: decomp.sousTotal,
        fraisLivraison: decomp.fraisLivraison,
        totalClient: decomp.totalClient,
        commissionPlateforme: decomp.commission,
        netBoutique: decomp.netBoutique,
        notesClient: notesGenerales,
      );

      batch.set(scRef, sc.toMap());
      sousCommandes.add(sc);

      // Écrire les livraisons en sous-collection
      for (final livraison in livraisons) {
        final livRef = EtapeLivraison.collection(scRef.id).doc(livraison.id);
        batch.set(livRef, {
          ...livraison.toMap(),
          // RÉSUMÉ ARTICLES : le livreur voit CE qu'il transporte
          // (miniature + nom) sans requête supplémentaire.
          'articles': items
              .map((it) => {
                    'nom': it.pagneNom,
                    'image': it.pagneImage,
                    'qte': it.quantite,
                  })
              .toList(),
        });
      }

      // Enregistrer la transaction financière
      final txRef = _db.collection('transactions').doc();
      batch.set(txRef, {
        'type': 'paiementCommande',
        'sessionId': sessionRef.id,
        'sousCommandeId': scRef.id,
        'boutiqueId': boutiqueId,
        'clientId': clientId,
        'montantBrut': decomp.totalClient,
        'montantNet': decomp.netBoutique,
        'commission': decomp.commission,
        'fraisLivraison': decomp.fraisLivraison,
        'gainLivreur': livraisons.fold<double>(0, (s, l) => s + l.gainLivreur),
        'methodePaiement': methodePaiement,
      if (numeroPaiement != null) 'numeroPaiement': numeroPaiement,
      if (refPaiement != null) 'refPaiement': refPaiement,
      // Transfert déclaré : la préparation ATTEND la vérification humaine
      if (methodePaiement == 'momo_declare') 'paiementVerifie': false,
      if (gpsClientLat != null) 'destLat': gpsClientLat,
      if (gpsClientLng != null) 'destLng': gpsClientLng,
        'statut': 'enAttente',
        'dateCreation': FieldValue.serverTimestamp(),
      });
    }

    // Session principale
    final session = SessionCommande(
      id: sessionRef.id,
      clientId: clientId,
      sousCommandeIds: sousCommandeIds,
      totalArticles: totalArticles,
      totalLivraisons: totalLivraisons,
      totalPayeClient: totalPaye,
      totalCommissions: totalCommissions,
      methodePaiement: methodePaiement,
      dateCreation: DateTime.now(),
      sousCommandes: sousCommandes,
    );

    batch.set(sessionRef, session.toMap());

    // Tout valider
    await batch.commit();

    // MODÈLE PRÉPAYÉ : débiter la commission du crédit boutiquier MAINTENANT
    // si son abonnement est en mode "commission d'avance". Sinon, le débit se
    // fera à la livraison confirmée (dans _declencherReversement).
    for (final sc in sousCommandes) {
      try {
        // Le débit du crédit ne concerne QUE les boutiques en mode prépayé.
        if (!await CommissionBoutiqueService.estPrepaye(sc.boutiqueId)) continue;
        final avance =
            await CommissionBoutiqueService.commissionEstAvance(sc.boutiqueId);
        if (avance) {
          await CommissionBoutiqueService.debiterCommission(
            boutiqueId: sc.boutiqueId,
            montantCommission: sc.commissionPlateforme,
            sousCommandeId: sc.id,
          );
        }
      } catch (e) {
        if (kDebugMode) print('[CommandeMulti] Débit commission avance échoué: $e');
      }
    }

    // Vider le panier
    // Le panier N'EST PLUS vidé ICI : vider la liste VIVANTE pendant
    // que la page peut l'itérer (rebuilds) = « Concurrent modification ».
    // La PAGE le vide après succès, à un instant où rien n'itère.

    await LogService.log('commande_creee', details: {
      'sessionId': sessionRef.id,
      'boutiques': groupesFiges.length,
      'methodePaiement': methodePaiement,
    });
    if (kDebugMode) print('[CommandeMulti] Session ${sessionRef.id} créée avec ${sousCommandeIds.length} sous-commandes');

    // 4. Créer une livraison RÉELLE par sous-commande + déclencher l'agent IA
    //    (assignation automatique du meilleur livreur)
    await _declencherLivraisons(
      sousCommandes: sousCommandes,
      configParBoutique: configParBoutique,
      adresseLivraison: adresseLivraison,
      methodePaiement: methodePaiement,
      gpsClientLat: gpsClientLat,
      gpsClientLng: gpsClientLng,
    );

    // NOTE : les points de fidélité + cashback sont crédités à la LIVRAISON
    //        confirmée (validerQRArrivee), pas ici, pour éviter qu'une commande
    //        annulée rapporte des avantages indus.

    return session..sousCommandes.addAll(sousCommandes);
  }

  /// Crée une Livraison par sous-commande et lance l'agent d'assignation.
  /// Coordonnées GPS par défaut = centre de Garoua (l'agent affine ensuite).
  static Future<void> _declencherLivraisons({
    required List<SousCommande> sousCommandes,
    required Map<String, ConfigLivraisonBoutique> configParBoutique,
    required String adresseLivraison,
    required String methodePaiement,
    double? gpsClientLat, // point posé sur la carte (prioritaire)
    double? gpsClientLng,
  }) async {
    // Centre de Garoua : fallback UNIQUEMENT si une coordonnée réelle manque
    const garouaLat = 9.3017;
    const garouaLng = 13.3984;

    // Récupérer les coordonnées GPS réelles du client (1 seule lecture)
    double clientLat = garouaLat, clientLng = garouaLng;
    try {
      final clientDoc = await _db.collection('utilisateurs')
          .doc(sousCommandes.first.clientId).get();
      final cd = clientDoc.data();
      if (cd != null) {
        clientLat = (cd['latitude'] as num?)?.toDouble() ?? garouaLat;
        clientLng = (cd['longitude'] as num?)?.toDouble() ?? garouaLng;
      }
    } catch (_) {}

    for (final sc in sousCommandes) {
      try {
        final avecCouture = sc.couturierId != null;
        // Cette sous-commande est-elle un retrait en boutique ?
        final config = configParBoutique[sc.boutiqueId];
        final estRetrait =
            config?.typeDestination == TypeDestination.retraitBoutique;

        // Coordonnées GPS réelles de la boutique (fallback Garoua si absentes)
        double boutiqueLat = garouaLat, boutiqueLng = garouaLng;
        try {
          final bDoc = await _db.collection('boutiques').doc(sc.boutiqueId).get();
          final bd = bDoc.data();
          if (bd != null) {
            boutiqueLat = (bd['latitude'] as num?)?.toDouble() ?? garouaLat;
            boutiqueLng = (bd['longitude'] as num?)?.toDouble() ?? garouaLng;
          }
        } catch (_) {}

        // NOTE : le flux COUTURE ne passe PAS par ici. Les commandes de
        // couture (pagne + confection + 2 trajets) sont entièrement gérées
        // par CoutureService.creerCommandesCouture. Ce service ne traite que
        // les ventes de pagnes classiques (livraison directe ou retrait).
        // Le point POSÉ SUR LA CARTE par le client prime sur sa position
        // de profil (précision du portail vs approximation du quartier).
        final destLat =
            estRetrait ? boutiqueLat : (gpsClientLat ?? clientLat);
        final destLng =
            estRetrait ? boutiqueLng : (gpsClientLng ?? clientLng);
        final destAdresse = estRetrait
            ? 'Retrait à la boutique ${sc.boutiqueNom}'
            : adresseLivraison;

        final livraison = await LivraisonService.creerLivraison(
          commandeId: sc.id,            // commandeId = ID sous-commande
          clientId: sc.clientId,
          boutiqueId: sc.boutiqueId,
          boutiqueNom: sc.boutiqueNom,
          origineLat: boutiqueLat,
          origineLng: boutiqueLng,
          origineAdresse: 'Boutique ${sc.boutiqueNom}, Garoua',
          destinationLat: destLat,
          destinationLng: destLng,
          destinationAdresse: destAdresse,
          destinationQuartier: adresseLivraison,
          prixClient: sc.totalClient,
          typeLivraison: avecCouture ? TypeLivraison.confection : TypeLivraison.pagne,
          modeRecuperation: estRetrait
              ? ModeRecuperation.retraitClient
              : ModeRecuperation.livreurVaBoutique,
          methodePaiement: methodePaiement,
        );

        if (estRetrait) {
          // RETRAIT : pas de livreur. La commande attend que le client
          // vienne chercher. On passe directement en 'pretRetrait'.
          await _db.collection('livraisons').doc(livraison.id).update({
            'statut': StatutLivraison.pretRetrait.name,
          });
        } else {
          // LIVRAISON : le livreur n'est PAS assigné maintenant — il le sera
          // quand la boutique marquera la commande « Prête » (sinon il
          // arriverait devant un colis pas encore préparé).
        }
        // Notifier la boutique : commande à préparer (clic → son tableau de bord)
        try {
          final bDoc = await _db.collection('boutiques').doc(sc.boutiqueId).get();
          final gs = List<String>.from(bDoc.data()?['gerants'] as List? ?? []);
          // TOUS les gérants (pas seulement le premier) — une boutique
          // à deux comptoirs a deux paires d'oreilles.
          for (final g in gs) {
            await NotificationService.envoyer(
              destinataireId: g,
              titre: 'Nouvelle commande à préparer 🛍️',
              message: '${sc.articles.length} article(s) — préparez le colis puis marquez « Prête » pour appeler un livreur.',
              route: '/dashboard_boutiquier',
              refId: sc.id,
            );
          }
        } catch (_) {}
        // Lien retour : la sous-commande connaît sa livraison (suivi client)
        await _db
            .collection('sous_commandes')
            .doc(sc.id)
            .update({'livraisonId': livraison.id});
      } catch (e) {
        if (kDebugMode) print('[CommandeMulti] Création livraison échouée sc=${sc.id}: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS SUR LES SOUS-COMMANDES
  // ══════════════════════════════════════════════════════════════════════════

  /// Boutiquier confirme sa sous-commande
  static Future<void> confirmerParBoutique(String sousCommandeId) async {
    await SousCommande.collection.doc(sousCommandeId).update({
      'statut': StatutSousCommande.confirmeeBoutique.name,
      'dateConfirmationBoutique': FieldValue.serverTimestamp(),
    });
  }

  /// Boutiquier marque la sous-commande comme prête pour enlèvement
  static Future<void> marquerPrete(String sousCommandeId) async {
    // GARDE : un transfert DÉCLARÉ non vérifié ne se prépare pas —
    // sinon un faux screenshot ferait partir un colis.
    final scDoc = await SousCommande.collection.doc(sousCommandeId).get();
    final sessId = scDoc.data()?['sessionId'] as String?;
    if (sessId != null) {
      final sess = await FirebaseFirestore.instance
          .collection('sessions_commande').doc(sessId).get();
      final d = sess.data();
      if (d?['methodePaiement'] == 'momo_declare' &&
          d?['paiementVerifie'] != true) {
        throw Exception(
            'Paiement par transfert en cours de vérification — '
            'préparation possible dès validation par l\'équipe.');
      }
    }

    await SousCommande.collection.doc(sousCommandeId).update({
      'statut': StatutSousCommande.prete.name,
    });
    // MAINTENANT que le colis est prêt : assigner un livreur (hors retrait).
    try {
      final q = await _db
          .collection('livraisons')
          .where('commandeId', isEqualTo: sousCommandeId)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final l = q.docs.first;
        final statut = l.data()['statut'] as String?;
        if (statut != StatutLivraison.pretRetrait.name) {
          AgentLivraison.traiterNouvelleLivraison(l.id).catchError((e) {
            if (kDebugMode) print('[CommandeMulti] Agent (prete) erreur: $e');
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('[CommandeMulti] marquerPrete/agent: $e');
    }
  }

  /// Livreur scanne le QR de départ (confirmation prise en charge)
  static Future<bool> validerQRDepart({
    required String sousCommandeId,
    required String livraisonId,
    required String qrScanne,
    required String livreurId,
  }) async {
    final livraisonDoc = await EtapeLivraison.collection(sousCommandeId).doc(livraisonId).get();
    if (!livraisonDoc.exists) return false;
    final livraison = EtapeLivraison.fromDoc(livraisonDoc);
    if (livraison.qrDepart != qrScanne) return false;

    final batch = _db.batch();
    batch.update(EtapeLivraison.collection(sousCommandeId).doc(livraisonId), {
      'statut': 'enCours',
      'livreurId': livreurId,
      'datePrisEnCharge': FieldValue.serverTimestamp(),
    });
    batch.update(SousCommande.collection.doc(sousCommandeId), {
      'statut': StatutSousCommande.enCoursLivraison.name,
    });
    await batch.commit();
    return true;
  }

  /// Destinataire scanne le QR d'arrivée (confirmation réception)
  static Future<bool> validerQRArrivee({
    required String sousCommandeId,
    required String livraisonId,
    required String qrScanne,
  }) async {
    final livraisonDoc = await EtapeLivraison.collection(sousCommandeId).doc(livraisonId).get();
    if (!livraisonDoc.exists) return false;
    final livraison = EtapeLivraison.fromDoc(livraisonDoc);
    if (livraison.qrArrivee != qrScanne) return false;

    // Vérifier si c'est la dernière livraison ou une livraison intermédiaire
    final toutesLivraisons = await EtapeLivraison.collection(sousCommandeId)
        .orderBy('ordre').get();

    final estDernier = livraison.ordre == toutesLivraisons.docs.length;

    final batch = _db.batch();
    batch.update(EtapeLivraison.collection(sousCommandeId).doc(livraisonId), {
      'statut': 'livree',
      'dateLivraison': FieldValue.serverTimestamp(),
    });

    if (estDernier) {
      // Dernière livraison → sous-commande terminée
      batch.update(SousCommande.collection.doc(sousCommandeId), {
        'statut': StatutSousCommande.terminee.name,
        'dateTerminaison': FieldValue.serverTimestamp(),
      });
      // Déclencher le reversement au boutiquier
      await _declencherReversement(sousCommandeId);

      // Créditer points + cashback au client MAINTENANT (livraison confirmée)
      try {
        final scDoc = await SousCommande.collection.doc(sousCommandeId).get();
        final scData = scDoc.data();
        if (scData != null) {
          final clientId = scData['clientId'] as String?;
          final totalClient = (scData['totalClient'] as num?)?.toDouble() ?? 0;
          if (clientId != null && totalClient > 0) {
            await StrategiesMarketingService.crediterPointsFidelite(
              utilisateurId: clientId,
              montantAchat: totalClient,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) print('[CommandeMulti] Crédit fidélité échoué: $e');
      }
    } else {
      // Livraison intermédiaire (pagne chez couturier)
      batch.update(SousCommande.collection.doc(sousCommandeId), {
        'statut': StatutSousCommande.avecCouturier.name,
      });
    }

    await batch.commit();

    // Mettre à jour le statut de la session parente
    await _mettreAJourStatutSession(sousCommandeId);

    return true;
  }

  /// Couturier marque la couture terminée (déclenche la livraison finale)
  static Future<void> coutureTerminee(String sousCommandeId) async {
    final batch = _db.batch();
    batch.update(SousCommande.collection.doc(sousCommandeId), {
      'statut': StatutSousCommande.costurierTermine.name,
    });
    // La livraison finale sera assignée à un livreur
    await batch.commit();
  }

  /// Annuler une sous-commande (avant confirmation boutique)
  static Future<void> annuler(String sousCommandeId, {String? raison}) async {
    await LogService.log('commande_annulation_demandee', details: {'sousCommandeId': sousCommandeId, 'raison': raison});
    final sc = await SousCommande.collection.doc(sousCommandeId).get();
    final statut = StatutSousCommande.values.firstWhere(
        (e) => e.name == (sc.data()?['statut'] as String? ?? 'enAttente'),
        orElse: () => StatutSousCommande.values.first);

    if (statut != StatutSousCommande.enAttente) {
      throw Exception('Impossible d\'annuler : déjà confirmée par la boutique');
    }

    // LIBÉRER LE STOCK (sinon la réservation reste fantôme à vie) et
    // DÉCOMPTER la vente (sinon les annulations gonflent le classement
    // « meilleures ventes » du carrousel).
    for (final a in List.from(sc.data()?['articles'] as List? ?? [])) {
      final art = a as Map;
      final q = (art['quantite'] as num?)?.toInt() ?? 1;
      try {
        await FirebaseFirestore.instance
            .collection('pagnes')
            .doc(art['pagneId'] as String? ?? '')
            .update({
          'quantiteReservee': FieldValue.increment(-q),
          'quantiteDisponible': FieldValue.increment(q),
          'nombreVentes': FieldValue.increment(-q),
        });
      } catch (_) {} // pagne supprimé entre-temps : rien à libérer
    }
    // ═══ REMBOURSEMENT ═══ La part de CETTE sous-commande est rendue :
    // payée en CRÉDITS → re-créditée automatiquement ; en Mobile Money →
    // marquée « à rembourser » (traçable au dashboard, geste manuel MoMo).
    try {
      final scData = sc.data() ?? {};
      final sessionId = scData['sessionId'] as String?;
      final part = (scData['totalClient'] as num?)?.toDouble() ?? 0;
      final clientId = scData['clientId'] as String?;
      if (sessionId != null && part > 0 && clientId != null) {
        final session = await FirebaseFirestore.instance
            .collection('sessions_commande').doc(sessionId).get();
        final methode = session.data()?['methodePaiement'] as String?;
        final refPaiement = session.data()?['refPaiement'] as String?;
        // Crédits COMME Mobile Money : via la file de remboursements —
        // le client ne peut pas s'auto-créditer (règle anti-fraude), donc
        // le staff valide d'un geste et tout est tracé.
        if (methode == 'credits' ||
            refPaiement == 'CREDITS' ||
            (methode == 'mobile_money' && refPaiement != null)) {
          await FirebaseFirestore.instance
              .collection('remboursements_a_faire')
              .add({
            'clientId': clientId,
            'montant': part,
            'refPaiement': refPaiement ?? 'CREDITS',
            'type': (methode == 'credits' || refPaiement == 'CREDITS')
                ? 'credits'
                : 'mobile_money',
            'sousCommandeId': sousCommandeId,
            'statut': 'a_traiter',
            'dateCreation': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {}
    await SousCommande.collection.doc(sousCommandeId).update({
      'statut': StatutSousCommande.annulee.name,
      'notesBoutique': raison,
    });
    // La livraison liée est annulée aussi (ne pas envoyer un livreur
    // sur une commande annulée) — sauf si déjà livrée.
    try {
      final q = await _db
          .collection('livraisons')
          .where('commandeId', isEqualTo: sousCommandeId)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final st = q.docs.first.data()['statut'] as String?;
        if (st != StatutLivraison.livre.name) {
          await q.docs.first.reference
              .update({'statut': StatutLivraison.annule.name});
        }
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LECTURES — VUES PAR RÔLE
  // ══════════════════════════════════════════════════════════════════════════

  /// Vue client : ses sessions avec le statut agrégé
  static Stream<List<SessionCommande>> sessionsClient(String clientId) =>
      SessionCommande.streamParClient(clientId);

  /// Vue boutiquier : ses sous-commandes à traiter
  static Stream<List<SousCommande>> sousCommandesBoutique(String boutiqueId) =>
      SousCommande.streamParBoutique(boutiqueId);

  /// Charger une session avec toutes ses sous-commandes
  static Future<SessionCommande> chargerSession(String sessionId) async {
    final sessionDoc = await SessionCommande.collection.doc(sessionId).get();
    final session = SessionCommande.fromDoc(sessionDoc);

    final sousSnap = await SousCommande.collection
        .where('sessionId', isEqualTo: sessionId)
        .get();
    // Réaffectation (pas de mutation) : le défaut du constructeur est une
    // liste const, donc immuable — ..clear() lèverait UnsupportedError.
    session.sousCommandes =
        sousSnap.docs.map(SousCommande.fromDoc).toList();

    // Charger les livraisons de chaque sous-commande
    for (final sc in session.sousCommandes) {
      final livSnap = await EtapeLivraison.collection(sc.id)
          .orderBy('ordre').get();
      sc.livraisons =
          livSnap.docs.map(EtapeLivraison.fromDoc).toList();
    }

    return session;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTHODES PRIVÉES
  // ══════════════════════════════════════════════════════════════════════════

  /// Grouper les items du panier par boutique
  static Map<String, List<PanierItem>> _grouperParBoutique(List<PanierItem> items) {
    final Map<String, List<PanierItem>> groupes = {};
    for (final item in items) {
      final boutiqueId = item.boutiqueId ?? 'boutique_inconnue';
      groupes.putIfAbsent(boutiqueId, () => []).add(item);
    }
    return groupes;
  }

  /// Calculer les montants d'une sous-commande
  /// Règle : 1 seul trajet par boutique → frais fixes quelle que soit la quantité d'articles
  static _DecompSC _calculerSousCommande({
    required List<PanierItem> items,
    required ConfigLivraisonBoutique config,
    required String methodePaiement,
    bool prepaye = false,
    bool gratuit = false,
  }) {
    // Sous-total de tous les articles de cette boutique
    final sousTotal = items.fold<double>(0, (s, i) => s + i.sousTotal);

    // ─── RÈGLE CLÉS ─────────────────────────────────────────────────────────
    // 1. Retrait boutique → 0 FCFA (client vient chercher)
    // 2. Livraison directe → 500 FCFA fixe (1 seul trajet, peu importe le nb d'articles)
    // 3. Avec couture → 1 000 FCFA (2 trajets : boutique→couturier + couturier→client)
    // La quantité d'articles n'influe PAS sur les frais de livraison
    final estRetrait = config.typeDestination == TypeDestination.retraitBoutique;
    final avecCouture = items.any((i) => i.avecCouture);

    final fraisLivraison = estRetrait
        ? 0.0
        : avecCouture
            ? _kFraisLivraison * 2   // 2 trajets si couture
            : _kFraisLivraison;      // 1 trajet fixe même pour 10 pagnes

    // Franchise gratuite → commission nulle (le boutiquier reçoit tout, tu ne prélèves rien)
    final commission = gratuit ? 0.0 : PrixFCFA.arrondirAu50(sousTotal * _kCommissionDefault / 100);

    // Frais passerelle paiement (0% si cash, 2.5% si MoMo)
    final fraisPaiement = methodePaiement == 'cash' ? 0.0
        : PrixFCFA.arrondirAu50((sousTotal + fraisLivraison) * _kFraisMMoney / 100);

    final totalClient = PrixFCFA.arrondirSuperieur50(
        sousTotal + fraisLivraison + fraisPaiement);

    // Gain livreur fixe par trajet (350 FCFA × nb trajets)
    final nbTrajets = estRetrait ? 0 : (avecCouture ? 2 : 1);
    final gainLivreur = _kGainLivreur * nbTrajets;

    // NET BOUTIQUIER selon le modèle de facturation :
    //  • PRÉPAYÉ      → reçoit TOUT le prix article ; la commission sera
    //                   débitée de son crédit (à la vente ou à la livraison).
    //  • COMMISSION   → reçoit le prix article MOINS la commission (prélevée
    //    SUR VENTE      directement sur la vente, rien à payer d'avance).
    // Dans les deux cas, les frais de livraison ne sont pas pris sur sa part.
    final netBoutique = prepaye
        ? PrixFCFA.arrondirInferieur50(sousTotal)
        : PrixFCFA.arrondirInferieur50(sousTotal - commission);

    return _DecompSC(
      sousTotal: sousTotal,
      fraisLivraison: fraisLivraison,
      commission: commission,   // tracée, débitée du crédit boutiquier
      totalClient: totalClient,
      netBoutique: netBoutique,
    );
  }

  /// Créer les étapes de livraison selon la config choisie
  static List<EtapeLivraison> _creerEtapesLivraison({
    required String sousCommandeId,
    required ConfigLivraisonBoutique config,
    required String adresseLivraison,
    required bool avecCouture,
    required String qrDepart,
    required String qrArrivee,
    required double fraisLivraison,
  }) {
    final livraisons = <EtapeLivraison>[];

    if (config.typeDestination == TypeDestination.retraitBoutique) {
      // Pas de livraison — client vient chercher
      livraisons.add(EtapeLivraison(
        id: _genererQR('LIV', sousCommandeId),
        sousCommandeId: sousCommandeId,
        ordre: 1,
        typeDestination: TypeDestination.retraitBoutique,
        adresseDepart: config.adresseBoutique,
        adresseArrivee: config.adresseBoutique,
        qrDepart: qrDepart,
        qrArrivee: qrArrivee,
        fraisLivraison: 0,
        gainLivreur: 0,
        dateLivraisonPrevue: DateTime.now().add(const Duration(hours: 4)),
      ));
    } else if (avecCouture) {
      // 2 livraisons : boutique → couturier → client
      livraisons.add(EtapeLivraison(
        id: _genererQR('LIV1', sousCommandeId),
        sousCommandeId: sousCommandeId,
        ordre: 1,
        typeDestination: TypeDestination.chezCouturier,
        adresseDepart: config.adresseBoutique,
        adresseArrivee: config.adresseCouturier ?? 'Couturier à définir',
        qrDepart: qrDepart,
        qrArrivee: _genererQR('ARR1', sousCommandeId),
        fraisLivraison: fraisLivraison / 2,
        gainLivreur: _kGainLivreur,
        dateLivraisonPrevue: DateTime.now().add(const Duration(hours: 2)),
      ));
      // Livraison finale après couture
      livraisons.add(EtapeLivraison(
        id: _genererQR('LIV2', sousCommandeId),
        sousCommandeId: sousCommandeId,
        ordre: 2,
        typeDestination: TypeDestination.domicileClient,
        adresseDepart: config.adresseCouturier ?? 'Couturier',
        adresseArrivee: adresseLivraison,
        qrDepart: _genererQR('DEP2', sousCommandeId),
        qrArrivee: qrArrivee,
        fraisLivraison: fraisLivraison / 2,
        gainLivreur: _kGainLivreur,
        dateLivraisonPrevue: DateTime.now().add(Duration(days: config.delaiCoutureJours)),
      ));
    } else {
      // Livraison directe : boutique → client
      livraisons.add(EtapeLivraison(
        id: _genererQR('LIV', sousCommandeId),
        sousCommandeId: sousCommandeId,
        ordre: 1,
        typeDestination: TypeDestination.domicileClient,
        adresseDepart: config.adresseBoutique,
        adresseArrivee: adresseLivraison,
        qrDepart: qrDepart,
        qrArrivee: qrArrivee,
        fraisLivraison: fraisLivraison,
        gainLivreur: _kGainLivreur,
        dateLivraisonPrevue: DateTime.now().add(const Duration(hours: 2)),
      ));
    }

    return livraisons;
  }

  /// Déclencher le reversement financier après livraison confirmée
  static Future<void> _declencherReversement(String sousCommandeId) async {
    final sc = await SousCommande.collection.doc(sousCommandeId).get();
    if (!sc.exists) return;
    final data = sc.data()!;

    // Créditer la boutique de son net (coût d'achat + bénéfice)
    final boutiqueId = data['boutiqueId'] as String? ?? '';
    final netBoutique = (data['netBoutique'] as num? ?? 0).toDouble();
    await FirebaseFirestore.instance.collection('boutiques').doc(boutiqueId)
        .update({'creditBalance': FieldValue.increment(netBoutique)});

    // MODÈLE PRÉPAYÉ : si l'abonnement débite la commission À LA LIVRAISON
    // (commissionAvance == false), c'est le moment de la prélever du crédit.
    try {
      // Le débit du crédit ne concerne QUE les boutiques en mode prépayé.
      if (await CommissionBoutiqueService.estPrepaye(boutiqueId)) {
        final avance = await CommissionBoutiqueService.commissionEstAvance(boutiqueId);
        if (!avance) {
          final commission = (data['commissionPlateforme'] as num?)?.toDouble() ?? 0;
          await CommissionBoutiqueService.debiterCommission(
            boutiqueId: boutiqueId,
            montantCommission: commission,
            sousCommandeId: sousCommandeId,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Reversement] Débit commission différé échoué: $e');
    }

    // Marquer la transaction comme confirmée
    await FirebaseFirestore.instance.collection('transactions')
        .where('sousCommandeId', isEqualTo: sousCommandeId)
        .get()
        .then((snap) async {
      for (final doc in snap.docs) {
        await doc.reference.update({'statut': 'confirmee'});
      }
    });
  }

  /// Recalculer le statut agrégé de la session parente
  static Future<void> _mettreAJourStatutSession(String sousCommandeId) async {
    final scDoc = await SousCommande.collection.doc(sousCommandeId).get();
    final sessionId = scDoc.data()?['sessionId'] as String?;
    if (sessionId == null) return;

    final toutesSnap = await SousCommande.collection
        .where('sessionId', isEqualTo: sessionId).get();
    final statuts = toutesSnap.docs
        .map((d) => StatutSousCommande.values.firstWhere((e) => e.name == (d.data()['statut'] as String? ?? ''), orElse: () => StatutSousCommande.values.first))
        .toList();

    bool fini(StatutSousCommande s) =>
        s == StatutSousCommande.livree ||
        s == StatutSousCommande.terminee || // legacy
        s == StatutSousCommande.annulee;
    final toutesTerminees = statuts.every(fini);
    final certainesTerminees = statuts.any(fini);

    await SessionCommande.collection.doc(sessionId).update({
      'statut': (toutesTerminees
          ? StatutSession.touteLivree
          : certainesTerminees
              ? StatutSession.partiellementLivree
              : StatutSession.enCours).name,
    });
  }

  static String _genererQR(String prefix, String id) {
    final random = Random().nextInt(9999).toString().padLeft(4, '0');
    return '$prefix-${id.substring(0, 6).toUpperCase()}-$random';
  }
}

// ─── Config livraison par boutique (choisie par le client) ───────────────────

class ConfigLivraisonBoutique {
  final String boutiqueId;
  final TypeDestination typeDestination;
  final String adresseBoutique;
  final String? adresseCouturier;   // si pagne avec couture
  final int delaiCoutureJours;      // délai avant livraison finale si couture

  const ConfigLivraisonBoutique({
    required this.boutiqueId,
    required this.typeDestination,
    required this.adresseBoutique,
    this.adresseCouturier,
    this.delaiCoutureJours = 3,
  });

  factory ConfigLivraisonBoutique.defaut(String adresseClient) =>
      ConfigLivraisonBoutique(
        boutiqueId: '',
        typeDestination: TypeDestination.domicileClient,
        adresseBoutique: '',
      );
}

// ─── Décomposition financière interne ────────────────────────────────────────

class _DecompSC {
  final double sousTotal;
  final double fraisLivraison;
  final double commission;
  final double totalClient;
  final double netBoutique;

  const _DecompSC({
    required this.sousTotal,
    required this.fraisLivraison,
    required this.commission,
    required this.totalClient,
    required this.netBoutique,
  });
}
