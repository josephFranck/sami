import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum Mention {
  aucun,
  coupDeCoeur,
  meilleureVente,
  nouveaute,
  exclusivite,
  premium,
  artisanatLocal,
  editionLimitee,
  enPromotion,
  bientotDisponible,
  ruptureDeStock,
}

class Pagne {
  final String id;
  final String nom;
  final String description;
  final double prixParBoutique;
  final double? prixBarre;
  /// PLANCHER DE PROMOTION : le boutiquier déclare à la création le prix
  /// en-dessous duquel il ne PEUT pas vendre (son coût + minimum vital).
  /// Toute promo qui passerait dessous est bloquée avec avertissement.
  final double? prixPlancher;
  final DateTime? promoFinLe;      // promo active jusqu'à…
  final double? prixAvantPromo;    // pour restaurer à l'expiration // prix « normal » affiché barré (marketing)
  final List<String> images;
  final List<String> categories;
  final List<String> tailles;
  final List<String> couleurs;
  final String matiere;
  final String createur;
  final List<String> tags;
  final Map<String, String> commentaires;
  final double noteMoyenne;
  final int nombreAvis;
  final Mention mention;
  final String origine;
  final bool disponible;
  final double prixDeGros;
  final int quantiteMinCommande;
  final int quantiteStock;          // stock total
  final int quantiteDisponible;     // stock - réservé en temps réel
  final int quantiteReservee;       // réservations actives
  final int delaiLivraison;
  final String videoPresentation;
  // Métadonnées financières (invisibles au client)
  final double? coutAchat;
  final double? beneficeSouhaite;
  final String? boutiqueId;
  // Storytelling
  final String? nomArtisan;
  final String? villageOrigine;
  final String? histoireTissu;
  // Boost & visibilité
  final String boost;
  final DateTime? dateAjout;

  Pagne({
    required this.id,
    required this.nom,
    required this.description,
    required this.prixParBoutique,
    this.prixBarre,
    this.prixPlancher,
    this.promoFinLe,
    this.prixAvantPromo,
    required this.images,
    required this.categories,
    required this.tailles,
    required this.couleurs,
    required this.matiere,
    required this.createur,
    required this.tags,
    required this.commentaires,
    required this.noteMoyenne,
    this.nombreAvis = 0,
    required this.mention,
    required this.origine,
    required this.disponible,
    required this.prixDeGros,
    required this.quantiteMinCommande,
    this.quantiteStock = 0,
    this.quantiteDisponible = 0,
    this.quantiteReservee = 0,
    required this.delaiLivraison,
    required this.videoPresentation,
    this.coutAchat,
    this.beneficeSouhaite,
    this.boutiqueId,
    this.nomArtisan,
    this.villageOrigine,
    this.histoireTissu,
    this.boost = 'standard',
    this.dateAjout,
  });

  static CollectionReference<Map<String, dynamic>> pagneCollection =
      FirebaseFirestore.instance.collection('pagnes');

  static Future<String> getNextId() async {
    final counterDoc = await FirebaseFirestore.instance
        .collection('counters')
        .doc('pagneCounter')
        .get();

    int nextId = counterDoc.exists ? counterDoc['nextId'] + 1 : 1;

    await FirebaseFirestore.instance
        .collection('counters')
        .doc('pagneCounter')
        .set({'nextId': nextId});

    return nextId.toString();
  }

