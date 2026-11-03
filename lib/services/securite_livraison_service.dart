import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME DE SÉCURITÉ LIVRAISON
//
// Problème : Comment s'assurer que le livreur ne fuit pas avec les articles,
//            ne les substitue pas, ou ne les détourne pas ?
//
// Réponse en 6 couches de protection :
//
//   1. CAUTION FINANCIÈRE     → livreur bloque X FCFA à l'inscription
//   2. VÉRIFICATION IDENTITÉ  → CNI obligatoire, validé manuellement
//   3. PREUVE PHOTO PAR ÉTAPE → photo du colis scellé + photo remise
//   4. GPS CONTINU + ALERTES  → trajet tracé, anomalie = alerte admin
//   5. NOTATION + SANCTIONS   → score baisse → missions réduites → blacklist
//   6. PROFIL PUBLIC LIVREUR  → client voit CNI, photo, historique avant remise
//
// Les couches se renforcent mutuellement : un livreur qui sait que son
// identité est vérifiée, que son GPS est suivi, et que sa caution peut être
// saisie a très peu d'intérêt à frauder.
// ═══════════════════════════════════════════════════════════════════════════

// ─── Niveaux de confiance livreur ─────────────────────────────────────────────

enum NiveauConfianceLivreur {
  nouveau,         // < 10 livraisons, caution bloquée, missions limitées
  confirme,        // 10-50 livraisons, bon historique
  fiable,          // 50-200 livraisons, note > 4.2
  expert,          // > 200 livraisons, note > 4.5
  suspendu,        // suspension temporaire (enquête en cours)
  blackliste,      // fraude avérée, compte désactivé
}

// ─── Preuve photo à chaque étape ─────────────────────────────────────────────

enum TypePreuvePhoto {
  colisRecuEnBoutique,    // livreur prend le colis en boutique
  colisScelle,            // gros plan sur le scellé intact
  enTransit,              // photo optionnelle en route
  remiseAuClient,         // photo lors de la remise
  clientSatisfait,        // selfie avec le client (optionnel, client consent)
  anomalie,               // photo en cas de problème détecté
}

class PreuvePhoto {
  final String id;
  final String livraisonId;
  final String sousCommandeId;
  final TypePreuvePhoto type;
  final String urlPhoto;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? note;

  const PreuvePhoto({
    required this.id,
    required this.livraisonId,
    required this.sousCommandeId,
    required this.type,
    required this.urlPhoto,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.note,
  });

  Map<String, dynamic> toMap() => {
    'livraisonId': livraisonId,
    'sousCommandeId': sousCommandeId,
    'type': type.name,
    'urlPhoto': urlPhoto,
    'timestamp': timestamp,
    'latitude': latitude,
    'longitude': longitude,
    'note': note,
  };
}

// ─── Alerte anomalie ──────────────────────────────────────────────────────────

enum TypeAnomalielivraison {
  delaiDepasse,          // pas de mouvement GPS depuis > 30 min
  sortieZone,            // livreur sort de la zone attendue
  livraisonNonConfirmee, // pas de scan arrivée après > 2h
  conflitClient,         // client signale un problème
  cniNonVerifie,         // tente de livrer sans CNI validé
  photoManquante,        // étape sans photo
  cautionInsuffisante,   // caution en dessous du minimum
}

class Anomalielivraison {
  final String livreurId;
  final String? livraisonId;
  final TypeAnomalielivraison type;
  final String description;
  final DateTime timestamp;
  bool traitee;
  String? actionPrise;

  Anomalielivraison({
    required this.livreurId,
    this.livraisonId,
    required this.type,
    required this.description,
    required this.timestamp,
    this.traitee = false,
    this.actionPrise,
  });

  Map<String, dynamic> toMap() => {
    'livreurId': livreurId,
    'livraisonId': livraisonId,
    'type': type.name,
    'description': description,
    'timestamp': timestamp,
    'traitee': traitee,
    'actionPrise': actionPrise,
  };
}

// ─── Profil de sécurité d'un livreur ─────────────────────────────────────────

class ProfilSecuriteLivreur {
  final String livreurId;

