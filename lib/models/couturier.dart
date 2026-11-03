import 'package:cloud_firestore/cloud_firestore.dart';

enum StatutCouturier {
  disponible,
  occupee,
  inactif,
  suspendu,
}

enum SpecialiteCouturier {
  bazin,
  pagne,
  gandoura,
  boubou,
  robe,
  costume,
  tous,
}

class Couturier {
  final String id;
  final String utilisateurId; // lié au compte utilisateur
  final String nom;
  final String prenom;
  final String telephone;
  final String adresse;
  final String quartier;
  final double latitude;
  final double longitude;
  final List<SpecialiteCouturier> specialites;
  final double noteMoyenne;
  final int nombreCommandes;
  StatutCouturier statut;

  // Champs pour l'agent IA
  final double tauxAcceptation;    // % de commandes acceptées
  final double tauxRespectDelai;   // % de livraisons dans les délais
  final int delaiMoyenJours;       // délai moyen de confection
  final double creditBalance;      // solde crédits plateforme
  final String billingModel;       // 'per_order' ou 'per_commission'

  // Disponibilité
  final List<String> joursDisponibles; // ['lundi','mardi'...]
  final String heureOuverture;
  final String heureFermeture;
  final String photo;
  final String description;
  final DateTime dateInscription;
  final bool estVerifie;

  Couturier({
    required this.id,
    required this.utilisateurId,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.adresse,
    required this.quartier,
    required this.latitude,
    required this.longitude,
    required this.specialites,
    this.noteMoyenne = 0.0,
    this.nombreCommandes = 0,
    this.statut = StatutCouturier.disponible,
    this.tauxAcceptation = 100.0,
    this.tauxRespectDelai = 100.0,
    this.delaiMoyenJours = 3,
    this.creditBalance = 0.0,
    this.billingModel = 'per_commission',
    this.joursDisponibles = const ['lundi','mardi','mercredi','jeudi','vendredi','samedi'],
    this.heureOuverture = '08:00',
    this.heureFermeture = '18:00',
    this.photo = '',
    this.description = '',
    required this.dateInscription,
    this.estVerifie = false,
  });

  static CollectionReference<Map<String, dynamic>> couturierCollection =
      FirebaseFirestore.instance.collection('couturiers');

  factory Couturier.fromFirebaseDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Couturier(
      id: doc.id,
      utilisateurId: data['utilisateurId'] as String? ?? '',
      nom: data['nom'] as String? ?? '',
      prenom: data['prenom'] as String? ?? '',
      telephone: data['telephone'] as String? ?? '',
      adresse: data['adresse'] as String? ?? '',
      quartier: data['quartier'] as String? ?? '',
      latitude: (data['latitude'] as num? ?? 0).toDouble(),
      longitude: (data['longitude'] as num? ?? 0).toDouble(),
      specialites: (data['specialites'] as List<dynamic>)
          .map((s) => SpecialiteCouturier.values.firstWhere((e) => e.name == (s?.toString() ?? ''), orElse: () => SpecialiteCouturier.values.first))
          .toList(),
      noteMoyenne: (data['noteMoyenne'] as num?)?.toDouble() ?? 0.0,
      nombreCommandes: data['nombreCommandes'] as int? ?? 0,
      statut: StatutCouturier.values.firstWhere((e) => e.name == (data['statut'] as String? ?? 'disponible'), orElse: () => StatutCouturier.values.first),
      tauxAcceptation: (data['tauxAcceptation'] as num?)?.toDouble() ?? 100.0,
      tauxRespectDelai: (data['tauxRespectDelai'] as num?)?.toDouble() ?? 100.0,
      delaiMoyenJours: data['delaiMoyenJours'] as int? ?? 3,
      creditBalance: (data['creditBalance'] as num?)?.toDouble() ?? 0.0,
      billingModel: data['billingModel'] as String? ?? 'per_commission',
      joursDisponibles: List<String>.from(data['joursDisponibles'] ?? []),
      heureOuverture: data['heureOuverture'] as String? ?? '08:00',
      heureFermeture: data['heureFermeture'] as String? ?? '18:00',
      photo: data['photo'] as String? ?? '',
      description: data['description'] as String? ?? '',
      dateInscription: ((data['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now()),
      estVerifie: data['estVerifie'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'utilisateurId': utilisateurId,
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'adresse': adresse,
      'quartier': quartier,
      'latitude': latitude,
      'longitude': longitude,
      'specialites': specialites.map((s) => s.name).toList(),
      'noteMoyenne': noteMoyenne,
      'nombreCommandes': nombreCommandes,
      'statut': statut.name,
      'tauxAcceptation': tauxAcceptation,
      'tauxRespectDelai': tauxRespectDelai,
      'delaiMoyenJours': delaiMoyenJours,
      'creditBalance': creditBalance,
      'billingModel': billingModel,
      'joursDisponibles': joursDisponibles,
      'heureOuverture': heureOuverture,
      'heureFermeture': heureFermeture,
      'photo': photo,
      'description': description,
      'dateInscription': dateInscription,
      'estVerifie': estVerifie,
    };
  }
}