  factory Pagne.fromFirebaseDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Pagne(
      id: doc.id,
      nom: data['nom'] as String? ?? '',
      description: data['description'] as String? ?? '',
      prixParBoutique: (data['prixParBoutique'] is int)
          ? data['prixParBoutique'].toDouble()
          : data['prixParBoutique'] ?? 0.0,
      prixBarre: (data['prixBarre'] as num?)?.toDouble(),
      prixPlancher: (data['prixPlancher'] as num?)?.toDouble(),
      promoFinLe: (data['promoFinLe'] as Timestamp?)?.toDate(),
      prixAvantPromo: (data['prixAvantPromo'] as num?)?.toDouble(),
      images: List<String>.from(data['images'] ?? []),
      categories: List<String>.from(data['categories'] ?? []),
      tailles: List<String>.from(data['tailles'] ?? []),
      couleurs: List<String>.from(data['couleurs'] ?? []),
      matiere: data['matiere'] as String? ?? '',
      createur: data['createur'] as String? ?? '',
      tags: List<String>.from(data['tags'] ?? []),
      commentaires: Map<String, String>.from(data['commentaires'] ?? {}),
      noteMoyenne: (data['noteMoyenne'] is int)
          ? data['noteMoyenne'].toDouble()
          : data['noteMoyenne'] ?? 0.0,
      nombreAvis: data['nombreAvis'] as int? ?? 0,
      mention: Mention.values.asNameMap()[data['mention']] ?? Mention.aucun,
      origine: data['origine'] as String? ?? '',
      disponible: data['disponible'] as bool,
      prixDeGros: (data['prixDeGros'] is int)
          ? data['prixDeGros'].toDouble()
          : data['prixDeGros'] ?? 0.0,
      quantiteMinCommande: data['quantiteMinCommande'] as int? ?? 0,
      quantiteStock: data['quantiteStock'] as int? ?? 0,
      quantiteDisponible: data['quantiteDisponible'] as int? ?? data['quantiteStock'] as int? ?? 0,
      quantiteReservee: data['quantiteReservee'] as int? ?? 0,
      delaiLivraison: data['delaiLivraison'] as int? ?? 0,
      videoPresentation: data['videoPresentation'] as String? ?? '',
      coutAchat: (data['_finance'] != null) ? (data['_finance']['coutAchat'] as num?)?.toDouble() : null,
      beneficeSouhaite: (data['_finance'] != null) ? (data['_finance']['beneficeSouhaite'] as num?)?.toDouble() : null,
      boutiqueId: data['boutiqueId'] as String?,
      nomArtisan: data['nomArtisan'] as String?,
      villageOrigine: data['villageOrigine'] as String?,
      histoireTissu: data['histoireTissu'] as String?,
      boost: data['boost'] as String? ?? 'standard',
      dateAjout: (data['dateAjout'] as Timestamp?)?.toDate(),
    );
  }

  static Pagne fromMap(Map<String, dynamic> map) {
    return Pagne(
      id: map['id'] as String? ?? '',
      nom: map['nom'] as String? ?? '',
      description: map['description'] as String? ?? '',
      prixParBoutique: (map['prixParBoutique'] is int)
          ? map['prixParBoutique'].toDouble()
          : map['prixParBoutique'] ?? 0.0,
      images: List<String>.from(map['images'] ?? []),
      categories: List<String>.from(map['categories'] ?? []),
      tailles: List<String>.from(map['tailles'] ?? []),
      couleurs: List<String>.from(map['couleurs'] ?? []),
      matiere: map['matiere'] as String? ?? '',
      createur: map['createur'] as String? ?? '',
      tags: List<String>.from(map['tags'] ?? []),
      commentaires: Map<String, String>.from(map['commentaires'] ?? {}),
      noteMoyenne: (map['noteMoyenne'] is int)
          ? map['noteMoyenne'].toDouble()
          : map['noteMoyenne'] ?? 0.0,
      nombreAvis: map['nombreAvis'] as int? ?? 0,
      mention: Mention.values.asNameMap()[map['mention']] ?? Mention.aucun,
      origine: map['origine'] as String? ?? '',
      disponible: map['disponible'] as bool,
      prixDeGros: (map['prixDeGros'] is int)
          ? map['prixDeGros'].toDouble()
          : map['prixDeGros'] ?? 0.0,
      quantiteMinCommande: map['quantiteMinCommande'] as int? ?? 1,
      quantiteStock: map['quantiteStock'] as int? ?? 0,
      quantiteDisponible: map['quantiteDisponible'] as int? ?? map['quantiteStock'] as int? ?? 0,
      quantiteReservee: map['quantiteReservee'] as int? ?? 0,
      delaiLivraison: map['delaiLivraison'] as int? ?? 0,
      videoPresentation: map['videoPresentation'] as String? ?? '',
      coutAchat: (map['_finance'] != null) ? (map['_finance']['coutAchat'] as num?)?.toDouble() : (map['coutAchat'] as num?)?.toDouble(),
      beneficeSouhaite: (map['_finance'] != null) ? (map['_finance']['beneficeSouhaite'] as num?)?.toDouble() : (map['beneficeSouhaite'] as num?)?.toDouble(),
      boutiqueId: map['boutiqueId'] as String?,
      nomArtisan: map['nomArtisan'] as String?,
      dateAjout: map['dateAjout'] is Timestamp ? ((map['dateAjout'] as Timestamp?)?.toDate() ?? DateTime.now()) : null,
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'description': description,
      'prixParBoutique': prixParBoutique,
      'images': images,
      'categories': categories,
      'tailles': tailles,
      'couleurs': couleurs,
      'matiere': matiere,
      'createur': createur,
      'tags': tags,
      'commentaires': commentaires,
      'noteMoyenne': noteMoyenne,
      'nombreAvis': nombreAvis,
      'mention': mention.name,
      'origine': origine,
      'disponible': disponible,
      'prixDeGros': prixDeGros,
      'quantiteMinCommande': quantiteMinCommande,
      'quantiteStock': quantiteStock,
      'quantiteDisponible': quantiteDisponible,
      'quantiteReservee': quantiteReservee,
      'delaiLivraison': delaiLivraison,
      'videoPresentation': videoPresentation,
      'boutiqueId': boutiqueId,
      'nomArtisan': nomArtisan,
      'villageOrigine': villageOrigine,
      'histoireTissu': histoireTissu,
      'boost': boost,
      'dateAjout': dateAjout ?? FieldValue.serverTimestamp(),
    };
  }

  Future<void> addToFirebase() async {
    try {
      await pagneCollection.doc(id).set(toMap());
      if (kDebugMode) print('Pagne ajouté : $id');
    } catch (e) {
      if (kDebugMode) {
        print('Erreur lors de l\'ajout du pagne à Firebase : $e');
      }
    }
  }
}