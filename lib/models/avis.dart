import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME DE NOTATION UNIFIÉ — Tous les acteurs SAMI
//
// QUI NOTE QUI :
//   Client      → Pagne · Boutique · Couturier · Livreur
//   Boutiquier  → Client (fiabilité paiement/présence)
//   Livreur     → Client (accessibilité/comportement)
//   Couturier   → Client (mesures exactes/respect RDV)
//
// À QUOI ÇA SERT :
//   1. Affichage étoiles → confiance pour les acheteurs
//   2. Agent IA          → score routing livraison (poids = 25%)
//   3. Tarification      → boost -50% si note ≥ 4.8, bloqué si < 3.0
//   4. Badges auto       → Top Vendeur, Excellence, À améliorer
//   5. Score client      → priorité de livraison, accès aux ventes flash
// ═══════════════════════════════════════════════════════════════════════════

// ─── Cibles de notation ───────────────────────────────────────────────────────

enum CibleAvis { pagne, boutique, couturier, livreur, client }

enum StatutAvis {
  enAttente,   // soumis, attente auto-modération
  publie,      // visible publiquement
  signale,     // signalé par la cible
  masque,      // masqué par modération
  rejete,      // faux avis ou contenu abusif
}

// ─── Avis ─────────────────────────────────────────────────────────────────────

class Avis {
  final String id;
  final CibleAvis cible;
  final String cibleId;
  final String auteurId;
  final String auteurRole;       // 'client' | 'boutiquier' | 'livreur' | 'couturier'
  final String auteurNom;        // prénom + initiale nom
  final String? auteurPhoto;

  // Preuve d'achat obligatoire — avis uniquement post-livraison
  final String? sousCommandeId;
  final String? livraisonId;
  final bool achatVerifie;

  // Note et contenu
  final double note;             // 1.0 à 5.0
  final String? commentaire;
  final Map<String, double> sousNotes; // ex: {'qualite': 4, 'rapidite': 5}

  // Modération
  StatutAvis statut;
  final DateTime dateCreation;
  int signalements;
  String? raisonMasquage;

  Avis({
    required this.id,
    required this.cible,
    required this.cibleId,
    required this.auteurId,
    required this.auteurRole,
    required this.auteurNom,
    this.auteurPhoto,
    this.sousCommandeId,
    this.livraisonId,
    this.achatVerifie = false,
    required this.note,
    this.commentaire,
    this.sousNotes = const {},
    this.statut = StatutAvis.enAttente,
    required this.dateCreation,
    this.signalements = 0,
    this.raisonMasquage,
  });

  bool get estPublic => statut == StatutAvis.publie;

  String get labelNote => switch (note.round()) {
    1 => 'Très mauvais',
    2 => 'Mauvais',
    3 => 'Correct',
    4 => 'Bien',
    5 => 'Excellent',
    _ => '',
  };

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('avis');

  static Stream<List<Avis>> streamPourCible(
    CibleAvis cible,
    String cibleId, {
    int limite = 20,
  }) =>
      collection
          .where('cible', isEqualTo: cible.name)
          .where('cibleId', isEqualTo: cibleId)
          .where('statut', isEqualTo: StatutAvis.publie.name)
          .orderBy('dateCreation', descending: true)
          .limit(limite)
          .snapshots()
          .map((s) => s.docs.map((d) => Avis.fromDoc(d)).toList());

