import 'package:sami/models/livreur.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/services/parrainage_service.dart';
import 'package:sami/models/strategies_marketing.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/recu_service.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/models/transaction_financiere.dart';
import 'package:sami/services/comptabilite_service.dart';

/// Service gérant tout le cycle de vie d'une livraison
/// Coordonne QR Code, paiement, validation, comptabilité
class LivraisonService {

  /// Crée une nouvelle livraison depuis une commande
  static Future<Livraison> creerLivraison({
    required String commandeId,
    required String clientId,
    required String boutiqueId,
    required String boutiqueNom,
    required double origineLat,
    required double origineLng,
    required String origineAdresse,
    required double destinationLat,
    required double destinationLng,
    required String destinationAdresse,
    required String destinationQuartier,
    required double prixClient,
    required TypeLivraison typeLivraison,
    ModeRecuperation modeRecuperation = ModeRecuperation.livreurVaBoutique,
    String methodePaiement = 'mobile_money',
    String? numeroTelephone,
  }) async {
    // 1. Calculer décomposition financière — le frais de course vient des
    // Paramètres admin : ce qu'on FACTURE au client (600) et ce qu'on
    // PARTAGE avec le livreur (70 %) ont la même source.
    final fraisCourse = await ParametresService.fraisLivraisonBase();
    final partLivreur = await ParametresService.gainLivreurPct();
    final decomposition = DecompositionFinanciere.calculer(
      prixClient: prixClient,
      fraisLivraisonIsole: fraisCourse,
      tauxGainLivreur: partLivreur / 100,
      tauxFraisPaiement: methodePaiement == 'cash' ? 0.0 : 2.5,
    );

    // 2. Générer ID et QR codes
    final docRef = FirebaseFirestore.instance.collection('livraisons').doc();
    // Générer le set QR cryptographique (offline-first)
    final qrSet = QRCryptoService.genererSet(livraisonId: docRef.id);
    final qrCode = QrLivraison(
      codeOrigine: qrSet.qrLivreurDepart,
      codeDestination: qrSet.qrClientEncode,
      dateExpiration: DateTime.fromMillisecondsSinceEpoch(
          qrSet.tokenDepart.expirationUnix * 1000),
    );

    // 3. Construire l'objet livraison
    final livraison = Livraison(
      id: docRef.id,
      commandeId: commandeId,
      clientId: clientId,
      typeLivraison: typeLivraison,
      modeRecuperation: modeRecuperation,
      origineId: boutiqueId,
      origineNom: boutiqueNom,
      origineLat: origineLat,
      origineLng: origineLng,
      origineAdresse: origineAdresse,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationAdresse: destinationAdresse,
      destinationQuartier: destinationQuartier,
      decompositionFinanciere: decomposition,
      methodePaiementChoisi: methodePaiement,
      qrCode: qrCode,
      dateCreation: DateTime.now(),
      dateLivraisonPrevue: DateTime.now().add(const Duration(hours: 2)),
    );

    // 4. Sauvegarder en Firebase
    await docRef.set(livraison.toMap());

    // 4b. Stocker le set QR + clé secrète séparément (jamais dans le QR lui-même)
    //     Distribué aux parties via leurs documents respectifs
    await FirebaseFirestore.instance
        .collection('qr_secrets').doc(docRef.id)
        .set(qrSet.toFirestore());

    // 5. Créer les transactions financières
    // (déclenchées après confirmation paiement)
    if (methodePaiement == 'mobile_money') {
      // Paiement Mobile Money → en attente webhook CinetPay
      await _initierPaiementMobileMoney(livraison, numeroTelephone);
    }
    // Cash → confirmé à la livraison (voir validerLivraisonQR)

    return livraison;
  }

  /// Étape 1 : Livreur scanne le QR code à l'ORIGINE (boutique/couturier)
  /// → Confirme que le livreur a bien récupéré l'article
  /// Le livreur démarre la course : il part vers la boutique/couturier.
  /// Passe le statut de livreurAssigne → enRouteOrigine.
  static Future<void> demarrerCourse(String livraisonId) async {
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update({
      'statut': StatutLivraison.enRouteOrigine.name,
      'dateDepartCourse': FieldValue.serverTimestamp(),
    });
  }

