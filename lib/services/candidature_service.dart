import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/l10n/tr.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CANDIDATURES PARTENAIRES
//
// Flux : un utilisateur (client) dépose une candidature pour devenir
// boutiquier, couturier ou livreur → l'admin VALIDE JUSTE (ou refuse).
// À la validation : le rôle de l'utilisateur change ET l'entité métier
// (boutique / fiche couturier / fiche livreur) est créée automatiquement
// à partir des infos du dossier.
// ═══════════════════════════════════════════════════════════════════════════

class CandidatureService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get collection =>
      _db.collection('candidatures');

  /// Dépose une candidature. `type` ∈ {boutiquier, couturier, livreur}.
  /// `infos` contient les champs du formulaire selon le type.
  static Future<void> deposer({
    required String type,
    required Map<String, dynamic> infos,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Non connecté');

    // Une seule candidature en attente par utilisateur et par type
    final existante = await collection
        .where('utilisateurId', isEqualTo: user.uid)
        .where('statut', isEqualTo: 'enAttente')
        .get();
    if (existante.docs.any((d) => d.data()['type'] == type)) {
      throw Exception('Vous avez déjà une candidature en attente pour ce rôle');
    }

    await collection.add({
      'utilisateurId': user.uid,
      'type': type,
      'infos': infos,
      'statut': 'enAttente',
      'dateDepot': FieldValue.serverTimestamp(),
    });

    // Prévenir les admins : sans notification, la candidature reste
    // invisible jusqu'à ce que quelqu'un pense à ouvrir la page.
    try {
      final admins = await _db
          .collection('utilisateurs')
          .where('role', isEqualTo: 'admin')
          .limit(5)
          .get();
      for (final a in admins.docs) {
        await NotificationService.envoyer(
          destinataireId: a.id,
          titre: (Tr t) => t.nouvelleCandidature,
          message: (Tr t) => t.candidatAttendVotreValidation(type),
          route: '/candidatures',
          refId: user.uid,
        );
      }
    } catch (_) {}
  }

  /// Flux des candidatures en attente (admin). Tri côté client.
  static Stream<List<Candidature>> streamEnAttente() {
    return collection
        .where('statut', isEqualTo: 'enAttente')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => Candidature.fromDoc(d)).toList();
      list.sort((a, b) =>
          (b.dateDepot ?? DateTime(2000)).compareTo(a.dateDepot ?? DateTime(2000)));
      return list;
    });
  }

  /// L'ADMIN VALIDE : change le rôle de l'utilisateur + crée l'entité métier.
  static Future<void> valider(Candidature c) async {
    final infos = c.infos;
    final batch = _db.batch();

    // 1. Créer l'entité métier selon le type
    switch (c.type) {
      case 'boutiquier':
        final bRef = _db.collection('boutiques').doc();
        batch.set(bRef, {
          'nom': infos['nomBoutique'] ?? Tr.s.boutique,
          'adresse': infos['quartier'] ?? 'Garoua',
          'telephone': infos['telephone'] ?? '',
          'description': infos['description'] ?? '',
          'logo': '',
          'methodesPaiement': ['cash', 'mobile_money'],
          'gerants': [c.utilisateurId],
          'ville': 'Garoua',
          'quartier': infos['quartier'] ?? '',
          'creditBalance': 0.0,
          'billingModel': 'per_commission', // gratuit pour attirer (hybride)
          'minimumBalance': 2000.0,
          'estActif': true,
          if (infos['latitude'] != null)
            'latitude': (infos['latitude'] as num? ?? 0).toDouble(),
          if (infos['longitude'] != null)
            'longitude': (infos['longitude'] as num? ?? 0).toDouble(),
          'dateInscription': FieldValue.serverTimestamp(),
        });
        break;

      case 'couturier':
        // id de fiche = uid : une seule lignée (comme la promotion admin,
        // gestion_utilisateurs_page) — les règles et les requêtes
        // `where('…Id', isEqualTo: uid)` supposent cette égalité.
        final cRef = _db.collection('couturiers').doc(c.utilisateurId);
        batch.set(cRef, {
          'utilisateurId': c.utilisateurId,
          'nom': infos['nom'] ?? '',
          'prenom': infos['prenom'] ?? '',
          'telephone': infos['telephone'] ?? '',
          'adresse': infos['quartier'] ?? 'Garoua',
          'quartier': infos['quartier'] ?? 'Garoua',
          // GPS de l'atelier capturé SUR PLACE à la candidature
          // (fallback Garoua si absent — anciens dossiers).
          'latitude': (infos['latitude'] as num?)?.toDouble() ?? 9.3017,
          'longitude': (infos['longitude'] as num?)?.toDouble() ?? 13.3984,
          'specialites': <String>[],
          'statut': 'disponible',
          'noteMoyenne': 0.0,
          'nombreCommandes': 0,
          'tauxAcceptation': 100.0,
          'typeAbonnement': 'gratuit',
          'creditBalance': 0.0,
          'dateInscription': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        break;

      case 'livreur':
        // id de fiche = uid : `livraisons.livreurId` (fiche) == moi() dans
        // les règles, le scan de départ (livraison.livreurId != uid) et le
        // tableau de bord livreur (where livreurId == uid). Avant : id auto
        // → ces trois contrôles échouaient pour tout livreur issu d'une
        // candidature (seuls les livreurs promus par l'admin marchaient).
        final lRef = _db.collection('livreurs').doc(c.utilisateurId);
        // (fiche marquée candidature plus bas via origine)
        batch.set(lRef, {
          'utilisateurId': c.utilisateurId,
          'nom': infos['nom'] ?? '',
          'prenom': infos['prenom'] ?? '',
          'telephone': infos['telephone'] ?? '',
          'quartierBase': infos['quartier'] ?? 'Garoua',
          'typeVehicule': infos['typeVehicule'] ?? 'moto',
          'numeroCNI': infos['numeroCNI'] ?? '',
          'statut': 'disponible',
          'estVerifie': true, // validé par l'admin
          'cautionDeposee': false,
          'creditBalance': 0.0,
          'gainTotal': 0.0,
          'dateInscription': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        break;

      default:
        throw Exception('Type de candidature inconnu : ${c.type}');
    }

    // 2. Changer le rôle de l'utilisateur
    batch.update(_db.collection('utilisateurs').doc(c.utilisateurId), {
      'role': c.type,
      'origineRole': 'candidature',       // vs 'admin' (traçabilité)
      'origineRoleLe': FieldValue.serverTimestamp(),
    });

    // 3. Marquer la candidature validée
    batch.update(collection.doc(c.id), {
      'statut': 'validee',
      'dateTraitement': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    await _purgerCNI(c); // conformité loi 2024/017 : la pièce n'a plus d'utilité
    await NotificationService.envoyer(
      destinataireId: c.utilisateurId,
      titre: (Tr t) => t.candidatureValidee,
      message: (Tr t) => t.votreCompteEstActiveBienvenue(c.type),
    );
  }

  /// L'admin refuse (avec motif optionnel).
  static Future<void> refuser(Candidature c, {String? motif}) async {
    await collection.doc(c.id).update({
      'statut': 'refusee',
      if (motif != null && motif.isNotEmpty) 'motifRefus': motif,
      'dateTraitement': FieldValue.serverTimestamp(),
    });
    await _purgerCNI(c);
    await NotificationService.envoyer(
      destinataireId: c.utilisateurId,
      titre: (Tr t) => t.candidatureRefusee,
      message: motif?.isNotEmpty == true
          ? Tr.s.motif2(motif)
          : Tr.s.votreCandidatureEteRefusee(c.type),
    );
  }

  /// Efface la photo de la pièce d'identité une fois la candidature
  /// traitée (protection des données — activable dans les Paramètres).
  static Future<void> _purgerCNI(Candidature c) async {
    try {
      if (!await ParametresService.supprimerCNIApresTraitement()) return;
      if (c.infos['pieceIdentite'] == null) return;
      await collection.doc(c.id).update({'infos.pieceIdentite': FieldValue.delete()});
    } catch (_) {}
  }

  /// Candidatures de l'utilisateur courant (pour afficher le suivi).
  static Stream<List<Candidature>> streamMesCandidatures() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return collection
        .where('utilisateurId', isEqualTo: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Candidature.fromDoc(d)).toList());
  }
}

class Candidature {
  final String id;
  final String utilisateurId;
  final String type; // boutiquier | couturier | livreur
  final Map<String, dynamic> infos;
  final String statut; // enAttente | validee | refusee
  final DateTime? dateDepot;

  Candidature({
    required this.id,
    required this.utilisateurId,
    required this.type,
    required this.infos,
    required this.statut,
    this.dateDepot,
  });

  factory Candidature.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Candidature(
      id: doc.id,
      utilisateurId: d['utilisateurId'] as String? ?? '',
      type: d['type'] as String? ?? '',
      infos: Map<String, dynamic>.from(d['infos'] as Map? ?? {}),
      statut: d['statut'] as String? ?? 'enAttente',
      dateDepot: (d['dateDepot'] is Timestamp)
          ? ((d['dateDepot'] as Timestamp?)?.toDate() ?? DateTime.now())
          : null,
    );
  }
}