  factory Avis.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Avis(
      id: doc.id,
      cible: CibleAvis.values.firstWhere((e) => e.name == (d['cible'] as String? ?? ''), orElse: () => CibleAvis.values.first),
      cibleId: d['cibleId'] as String? ?? '',
      auteurId: d['auteurId'] as String? ?? '',
      auteurRole: d['auteurRole'] as String? ?? 'client',
      auteurNom: d['auteurNom'] as String? ?? 'Anonyme',
      auteurPhoto: d['auteurPhoto'] as String?,
      sousCommandeId: d['sousCommandeId'] as String?,
      livraisonId: d['livraisonId'] as String?,
      achatVerifie: d['achatVerifie'] as bool? ?? false,
      note: (d['note'] as num? ?? 0).toDouble(),
      commentaire: d['commentaire'] as String?,
      sousNotes: Map<String, double>.from(
        (d['sousNotes'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num? ?? 0).toDouble()),
        ),
      ),
      statut: StatutAvis.values.firstWhere((e) => e.name == (d['statut'] as String? ?? 'enAttente'), orElse: () => StatutAvis.values.first),
      dateCreation: ((d['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now()),
      signalements: d['signalements'] as int? ?? 0,
      raisonMasquage: d['raisonMasquage'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'cible': cible.name,
    'cibleId': cibleId,
    'auteurId': auteurId,
    'auteurRole': auteurRole,
    'auteurNom': auteurNom,
    'auteurPhoto': auteurPhoto,
    'sousCommandeId': sousCommandeId,
    'livraisonId': livraisonId,
    'achatVerifie': achatVerifie,
    'note': note,
    'commentaire': commentaire,
    'sousNotes': sousNotes,
    'statut': statut.name,
    'dateCreation': FieldValue.serverTimestamp(),
    'signalements': signalements,
    'raisonMasquage': raisonMasquage,
  };
}

// ─── Score de fiabilité client ────────────────────────────────────────────────

class ScoreClient {
  final String clientId;
  final double scoreFiabilite;    // 0 à 100
  final int commandesTotal;
  final int commandesAnnulees;
  final int litigesInities;
  final int litigesGagnes;
  final int litigesPerdus;
  final double noteMoyenneRecue;  // moyenne des notes données par vendeurs/livreurs
  final bool estBloque;

  ScoreClient({
    required this.clientId,
    required this.scoreFiabilite,
    this.commandesTotal = 0,
    this.commandesAnnulees = 0,
    this.litigesInities = 0,
    this.litigesGagnes = 0,
    this.litigesPerdus = 0,
    this.noteMoyenneRecue = 5.0,
    this.estBloque = false,
  });

  String get niveau => switch (scoreFiabilite) {
    >= 90 => '⭐ Client Premium',
    >= 75 => '✅ Client fiable',
    >= 50 => '😐 Client standard',
    >= 25 => '⚠️ Historique mitigé',
    _     => '🔴 Client restreint',
  };

  // Priorité livraison : meilleur score → livré en premier
  int get prioriteLivraison => switch (scoreFiabilite) {
    >= 90 => 1,
    >= 75 => 2,
    >= 50 => 3,
    _     => 4,
  };

  // Accès aux ventes flash réservé aux bons clients
  bool get accesVentesFlash => scoreFiabilite >= 75;

  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('scores_clients');

  factory ScoreClient.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ScoreClient(
      clientId: doc.id,
      scoreFiabilite: (d['scoreFiabilite'] as num?)?.toDouble() ?? 100,
      commandesTotal: d['commandesTotal'] as int? ?? 0,
      commandesAnnulees: d['commandesAnnulees'] as int? ?? 0,
      litigesInities: d['litigesInities'] as int? ?? 0,
      litigesGagnes: d['litigesGagnes'] as int? ?? 0,
      litigesPerdus: d['litigesPerdus'] as int? ?? 0,
      noteMoyenneRecue: (d['noteMoyenneRecue'] as num?)?.toDouble() ?? 5.0,
      estBloque: d['estBloque'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    'scoreFiabilite': scoreFiabilite,
    'commandesTotal': commandesTotal,
    'commandesAnnulees': commandesAnnulees,
    'litigesInities': litigesInities,
    'litigesGagnes': litigesGagnes,
    'litigesPerdus': litigesPerdus,
    'noteMoyenneRecue': noteMoyenneRecue,
    'estBloque': estBloque,
    'dateMiseAJour': FieldValue.serverTimestamp(),
  };
}

// ─── Tarification boosts selon les notes ─────────────────────────────────────

class TarificationBoost {
  static const double _prixBase = 2000; // FCFA

  static ResultatTarificationBoost calculer({
    required double noteMoyenne,
    required int nombreAvis,
    String typeBoost = 'standard', // 'flash' | 'standard' | 'premium'
  }) {
    // Minimum 3 avis pour accéder aux boosts
    if (nombreAvis < 3) {
      return ResultatTarificationBoost(
        eligible: false,
        prix: 0,
        raisonIneligibilite: 'Minimum 3 avis requis (vous en avez $nombreAvis)',
      );
    }

    // Note trop basse → pas de boost
    if (noteMoyenne < 3.0) {
      return ResultatTarificationBoost(
        eligible: false,
        prix: 0,
        raisonIneligibilite:
            'Note insuffisante (${noteMoyenne.toStringAsFixed(1)}/5)\n'
            'Améliorez votre service pour accéder aux boosts',
      );
    }

    // Multiplicateur : meilleure note = tarif plus bas
    final multiplicateur = switch (noteMoyenne) {
      >= 4.8 => 0.50, // -50% — excellence récompensée
      >= 4.5 => 0.70, // -30%
      >= 4.0 => 0.90, // -10%
      >= 3.5 => 1.00, // tarif normal
      _      => 1.30, // +30% — note limite, malus appliqué
    };

    final prixBase = switch (typeBoost) {
      'flash'   => _prixBase * 0.5,   // 1 000 F — boost 3h
      'premium' => _prixBase * 2.5,   // 5 000 F — boost 7 jours
      _         => _prixBase,          // 2 000 F — boost 24h
    };

    final prix = PrixFCFA.arrondirAu50(prixBase * multiplicateur);
    final badge = _badge(noteMoyenne);

    return ResultatTarificationBoost(
      eligible: true,
      prix: prix,
      multiplicateur: multiplicateur,
      badge: badge,
      remise: multiplicateur < 1.0 ? ((1 - multiplicateur) * 100).round() : 0,
      majoration: multiplicateur > 1.0 ? ((multiplicateur - 1) * 100).round() : 0,
    );
  }

  static String _badge(double note) {
    if (note >= 4.8) return '🏆 Excellence SAMI';
    if (note >= 4.5) return '⭐ Top Vendeur';
    if (note >= 4.0) return '✅ Fiable';
    return '';
  }

  // Seuils utilisés par le service de notation pour attribuer les badges
  static const Map<String, double> seuilsBadges = {
    'excellence'     : 4.8,
    'top_vendeur'    : 4.5,
    'fiable'         : 4.0,
    'a_ameliorer'    : 3.5,
    'bloque_boost'   : 3.0,
  };
}

class ResultatTarificationBoost {
  final bool eligible;
  final double prix;
  final double multiplicateur;
  final String? badge;
  final int remise;        // % de réduction appliqué
  final int majoration;    // % de majoration appliqué
  final String? raisonIneligibilite;

  const ResultatTarificationBoost({
    required this.eligible,
    required this.prix,
    this.multiplicateur = 1.0,
    this.badge,
    this.remise = 0,
    this.majoration = 0,
    this.raisonIneligibilite,
  });

  String get prixFmt => PrixFCFA.formater(prix);
}

// ─── Sous-notes disponibles par cible ────────────────────────────────────────

class SousNote {
  final String id;
  final String label;
  final IconData icone;
  const SousNote(this.id, this.label, this.icone);
}

class SousNotesConfig {
  static const Map<CibleAvis, List<SousNote>> catalogue = {
    CibleAvis.pagne: [
      SousNote('qualite',              'Qualité du tissu',       Icons.texture),
      SousNote('conformite',           'Conforme à la photo',    Icons.camera_alt),
      SousNote('rapport_qualite_prix', 'Rapport qualité/prix',   Icons.price_check),
    ],
    CibleAvis.boutique: [
      SousNote('reactivite',  'Réactivité boutique',     Icons.support_agent),
      SousNote('description', 'Descriptions fidèles',    Icons.description_outlined),
      SousNote('emballage',   'Soin de l\'emballage',    Icons.inventory_2_outlined),
    ],
    CibleAvis.couturier: [
      SousNote('qualite_couture',  'Qualité de la couture',  Icons.content_cut),
      SousNote('respect_mesures',  'Respect des mesures',    Icons.straighten),
      SousNote('respect_delais',   'Respect des délais',     Icons.schedule),
      SousNote('communication',    'Communication',           Icons.chat_outlined),
    ],
    CibleAvis.livreur: [
      SousNote('rapidite',  'Rapidité',       Icons.speed),
      SousNote('soin_colis','Soin du colis',  Icons.inventory_outlined),
      SousNote('politesse', 'Politesse',      Icons.sentiment_satisfied),
    ],
    CibleAvis.client: [
      SousNote('paiement',       'Sérieux paiement',         Icons.payment),
      SousNote('disponibilite',  'Disponibilité livraison',  Icons.location_on_outlined),
      SousNote('respect',        'Respect des conditions',   Icons.handshake_outlined),
    ],
  };
}
