import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sami/models/avis.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE NOTATION
//
// Toutes les opérations de notation passent par ici :
//   soumettre()     → créer un avis lié à une livraison confirmée
//   _recalculer()   → mettre à jour la note moyenne de la cible
//   _mettreAJourAgent() → propager la note vers l'agent IA
//   _attribuerBadge()   → badge automatique selon seuil
//   signalerAvis()  → modération collaborative
//   calculerScoreClient() → score fiabilité 0-100
// ═══════════════════════════════════════════════════════════════════════════

class NotationService {
  static final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // SOUMETTRE UN AVIS
  // ══════════════════════════════════════════════════════════════════════════

  /// Soumettre un avis après livraison confirmée
  /// Retourne null si succès, message d'erreur sinon
  static Future<String?> soumettre({
    required CibleAvis cible,
    required String cibleId,
    required String auteurId,
    required String auteurRole,
    required String auteurNom,
    String? auteurPhoto,
    required double note,
    String? commentaire,
    Map<String, double> sousNotes = const {},
    String? sousCommandeId,
    String? livraisonId,
  }) async {
    // 1. Vérifier que la livraison est bien confirmée (achatVerifie)
    bool achatVerifie = false;
    if (sousCommandeId != null) {
      final sc = await _db.collection('sous_commandes').doc(sousCommandeId).get();
      if (sc.exists) {
        final statut = sc.data()?['statut'] as String? ?? '';
        achatVerifie = statut == 'terminee';
      }
    }

    // 2. Vérifier qu'il n'a pas déjà noté cette cible pour cette commande
    if (sousCommandeId != null) {
      final dejaNote = await Avis.collection
          .where('auteurId', isEqualTo: auteurId)
          .where('cibleId', isEqualTo: cibleId)
          .where('sousCommandeId', isEqualTo: sousCommandeId)
          .limit(1)
          .get();
      if (dejaNote.docs.isNotEmpty) {
        return 'Vous avez déjà noté cet élément pour cette commande';
      }
    }

    // 3. Valider la note
    if (note < 1 || note > 5) return 'La note doit être entre 1 et 5';

    // 4. Créer l'avis
    final ref = Avis.collection.doc();
    final avis = Avis(
      id: ref.id,
      cible: cible,
      cibleId: cibleId,
      auteurId: auteurId,
      auteurRole: auteurRole,
      auteurNom: auteurNom,
      auteurPhoto: auteurPhoto,
      sousCommandeId: sousCommandeId,
      livraisonId: livraisonId,
      achatVerifie: achatVerifie,
      note: note,
      commentaire: commentaire?.trim(),
      sousNotes: sousNotes,
      // Auto-publié si achat vérifié, sinon en attente
      statut: achatVerifie ? StatutAvis.publie : StatutAvis.enAttente,
      dateCreation: DateTime.now(),
    );

    await ref.set(avis.toMap());

    // 5. Recalculer la moyenne de la cible
    await _recalculerMoyenne(cible, cibleId);

    if (kDebugMode) {
      print('[Notation] Avis soumis : $auteurRole → ${cible.name} $cibleId (note: $note)');
    }

    return null; // succès
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECALCUL DE LA MOYENNE
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _recalculerMoyenne(CibleAvis cible, String cibleId) async {
    // Calculer la moyenne de tous les avis publiés
    final snap = await Avis.collection
        .where('cible', isEqualTo: cible.name)
        .where('cibleId', isEqualTo: cibleId)
        .where('statut', isEqualTo: StatutAvis.publie.name)
        .get();

    if (snap.docs.isEmpty) return;

    final avis = snap.docs.map(Avis.fromDoc).toList();
    final moyenne = avis.fold<double>(0, (s, a) => s + a.note) / avis.length;
    final moyenneArrondie = double.parse(moyenne.toStringAsFixed(2));
    final nombreAvis = avis.length;

    // Calculer la moyenne pondérée des sous-notes si présentes
    final Map<String, double> moyennesSousNotes = {};
    final sousNotesKeys = SousNotesConfig.catalogue[cible]?.map((s) => s.id) ?? [];
    for (final key in sousNotesKeys) {
      final vals = avis
          .where((a) => a.sousNotes.containsKey(key))
          .map((a) => a.sousNotes[key]!)
          .toList();
      if (vals.isNotEmpty) {
        moyennesSousNotes[key] =
            double.parse((vals.reduce((a, b) => a + b) / vals.length).toStringAsFixed(2));
      }
    }

    // Mettre à jour selon la cible
    switch (cible) {
      case CibleAvis.pagne:
        await _db.collection('pagnes').doc(cibleId).update({
          'noteMoyenne': moyenneArrondie,
          'nombreAvis': nombreAvis,
          'moyennesSousNotes': moyennesSousNotes,
        });

      case CibleAvis.boutique:
        await _db.collection('boutiques').doc(cibleId).update({
          'noteMoyenne': moyenneArrondie,
          'nombreAvis': nombreAvis,
          'moyennesSousNotes': moyennesSousNotes,
        });
        await _attribuerBadge(cible, cibleId, moyenneArrondie);

      case CibleAvis.couturier:
        await _db.collection('couturiers').doc(cibleId).update({
          'noteMoyenne': moyenneArrondie,
          'nombreAvis': nombreAvis,
          'moyennesSousNotes': moyennesSousNotes,
        });
        await _attribuerBadge(cible, cibleId, moyenneArrondie);

      case CibleAvis.livreur:
        // Mise à jour livreur + propagation vers agent IA
        await _db.collection('livreurs').doc(cibleId).set({
          'noteMoyenne': moyenneArrondie,
          'nombreAvis': nombreAvis,
        }, SetOptions(merge: true));
        await _mettreAJourAgentLivraison(cibleId, moyenneArrondie);

      case CibleAvis.client:
        await calculerScoreClient(cibleId);
    }

    if (kDebugMode) {
      print('[Notation] Moyenne recalculée : ${cible.name} $cibleId → $moyenneArrondie ($nombreAvis avis)');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BADGES AUTOMATIQUES
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _attribuerBadge(
    CibleAvis cible,
    String cibleId,
    double noteMoyenne,
  ) async {
    final collection = cible == CibleAvis.boutique ? 'boutiques' : 'couturiers';

    String badge = '';
    if (noteMoyenne >= TarificationBoost.seuilsBadges['excellence']!) {
      badge = '🏆 Excellence SAMI';
    } else if (noteMoyenne >= TarificationBoost.seuilsBadges['top_vendeur']!) {
      badge = '⭐ Top Vendeur';
    } else if (noteMoyenne >= TarificationBoost.seuilsBadges['fiable']!) {
      badge = '✅ Fiable';
    } else if (noteMoyenne < TarificationBoost.seuilsBadges['a_ameliorer']!) {
      badge = '⚠️ À améliorer';
    }

    await _db.collection(collection).doc(cibleId).update({
      'badge': badge,
      'eligibleBoost': noteMoyenne >= TarificationBoost.seuilsBadges['bloque_boost']!,
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROPAGATION VERS L'AGENT IA
  // ══════════════════════════════════════════════════════════════════════════

  /// Mettre à jour le profil de scoring du livreur pour l'agent IA
  static Future<void> _mettreAJourAgentLivraison(
      String livreurId, double nouvelleNote) async {
    // L'agent utilise : scoreNote = noteMoyenne / 5.0 (poids 25%)
    // On met à jour dans securite_livreurs pour que l'agent le lise
    await _db.collection('securite_livreurs').doc(livreurId).update({
      'noteMoyenne': nouvelleNote,
      'scoreNoteAgent': double.parse((nouvelleNote / 5.0).toStringAsFixed(4)),
      'dateMiseAJourNote': FieldValue.serverTimestamp(),
    });
  }

  /// Score agrégé pour l'agent : boutique + couturier utilisés dans la commande
  static Future<double> scoreCompletPourCommande(String sousCommandeId) async {
    final sc = await _db.collection('sous_commandes').doc(sousCommandeId).get();
    if (!sc.exists) return 0;

    final data = sc.data()!;
    final boutiqueId = data['boutiqueId'] as String?;
    final couturierId = data['couturierId'] as String?;

    double scoreBoutique = 4.0; // défaut neutre
    double scoreCouturier = 4.0;

    if (boutiqueId != null) {
      final bDoc = await _db.collection('boutiques').doc(boutiqueId).get();
      scoreBoutique = (bDoc.data()?['noteMoyenne'] as num?)?.toDouble() ?? 4.0;
    }

    if (couturierId != null) {
      final cDoc = await _db.collection('couturiers').doc(couturierId).get();
      scoreCouturier = (cDoc.data()?['noteMoyenne'] as num?)?.toDouble() ?? 4.0;
    }

    // Score de la commande = moyenne boutique + couturier
    return (scoreBoutique + scoreCouturier) / 2;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCORE DE FIABILITÉ CLIENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Calculer et mettre à jour le score de fiabilité d'un client
  static Future<ScoreClient> calculerScoreClient(String clientId) async {
    // Récupérer les données historiques
    final [cmdSnap, litigesSnap, avisSnap] = await Future.wait([
      _db.collection('sessions_commande')
          .where('clientId', isEqualTo: clientId)
          .get(),
      _db.collection('anomalies_livraison')
          .where('clientId', isEqualTo: clientId)
          .get(),
      Avis.collection
          .where('cibleId', isEqualTo: clientId)
          .where('cible', isEqualTo: CibleAvis.client.name)
          .where('statut', isEqualTo: StatutAvis.publie.name)
          .get(),
    ]);

    final totalCommandes = cmdSnap.docs.length;
    final commandesAnnulees = cmdSnap.docs
        .where((d) => d.data()['statut'] == 'annulee')
        .length;

    final litigesInities = litigesSnap.docs.length;
    final litigesGagnes = litigesSnap.docs
        .where((d) => d.data()['resoluEnFaveurClient'] == true)
        .length;
    final litigesPerdus = litigesInities - litigesGagnes;

    // Moyenne des notes reçues de la part des vendeurs/livreurs
    double noteMoyenneRecue = 5.0;
    if (avisSnap.docs.isNotEmpty) {
      final notes = avisSnap.docs
          .map((d) => (d.data()['note'] as num? ?? 0).toDouble())
          .toList();
      noteMoyenneRecue = notes.reduce((a, b) => a + b) / notes.length;
    }

    // ─── Calcul du score 0-100 ───────────────────────────────────────────
    // Départ à 100, on retire des points selon les comportements négatifs

    double score = 100;

    // Taux d'annulation (max -30 points)
    if (totalCommandes > 0) {
      final tauxAnnulation = commandesAnnulees / totalCommandes;
      score -= (tauxAnnulation * 30).clamp(0, 30);
    }

    // Litiges mal fondés (-10 par litige perdu, max -30)
    score -= (litigesPerdus * 10.0).clamp(0, 30);

    // Note moyenne reçue (max -20 points si très mauvaise note)
    if (noteMoyenneRecue < 5.0) {
      score -= ((5.0 - noteMoyenneRecue) * 5).clamp(0, 20);
    }

    // Bonus ancienneté : +5 si > 10 commandes réussies
    final commandesReussies = totalCommandes - commandesAnnulees;
    if (commandesReussies >= 10) score = (score + 5).clamp(0, 100);
    if (commandesReussies >= 50) score = (score + 5).clamp(0, 100);

    score = score.clamp(0, 100);

    final client = ScoreClient(
      clientId: clientId,
      scoreFiabilite: double.parse(score.toStringAsFixed(1)),
      commandesTotal: totalCommandes,
      commandesAnnulees: commandesAnnulees,
      litigesInities: litigesInities,
      litigesGagnes: litigesGagnes,
      litigesPerdus: litigesPerdus,
      noteMoyenneRecue: double.parse(noteMoyenneRecue.toStringAsFixed(2)),
      estBloque: score < 20, // score très bas → bloqué
    );

    // Sauvegarder
    await ScoreClient.collection.doc(clientId).set(client.toMap());

    // Bloquer si score critique
    if (client.estBloque) {
      await _db.collection('utilisateurs').doc(clientId)
          .update({'estBloque': true, 'raisonBlocage': 'Score fiabilité trop bas (${score.round()}/100)'});
    }

    return client;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODÉRATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Signaler un avis abusif
  static Future<void> signalerAvis(String avisId, String signaleurId, String raison) async {
    await _db.runTransaction((txn) async {
      final ref = Avis.collection.doc(avisId);
      final doc = await txn.get(ref);
      if (!doc.exists) return;

      final signalements = (doc.data()!['signalements'] as int? ?? 0) + 1;
      txn.update(ref, {
        'signalements': signalements,
        // Auto-masquage si > 3 signalements différents
        if (signalements >= 3) 'statut': StatutAvis.signale.name,
      });

      // Log du signalement
      _db.collection('signalements_avis').add({
        'avisId': avisId,
        'signaleurId': signaleurId,
        'raison': raison,
        'date': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Modérer un avis (admin)
  static Future<void> moderer(
    String avisId,
    StatutAvis nouveauStatut, {
    String? raison,
  }) async {
    await Avis.collection.doc(avisId).update({
      'statut': nouveauStatut.name,
      if (raison != null) 'raisonMasquage': raison,
    });

    // Recalculer la moyenne après modération
    final doc = await Avis.collection.doc(avisId).get();
    if (doc.exists) {
      final avis = Avis.fromDoc(doc);
      await _recalculerMoyenne(avis.cible, avis.cibleId);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LECTURE
  // ══════════════════════════════════════════════════════════════════════════

  /// Résumé des notes d'une cible (pour affichage dans les listes)
  static Future<ResumeNotes> getResume(CibleAvis cible, String cibleId) async {
    final snap = await Avis.collection
        .where('cible', isEqualTo: cible.name)
        .where('cibleId', isEqualTo: cibleId)
        .where('statut', isEqualTo: StatutAvis.publie.name)
        .get();

    if (snap.docs.isEmpty) {
      return ResumeNotes(cibleId: cibleId, moyenne: 0, nombre: 0);
    }

    final avis = snap.docs.map(Avis.fromDoc).toList();
    final moyenne = avis.fold<double>(0, (s, a) => s + a.note) / avis.length;

    // Distribution des notes (combien de 1⭐, 2⭐, etc.)
    final distribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final a in avis) {
      distribution[a.note.round()] = (distribution[a.note.round()] ?? 0) + 1;
    }

    return ResumeNotes(
      cibleId: cibleId,
      moyenne: double.parse(moyenne.toStringAsFixed(2)),
      nombre: avis.length,
      distribution: distribution,
    );
  }

  /// Vérifier si un utilisateur peut noter (a une livraison confirmée)
  static Future<bool> peutNoter({
    required String auteurId,
    required CibleAvis cible,
    required String cibleId,
  }) async {
    // Chercher une livraison terminée qui implique cette cible
    if (cible == CibleAvis.pagne || cible == CibleAvis.boutique) {
      final snap = await _db.collection('sous_commandes')
          .where('clientId', isEqualTo: auteurId)
          .where('boutiqueId', isEqualTo: cibleId)
          .where('statut', isEqualTo: 'livree')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    }
    if (cible == CibleAvis.livreur) {
      final snap = await _db.collectionGroup('livraisons')
          .where('livreurId', isEqualTo: cibleId)
          .where('statut', isEqualTo: 'livree')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    }
    // Couturier, client → on vérifie une commande terminée
    return true;
  }
}

// ─── Résumé des notes ─────────────────────────────────────────────────────────

class ResumeNotes {
  final String cibleId;
  final double moyenne;
  final int nombre;
  final Map<int, int> distribution;

  const ResumeNotes({
    required this.cibleId,
    required this.moyenne,
    required this.nombre,
    this.distribution = const {},
  });

  bool get aDesAvis => nombre > 0;

  // Pourcentage de chaque note pour la barre de distribution
  double pct(int etoiles) =>
      nombre == 0 ? 0 : (distribution[etoiles] ?? 0) / nombre;
}