  static Future<bool> validerRecuperationQR({
    required String livraisonId,
    required String livreurId,
    required String codeScanne,
    required double livreurLat,
    required double livreurLng,
    String? photoUrl,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .get();

    if (!doc.exists) return false;
    final livraison = Livraison.fromFirebaseDocument(doc);

    // Vérifier le bon code QR
    // Validation cryptographique locale (HMAC-SHA256)
    final localData = await QRCryptoService.chargerLocal(livraisonId);
    if (localData != null) {
      final resultat = QRCryptoService.validerOffline(
        qrScanne: codeScanne,
        cleSecreteLocale: localData.cleSecrete,
        livraisonIdAttendu: livraisonId,
        typeAttendu: TypeQR.depart,
      );
      if (!resultat.valide) return false;
    } else if (livraison.qrCode.codeOrigine != codeScanne) return false;
    if (livraison.qrCode.estExpire) return false;
    if (livraison.livreurId != livreurId) return false;

    final preuve = PreuveLivraison(
      mode: ModeValidation.qrCode,
      dateValidation: DateTime.now(),
      valideePar: livreurId,
      photoUrl: photoUrl,
      latitudeValidation: livreurLat,
      longitudeValidation: livreurLng,
    );

    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update({
      'statut': StatutLivraison.enLivraison.name,
      'dateRecuperation': DateTime.now(),
      'preuveRecuperation': preuve.toMap(),
      'qrCode.origineScanne': true,
      'qrCode.dateScannOrigine': DateTime.now(),
      'qrCode.scannePar': livreurId,
      'livreurLatActuelle': livreurLat,
      'livreurLngActuelle': livreurLng,
    });

    // ═══ PROPAGATION AU BOUTIQUIER ═══ la sous-commande suit :
    // « Prête » → « En livraison » dès le scan de départ, sinon le
    // tableau de bord boutique ment (reste « À traiter »).
    if (livraison.commandeId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('sous_commandes')
          .doc(livraison.commandeId)
          .set({
        'statut': StatutSousCommande.enCoursLivraison.name,
      }, SetOptions(merge: true));
    }

    // Le CLIENT apprend que son colis voyage (l'attente informée
    // est une attente sereine).
    if (livraison.clientId.isNotEmpty) {
      await NotificationService.envoyer(
        destinataireId: livraison.clientId,
        titre: 'Colis pris en charge 🛵',
        message:
            'Le livreur a récupéré votre commande — elle est en route !',
        route: '/commandes',
        refId: livraison.commandeId,
      );
    }

    return true;
  }

  /// Étape 2 : Client scanne le QR code à la DESTINATION
  /// → Confirme la livraison, déclenche les reversements financiers
  static Future<ResultatValidation> validerLivraisonQR({
    required String livraisonId,
    required String clientId,
    required String codeScanne,
    required ModeValidation modeUtilise,
    double? clientLat,
    double? clientLng,
    String? photoUrl,
    String? otpUtilise,
    String? signatureBase64,
    // Si paiement cash : montant encaissé par livreur
    double? montantCashEncaisse,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .get();

    if (!doc.exists) {
      return ResultatValidation(succes: false, message: 'Livraison introuvable');
    }

    final livraison = Livraison.fromFirebaseDocument(doc);

    // Vérifications
    if (livraison.qrCode.codeDestination != codeScanne) {
      return ResultatValidation(succes: false, message: 'QR Code invalide');
    }
    if (livraison.qrCode.estExpire) {
      return ResultatValidation(succes: false, message: 'QR Code expiré');
    }

    final preuveLivraison = PreuveLivraison(
      mode: modeUtilise,
      dateValidation: DateTime.now(),
      valideePar: clientId,
      photoUrl: photoUrl,
      otpUtilise: otpUtilise,
      latitudeValidation: clientLat,
      longitudeValidation: clientLng,
      signatureBase64: signatureBase64,
    );

    // CONTRÔLE DE COHÉRENCE GPS (détection, pas blocage).
    // On compare la position du scan avec la destination attendue. Si l'écart
    // est anormal (> seuil), on lève un drapeau 'aVerifier' : la livraison
    // passe quand même (le réseau peut être absent, le GPS imprécis), mais
    // l'admin peut la contrôler avant de payer. Détecte une validation faite
    // loin du client (ex: livreur qui valide depuis chez lui).
    bool aVerifier = false;
    String? motifVerif;
    if (clientLat != null && clientLng != null) {
      final dist = _distanceMetres(
        clientLat, clientLng,
        livraison.destinationLat, livraison.destinationLng,
      );
      if (dist > 500) { // plus de 500 m de la destination attendue
        aVerifier = true;
        motifVerif = 'Scan à ${dist.toStringAsFixed(0)} m de la destination';
      }
    } else {
      // Aucune position au scan : à signaler aussi (GPS coupé volontairement ?)
      aVerifier = true;
      motifVerif = 'Aucune position GPS au moment du scan';
    }

    // Mise à jour livraison
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update({
      'statut': StatutLivraison.livre.name,
      'dateLivraison': DateTime.now(),
      'preuveLivraison': preuveLivraison.toMap(),
      'paiementConfirme': true,
      'qrCode.destinationScanne': true,
      'qrCode.dateScannDestination': DateTime.now(),
      'aVerifier': aVerifier,
      if (motifVerif != null) 'motifVerification': motifVerif,
    });

    // ═══ PROPAGATION FINALE ═══ la sous-commande passe « livree »
    // (sinon l'onglet « Terminées » du boutiquier et les stats de
    // ventes restent aveugles à jamais).
    if (livraison.commandeId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('sous_commandes')
          .doc(livraison.commandeId)
          .set({
        'statut': StatutSousCommande.livree.name,
        'dateLivraison': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // ═══ SYNC SESSION ═══ la carte « Mes commandes » du client suit :
    // toutes les sous-commandes livrées ⇒ touteLivree ; certaines ⇒
    // partiellementLivree — sinon « En cours · 0/1 » ment à vie.
    try {
      final scDoc = await FirebaseFirestore.instance
          .collection('sous_commandes')
          .doc(livraison.commandeId)
          .get();
      final sessionId = scDoc.data()?['sessionId'] as String? ?? '';
      if (sessionId.isNotEmpty) {
        final freres = await FirebaseFirestore.instance
            .collection('sous_commandes')
            .where('sessionId', isEqualTo: sessionId)
            .get();
        bool fini(String st) =>
            st == 'livree' || st == 'terminee' || st == 'annulee';
        final tous = freres.docs
            .map((d) => d.data()['statut'] as String? ?? '')
            .toList();
        final statutSession = tous.every(fini)
            ? 'touteLivree'
            : (tous.any(fini) ? 'partiellementLivree' : 'enCours');
        await FirebaseFirestore.instance
            .collection('sessions_commande')
            .doc(sessionId)
            .set({'statut': statutSession},
                SetOptions(merge: true));
      }
    } catch (_) {}

    // Plafond cash + reçu de vente signé pour le CLIENT (livraison complétée)
    await _majEncoursCash(livraison);
    await _synchroniserCommande(livraison);
    RecuService.creer(
      type: 'vente',
      refId: livraison.id,
      beneficiaireId: livraison.clientId,
      beneficiaireNom: 'Client',
      montant: livraison.decompositionFinanciere.prixClient,
      detail: 'Achat livré - ${livraison.destinationAdresse}',
    ).catchError((_) => <String, dynamic>{});

    // Déclencher comptabilité
    if (livraison.livreurId != null) {
      await ComptabiliteService.confirmerReversementsApresLivraison(
        livraisonId: livraisonId,
        boutiqueId: livraison.origineId,
        livreurId: livraison.livreurId!,
      );
    }

    // Si paiement cash → créer la transaction maintenant
    if (livraison.methodePaiementChoisi == 'cash' && montantCashEncaisse != null) {
      await _confirmerPaiementCash(livraison, montantCashEncaisse);
    }

    // Libérer le livreur
    if (livraison.livreurId != null) {
      await FirebaseFirestore.instance
          .collection('livreurs')
          .doc(livraison.livreurId!)
          .set({'statut': 'disponible'}, SetOptions(merge: true));
    }

    return ResultatValidation(
      succes: true,
      message: 'Livraison confirmée !',
      gainLivreur: livraison.decompositionFinanciere.gainLivreur,
      netBoutique: livraison.decompositionFinanciere.netBoutique,
    );
  }

  /// SCAN-D'ABORD : à partir d'un QR scanné, retrouve la livraison concernée
  /// (via le livraisonId encodé) ET vérifie que le compte courant y est impliqué
  /// dans le rôle attendu. Retourne la livraison si l'utilisateur est autorisé,
  /// null sinon. Fonctionne en ligne (lecture Firestore) ; en hors-ligne complet,
  /// l'app retombe sur la sélection manuelle.
  static Future<Livraison?> resoudreLivraisonDepuisQR({
    required String qrScanne,
    required String compteId,
    required RoleLivraison roleAttendu,
  }) async {
    try {
      final token = TokenQR.decode(qrScanne);
      final doc = await FirebaseFirestore.instance
          .collection('livraisons')
          .doc(token.livraisonId)
          .get();
      if (!doc.exists) return null;
      final liv = Livraison.fromFirebaseDocument(doc);

      // Vérifier que le compte courant est bien l'acteur attendu
      final autorise = switch (roleAttendu) {
        RoleLivraison.livreur => liv.livreurId == compteId,
        RoleLivraison.client => liv.clientId == compteId,
        RoleLivraison.boutique => liv.origineId == compteId,
      };
      if (!autorise) return null;
      return liv;
    } catch (_) {
      return null;
    }
  }

  /// RETOUR D'ÉTAT : la validation du livreur met à jour la COMMANDE
  /// d'origine — sinon le client et la boutique gardent un statut périmé
  /// et les reversements couture ne se déclenchent jamais.
  /// FIDÉLITÉ : chaque livraison RÉUSSIE crédite le client
  /// (≈1 pt / 1000 F) et recalcule son niveau — sans quoi la règle
  /// « espèces réservées aux fidèles » bloquerait à vie.
  static Future<void> _crediterFidelite(
      String clientId, double montant) async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(clientId);
        final doc = await tx.get(ref);
        final points = ((doc.data()?['points'] as num?)?.toInt() ?? 0) +
            (montant / 1000).floor();
        tx.update(ref, {
          'points': points,
          'niveau': NiveauFidelite.fromPoints(points).niveau,
        });
      });
    } catch (_) {}
  }

  static Future<void> _synchroniserCommande(Livraison l) async {
    try {
      final db = FirebaseFirestore.instance;
      // ── VERROU IDEMPOTENT ── une livraison ne crédite la fidélité
      // (et ne déclenche le parrainage) qu'UNE fois, même si
      // l'événement 'livree' est rejoué (réseau, double tap).
      String? commandeCouturierId;
      final dejaFait = await db.runTransaction<bool>((tx) async {
        final ref = db.collection('livraisons').doc(l.id);
        final doc = await tx.get(ref);
        if (doc.data()?['fideliteCreditee'] == true) return true;
        // trajet 1 d'une couture (tissu → atelier) : porte la référence
        commandeCouturierId = doc.data()?['commandeCouturierId'] as String?;
        tx.update(ref, {'fideliteCreditee': true});
        return false;
      });
      if (dejaFait) return;
      // La sous-commande (vente classique OU pagne d'une couture) passe 'livree'
      final sc = await db.collection('sous_commandes').doc(l.commandeId).get();
      if (sc.exists && commandeCouturierId != null) {
        // COUTURE, trajet 1 : le pagne est arrivé à l'atelier. Pour le
        // boutiquier c'est une vente livrée ; pour le client ce n'est PAS
        // « votre commande est livrée » (on ne notifie pas ici) — la chaîne
        // couture continue plus bas (enConfection).
        await sc.reference.update({
          'statut': 'livree',
          'dateTerminaison': FieldValue.serverTimestamp(),
        });
        if (l.livreurId != null && l.livreurId!.isNotEmpty) {
          await db.collection('livreurs').doc(l.livreurId).set({
            'statut': StatutLivreur.disponible.name,
          }, SetOptions(merge: true));
        }
      } else if (sc.exists) {
        await sc.reference.update({'statut': 'livree'});
        // fidélité : la livraison réussie crédite points + niveau
        await _crediterFidelite(
            l.clientId, l.decompositionFinanciere.prixClient);
        await ParrainageService.validerSiPremiereLivraison(l.clientId);
        // Le client APPREND que c'est livré — et l'avis est invité :
        // c'est maintenant que l'expérience est chaude.
        await NotificationService.envoyer(
          destinataireId: l.clientId,
          titre: 'Commande livrée 🎉',
          message:
              'Votre colis est arrivé. Donnez votre avis sur la boutique et le livreur !',
          route: '/commandes',
          refId: l.commandeId,
        );
        // ── Le livreur redevient DISPONIBLE (l'encours cash est déjà
        // suivi par validerLivraisonQR) ──
        if (l.livreurId != null && l.livreurId!.isNotEmpty) {
          await db.collection('livreurs').doc(l.livreurId).set({
            'statut': StatutLivreur.disponible.name,
            // (le compteur de carrière n'est plus écrit ici : la part
            //  effective COMPTE les livraisons « livree » — infalsifiable)
          }, SetOptions(merge: true));
        }
        return;
      }
      // Couture : trajet 1 (tissu reçu) ou trajet 2 (vêtement livré) ?
      final cc = await db
          .collection('commandes_couturier')
          .doc(commandeCouturierId ?? l.commandeId)
          .get();
      if (!cc.exists) return;
      final d = cc.data()!;
      if (d['livraisonRetourId'] == l.id) {
        await cc.reference.update({
          'statut': 'livree',
          'dateLivraisonReelle': FieldValue.serverTimestamp(),
        });
        await _crediterFidelite(
            l.clientId, l.decompositionFinanciere.prixClient);
        await NotificationService.envoyer(
          destinataireId: d['clientId'] as String? ?? '',
          titre: 'Vêtement livré 🎉',
          message: 'Votre confection est arrivée. Votre reçu est disponible.',
          route: '/mes-recus',
          refId: l.commandeId,
        );
      } else if (d['livraisonPagneId'] == l.id) {
        await cc.reference.update({'statut': 'enConfection'});
        await NotificationService.envoyer(
          destinataireId: d['couturierId'] as String? ?? '',
          titre: 'Tissu reçu ✂️',
          route: '/dashboard_couturier',
          message: 'Le pagne est arrivé à votre atelier. La confection peut commencer.',
          refId: l.commandeId,
        );
      }
    } catch (_) {}
  }

  /// Incrémente l'encours cash du livreur (plafond anti-fraude) quand une
  /// livraison en espèces est validée. L'admin le remet à zéro à la remise.
  static Future<void> _majEncoursCash(Livraison l) async {
    try {
      if (l.methodePaiementChoisi != 'cash' || l.livreurId == null) return;
      await FirebaseFirestore.instance
          .collection('livreurs')
          .doc(l.livreurId)
          .set({
        'encoursCash':
            FieldValue.increment(l.decompositionFinanciere.prixClient)
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// VALIDATION PAR CODE COURT (secours téléphone éteint).
  /// Le livreur saisit le code à 6 chiffres dicté par le client/boutiquier.
  /// On vérifie le code avec la clé locale (préchargée), puis on valide.
  static Future<bool> validerParCodeCourt({
    required String livraisonId,
    required String codeSaisi,
    required TypeQR type,
    double? lat,
    double? lng,
  }) async {
    // Récupérer la clé locale préchargée
    final local = await QRCryptoService.chargerLocal(livraisonId);
    if (local == null) return false;
    final ok = QRCryptoService.verifierCodeCourt(
      livraisonId: livraisonId,
      cleSecrete: local.cleSecrete,
      codeSaisi: codeSaisi,
    );
    if (!ok) return false;

    // Code correct → marquer le statut (départ → enLivraison, arrivée → livre)
    final maj = <String, dynamic>{
      'validationSecours': 'code_court',
      if (lat != null) 'latitudeValidation': lat,
      if (lng != null) 'longitudeValidation': lng,
    };
    if (type == TypeQR.depart) {
      maj['statut'] = StatutLivraison.enLivraison.name;
    } else {
      maj['statut'] = StatutLivraison.livre.name;
      maj['dateLivraison'] = DateTime.now();
      maj['aVerifier'] = true; // validation secours → contrôle conseillé
      maj['motifVerification'] = 'Validé par code court (secours)';
    }
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update(maj);
    return true;
  }

  /// VALIDATION PAR SIGNATURE (dernier recours).
  /// Enregistre la signature (image base64) comme preuve, marque livré, et
  /// lève le drapeau 'aVerifier' (preuve faible → contrôle admin conseillé).
  static Future<bool> validerParSignature({
    required String livraisonId,
    required String signatureBase64,
  }) async {
    // ═══ RÈGLE DE SÉCURITÉ ═══ la signature est une PREUVE
    // COMPLÉMENTAIRE, jamais une clôture : seul le CODE DU CLIENT
    // (scan/code court) valide la remise. Un gribouillis ne peut pas
    // remplacer le consentement du destinataire.
    final ref = FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId);
    final doc = await ref.get();
    final statut = doc.data()?['statut'] as String? ?? '';
    if (statut != StatutLivraison.livre.name) {
      // Pas encore livrée par le code → la signature seule est REFUSÉE.
      return false;
    }
    await ref.set({
      'signatureClient': signatureBase64,
      'signatureLe': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  /// Distance en mètres entre deux points GPS (formule de Haversine).
  static double _distanceMetres(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // rayon Terre en mètres
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Retrait client (click & collect) — client vient chercher lui-même
  static Future<bool> validerRetraitClient({
    required String livraisonId,
    required String clientId,
    required String codeScanne,
  }) async {
    // Même logique que validerLivraisonQR mais sans livreur
    return validerLivraisonQR(
      livraisonId: livraisonId,
      clientId: clientId,
      codeScanne: codeScanne,
      modeUtilise: ModeValidation.qrCode,
    ).then((r) => r.succes);
  }

  // ── Suivi temps réel ──────────────────────────────────────────────────────

  /// Met à jour la position GPS du livreur (appelé toutes les 30s)
  static Future<void> mettreAJourPositionLivreur({
    required String livraisonId,
    required String livreurId,
    required double latitude,
    required double longitude,
  }) async {
    final batch = FirebaseFirestore.instance.batch();

    // Mise à jour dans la livraison (pour le client)
    batch.update(
      FirebaseFirestore.instance.collection('livraisons').doc(livraisonId),
      {'livreurLatActuelle': latitude, 'livreurLngActuelle': longitude},
    );

    // Mise à jour profil livreur
    batch.update(
      FirebaseFirestore.instance.collection('livreurs').doc(livreurId),
      {
        'latitude': latitude,
        'longitude': longitude,
        'dernierePosition': DateTime.now(),
      },
    );

    await batch.commit();
  }

  // ── Privé ─────────────────────────────────────────────────────────────────

  static Future<void> _initierPaiementMobileMoney(
    Livraison livraison,
    String? numeroTelephone,
  ) async {
    // TODO: Appel API CinetPay/Monetbil
    // Pour l'instant on enregistre en attente
    await FirebaseFirestore.instance.collection('transactions').add(
      TransactionFinanciere(
        id: '',
        type: TypeTransaction.paiementMobileMoney,
        statut: StatutTransaction.enAttente,
        clientId: livraison.clientId,
        boutiqueId: livraison.origineId,
        livraisonId: livraison.id,
        commandeId: livraison.commandeId,
        montantBrut: livraison.decompositionFinanciere.prixClient,
        montantNet: livraison.decompositionFinanciere.prixClient,
        decomposition: livraison.decompositionFinanciere,
        methodePaiement: 'mobile_money',
        numeroTelephone: numeroTelephone,
        dateCreation: DateTime.now(),
      ).toMap(),
    );
  }

  static Future<void> _confirmerPaiementCash(
    Livraison livraison,
    double montantEncaisse,
  ) async {
    await FirebaseFirestore.instance.collection('transactions').add(
      TransactionFinanciere(
        id: '',
        type: TypeTransaction.paiementCash,
        statut: StatutTransaction.confirmee,
        clientId: livraison.clientId,
        boutiqueId: livraison.origineId,
        livreurId: livraison.livreurId,
        livraisonId: livraison.id,
        commandeId: livraison.commandeId,
        montantBrut: montantEncaisse,
        montantNet: montantEncaisse,
        decomposition: livraison.decompositionFinanciere,
        methodePaiement: 'cash',
        dateCreation: DateTime.now(),
        dateConfirmation: DateTime.now(),
        note: 'Cash encaissé par livreur à la livraison',
      ).toMap(),
    );
  }
}

class ResultatValidation {
  final bool succes;
  final String message;
  final double? gainLivreur;
  final double? netBoutique;

  ResultatValidation({
    required this.succes,
    required this.message,
    this.gainLivreur,
    this.netBoutique,
  });
}
