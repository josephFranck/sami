import 'package:cloud_firestore/cloud_firestore.dart';

class Utilisateur {
  final String id;
  final String image;
  final String nom;
  final String prenom; // Added prenom
  final String email;
  final String adresse;
  final String telephone; // Added telephone
  final DateTime dateInscription; // Added dateInscription
  final DateTime derniereConnexion; // Added derniereConnexion
  final bool estVerifie; // Added estVerifie
  final bool estActif; // Added estActif
  final String role; // Added role
  final List<String> permissions; // droits granulaires des agents (mini-admins)
  /// MULTI-RÔLES (décision 03/11/2026) : un compte peut porter plusieurs
  /// rôles (ex. boutiquier ET client). `role` reste le rôle PRINCIPAL
  /// (compatibilité, règles Firestore) ; `roles` la liste complète.
  /// Tout compte est client.
  final List<String> roles;
  bool aRole(String r) =>
      r == 'client' || role == r || roles.contains(r);
  final List<String> historiqueCommandes; // Added historiqueCommandes
  final List<Map<String, dynamic>> panier; // Added panier
  List<String> favoris; // Added favoris
  final List<String> methodesPaiement; // Added methodesPaiement
  final List<String> adresseLivraison; // Added adresseLivraison
  final String langue; // Added langue
  final bool notifications; // Added notifications
  final String quartier; // Added quartier
  final double? latitude;   // GPS de l'adresse de livraison
  final double? longitude;
  final String ville; // Added ville
  final String pays; // Added pays
  final int niveau;
  final int pointsFidelite;
  final double creditBalance;
  final String? codeParrainage;

  Utilisateur({
    required this.id,
    required this.image,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.adresse,
    required this.telephone,
    required this.dateInscription,
    required this.derniereConnexion,
    required this.estVerifie,
    required this.estActif,
    required this.role,
    this.permissions = const [],
    List<String>? roles,
    required this.historiqueCommandes,
    required this.panier,
    required this.favoris,
    required this.methodesPaiement,
    required this.adresseLivraison,
    required this.langue,
    required this.notifications,
    required this.quartier,
    this.latitude,
    this.longitude,
    required this.ville,
    required this.pays,
    required this.niveau,
    this.pointsFidelite = 0,
    this.creditBalance = 0.0,
    this.codeParrainage,
  }) : roles = roles ?? {role, 'client'}.toList();

  static CollectionReference<Map<String, dynamic>> utilisateurCollection =
      FirebaseFirestore.instance.collection('utilisateurs');

