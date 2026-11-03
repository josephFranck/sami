import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/services/notation_service.dart';
import 'package:sami/services/notification_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/models/livreur.dart';

/// Agent IA responsable de l'assignation des livraisons.
/// Il opère sous l'autorité d'un agent humain (superviseur).
///
/// NIVEAUX D'AUTONOMIE :
/// - Score > 0.85 → décision autonome, log envoyé au superviseur
/// - Score 0.60-0.85 → proposition soumise au superviseur pour validation
/// - Score < 0.60 → escalade obligatoire au superviseur humain
class AgentLivraison {
  /// Les alertes ne doivent pas dormir dans une collection : chaque
  /// escalade/proposition PRÉVIENT les admins d'une notification
  /// cliquable qui ouvre le poste de supervision.
  static Future<void> _prevenirSuperviseurs(String message) async {
    try {
      final admins = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .where('role', isEqualTo: 'admin')
          .limit(5)
          .get();
      for (final a in admins.docs) {
        await NotificationService.envoyer(
          destinataireId: a.id,
          titre: 'Supervision livraison 🚨',
          message: message,
          route: '/supervision',
        );
      }
    } catch (_) {}
  }

  static const double SEUIL_AUTONOMIE_TOTALE = 0.85;
  static const double SEUIL_SUPERVISION = 0.60;

  /// Point d'entrée principal : l'agent traite une nouvelle livraison
  static Future<void> traiterNouvelleLivraison(String livraisonId) async {
    // LOT C : si l'assignation est faite par la Cloud Function
    // (onLivraisonCreee, privilèges serveur), cet agent local se tait.
    if (await ParametresService.assignationServeur()) return;
    try {
      // 1. Récupérer la livraison
      final livraisonDoc = await FirebaseFirestore.instance
          .collection('livraisons')
          .doc(livraisonId)
          .get();

      if (!livraisonDoc.exists) return;

      final livraison = Livraison.fromFirebaseDocument(livraisonDoc);

      // 2. Mettre à jour le statut
      await _updateStatut(livraisonId, StatutLivraison.rechercheLibreur);

      // 3. Trouver les meilleurs livreurs candidats
      final candidats = await _trouverCandidats(livraison);

      // DÉROGATION ADMIN (paramétrable PAR livreur) : un livreur dont
      // `autoriseJusquau` est dans le futur reste éligible même si son
      // abonnement/quota a expiré ; passé cette date, la dérogation tombe.
      // Un livreur non disponible sans dérogation valide est écarté.
      candidats.removeWhere((l) {
        if (l.statut == StatutLivreur.disponible) return false; // dispo normale : on garde
        final derog = l.autoriseJusquau;
        return derog == null || DateTime.now().isAfter(derog);
      });

      // PLAFOND CASH : pour une course en espèces, écarter les livreurs
      // dont l'encours dépasse le plafond (Paramètres) tant qu'ils n'ont
      // pas remis leur caisse.
      final plafond = await ParametresService.plafondCashLivreur();
      if (plafond > 0 && livraison.methodePaiementChoisi == 'cash') {
        candidats.removeWhere((l) => l.encoursCash >= plafond);
      }

      if (candidats.isEmpty) {
        // Aucun livreur disponible → escalade humaine obligatoire
        await _escaladerVersHumain(
          livraisonId,
          'Aucun livreur disponible dans le secteur ${livraison.destinationQuartier}',
          AlerteNiveau.urgent,
        );
        return;
      }

      // 4. Scorer chaque candidat
      // Le score de la commande (boutique+couturier) ne dépend pas du livreur
      // → on le calcule une seule fois ici, pas dans la boucle
      final scoreCommande = await NotationService.scoreCompletPourCommande(
          livraison.sousCommandeId);
      final meilleurCandidatResult = _scorerCandidats(candidats, livraison, scoreCommande);
      final meilleurLivreur = meilleurCandidatResult['livreur'] as Livreur;
      final score = meilleurCandidatResult['score'] as double? ?? 0.0;
      final raisonnement = meilleurCandidatResult['raisonnement'] as String? ?? '';

      final decision = DecisionAgent(
        livreurId: meilleurLivreur.id,
        raisonnement: raisonnement,
        scoreConfiance: score,
        timestamp: DateTime.now(),
        valideeParHumain: false,
      );

      // 5. Décision selon le niveau d'autonomie
      if (score >= SEUIL_AUTONOMIE_TOTALE) {
        // ✅ Autonomie totale — agent décide seul
        await _assignerLivreur(livraisonId, meilleurLivreur.id, decision, 'auto');
        // Log envoyé au superviseur (informatif, pas bloquant)
        await _logDecisionAutonome(livraisonId, decision);
      } else if (score >= SEUIL_SUPERVISION) {
        // ⏳ Supervision — agent propose, humain valide
        await _soumettrePropositionHumain(livraisonId, decision);
      } else {
        // 🚨 Escalade — humain obligatoire
        await _escaladerVersHumain(
          livraisonId,
          'Score de confiance insuffisant ($score). Candidats : ${candidats.length}. $raisonnement',
          AlerteNiveau.aValider,
        );
      }
    } catch (e) {
      // En cas d'erreur technique → escalade automatique
      await _escaladerVersHumain(
        livraisonId,
        'Erreur technique agent : $e',
        AlerteNiveau.urgent,
      );
    }
  }

