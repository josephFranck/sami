import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ── PanierItem ────────────────────────────────────────────────────────────────
class PanierItem {
  final String pagneId;
  final String pagneNom;
  final String? pagneImage;
  int quantite;
  final double prixUnitaire;     // prix client (multiple de 50 FCFA)
  final String? boutiqueId;
  final String? couturierId;     // si commande avec couture
  final bool avecCouture;

  PanierItem({
    required this.pagneId,
    required this.pagneNom,
    this.pagneImage,
    required this.quantite,
    required this.prixUnitaire,
    this.boutiqueId,
    this.couturierId,
    this.avecCouture = false,
  });

  double get sousTotal => PrixFCFA.arrondirAu50(prixUnitaire * quantite);

  bool estQuantiteValide(int quantiteMin) => quantite >= quantiteMin;

  Map<String, dynamic> toMap() => {
    'pagneId': pagneId,
    'pagneNom': pagneNom,
    'pagneImage': pagneImage,
    'quantite': quantite,
    'prixUnitaire': prixUnitaire,
    'boutiqueId': boutiqueId,
    'couturierId': couturierId,
    'avecCouture': avecCouture,
  };

  factory PanierItem.fromMap(Map<String, dynamic> map) => PanierItem(
    pagneId: map['pagneId'] as String? ?? '',
    pagneNom: map['pagneNom'] as String? ?? '',
    pagneImage: map['pagneImage'] as String?,
    quantite: map['quantite'] as int? ?? 1,
    prixUnitaire: (map['prixUnitaire'] as num? ?? 0).toDouble(),
    boutiqueId: map['boutiqueId'] as String?,
    couturierId: map['couturierId'] as String?,
    avecCouture: map['avecCouture'] as bool? ?? false,
  );
}

// ── Panier (gestionnaire en mémoire + Firestore) ──────────────────────────────
class Panier {
  final String userId;
  List<PanierItem> items;

  Panier({required this.userId, List<PanierItem>? items})
      : items = items ?? [];

  // ── Calculs ────────────────────────────────────────────────────────────────
  double get sousTotal => items.fold(0, (s, i) => s + i.sousTotal);
  /// Frais d'une course de livraison — ALIGNÉ sur ParametresService
  /// (fraisLivraisonBase). panierpage le charge au démarrage ; le repli
  /// 600 s'applique hors-ligne.
  static double fraisBase = 600;
  /// RETRAIT EN BOUTIQUE : le client vient chercher → AUCUN frais de
  /// livraison (avant : les 600 F étaient facturés même au retrait !)
  static bool modeRetrait = false;
  double get fraisLivraison =>
      (items.isEmpty || modeRetrait) ? 0 : fraisBase;
  double get total => PrixFCFA.arrondirAu50(sousTotal + fraisLivraison);
  int get nombreArticles => items.fold(0, (s, i) => s + i.quantite);
  bool get estVide => items.isEmpty;

  // ── Opérations ─────────────────────────────────────────────────────────────
  void ajouter(PanierItem item) {
    final idx = items.indexWhere((i) => i.pagneId == item.pagneId);
    if (idx >= 0) {
      items[idx].quantite += item.quantite;
    } else {
      items.add(item);
    }
  }

  void supprimer(String pagneId) =>
      items.removeWhere((i) => i.pagneId == pagneId);

  void modifierQuantite(String pagneId, int qte) {
    final idx = items.indexWhere((i) => i.pagneId == pagneId);
    if (idx >= 0) {
      if (qte <= 0) items.removeAt(idx);
      else items[idx].quantite = qte;
    }
  }

  void vider() => items.clear();

  // ── Persistance Firestore ──────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('paniers');

  Future<void> sauvegarder() async {
    await _col.doc(userId).set({
      'userId': userId,
      'items': items.map((i) => i.toMap()).toList(),
      'dateModif': FieldValue.serverTimestamp(),
    });
  }

  static Future<Panier> charger(String userId) async {
    final doc = await _col.doc(userId).get();
    if (!doc.exists) return Panier(userId: userId);
    final data = doc.data()!;
    return Panier(
      userId: userId,
      items: (data['items'] as List<dynamic>? ?? [])
          .map((e) => PanierItem.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  List<Map<String, dynamic>> toFirestoreList() =>
      items.map((i) => i.toMap()).toList();
}