  factory Utilisateur.fromFirebaseDocuments(Map<String, dynamic> data) {
    return Utilisateur(
      id: data['id'] as String? ?? '',
      image: data['image'] as String? ?? '',
      nom: data['nom'] as String? ?? '',
      prenom: data['prenom'] as String? ?? '',
      email: data['email'] as String? ?? '',
      adresse: data['adresse'] as String? ?? '',
      telephone: data['telephone'] as String? ?? '',
      dateInscription: ((data['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now()),
      derniereConnexion: ((data['derniereConnexion'] as Timestamp?)?.toDate() ?? DateTime.now()),
      estVerifie: data['estVerifie'] as bool,
      estActif: data['estActif'] as bool,
      role: data['role'] as String? ?? '',
      roles: List<String>.from(data['roles'] as List? ?? const []),
      permissions: List<String>.from(data['permissions'] as List? ?? const []),
      historiqueCommandes: List<String>.from(data['historiqueCommandes'] ?? []),
      panier: List<Map<String, dynamic>>.from(data['panier'] ?? []),
      favoris: List<String>.from(data['favoris'] ?? []),
      methodesPaiement: List<String>.from(data['methodesPaiement'] ?? []),
      adresseLivraison: List<String>.from(data['adresseLivraison'] ?? []),
      langue: data['langue'] as String? ?? '',
      notifications: data['notifications'] as bool,
      quartier: data['quartier'] as String? ?? '',
      ville: data['ville'] as String? ?? '',
      pays: data['pays'] as String? ?? '',
      niveau: data['niveau'] as int? ?? 1,
      pointsFidelite: data['pointsFidelite'] as int? ?? 0,
      creditBalance: (data['creditBalance'] as num?)?.toDouble() ?? 0.0,
      codeParrainage: data['codeParrainage'] as String?,
    );
  }

  static Utilisateur fromMap(Map<String, dynamic> map) {
    return Utilisateur(
      id: map['id'] as String? ?? '',
      image: map['image'] as String? ?? '',
      nom: map['nom'] as String? ?? '',
      prenom: map['prenom'] as String? ?? '',
      email: map['email'] as String? ?? '',
      adresse: map['adresse'] as String? ?? '',
      telephone: map['telephone'] as String? ?? '',
      dateInscription: (map['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(),
      derniereConnexion: (map['derniereConnexion'] as Timestamp?)?.toDate() ?? DateTime.now(),
      estVerifie: map['estVerifie'] as bool? ?? false,
      estActif: map['estActif'] as bool? ?? true,
      role: map['role'] as String? ?? 'client',
      roles: List<String>.from(map['roles'] as List? ?? const []),
      permissions: List<String>.from(map['permissions'] as List? ?? const []),
      historiqueCommandes: List<String>.from(map['historiqueCommandes'] ?? []),
      panier: List<Map<String, dynamic>>.from(map['panier'] ?? []),
      favoris: List<String>.from(map['favoris'] ?? []),
      methodesPaiement: List<String>.from(map['methodesPaiement'] ?? []),
      adresseLivraison: List<String>.from(map['adresseLivraison'] ?? []),
      langue: map['langue'] as String? ?? 'fr',
      notifications: map['notifications'] as bool? ?? true,
      quartier: map['quartier'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      ville: map['ville'] as String? ?? 'Garoua',
      pays: map['pays'] as String? ?? 'Cameroun',
      niveau: map['niveau'] as int? ?? 1,
      pointsFidelite: map['pointsFidelite'] as int? ?? 0,
      creditBalance: (map['creditBalance'] as num?)?.toDouble() ?? 0.0,
      codeParrainage: map['codeParrainage'] as String?,
    );
  }

  static Utilisateur fromFirebaseDocument(DocumentSnapshot doc) {
    // Lecture robuste : un document peut manquer certains champs
    // (compte créé avant l'ajout d'un champ, données partielles, etc.)
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return Utilisateur(
      id: doc.id,
      image: data['image'] as String? ?? '',
      nom: data['nom'] as String? ?? '',
      prenom: data['prenom'] as String? ?? '',
      email: data['email'] as String? ?? '',
      adresse: data['adresse'] as String? ?? '',
      telephone: data['telephone'] as String? ?? '',
      dateInscription: (data['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(),
      derniereConnexion: (data['derniereConnexion'] as Timestamp?)?.toDate() ?? DateTime.now(),
      estVerifie: data['estVerifie'] as bool? ?? false,
      estActif: data['estActif'] as bool? ?? true,
      role: data['role'] as String? ?? 'client',
      roles: List<String>.from(data['roles'] as List? ?? const []),
      historiqueCommandes: List<String>.from(data['historiqueCommandes'] ?? []),
      panier: List<Map<String, dynamic>>.from(data['panier'] ?? []),
      favoris: List<String>.from(data['favoris'] ?? []),
      methodesPaiement: List<String>.from(data['methodesPaiement'] ?? []),
      adresseLivraison: List<String>.from(data['adresseLivraison'] ?? []),
      langue: data['langue'] as String? ?? 'fr',
      notifications: data['notifications'] as bool? ?? true,
      quartier: data['quartier'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      ville: data['ville'] as String? ?? 'Garoua',
      pays: data['pays'] as String? ?? 'Cameroun',
      niveau: data['niveau'] as int? ?? 1,
      pointsFidelite: data['pointsFidelite'] as int? ?? 0,
      creditBalance: (data['creditBalance'] as num?)?.toDouble() ?? 0.0,
      codeParrainage: data['codeParrainage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image': image,
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'adresse': adresse,
      'telephone': telephone,
      'dateInscription': dateInscription,
      'derniereConnexion': derniereConnexion,
      'estVerifie': estVerifie,
      'estActif': estActif,
      'role': role,
      'roles': roles,
      'historiqueCommandes': historiqueCommandes,
      'panier': panier,
      'favoris': favoris,
      'methodesPaiement': methodesPaiement,
      'adresseLivraison': adresseLivraison,
      'langue': langue,
      'notifications': notifications,
      'quartier': quartier,
      'latitude': latitude,
      'longitude': longitude,
      'ville': ville,
      'pays': pays,
      'niveau': niveau,
      'pointsFidelite': pointsFidelite,
      'creditBalance': creditBalance,
      'codeParrainage': codeParrainage,
    };
  }

  Future<void> addToFirebase() async {
    try {
      await utilisateurCollection.doc(id).set(toMap());
      print('Utilisateur ajouté avec succès à Firebase');
    } catch (e) {
      print('Erreur lors de l\'ajout de l\'utilisateur à Firebase : $e');
    }
  }

  static Future<Utilisateur?> fromUid(String uid) async {
    try {
      final userDoc = await utilisateurCollection.doc(uid).get();
      if (userDoc.exists) {
        return Utilisateur.fromFirebaseDocument(userDoc);
      } else {
        return null; // Utilisateur non trouvé
      }
    } catch (e) {
      print('Erreur lors de la récupération de l\'utilisateur par UID : $e');
      return null; // Erreur lors de la récupération
    }
  }

}