  /// Trouve les livreurs disponibles proches de l'origine
  static Future<List<Livreur>> _trouverCandidats(Livraison livraison) async {
    // Rayon de recherche : ~5km autour de l'origine
    const double RAYON_DEGRES = 0.045; // ~5km

    final snapshot = await FirebaseFirestore.instance
        .collection('livreurs')
        // DEUX LIGNÉES de fiches coexistent : les modernes portent le
        // booléen `disponible`, les anciennes un `statut` texte. La
        // requête stricte sur `statut` excluait TOUTES les fiches
        // modernes → « aucun livreur » à tort. On requête LARGE et on
        // filtre finement côté client.
        .where('disponible', isEqualTo: true)
        .get();

    final candidats = <Livreur>[];

    for (final doc in snapshot.docs) {
      final d = doc.data();
      // exclusions FINES côté client (tolérant aux champs absents) :
      // un `estVerifie: false` EXPLICITE écarte ; absent = accepté.
      if (d['estVerifie'] == false) continue;
      if (d['statut'] == 'indisponible') continue;
      final livreur = Livreur.fromFirebaseDocument(doc);
      // Filtre géographique simple (proximité origine)
      final sansPosition =
          livreur.latitude == 0 && livreur.longitude == 0;
      final distLat = (livreur.latitude - livraison.origineLat).abs();
      final distLng = (livreur.longitude - livraison.origineLng).abs();
      // Sans position connue : on INCLUT (le score de proximité le
      // pénalisera) — l'exclure ferait mentir « aucun livreur ».
      if (sansPosition ||
          (distLat <= RAYON_DEGRES && distLng <= RAYON_DEGRES)) {
        // Filtre créneau horaire — une fiche SANS créneaux déclarés
        // (moderne/minimale) = disponible en continu, sinon les
        // fiches promues seraient invisibles à toute heure.
        final aucunCreneau = !livreur.disponibleMatin &&
            !livreur.disponibleApresmidi &&
            !livreur.disponibleSoir;
        final heure = DateTime.now().hour;
        if (aucunCreneau) {
          candidats.add(livreur);
        } else if (heure >= 7 && heure < 12 && livreur.disponibleMatin) {
          candidats.add(livreur);
        } else if (heure >= 12 && heure < 17 && livreur.disponibleApresmidi) {
          candidats.add(livreur);
        } else if (heure >= 17 && heure < 22 && livreur.disponibleSoir) {
          candidats.add(livreur);
        }
      }
    }

    return candidats;
  }

  /// Attribue un score à chaque candidat et retourne le meilleur
  static Map<String, dynamic> _scorerCandidats(
    List<Livreur> candidats,
    Livraison livraison,
    double scoreCommande,
  ) {
    Livreur? meilleur;
    double meilleurScore = 0.0;
    String meilleurRaisonnement = '';

    for (final livreur in candidats) {
      // Calcul distance (approximation euclidienne)
      final distOrigine = _distanceKm(
        livreur.latitude, livreur.longitude,
        livraison.origineLat, livraison.origineLng,
      );

      // Facteurs de score (pondérés)
      final scoreProximite = _normaliser(5.0 - distOrigine, 0, 5); // max 5km
      final scoreNote = livreur.noteMoyenne / 5.0;
      // Score de la commande (boutique + couturier) — poids 15%
      // Calculé une seule fois en amont, passé en paramètre
      final scoreCommandeNorm = scoreCommande / 5.0;
      final scoreDelai = livreur.tauxRespectDelai / 100.0;
      final scoreExperience = _normaliser(livreur.nombreLivraisons.toDouble(), 0, 200);

      // Bonus véhicule adapté
      double bonusVehicule = 0.0;
      if (livraison.typeLivraison == TypeLivraison.glace &&
          livreur.typeVehicule == TypeVehicule.tricycle) {
        bonusVehicule = 0.15;
      }

      // Score final pondéré
      final score = (scoreProximite * 0.35) +
          (scoreNote * 0.25) +
          (scoreCommandeNorm * 0.15) +
          (scoreDelai * 0.20) +
          (scoreExperience * 0.10) +
          bonusVehicule;

      final raisonnement = 'Livreur ${livreur.nom}: '
          'proximité=${(distOrigine).toStringAsFixed(1)}km, '
          'note=${livreur.noteMoyenne}/5, scoreCommande=${scoreCommande.toStringAsFixed(1)}, '
          'délais=${livreur.tauxRespectDelai}%, '
          'score=${ (score * 100).toStringAsFixed(0)}%';

      if (score > meilleurScore) {
        meilleurScore = score;
        meilleur = livreur;
        meilleurRaisonnement = raisonnement;
      }
    }

    return {
      'livreur': meilleur!,
      'score': meilleurScore,
      'raisonnement': meilleurRaisonnement,
    };
  }

