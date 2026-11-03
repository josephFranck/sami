import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Categorie {
  final String id;
  final String nom;
  final String description;
  final String image; // URL de l'image de la catégorie

  Categorie({
    required this.id,
    required this.nom,
    required this.description,
    required this.image,
  });

  static CollectionReference<Map<String, dynamic>> categorieCollection =
      FirebaseFirestore.instance.collection('categories');

  static Future<String> getNextId() async {
    final counterDoc = await FirebaseFirestore.instance
        .collection('counters')
        .doc('categorieCounter') // Nom du compteur spécifique aux catégories
        .get();

    int nextId = counterDoc.exists ? counterDoc['nextId'] + 1 : 1;

    await FirebaseFirestore.instance
        .collection('counters')
        .doc('categorieCounter')
        .set({'nextId': nextId});

    return nextId.toString();
  }

  factory Categorie.fromFirebaseDocuments(Map<String, dynamic> data) {
    return Categorie(
      id: data['id'] as String? ?? '',
      nom: data['nom'] as String? ?? '',
      description: data['description'] as String? ?? '',
      image: data['image'] as String? ?? '',
    );
  }


  static Categorie fromMap(Map<String, dynamic> map) {
    return Categorie(
      id: map['id'] as String? ?? '',
      image: map['image'] as String? ?? '',
      nom: map['nom'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  static Categorie fromFirebaseDocument(DocumentSnapshot doc) {
    return Categorie(
      id: doc.id,
      image: doc['image'] as String? ?? '',
      nom: doc['nom'] as String? ?? '',
      description: doc['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image': image,
      'nom': nom,
      'description': description,
    };
  }

  Future<void> addToFirebase() async {
    try {
      await categorieCollection.doc(id).set(toMap());
      if (kDebugMode) print('Catégorie ajoutée : $id');
    } catch (e) {
      if (kDebugMode) print('Erreur ajout catégorie : $e');
    }
  }
}