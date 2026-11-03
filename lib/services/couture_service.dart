import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/services/stock_service.dart';
import 'package:sami/services/commission_boutique_service.dart';
import 'package:sami/services/livraison_service.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/agents/agent_livraison.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE COUTURE
//
// Couche d'orchestration du métier couturier :
//   1. PROFILS DE MESURES (multi-bénéficiaires) : un client crée plusieurs
//      profils ("Moi", "Mon mari", "Ma fille Aïssa"), chacun avec ses mesures.
//      Réutilisables d'une commande à l'autre.
//   2. COMMANDE GROUPÉE : un client achète N pagnes destinés à la couture pour
//      plusieurs personnes → on crée N CommandeCouturier, chacune liée à un
//      profil de mesures et à un modèle. (ex : 10 pagnes pour 3 personnes)
//
// La livraison de chaque vêtement se fait en DEUX trajets indépendants
// (boutique→couturier, puis couturier→client), gérés séparément pour qu'ils
// puissent être assignés à des livreurs différents.
// ═══════════════════════════════════════════════════════════════════════════

class CoutureService {
  static final _db = FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── PROFILS DE MESURES ────────────────────────────────────────────────────

  /// Flux des profils de mesures du client courant.
  static Stream<List<MesuresClient>> streamProfils() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return MesuresClient.collection(uid).snapshots().map(
        (snap) => snap.docs.map((d) => MesuresClient.fromDoc(d)).toList());
  }

  /// Crée ou met à jour un profil de mesures.
  /// Si valeurs vides → profil "à mesurer par le couturier" (mesures prises en RDV).
  static Future<String> sauvegarderProfil({
    required String nomProfil,
    required Map<String, double> valeurs,
    String? profilId,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Non connecté');

    final col = MesuresClient.collection(uid);
    final ref = profilId != null ? col.doc(profilId) : col.doc();
    final profil = MesuresClient(
      id: ref.id,
      clientId: uid,
      nomProfil: nomProfil,
      valeurs: valeurs,
      dateCreation: DateTime.now(),
      dateMiseAJour: DateTime.now(),
    );
    await ref.set(profil.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  /// Supprime un profil de mesures.
  static Future<void> supprimerProfil(String profilId) async {
    final uid = _uid;
    if (uid == null) return;
    await MesuresClient.collection(uid).doc(profilId).delete();
  }

  /// Taux de commission d'un couturier selon son abonnement (12% → 5%).
  /// C'est une SOURCE DE REVENU liée à l'abonnement : moins le couturier paie
  /// d'abonnement, plus sa commission est élevée.
  static Future<double> tauxCommissionCouturier(String couturierId) async {
    try {
      final q = await _db
          .collection('couturiers')
          .where('utilisateurId', isEqualTo: couturierId)
          .limit(1)
          .get();
      String type = 'gratuit';
      if (q.docs.isNotEmpty) {
        type = q.docs.first.data()['typeAbonnement'] as String? ?? 'gratuit';
        // EXPIRATION : palier périmé ⇒ gratuit (champ optionnel)
        final _finLe = q.docs.first.data()['abonnementFinLe'];
        if (_finLe is Timestamp && _finLe.toDate().isBefore(DateTime.now())) {
          type = 'gratuit';
        }
      }
      final abo = AbonnementCouturier.catalogue[
          TypeAbonnementCouturier.values.firstWhere((e) => e.name == (type), orElse: () => TypeAbonnementCouturier.values.first)];
      if (abo != null && type != 'gratuit') {
        return abo.tauxCommission / 100.0; // taux dégressif de l'abonné
      }
      // Sans abonnement : commission PARAMÉTRABLE (admin → FINANCES)
      return (await ParametresService.commissionCouturePct()) / 100.0;
    } catch (_) {
      return 0.10; // repli hors-ligne
    }
  }

  // ── COMMANDE GROUPÉE (multi-bénéficiaires) ────────────────────────────────

  /// Un "vêtement à coudre" : un pagne + un modèle + un bénéficiaire (profil).
  /// C'est l'unité que le client assemble avant de commander.

  /// Crée les commandes couturier pour une liste de vêtements.
  /// Chaque vêtement devient une CommandeCouturier indépendante (donc une
  /// confection + deux trajets de livraison propres).
  /// Retourne la liste des IDs créés.
  static Future<List<String>> creerCommandesCouture({
    required List<VetementACoudre> vetements,
    required String methodePaiement,
  }) async {
    // 2 trajets × frais de base (paramétrable admin)
    final fraisLivraisonCouture =
        2 * await ParametresService.fraisLivraisonBase();
    final uid = _uid;
    if (uid == null) throw Exception('Non connecté');

    // 1. ACHAT DU PAGNE : décompter le stock AVANT de créer les commandes
    // (1 pagne par vêtement). Bloque si stock insuffisant.
    final resultatStock = await StockService.confirmerStock(
      articles: vetements.map((v) => (pagneId: v.pagneId, quantite: v.nombrePagnes)).toList(),
    );
    if (!resultatStock.succes) {
      throw Exception(resultatStock.erreurs.join('\n'));
    }

    final batch = _db.batch();
    final ids = <String>[];

    // Taux de commission par couturier (selon son abonnement) — mis en cache
    final Map<String, double> tauxParCouturier = {};
    // Infos pagne (prix + boutique) — mises en cache par pagneId
    final Map<String, ({double prix, String boutiqueId})> infoPagne = {};
    // Débits de commission boutique à faire après le commit (mode prépayé avance)
    final List<({String boutiqueId, double commission, String cmdId})> debits = [];

    for (final v in vetements) {
      final ref = CommandeCouturier.collection.doc();
      tauxParCouturier[v.couturierId] ??=
          await tauxCommissionCouturier(v.couturierId);
      final taux = tauxParCouturier[v.couturierId]!;
      final commission =
          PrixFCFA.arrondirAu50(v.prixConfection * taux);

      // 2. PART DU PAGNE : lire prix + boutique, calculer la part boutiquier
      // selon le MODÈLE HYBRIDE (franchise gratuite / commission-sur-vente /
      // prépayé), comme pour une vente normale.
      if (!infoPagne.containsKey(v.pagneId)) {
        final pDoc = await _db.collection('pagnes').doc(v.pagneId).get();
        final pd = pDoc.data();
        infoPagne[v.pagneId] = (
          prix: (pd?['prixParBoutique'] as num?)?.toDouble() ?? 0,
          boutiqueId: pd?['boutiqueId'] as String? ?? '',
        );
      }
      final pagne = infoPagne[v.pagneId]!;
      double commissionBoutique = 0;
      double netBoutique = pagne.prix;
      bool prepaye = false;
      if (pagne.boutiqueId.isNotEmpty && pagne.prix > 0) {
        final gratuit = await CommissionBoutiqueService
            .enFranchiseGratuite(pagne.boutiqueId);
        prepaye = gratuit
            ? false
            : await CommissionBoutiqueService.estPrepaye(pagne.boutiqueId);
        final txCom = await ParametresService.commissionDefautPct() / 100.0;
        commissionBoutique =
            gratuit ? 0.0 : PrixFCFA.arrondirAu50(pagne.prix * txCom);
        netBoutique = prepaye
            ? PrixFCFA.arrondirInferieur50(pagne.prix)
            : PrixFCFA.arrondirInferieur50(pagne.prix - commissionBoutique);
        if (prepaye && commissionBoutique > 0) {
          final avance = await CommissionBoutiqueService
              .commissionEstAvance(pagne.boutiqueId);
          if (avance) {
            debits.add((
              boutiqueId: pagne.boutiqueId,
              commission: commissionBoutique,
              cmdId: ref.id,
            ));
          }
        }
      }

      final cmd = CommandeCouturier(
        id: ref.id,
        clientId: uid,
        couturierId: v.couturierId,
        modeleId: v.modeleId,
        surDevis: v.surDevis,
        pagneId: v.pagneId,
        mesuresClientId: v.profilMesuresId,
        mesuresSnapshot: v.mesuresSnapshot,
        modeRencontre: v.modeRencontre,
        rdvDate: v.rdvDate,
        rdvLieu: v.rdvLieu,
        prixConvenu: v.prixConfection,
        commissionPlateforme: commission,
        prixPagne: pagne.prix * v.nombrePagnes,
        // LIVRAISON COUTURE = 2 courses réelles (tissu → atelier, puis
        // vêtement → client) : facturées au client, sinon la plateforme
        // paierait les livreurs à perte.
        fraisLivraison: fraisLivraisonCouture,
        nombrePagnes: v.nombrePagnes,
        netBoutique: netBoutique,
        boutiqueId: pagne.boutiqueId,
        methodePaiement: methodePaiement,
        statut: StatutCommandeCouturier.enAttente,
        dateCommande: DateTime.now(),
        notesClient: v.notes,
      );
      batch.set(ref, cmd.toMap());
      ids.add(ref.id);
    }

    await batch.commit();

    // 3. Débits de commission boutique (mode prépayé "commission d'avance")
    for (final d in List.of(debits)) {
      try {
        await CommissionBoutiqueService.debiterCommission(
          boutiqueId: d.boutiqueId,
          montantCommission: d.commission,
          sousCommandeId: d.cmdId,
        );
      } catch (e) {
        if (kDebugMode) print('[Couture] Débit commission boutique échoué: $e');
      }
    }

    // TRAJET 1 (boutique → couturier) pour chaque vêtement : on le crée APRÈS
    // le commit, et on stocke son ID dans livraisonPagneId de la commande.
    // C'est ce lien qui permet au couturier de précharger la bonne clé QR.
    for (var i = 0; i < vetements.length; i++) {
      // SUR DEVIS : le tissu ne part PAS avant l'accord — le trajet 1 sera
      // créé quand le client ACCEPTE le devis (sinon un refus signifierait
      // un pagne déjà transporté à l'atelier pour rien).
      if (vetements[i].surDevis) continue;
      try {
        await _creerTrajet1(
            commandeId: ids[i],
            pagneId: vetements[i].pagneId,
            couturierId: vetements[i].couturierId);
      } catch (e) {
        if (kDebugMode) print('[Couture] Trajet 1 échoué pour ${ids[i]}: $e');
      }
    }

    return ids;
  }

  /// Crée la livraison boutique → couturier (trajet 1) et lie son ID à la
  /// commande (livraisonPagneId). Assignée par l'agent à un livreur.
  static Future<void> _creerTrajet1({
    required String commandeId,
    required String pagneId,
    required String couturierId,
  }) async {
    // Coords boutique du pagne (origine)
    double origLat = 9.3017, origLng = 13.3984;
    String origAdresse = 'Boutique, Garoua';
    String boutiqueId = '';
    try {
      final pDoc = await _db.collection('pagnes').doc(pagneId).get();
      final pd = pDoc.data();
      if (pd != null) {
        boutiqueId = pd['boutiqueId'] as String? ?? '';
        if (boutiqueId.isNotEmpty) {
          final bDoc =
              await _db.collection('boutiques').doc(boutiqueId).get();
          final bd = bDoc.data();
          if (bd != null) {
            origLat = (bd['latitude'] as num?)?.toDouble() ?? origLat;
            origLng = (bd['longitude'] as num?)?.toDouble() ?? origLng;
            origAdresse = 'Boutique ${bd['nom'] ?? ''}, Garoua';
          }
        }
      }
    } catch (_) {}

    // Coords couturier (destination)
    double destLat = origLat, destLng = origLng;
    String destAdresse = 'Couturier, Garoua';
    try {
      final cq = await _db
          .collection('couturiers')
          .where('utilisateurId', isEqualTo: couturierId)
          .limit(1)
          .get();
      if (cq.docs.isNotEmpty) {
        final cd = cq.docs.first.data();
        destLat = (cd['latitude'] as num?)?.toDouble() ?? destLat;
        destLng = (cd['longitude'] as num?)?.toDouble() ?? destLng;
        destAdresse =
            'Couturier ${cd['prenom'] ?? ''} ${cd['nom'] ?? ''}, ${cd['quartier'] ?? 'Garoua'}';
      }
    } catch (_) {}

    final livraison = await LivraisonService.creerLivraison(
      commandeId: commandeId,
      clientId: _uid ?? '',
      boutiqueId: boutiqueId,
      boutiqueNom: origAdresse,
      origineLat: origLat,
      origineLng: origLng,
      origineAdresse: origAdresse,
      destinationLat: destLat,
      destinationLng: destLng,
      destinationAdresse: destAdresse,
      destinationQuartier: destAdresse,
      // Rien n'est encaissé au dépôt du tissu : le client règle TOUT
      // (pagne + confection) à la réception du vêtement (trajet 2).
      prixClient: 0,
      typeLivraison: TypeLivraison.confection,
    );

    // Lier le trajet 1 à la commande
    await CommandeCouturier.collection.doc(commandeId).update({
      'livraisonPagneId': livraison.id,
    });

    // Assigner un livreur
    // Prévenir la boutique : un livreur vient chercher le tissu
    try {
      final b = await FirebaseFirestore.instance
          .collection('boutiques').doc(boutiqueId).get();
      final gerants = List<String>.from(b.data()?['gerants'] as List? ?? []);
      if (gerants.isNotEmpty) {
        await NotificationService.envoyer(
          destinataireId: gerants.first,
          titre: 'Pagne à préparer ✂️',
          message: 'Un livreur viendra chercher le tissu pour l\'atelier du couturier.',
          route: '/dashboard_boutiquier',
          refId: commandeId,
        );
      }
    } catch (_) {}
    AgentLivraison.traiterNouvelleLivraison(livraison.id).catchError((e) {
      if (kDebugMode) print('[Couture] Agent trajet 1 erreur: $e');
    });
  }

  // ── VUES ──────────────────────────────────────────────────────────────────

  /// Commandes de couture du client (toutes), triées côté client.
  static Stream<List<CommandeCouturier>> streamCommandesClient() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return CommandeCouturier.collection
        .where('clientId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => CommandeCouturier.fromDoc(d)).toList();
      list.sort((a, b) => b.dateCommande.compareTo(a.dateCommande));
      return list;
    });
  }

  /// Commandes reçues par un couturier (toutes), triées côté client.
  static Stream<List<CommandeCouturier>> streamCommandesCouturier(
      String couturierId) {
    return CommandeCouturier.collection
        .where('couturierId', isEqualTo: couturierId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => CommandeCouturier.fromDoc(d)).toList();
      list.sort((a, b) => b.dateCommande.compareTo(a.dateCommande));
      return list;
    });
  }

  /// Le couturier change le statut d'une commande.
  static Future<void> changerStatut({
    required String commandeId,
    required StatutCommandeCouturier statut,
  }) async {
    final maj = <String, dynamic>{'statut': statut.name};
    if (statut == StatutCommandeCouturier.confirmeeCouturier) {
      maj['dateConfirmation'] = FieldValue.serverTimestamp();
    }
    if (statut == StatutCommandeCouturier.livree) {
      maj['dateLivraisonReelle'] = FieldValue.serverTimestamp();
    }
    await CommandeCouturier.collection.doc(commandeId).update(maj);

    // TRAJET 2 : quand le vêtement est PRÊT, on crée une NOUVELLE livraison
    // indépendante (couturier → client). Elle est assignée par l'agent à
    // n'importe quel livreur disponible — pas forcément celui du trajet 1.
    if (statut == StatutCommandeCouturier.preteLivraison) {
      await _creerTrajet2(commandeId);
    }
  }

  /// Crée la livraison couturier → client (trajet 2), assignée indépendamment.
  static Future<void> _creerTrajet2(String commandeId) async {
    try {
      final doc = await CommandeCouturier.collection.doc(commandeId).get();
      final d = doc.data();
      if (d == null) return;

      final clientId = d['clientId'] as String? ?? '';
      final couturierId = d['couturierId'] as String? ?? '';

      // Coords du couturier (origine du trajet 2)
      double origLat = 9.3017, origLng = 13.3984; // fallback Garoua
      String origAdresse = 'Couturier, Garoua';
      try {
        final cq = await _db
            .collection('couturiers')
            .where('utilisateurId', isEqualTo: couturierId)
            .limit(1)
            .get();
        if (cq.docs.isNotEmpty) {
          final cd = cq.docs.first.data();
          origLat = (cd['latitude'] as num?)?.toDouble() ?? origLat;
          origLng = (cd['longitude'] as num?)?.toDouble() ?? origLng;
          origAdresse =
              'Couturier ${cd['prenom'] ?? ''} ${cd['nom'] ?? ''}, ${cd['quartier'] ?? 'Garoua'}';
        }
      } catch (_) {}

      // Coords du client (destination)
      double destLat = origLat, destLng = origLng;
      String destAdresse = 'Client';
      try {
        final uDoc = await _db.collection('utilisateurs').doc(clientId).get();
        final ud = uDoc.data();
        if (ud != null) {
          destLat = (ud['latitude'] as num?)?.toDouble() ?? destLat;
          destLng = (ud['longitude'] as num?)?.toDouble() ?? destLng;
          destAdresse = ud['quartier'] as String? ?? 'Client, Garoua';
        }
      } catch (_) {}

      final livraison = await LivraisonService.creerLivraison(
        commandeId: commandeId,
        clientId: clientId,
        boutiqueId: couturierId, // origine = couturier
        boutiqueNom: origAdresse,
        origineLat: origLat,
        origineLng: origLng,
        origineAdresse: origAdresse,
        destinationLat: destLat,
        destinationLng: destLng,
        destinationAdresse: destAdresse,
        destinationQuartier: destAdresse,
        // Encaissement TOTAL à la réception : confection + pagne + les
        // 2 courses de livraison (tissu ET vêtement)
        prixClient: ((d['prixConvenu'] as num?)?.toDouble() ?? 0) +
            ((d['prixPagne'] as num?)?.toDouble() ?? 0) +
            ((d['fraisLivraison'] as num?)?.toDouble() ?? 0),
        typeLivraison: TypeLivraison.confection,
      );

      // Lier la livraison du trajet 2 à la commande
      await CommandeCouturier.collection.doc(commandeId).update({
        'livraisonRetourId': livraison.id,
      });

      // Assigner un livreur (indépendant du trajet 1)
      AgentLivraison.traiterNouvelleLivraison(livraison.id).catchError((e) {
        if (kDebugMode) print('[Couture] Agent trajet 2 erreur: $e');
      });
    } catch (e) {
      if (kDebugMode) print('[Couture] Création trajet 2 échouée: $e');
    }
  }

  // ── NÉGOCIATION (modèles sur devis) ───────────────────────────────────────

  /// Le couturier propose un prix pour une commande sur devis.
  /// La commission est recalculée sur le prix proposé (selon son abonnement).
  static Future<void> proposerDevis({
    required String commandeId,
    required String couturierId,
    required double prixPropose,
  }) async {
    final taux = await tauxCommissionCouturier(couturierId);
    final commission = PrixFCFA.arrondirAu50(prixPropose * taux);
    await CommandeCouturier.collection.doc(commandeId).update({
      'prixPropose': prixPropose,
      'commissionPlateforme': commission,
      'statut': StatutCommandeCouturier.devisPropose.name,
    });
    final doc = await CommandeCouturier.collection.doc(commandeId).get();
    await NotificationService.envoyer(
      destinataireId: doc.data()?['clientId'] as String? ?? '',
      titre: 'Devis reçu 📄',
      message: 'Le couturier propose ${PrixFCFA.formater(prixPropose)}. Acceptez ou refusez.',
      route: '/mes-coutures', refId: commandeId,
    );
  }

  /// Le client accepte le devis proposé → le prix proposé devient le prix convenu.
  static Future<void> accepterDevis(String commandeId) async {
    final doc = await CommandeCouturier.collection.doc(commandeId).get();
    final prix = (doc.data()?['prixPropose'] as num?)?.toDouble();
    await CommandeCouturier.collection.doc(commandeId).update({
      if (prix != null) 'prixConvenu': prix,
      'statut': StatutCommandeCouturier.confirmeeCouturier.name,
    });
    // Devis accepté → le tissu peut partir : créer le TRAJET 1 maintenant.
    try {
      final data = doc.data();
      if (data != null &&
          (data['livraisonPagneId'] as String?) == null &&
          (data['pagneId'] as String?) != null) {
        await _creerTrajet1(
            commandeId: commandeId,
            pagneId: data['pagneId'] as String? ?? '',
            couturierId: data['couturierId'] as String? ?? '');
      }
    } catch (e) {
      if (kDebugMode) print('[Couture] Trajet 1 (devis accepté) échoué: $e');
    }
    await NotificationService.envoyer(
      destinataireId: doc.data()?['couturierId'] as String? ?? '',
      titre: 'Devis accepté ✅',
      message: 'Le client a accepté votre devis. La confection peut commencer.',
      refId: commandeId,
    );
  }

  /// Le client refuse le devis → la commande est annulée et le pagne
  /// décompté à la commande est RESTITUÉ au stock de la boutique.
  static Future<void> refuserDevis(String commandeId) async {
    final doc = await CommandeCouturier.collection.doc(commandeId).get();
    final pagneId = doc.data()?['pagneId'] as String?;
    await CommandeCouturier.collection.doc(commandeId).update({
      'statut': StatutCommandeCouturier.annulee.name,
    });
    if (pagneId != null && pagneId.isNotEmpty) {
      try {
        await StockService.restituerStock(pagneId: pagneId, quantite: 1);
      } catch (e) {
        if (kDebugMode) print('[Couture] Restitution stock échouée: $e');
      }
    }
  }
}

/// Unité assemblée par le client avant commande : un pagne à coudre pour un
/// bénéficiaire donné, selon un modèle, avec un mode de rencontre.
class VetementACoudre {
  final String pagneId;
  final String couturierId;
  final String modeleId;
  final String profilMesuresId;       // bénéficiaire (profil)
  final Map<String, double> mesuresSnapshot;
  final double prixConfection;
  final bool surDevis; // prix à négocier : le tissu ne part qu'après accord
  final int nombrePagnes; // quantité de tissu (boubou grand format, ensembles…)
  final ModeRencontre modeRencontre;
  final DateTime? rdvDate;
  final String? rdvLieu;
  final String? notes;

  VetementACoudre({
    required this.pagneId,
    required this.couturierId,
    required this.modeleId,
    required this.profilMesuresId,
    required this.mesuresSnapshot,
    required this.prixConfection,
    this.surDevis = false,
    this.nombrePagnes = 1,
    required this.modeRencontre,
    this.rdvDate,
    this.rdvLieu,
    this.notes,
  });
}