  /// Assigne effectivement le livreur à la livraison
  static Future<void> _assignerLivreur(
    String livraisonId,
    String livreurId,
    DecisionAgent decision,
    String niveauAutonomie,
  ) async {
    final batch = FirebaseFirestore.instance.batch();

    // Mettre à jour la livraison
    final livraisonRef = FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId);
    batch.update(livraisonRef, {
      'livreurId': livreurId,
      'statut': StatutLivraison.livreurAssigne.name,
      'dateAssignation': DateTime.now(),
      'decisionAgent': decision.toMap(),
      'niveauAutonomie': niveauAutonomie,
    });

    // Mettre à jour le statut du livreur
    final livreurRef = FirebaseFirestore.instance
        .collection('livreurs')
        .doc(livreurId);
    batch.set(livreurRef, {
      'statut': StatutLivreur.enCourse.name,
    }, SetOptions(merge: true));

    // le livreur est INSCRIT sur la sous-commande — la règle de
    // sécurité s'appuie dessus (seules les parties prenantes écrivent).
    final livDoc = await FirebaseFirestore.instance
        .collection('livraisons').doc(livraisonId).get();
    final cmdId = livDoc.data()?['commandeId'] as String? ?? '';
    if (cmdId.isNotEmpty) {
      batch.set(
          FirebaseFirestore.instance
              .collection('sous_commandes').doc(cmdId),
          {'livreurId': livreurId},
          SetOptions(merge: true));
    }

    await batch.commit();