  // Identité vérifiée
  final bool cniVerifiee;
  final String? urlPhotoCNI;
  final bool permisVerifie;
  final String? urlPhotoPermis;
  final bool selfieVerifie;     // photo du livreur avec sa CNI
  final String? urlSelfieVerification;
  final DateTime? dateVerification;
  final String? verifiePar;     // ID admin qui a validé

  // Caution financière
  final double cautionDeposee;    // FCFA bloqués
  final double cautionMinimum;    // seuil requis pour livrer
  final double cautionSaisie;     // FCFA saisis après fraudes
  final bool cautionSuffisante;

  // Score et historique
  NiveauConfianceLivreur niveauConfiance;
  final int livraisonsReussies;
  final int livraisonsEchouees;
  final int conflitsSignales;
  final int fraudesAverees;
  final double tauxReussite;

  // Sanctions
  final List<String> avertissements;
  final DateTime? suspendueJusquau;
  final String? raisonSuspension;

  ProfilSecuriteLivreur({
    required this.livreurId,
    this.cniVerifiee = false,
    this.urlPhotoCNI,
    this.permisVerifie = false,
    this.urlPhotoPermis,
    this.selfieVerifie = false,
    this.urlSelfieVerification,
    this.dateVerification,
    this.verifiePar,
    this.cautionDeposee = 0,
    this.cautionMinimum = 5000,
    this.cautionSaisie = 0,
    this.cautionSuffisante = false,
    this.niveauConfiance = NiveauConfianceLivreur.nouveau,
    this.livraisonsReussies = 0,
    this.livraisonsEchouees = 0,
    this.conflitsSignales = 0,
    this.fraudesAverees = 0,
    this.tauxReussite = 100,
    this.avertissements = const [],
    this.suspendueJusquau,
    this.raisonSuspension,
  });

  bool get peutLivrer {
    if (niveauConfiance == NiveauConfianceLivreur.blackliste) return false;
    if (niveauConfiance == NiveauConfianceLivreur.suspendu) {
      if (suspendueJusquau != null && DateTime.now().isBefore(suspendueJusquau!)) return false;
    }
    if (!cniVerifiee) return false;
    if (!cautionSuffisante) return false;
    return true;
  }

  // Montant max de colis qu'il peut transporter selon son niveau
  double get limiteValeurColis => switch (niveauConfiance) {
    NiveauConfianceLivreur.nouveau  => 25000,
    NiveauConfianceLivreur.confirme => 75000,
    NiveauConfianceLivreur.fiable   => 200000,
    NiveauConfianceLivreur.expert   => 500000,
    _                               => 0,
  };

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('securite_livreurs');

  factory ProfilSecuriteLivreur.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ProfilSecuriteLivreur(
      livreurId: doc.id,
      cniVerifiee: d['cniVerifiee'] as bool? ?? false,
      urlPhotoCNI: d['urlPhotoCNI'] as String?,
      permisVerifie: d['permisVerifie'] as bool? ?? false,
      selfieVerifie: d['selfieVerifie'] as bool? ?? false,
      urlSelfieVerification: d['urlSelfieVerification'] as String?,
      dateVerification: (d['dateVerification'] as Timestamp?)?.toDate(),
      verifiePar: d['verifiePar'] as String?,
      cautionDeposee: (d['cautionDeposee'] as num?)?.toDouble() ?? 0,
      cautionMinimum: (d['cautionMinimum'] as num?)?.toDouble() ?? 5000,
      cautionSaisie: (d['cautionSaisie'] as num?)?.toDouble() ?? 0,
      cautionSuffisante: d['cautionSuffisante'] as bool? ?? false,
      niveauConfiance: NiveauConfianceLivreur.values.firstWhere((e) => e.name == (d['niveauConfiance'] as String? ?? 'nouveau'), orElse: () => NiveauConfianceLivreur.values.first),
      livraisonsReussies: d['livraisonsReussies'] as int? ?? 0,
      livraisonsEchouees: d['livraisonsEchouees'] as int? ?? 0,
      conflitsSignales: d['conflitsSignales'] as int? ?? 0,
      fraudesAverees: d['fraudesAverees'] as int? ?? 0,
      tauxReussite: (d['tauxReussite'] as num?)?.toDouble() ?? 100,
      avertissements: List<String>.from(d['avertissements'] ?? []),
      suspendueJusquau: (d['suspendueJusquau'] as Timestamp?)?.toDate(),
      raisonSuspension: d['raisonSuspension'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'livreurId': livreurId,
    'cniVerifiee': cniVerifiee,
    'urlPhotoCNI': urlPhotoCNI,
    'permisVerifie': permisVerifie,
    'selfieVerifie': selfieVerifie,
    'urlSelfieVerification': urlSelfieVerification,
    'dateVerification': dateVerification,
    'verifiePar': verifiePar,
    'cautionDeposee': cautionDeposee,
    'cautionMinimum': cautionMinimum,
    'cautionSaisie': cautionSaisie,
    'cautionSuffisante': cautionSuffisante,
    'niveauConfiance': niveauConfiance.name,
    'livraisonsReussies': livraisonsReussies,
    'livraisonsEchouees': livraisonsEchouees,
    'conflitsSignales': conflitsSignales,
    'fraudesAverees': fraudesAverees,
    'tauxReussite': tauxReussite,
    'avertissements': avertissements,
    'suspendueJusquau': suspendueJusquau,
    'raisonSuspension': raisonSuspension,
  };
}

// ─── Service de sécurité ──────────────────────────────────────────────────────

class SecuriteLivraisonService {

