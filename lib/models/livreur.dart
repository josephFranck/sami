import 'package:sami/services/securite_livraison_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum StatutLivreur {
  disponible,
  enCourse,
  inactif,
  suspendu,
}

enum TypeVehicule {
  moto,
  tricycle,
  velo,
  apied,
}

class Livreur {
  final String id;
  final String utilisateurId;
  final String? origine; // 'admin' | 'candidature'
  final String nom;
  final String prenom;
  final String telephone;
  final String quartierBase; // quartier de départ habituel
  double latitude;           // position temps réel
  double longitude;
  final TypeVehicule typeVehicule;
  final String numeroCNI;
  final double encoursCash; // cash collecté non encore remis (plafond)
  final DateTime? autoriseJusquau; // dérogation admin : éligible jusqu'à cette date
  final String numeroPermis;
  StatutLivreur statut;
  final String photo;

  // Métriques pour l'agent IA
  final double noteMoyenne;
  final int nombreLivraisons;
  final double tauxRespectDelai;
  final double distanceTotaleKm;
  final double creditBalance;
  final double gainTotal;

  // Disponibilité
  final bool disponibleMatin;   // 7h-12h (marché, pagnes)
  final bool disponibleApresmidi; // 12h-17h
  final bool disponibleSoir;    // 17h-22h (suya, food)

  final DateTime dateInscription;
  final bool estVerifie;
  final double cautionDeposee;
  final NiveauConfianceLivreur niveauConfiance;
  final int conflitsSignales;
  final double limiteValeurColis;
  final DateTime? dernierePosition; // timestamp dernière mise à jour GPS

  Livreur({
    required this.id,
    required this.utilisateurId,
    this.origine,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.quartierBase,
    this.latitude = 0.0,
    this.longitude = 0.0,
    required this.typeVehicule,
    required this.numeroCNI,
    this.encoursCash = 0,
    this.autoriseJusquau,
    this.numeroPermis = '',
    this.statut = StatutLivreur.disponible,
    this.photo = '',
    this.noteMoyenne = 0.0,
    this.nombreLivraisons = 0,
    this.tauxRespectDelai = 100.0,
    this.distanceTotaleKm = 0.0,
    this.creditBalance = 0.0,
    this.gainTotal = 0.0,
    this.disponibleMatin = true,
    this.disponibleApresmidi = true,
    this.disponibleSoir = false,
    required this.dateInscription,
    this.estVerifie = false,
    this.dernierePosition,
    this.cautionDeposee = 0.0,
    this.niveauConfiance = NiveauConfianceLivreur.nouveau,
    this.conflitsSignales = 0,
    this.limiteValeurColis = 25000.0,
  });

  static CollectionReference<Map<String, dynamic>> livreurCollection =
      FirebaseFirestore.instance.collection('livreurs');

  factory Livreur.fromFirebaseDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Livreur(
      id: doc.id,
      utilisateurId: data['utilisateurId'] as String? ?? '',
      origine: data['origine'] as String?,
      nom: data['nom'] as String? ?? '',
      prenom: data['prenom'] as String? ?? '',
      telephone: data['telephone'] as String? ?? '',
      quartierBase: data['quartierBase'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      typeVehicule: TypeVehicule.values.firstWhere((e) => e.name == (data['typeVehicule'] as String? ?? 'moto'), orElse: () => TypeVehicule.values.first),
      numeroCNI: data['numeroCNI'] as String? ?? '',
      encoursCash: (data['encoursCash'] as num?)?.toDouble() ?? 0,
      autoriseJusquau: (data['autoriseJusquau'] as Timestamp?)?.toDate(),
      numeroPermis: data['numeroPermis'] as String? ?? '',
      statut: StatutLivreur.values.firstWhere((e) => e.name == (data['statut'] as String? ?? 'disponible'), orElse: () => StatutLivreur.values.first),
      photo: data['photo'] as String? ?? '',
      noteMoyenne: (data['noteMoyenne'] as num?)?.toDouble() ?? 0.0,
      nombreLivraisons: data['nombreLivraisons'] as int? ?? 0,
      tauxRespectDelai: (data['tauxRespectDelai'] as num?)?.toDouble() ?? 100.0,
      distanceTotaleKm: (data['distanceTotaleKm'] as num?)?.toDouble() ?? 0.0,
      creditBalance: (data['creditBalance'] as num?)?.toDouble() ?? 0.0,
      gainTotal: (data['gainTotal'] as num?)?.toDouble() ?? 0.0,
      disponibleMatin: data['disponibleMatin'] as bool? ?? true,
      disponibleApresmidi: data['disponibleApresmidi'] as bool? ?? true,
      disponibleSoir: data['disponibleSoir'] as bool? ?? false,
      dateInscription: ((data['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now()),
      estVerifie: data['estVerifie'] as bool? ?? false,
      dernierePosition: (data['dernierePosition'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'utilisateurId': utilisateurId,
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'quartierBase': quartierBase,
      'latitude': latitude,
      'longitude': longitude,
      'typeVehicule': typeVehicule.name,
      'numeroCNI': numeroCNI,
      'numeroPermis': numeroPermis,
      'statut': statut.name,
      'photo': photo,
      'noteMoyenne': noteMoyenne,
      'nombreLivraisons': nombreLivraisons,
      'tauxRespectDelai': tauxRespectDelai,
      'distanceTotaleKm': distanceTotaleKm,
      'creditBalance': creditBalance,
      'gainTotal': gainTotal,
      'disponibleMatin': disponibleMatin,
      'disponibleApresmidi': disponibleApresmidi,
      'disponibleSoir': disponibleSoir,
      'dateInscription': dateInscription,
      'estVerifie': estVerifie,
      'dernierePosition': dernierePosition,
    };
  }
}