    // Envoyer notification au livreur (via FCM — à implémenter)
    await _notifierLivreur(livreurId, livraisonId);
  }

  /// Soumet une proposition à valider par le superviseur humain
  static Future<void> _soumettrePropositionHumain(
    String livraisonId,
    DecisionAgent decision,
  ) async {
    await FirebaseFirestore.instance
        .collection('alertes_agent')
        .add({
      'type': 'proposition_assignation',
      'livraisonId': livraisonId,
      'decisionProposee': decision.toMap(),
      'niveau': AlerteNiveau.aValider.name,
      'statut': 'en_attente',
      'dateCreation': DateTime.now(),
      'message': '⏳ Validation requise : ${decision.raisonnement}',
    });
    await _prevenirSuperviseurs('Proposition à valider — un livreur attend votre feu vert.');

    // Mettre à jour la livraison en attente de validation
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update({
      'statut': StatutLivraison.rechercheLibreur.name,
      'decisionAgent': decision.toMap(),
      'niveauAutonomie': 'supervised',
    });
  }

  /// Escalade vers le superviseur humain (cas critiques)
  static Future<void> _escaladerVersHumain(
    String livraisonId,
    String message,
    AlerteNiveau niveau,
  ) async {
    await FirebaseFirestore.instance
        .collection('alertes_agent')
        .add({
      'type': 'escalade_livraison',
      'livraisonId': livraisonId,
      'niveau': niveau.name,
      'statut': 'en_attente',
      'dateCreation': DateTime.now(),
      'message': '🚨 Action humaine requise : $message',
    });
    await _prevenirSuperviseurs('Escalade : aucune assignation automatique possible.');
  }

  /// Log informatif pour les décisions autonomes (superviseur informé)
  static Future<void> _logDecisionAutonome(
    String livraisonId,
    DecisionAgent decision,
  ) async {
    await FirebaseFirestore.instance
        .collection('logs_agent')
        .add({
      'type': 'decision_autonome',
      'livraisonId': livraisonId,
      'decision': decision.toMap(),
      'dateCreation': DateTime.now(),
      'message': '✅ Assignation autonome : ${decision.raisonnement}',
    });
  }

  // ─── Méthodes appelées par le superviseur humain ──────────────────────────

  /// Le superviseur valide la proposition de l'agent
  static Future<void> validerProposition(
    String alerteId,
    String livraisonId,
    DecisionAgent decision,
    String commentaireSuperviseur,
  ) async {
    final decisionValidee = DecisionAgent(
      livreurId: decision.livreurId,
      raisonnement: decision.raisonnement,
      scoreConfiance: decision.scoreConfiance,
      timestamp: decision.timestamp,
      valideeParHumain: true,
      commentaireHumain: commentaireSuperviseur,
    );

    await _assignerLivreur(livraisonId, decision.livreurId, decisionValidee, 'supervised');

    // Fermer l'alerte
    await FirebaseFirestore.instance
        .collection('alertes_agent')
        .doc(alerteId)
        .update({'statut': 'traitee', 'dateCloture': DateTime.now()});
    await _cloreAlertes(livraisonId,
        resolution: 'proposition_validee',
        par: FirebaseAuth.instance.currentUser?.uid);
  }

  /// Le superviseur rejette et choisit manuellement un autre livreur

  /// Clore TOUTES les alertes ouvertes d'une livraison — l'agent SAIT
  /// que son escalade a été traitée (auto, validée ou manuelle) et
  /// l'onglet Urgent ne collectionne plus de fantômes.
  static Future<void> _cloreAlertes(String livraisonId,
      {required String resolution, String? par}) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('alertes_agent')
          .where('livraisonId', isEqualTo: livraisonId)
          .get(); // mono-champ : AUCUN index requis (la clôture doit
                  // marcher même avant tout déploiement d'index)
      for (final d in q.docs) {
        if (d.data()['statut'] != 'en_attente') continue;
        await d.reference.update({
          'statut': 'traitee',
          'resolution': resolution,
          'traiteePar': par,
          'traiteLe': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  static Future<void> rejeterEtAssignerManuellement(
    String alerteId,
    String livraisonId,
    String livreurIdChoisiParHumain,
    String raisonRejet,
  ) async {
    final decisionHumaine = DecisionAgent(
      livreurId: livreurIdChoisiParHumain,
      raisonnement: 'Décision manuelle superviseur : $raisonRejet',
      scoreConfiance: 1.0,
      timestamp: DateTime.now(),
      valideeParHumain: true,
      commentaireHumain: raisonRejet,
    );

    await _assignerLivreur(
        livraisonId, livreurIdChoisiParHumain, decisionHumaine, 'manual');

    await FirebaseFirestore.instance
        .collection('alertes_agent')
        .doc(alerteId)
        .update({
      'statut': 'rejetee_manuelle',
      'raisonRejet': raisonRejet,
      'dateCloture': DateTime.now(),
    });
    await _cloreAlertes(livraisonId,
        resolution: 'assignation_manuelle',
        par: FirebaseAuth.instance.currentUser?.uid);
  }

  // ─── Utilitaires ──────────────────────────────────────────────────────────

  static Future<void> _updateStatut(String livraisonId, StatutLivraison statut) async {
    await FirebaseFirestore.instance
        .collection('livraisons')
        .doc(livraisonId)
        .update({'statut': statut.name});
  }

  static Future<void> _notifierLivreur(String livreurId, String livraisonId) async {
    // Notification in-app (la Cloud Function FCM relaiera en push)
    try {
      final fiche = await FirebaseFirestore.instance
          .collection('livreurs').doc(livreurId).get();
      final uid = fiche.data()?['utilisateurId'] as String? ?? '';
      await NotificationService.envoyer(
        destinataireId: uid,
        titre: 'Nouvelle course 🛵',
        message: 'Une livraison vous a été assignée.',
        route: '/mes-livraisons',
        refId: livraisonId,
      );
    } catch (_) {}
    // Pour l'instant, on enregistre la notification en DB
    await FirebaseFirestore.instance.collection('notifications').add({
      'destinataireId': livreurId,
      'type': 'nouvelle_livraison',
      'livraisonId': livraisonId,
      'message': 'Nouvelle livraison disponible !',
      'lu': false,
      'dateCreation': DateTime.now(),
    });
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    // Approximation simple (suffisante pour Garoua ~50km)
    final dlat = (lat2 - lat1) * 111.0;
    final dlng = (lng2 - lng1) * 111.0 * 0.85; // correction latitude 9°N
    return (dlat * dlat + dlng * dlng);
  }

  static double _normaliser(double valeur, double min, double max) {
    if (max == min) return 0.0;
    final result = (valeur - min) / (max - min);
    return result.clamp(0.0, 1.0);
  }
}

enum AlerteNiveau {
  info,       // informatif, pas d'action requise
  aValider,   // agent attend validation humaine
  urgent,     // action humaine immédiate requise
}