  static final _db = FirebaseFirestore.instance;

  // Cautions par niveau de véhicule
  static const Map<String, double> _cautionsParVehicule = {
    'moto'     : 5000,    // 5 000 FCFA
    'tricycle' : 7500,    // 7 500 FCFA
    'voiture'  : 15000,   // 15 000 FCFA
    'vip'      : 25000,   // 25 000 FCFA
  };

  // ══════════════════════════════════════════════════════════════════════════
  // VÉRIFICATION IDENTITÉ (admin)
  // ══════════════════════════════════════════════════════════════════════════

  /// Vérifier l'identité d'un livreur (à faire par un admin)
  static Future<void> validerIdentite({
    required String livreurId,
    required String adminId,
    required String urlPhotoCNI,
    required String? urlPhotoPermis,
    required String urlSelfie,
  }) async {
    await ProfilSecuriteLivreur.collection.doc(livreurId).set({
      'cniVerifiee': true,
      'urlPhotoCNI': urlPhotoCNI,
      'permisVerifie': urlPhotoPermis != null,
      'urlPhotoPermis': urlPhotoPermis,
      'selfieVerifie': true,
      'urlSelfieVerification': urlSelfie,
      'dateVerification': FieldValue.serverTimestamp(),
      'verifiePar': adminId,
    }, SetOptions(merge: true));

    // Mettre à jour le statut dans la collection livreurs
    await _db.collection('livreurs').doc(livreurId).set({
      'estVerifie': true,
      'dateVerification': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (kDebugMode) print('[Sécurité] Identité validée : $livreurId par admin $adminId');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CAUTION FINANCIÈRE
  // ══════════════════════════════════════════════════════════════════════════

  /// Enregistrer le dépôt de caution après paiement confirmé
  static Future<void> enregistrerCaution({
    required String livreurId,
    required double montant,
    required String typeVehicule,
    required String transactionId,
  }) async {
    final minimum = _cautionsParVehicule[typeVehicule] ?? 5000;

    await _db.runTransaction((txn) async {
      final ref = ProfilSecuriteLivreur.collection.doc(livreurId);
      final doc = await txn.get(ref);
      final actuel = doc.exists
          ? (doc.data()!['cautionDeposee'] as num?)?.toDouble() ?? 0
          : 0.0;
      final nouveau = actuel + montant;

      txn.set(ref, {
        'cautionDeposee': nouveau,
        'cautionMinimum': minimum,
        'cautionSuffisante': nouveau >= minimum,
        'dernierDepotCaution': FieldValue.serverTimestamp(),
        'transactionCaution': transactionId,
      }, SetOptions(merge: true));
    });

    // Activer le livreur si caution suffisante
    final profil = await ProfilSecuriteLivreur.collection.doc(livreurId).get();
    if (profil.data()?['cautionSuffisante'] == true &&
        profil.data()?['cniVerifiee'] == true) {
      await _db.collection('livreurs').doc(livreurId).set({'disponible': true}, SetOptions(merge: true));
    }
  }

  /// Saisir partiellement la caution en cas de fraude prouvée
  static Future<void> saisirCaution({
    required String livreurId,
    required double montantSaisi,
    required String raison,
    required String adminId,
  }) async {
    await _db.runTransaction((txn) async {
      final ref = ProfilSecuriteLivreur.collection.doc(livreurId);
      final doc = await txn.get(ref);
      final actuel = (doc.data()!['cautionDeposee'] as num?)?.toDouble() ?? 0;
      final saisiActuel = (doc.data()!['cautionSaisie'] as num?)?.toDouble() ?? 0;
      final minimum = (doc.data()!['cautionMinimum'] as num?)?.toDouble() ?? 5000;

      final nouveau = (actuel - montantSaisi).clamp(0, double.infinity);

      txn.update(ref, {
        'cautionDeposee': nouveau,
        'cautionSaisie': saisiActuel + montantSaisi,
        'cautionSuffisante': nouveau >= minimum,
        'derniereSaisie': {
          'montant': montantSaisi,
          'raison': raison,
          'adminId': adminId,
          'date': DateTime.now().toIso8601String(),
        },
      });

      // Enregistrer dans l'historique
      _db.collection('saisies_caution').add({
        'livreurId': livreurId,
        'montant': montantSaisi,
        'raison': raison,
        'adminId': adminId,
        'date': FieldValue.serverTimestamp(),
      });
    });

    // Suspendre si caution insuffisante
    final profil = await ProfilSecuriteLivreur.collection.doc(livreurId).get();
    if (profil.data()?['cautionSuffisante'] == false) {
      await suspendre(livreurId: livreurId,
          raison: 'Caution insuffisante — rechargement requis',
          adminId: adminId,
          jours: 0); // suspendu jusqu'au rechargement
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PREUVES PHOTOS OBLIGATOIRES
  // ══════════════════════════════════════════════════════════════════════════

  /// Livreur prend une photo obligatoire à une étape
  static Future<String> enregistrerPreuvePhoto({
    required String livreurId,
    required String livraisonId,
    required String sousCommandeId,
    required TypePreuvePhoto type,
    required XFile photoFile,
    double? latitude,
    double? longitude,
    String? note,
  }) async {
    // Upload la photo
    final url = await StockageService.uploadXFile(
      fichier: photoFile,
      dossier: 'preuves_livraison/$livraisonId',
      nomFichier: '${type.name}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    // GARDE : une livraison de test née pendant un crash peut porter des
    // identifiants VIDES → .doc('') exploserait en assertion cryptique.
    if (sousCommandeId.isEmpty) {
      throw Exception(
          'Livraison de test corrompue (identifiant vide) — purgez les '
          'commandes en cours (Paramètres admin) et refaites une commande neuve.');
    }
    // Enregistrer la preuve
    final ref = _db
        .collection('sous_commandes').doc(sousCommandeId)
        .collection('preuves_photo').doc();

    await ref.set({
      'id': ref.id,
      'livreurId': livreurId,
      'livraisonId': livraisonId,
      'sousCommandeId': sousCommandeId,
      'type': type.name,
      'urlPhoto': url,
      'timestamp': FieldValue.serverTimestamp(),
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
    }, SetOptions(merge: true));

    // Tracer la preuve SUR LA LIVRAISON RACINE (l'ancienne cible était
    // la sous-collection legacy, inexistante → NOT_FOUND). set+merge :
    // ne peut jamais échouer sur un doc absent.
    await _db.collection('livraisons').doc(livraisonId).set({
      'photo${_capitalise(type.name)}': url,
      'timestamp${_capitalise(type.name)}': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (kDebugMode) print('[Sécurité] Preuve photo enregistrée : ${type.name}');
    return url;
  }

  /// Vérifier qu'une étape critique a bien une photo
  static Future<bool> preuvePhotoExiste({
    required String sousCommandeId,
    required TypePreuvePhoto type,
  }) async {
    final snap = await _db
        .collection('sous_commandes').doc(sousCommandeId)
        .collection('preuves_photo')
        .where('type', isEqualTo: type.name)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DÉTECTION D'ANOMALIES
  // ══════════════════════════════════════════════════════════════════════════

  /// Vérifier les livraisons en cours et détecter les anomalies
  static Future<List<Anomalielivraison>> detecterAnomalies(String livreurId) async {
    final anomalies = <Anomalielivraison>[];
    final maintenant = DateTime.now();

    // Récupérer les livraisons en cours
    final livraisonsSnap = await _db.collectionGroup('livraisons')
        .where('livreurId', isEqualTo: livreurId)
        .where('statut', isEqualTo: 'enCours')
        .get();

    for (final doc in livraisonsSnap.docs) {
      final data = doc.data();
      final datePrise = (data['datePrisEnCharge'] as Timestamp?)?.toDate();
      final livraisonId = doc.id;
      final scId = doc.reference.parent.parent?.id ?? '';

      if (datePrise == null) continue;

      final duree = maintenant.difference(datePrise);

      // Anomalie 1 : Délai dépassé (> 2h pour Garoua)
      if (duree.inMinutes > 120) {
        anomalies.add(Anomalielivraison(
          livreurId: livreurId,
          livraisonId: livraisonId,
          type: TypeAnomalielivraison.livraisonNonConfirmee,
          description: 'Livraison en cours depuis ${duree.inMinutes} min sans confirmation',
          timestamp: maintenant,
        ));
      }

      // Anomalie 2 : Photo manquante à la prise en charge
      final aPhoto = await preuvePhotoExiste(
        sousCommandeId: scId,
        type: TypePreuvePhoto.colisRecuEnBoutique,
      );
      if (!aPhoto) {
        anomalies.add(Anomalielivraison(
          livreurId: livreurId,
          livraisonId: livraisonId,
          type: TypeAnomalielivraison.photoManquante,
          description: 'Aucune photo de prise en charge enregistrée',
          timestamp: maintenant,
        ));
      }
    }

    // Enregistrer les anomalies
    for (final a in List.of(anomalies)) {
      await _db.collection('anomalies_livraison').add(a.toMap());
    }

    return anomalies;
  }

  /// Client signale un problème
  static Future<void> signalerProbleme({
    required String clientId,
    required String livreurId,
    required String sousCommandeId,
    required String description,
    required TypeAnomalielivraison type,
    XFile? photoPreuve,
  }) async {
    String? urlPreuve;
    if (photoPreuve != null) {
      urlPreuve = await StockageService.uploadXFile(
        fichier: photoPreuve,
        dossier: 'signalements',
        nomFichier: '${clientId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    }

    await _db.collection('anomalies_livraison').add({
      'livreurId': livreurId,
      'clientId': clientId,
      'sousCommandeId': sousCommandeId,
      'type': type.name,
      'description': description,
      'urlPreuve': urlPreuve,
      'timestamp': FieldValue.serverTimestamp(),
      'traitee': false,
      'initiateurType': 'client',
    });

    // Incrémenter le compteur de conflits du livreur
    await ProfilSecuriteLivreur.collection.doc(livreurId).set({
      'conflitsSignales': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // Si > 3 conflits → alerte admin
    final profil = await ProfilSecuriteLivreur.collection.doc(livreurId).get();
    final conflits = profil.data()?['conflitsSignales'] as int? ?? 0;
    if (conflits >= 3) {
      await _creerAlerteAdmin(
        livreurId: livreurId,
        message: '$conflits conflits signalés — investigation requise',
        niveau: 'haute',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTATION ET SANCTIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Mettre à jour le score après une livraison
  static Future<void> mettreAJourScore({
    required String livreurId,
    required bool livraisonReussie,
    required double noteClient,       // 1.0 à 5.0
    required bool dansLeDelai,
    required bool photosCompletes,
  }) async {
    await _db.runTransaction((txn) async {
      final ref = ProfilSecuriteLivreur.collection.doc(livreurId);
      final doc = await txn.get(ref);
      final d = doc.data() ?? {};

      final reussies = (d['livraisonsReussies'] as int? ?? 0) +
          (livraisonReussie ? 1 : 0);
      final echouees = (d['livraisonsEchouees'] as int? ?? 0) +
          (livraisonReussie ? 0 : 1);
      final total = reussies + echouees;
      final tauxReussite = total > 0 ? (reussies / total * 100) : 100.0;

      // Recalculer le niveau de confiance
      final niveau = _calculerNiveau(
        reussies: reussies,
        tauxReussite: tauxReussite,
        conflits: d['conflitsSignales'] as int? ?? 0,
        fraudes: d['fraudesAverees'] as int? ?? 0,
      );

      txn.update(ref, {
        'livraisonsReussies': reussies,
        'livraisonsEchouees': echouees,
        'tauxReussite': tauxReussite,
        'niveauConfiance': niveau.name,
        'derniereNoteClient': noteClient,
        'dateDerriereLivraison': FieldValue.serverTimestamp(),
      });

      // Mettre à jour la note dans la collection principale
      final livreurRef = _db.collection('livreurs').doc(livreurId);
      final livreurDoc = await txn.get(livreurRef);
      if (livreurDoc.exists) {
        final ancienneNote = (livreurDoc.data()!['noteMoyenne'] as num?)?.toDouble() ?? 0;
        final nbLivraisons = livreurDoc.data()!['nombreLivraisons'] as int? ?? 0;
        // Moyenne pondérée
        final nouvelleNote = nbLivraisons > 0
            ? ((ancienneNote * nbLivraisons) + noteClient) / (nbLivraisons + 1)
            : noteClient;
        txn.update(livreurRef, {
          'noteMoyenne': double.parse(nouvelleNote.toStringAsFixed(2)),
          'nombreLivraisons': nbLivraisons + 1,
        });
      }
    });
  }

  /// Suspendre un livreur
  static Future<void> suspendre({
    required String livreurId,
    required String raison,
    required String adminId,
    int jours = 7,
  }) async {
    final suspenduJusquau = jours > 0
        ? DateTime.now().add(Duration(days: jours))
        : null;

    await ProfilSecuriteLivreur.collection.doc(livreurId).update({
      'niveauConfiance': NiveauConfianceLivreur.suspendu.name,
      'suspendueJusquau': suspenduJusquau,
      'raisonSuspension': raison,
      'dateSuspension': FieldValue.serverTimestamp(),
      'suspenduPar': adminId,
    });

    await _db.collection('livreurs').doc(livreurId).set({'disponible': false}, SetOptions(merge: true));

    if (kDebugMode) print('[Sécurité] Livreur $livreurId suspendu pour $jours jours : $raison');
  }

  /// Blacklister définitivement
  static Future<void> blacklister({
    required String livreurId,
    required String raison,
    required String adminId,
    double montantSaisiCaution = 0,
  }) async {
    final batch = _db.batch();

    batch.update(ProfilSecuriteLivreur.collection.doc(livreurId), {
      'niveauConfiance': NiveauConfianceLivreur.blackliste.name,
      'raisonBlacklist': raison,
      'dateBlacklist': FieldValue.serverTimestamp(),
      'blacklistePar': adminId,
    });

    batch.update(_db.collection('livreurs').doc(livreurId), {
      'disponible': false,
      'estVerifie': false,
    });

    await batch.commit();

    // Saisir la caution si fraude
    if (montantSaisiCaution > 0) {
      await saisirCaution(
        livreurId: livreurId,
        montantSaisi: montantSaisiCaution,
        raison: 'Fraude avérée — blacklist',
        adminId: adminId,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROFIL PUBLIC LIVREUR (visible par le client avant remise)
  // ══════════════════════════════════════════════════════════════════════════

  /// Récupérer le profil public d'un livreur pour le client
  static Future<ProfilPublicLivreur?> getProfilPublic(String livreurId) async {
    final livreurDoc = await _db.collection('livreurs').doc(livreurId).get();
    final securiteDoc = await ProfilSecuriteLivreur.collection.doc(livreurId).get();

    if (!livreurDoc.exists) return null;
    final l = livreurDoc.data()!;
    final s = securiteDoc.data() ?? {};

    return ProfilPublicLivreur(
      id: livreurId,
      nom: '${l['prenom']} ${l['nom']}',
      photo: l['photo'] as String? ?? '',
      typeVehicule: l['typeVehicule'] as String? ?? 'moto',
      noteMoyenne: (l['noteMoyenne'] as num?)?.toDouble() ?? 0,
      nombreLivraisons: l['nombreLivraisons'] as int? ?? 0,
      cniVerifiee: s['cniVerifiee'] as bool? ?? false,
      niveauConfiance: NiveauConfianceLivreur.values.firstWhere((e) => e.name == (s['niveauConfiance'] as String? ?? 'nouveau'), orElse: () => NiveauConfianceLivreur.values.first),
      tauxReussite: (s['tauxReussite'] as num?)?.toDouble() ?? 100,
      // Numéro masqué pour la confidentialité
      telephoneMasque: _masquerTelephone(l['telephone'] as String? ?? ''),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITAIRES PRIVÉS
  // ══════════════════════════════════════════════════════════════════════════

  static NiveauConfianceLivreur _calculerNiveau({
    required int reussies,
    required double tauxReussite,
    required int conflits,
    required int fraudes,
  }) {
    if (fraudes > 0) return NiveauConfianceLivreur.blackliste;
    if (conflits > 5 || tauxReussite < 70) return NiveauConfianceLivreur.suspendu;
    if (reussies >= 200 && tauxReussite >= 95) return NiveauConfianceLivreur.expert;
    if (reussies >= 50 && tauxReussite >= 90) return NiveauConfianceLivreur.fiable;
    if (reussies >= 10 && tauxReussite >= 80) return NiveauConfianceLivreur.confirme;
    return NiveauConfianceLivreur.nouveau;
  }

  static String _masquerTelephone(String tel) {
    if (tel.length < 8) return tel;
    final visible = tel.substring(tel.length - 3);
    return '****** $visible';
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Future<void> _creerAlerteAdmin({
    required String livreurId,
    required String message,
    required String niveau,
  }) async {
    // UNE seule boîte : la Supervision (alertes_agent). Niveau 'haute' /
    // 'critique' → URGENT ; sinon info. Avant : 'alertes_admin', jamais lue.
    await _db.collection('alertes_agent').add({
      'type': 'securite_livreur',
      'livraisonId': '',
      'livreurId': livreurId,
      'niveau': (niveau == 'haute' || niveau == 'critique') ? 'urgent' : 'info',
      'statut': 'en_attente',
      'message': '🛡️ Sécurité livreur : $message',
      'dateCreation': DateTime.now(),
    });
  }
}

// ─── Profil public livreur ────────────────────────────────────────────────────

class ProfilPublicLivreur {
  final String id;
  final String nom;
  final String photo;
  final String typeVehicule;
  final double noteMoyenne;
  final int nombreLivraisons;
  final bool cniVerifiee;
  final NiveauConfianceLivreur niveauConfiance;
  final double tauxReussite;
  final String telephoneMasque;

  const ProfilPublicLivreur({
    required this.id,
    required this.nom,
    required this.photo,
    required this.typeVehicule,
    required this.noteMoyenne,
    required this.nombreLivraisons,
    required this.cniVerifiee,
    required this.niveauConfiance,
    required this.tauxReussite,
    required this.telephoneMasque,
  });

  String get badgeNiveau => switch (niveauConfiance) {
    NiveauConfianceLivreur.nouveau  => '🆕 Nouveau',
    NiveauConfianceLivreur.confirme => '✅ Confirmé',
    NiveauConfianceLivreur.fiable   => '⭐ Fiable',
    NiveauConfianceLivreur.expert   => '🏆 Expert',
    _ => '⚠️ Indisponible',
  };

  String get montantCautionFmt =>
      PrixFCFA.formater(switch (niveauConfiance) {
        NiveauConfianceLivreur.expert  => 25000,
        NiveauConfianceLivreur.fiable  => 15000,
        NiveauConfianceLivreur.confirme => 7500,
        _                              => 5000,
      });
}
