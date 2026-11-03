import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Boutique {
  final String id;
  final String nom;
  final String adresse;
  final String telephone;
  final String description;
  final String logo;
  final List<String> methodesPaiement;
  final List<String> gerants;
  final bool? contactVisible; // numéro affiché publiquement (admin/premium)
  final String? abonnement;   // niveau d'abonnement (per la politique contact)
  final String? ville;
  final String? quartier;
  final double creditBalance;
  final String billingModel;
  final double minimumBalance;
  final bool estActif;
  final bool retraitEnBoutique; // le client vient payer/retirer sur place
  final DateTime? dateInscription;
  final double? latitude;   // coordonnée GPS (null si pas encore renseignée)
  final double? longitude;
  final DateTime? franchiseGratuiteJusqu; // période gratuite (0 commission) accordée par l'admin

  Boutique({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.telephone,
    required this.description,
    required this.logo,
    required this.methodesPaiement,
    required this.gerants,
    this.contactVisible,
    this.abonnement,
    this.ville,
    this.quartier,
    this.creditBalance = 0.0,
    this.billingModel = 'per_commission',
    this.minimumBalance = 2000.0,
    this.estActif = true,
    this.retraitEnBoutique = false,
    this.dateInscription,
    this.latitude,
    this.longitude,
    this.franchiseGratuiteJusqu,
  });

  static CollectionReference<Map<String, dynamic>> boutiqueCollection =
      FirebaseFirestore.instance.collection('boutiques');

  static Future<String> getNextId() async {
    final counterDoc = await FirebaseFirestore.instance
        .collection('counters')
        .doc('boutiqueCounter')
        .get();

    int nextId = counterDoc.exists ? counterDoc['nextId'] + 1 : 1;

    await FirebaseFirestore.instance
        .collection('counters')
        .doc('boutiqueCounter')
        .set({'nextId': nextId});

    return nextId.toString();
  }

  factory Boutique.fromFirebaseDocuments(Map<String, dynamic> data) {
    return Boutique(
      id: data['id'] as String? ?? '',
      nom: data['nom'] as String? ?? '',
      adresse: data['adresse'] as String? ?? '',
      telephone: data['telephone'] as String? ?? '',
      description: data['description'] as String? ?? '',
      logo: data['logo'] as String? ?? '',
      methodesPaiement: List<String>.from(data['methodesPaiement']),
      gerants: List<String>.from(data['gerants']),
      contactVisible: data['contactVisible'] as bool?,
      abonnement: data['abonnement'] as String?,
    );
  }

  static Boutique fromMap(Map<String, dynamic> map) {
    return Boutique(
      id: map['id'] as String? ?? '',
      nom: map['nom'] as String? ?? '',
      adresse: map['adresse'] as String? ?? '',
      telephone: map['telephone'] as String? ?? '',
      description: map['description'] as String? ?? '',
      logo: map['logo'] as String? ?? '',
      methodesPaiement: List<String>.from(map['methodesPaiement']),
      gerants: List<String>.from(map['gerants']),
    );
  }

  static Boutique fromFirebaseDocument(DocumentSnapshot doc) {
    return Boutique(
      id: doc.id,
      nom: doc['nom'] as String? ?? '',
      adresse: doc['adresse'] as String? ?? '',
      telephone: doc['telephone'] as String? ?? '',
      description: doc['description'] as String? ?? '',
      logo: doc['logo'] as String? ?? '',
      methodesPaiement: List<String>.from(doc['methodesPaiement']),
      gerants: List<String>.from(doc['gerants'] ?? []),
      ville: doc.data() != null && (doc.data() as Map).containsKey('ville') ? doc['ville'] as String? : null,
      quartier: doc.data() != null && (doc.data() as Map).containsKey('quartier') ? doc['quartier'] as String? : null,
      creditBalance: (doc.data() != null && (doc.data() as Map).containsKey('creditBalance')) ? (doc['creditBalance'] as num?)?.toDouble() ?? 0.0 : 0.0,
      billingModel: doc.data() != null && (doc.data() as Map).containsKey('billingModel') ? doc['billingModel'] as String? ?? 'per_commission' : 'per_commission',
      minimumBalance: doc.data() != null && (doc.data() as Map).containsKey('minimumBalance') ? (doc['minimumBalance'] as num?)?.toDouble() ?? 2000.0 : 2000.0,
      estActif: doc.data() != null && (doc.data() as Map).containsKey('estActif') ? doc['estActif'] as bool? ?? true : true,
      retraitEnBoutique: doc.data() != null && (doc.data() as Map).containsKey('retraitEnBoutique') ? doc['retraitEnBoutique'] as bool? ?? false : false,
      dateInscription: doc.data() != null && (doc.data() as Map).containsKey('dateInscription') ? (doc['dateInscription'] as Timestamp?)?.toDate() : null,
      latitude: doc.data() != null && (doc.data() as Map).containsKey('latitude') ? (doc['latitude'] as num?)?.toDouble() : null,
      longitude: doc.data() != null && (doc.data() as Map).containsKey('longitude') ? (doc['longitude'] as num?)?.toDouble() : null,
      franchiseGratuiteJusqu: doc.data() != null && (doc.data() as Map).containsKey('franchiseGratuiteJusqu') && doc['franchiseGratuiteJusqu'] != null ? ((doc['franchiseGratuiteJusqu'] as Timestamp?)?.toDate() ?? DateTime.now()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'adresse': adresse,
      'telephone': telephone,
      'description': description,
      'logo': logo,
      'methodesPaiement': methodesPaiement,
      'gerants': gerants,
      'ville': ville,
      'quartier': quartier,
      'creditBalance': creditBalance,
      'billingModel': billingModel,
      'franchiseGratuiteJusqu': franchiseGratuiteJusqu,
      'minimumBalance': minimumBalance,
      'estActif': estActif,
      'retraitEnBoutique': retraitEnBoutique,
      'dateInscription': dateInscription,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  Future<void> addToFirebase() async {
    try {
      await boutiqueCollection.doc(id).set(toMap());
      if (kDebugMode) print('Boutique ajoutée : $id');
    } catch (e) {
      if (kDebugMode) print('Erreur ajout boutique : $e');
    }
  }
}