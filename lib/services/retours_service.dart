import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/models/retour.dart';
import 'package:sami/services/stock_service.dart';
import 'package:sami/models/configuration_taxes.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE RETOURS — Logique complète
// Gère : initiation, analyse agent IA, décision superviseur, remboursement
// ═══════════════════════════════════════════════════════════════════════════

class RetoursService {

  // ── Initiation d'un retour ────────────────────────────────────────────────

  /// Initié par le CLIENT
  static Future<DossierRetour> initierRetourClient({
    required String clientId,
    required String livraisonId,
    required String commandeId,
    required String boutiqueId,
    required String pagneId,
    required MotifRetour motif,
    required double montantPaye,
    required double fraisLivraisonPaye,
    PreuveRetour? preuve,
    String? livreurId,
  }) async {
    return _creerDossier(
      livraisonId: livraisonId,
      commandeId: commandeId,
      clientId: clientId,
      boutiqueId: boutiqueId,
      pagneId: pagneId,
      livreurId: livreurId,
      motif: motif,
      initiateur: InitiateurRetour.client,
      initieurId: clientId,
      montantPaye: montantPaye,
      fraisLivraisonPaye: fraisLivraisonPaye,
      preuve: preuve,
      priorite: motif == MotifRetour.pagneDefectueux ? 1 : 2,
    );
  }

  /// Initié par le BOUTIQUIER (ex: il reconnaît une erreur de taille)
  static Future<DossierRetour> initierRetourBoutiquier({
    required String boutiqueId,
    required String livraisonId,
    required String commandeId,
    required String clientId,
    required String pagneId,
    required MotifRetour motif,
    required double montantPaye,
    required double fraisLivraisonPaye,
    String? noteInterne,
  }) async {
    return _creerDossier(
      livraisonId: livraisonId,
      commandeId: commandeId,
      clientId: clientId,
      boutiqueId: boutiqueId,
      pagneId: pagneId,
      motif: motif,
      initiateur: InitiateurRetour.boutiquier,
      initieurId: boutiqueId,
      montantPaye: montantPaye,
      fraisLivraisonPaye: fraisLivraisonPaye,
      noteInterne: noteInterne,
      priorite: 2,
    );
  }

  /// Initié par l'AGENT IA — détection automatique (retard, anomalie)
  static Future<DossierRetour?> detecterRetourAutomatique({
    required String livraisonId,
    required String commandeId,
    required String clientId,
    required String boutiqueId,
    required String pagneId,
    required String? livreurId,
    required double montantPaye,
    required double fraisLivraisonPaye,
    required DateTime dateLivraisonPrevue,
  }) async {
    final now = DateTime.now();
    final retardHeures = now.difference(dateLivraisonPrevue).inHours;

    // Seuil : retard > 2h → agent ouvre automatiquement un dossier
    if (retardHeures < 2) return null;

    // Vérifier qu'un dossier n'existe pas déjà
    final existant = await DossierRetour.collection
        .where('livraisonId', isEqualTo: livraisonId)
        .limit(1)
        .get();
    if (existant.docs.isNotEmpty) return null;

    final dossier = await _creerDossier(
      livraisonId: livraisonId,
      commandeId: commandeId,
      clientId: clientId,
      boutiqueId: boutiqueId,
      pagneId: pagneId,
      livreurId: livreurId,
      motif: MotifRetour.retardLivraison,
      initiateur: InitiateurRetour.agentIA,
      initieurId: null,
      montantPaye: montantPaye,
      fraisLivraisonPaye: fraisLivraisonPaye,
      noteInterne: 'Détecté automatiquement — retard de ${retardHeures}h',
      priorite: 1, // urgent
    );

    // Escalade immédiate au superviseur
    await _escaladerSuperviseur(
      dossierRetourId: dossier.id,
      message: '🚨 Retard détecté automatiquement — '
          'livraison #$livraisonId en retard de ${retardHeures}h. '
          'Client non livré. Action requise.',
    );

    return dossier;
  }

  // ── Analyse et décision ───────────────────────────────────────────────────

  /// L'agent IA analyse le dossier et prend/propose une décision
  static Future<void> analyserDossierAgent(String dossierId) async {
    final doc = await DossierRetour.collection.doc(dossierId).get();
    if (!doc.exists) return;

    final dossier = DossierRetour.fromFirebaseDocument(doc);
    final regle = dossier.regle;

    // Mise à jour statut
    await DossierRetour.collection.doc(dossierId).update({
      'statut': StatutRetour.enExamen.name,
      'dateExamen': DateTime.now(),
    });

    // Score de confiance selon la clarté du cas
    final double scoreConfiance = _calculerScoreConfiance(dossier);

    // Décision proposée
    final montantRembourse = dossier.montantRemboursable;
    final decision = DecisionRetour(
      decideurId: 'agent_retours',
      estAgent: true,
      decision: StatutRetour.accepte,
      justification: _genererJustification(dossier, regle),
      typeRemboursement: regle.remboursementParDefaut,
      montantRembourse: montantRembourse,
      dateDecision: DateTime.now(),
      valideeParHumain: false,
    );

    if (scoreConfiance >= 0.85) {
      // Autonomie totale : agent décide seul
      await _appliquerDecision(dossierId, dossier, decision);
      await _logDecisionAgentRetour(dossierId, decision, scoreConfiance, 'auto');
    } else {
      // Supervision requise : agent soumet au superviseur
      await DossierRetour.collection.doc(dossierId).update({
        'decision': decision.toMap(),
      });
      await _escaladerSuperviseur(
        dossierRetourId: dossierId,
        message: '⏳ Validation requise — Retour #$dossierId\n'
            'Motif : ${dossier.motif.name}\n'
            'Proposition : ${decision.typeRemboursement.name} '
            '(${PrixFCFA.formater(montantRembourse)})\n'
            'Confiance agent : ${(scoreConfiance * 100).round()}%',
      );
    }
  }

  /// Le superviseur valide la décision de l'agent
  static Future<void> validerDecisionSuperviseur({
    required String dossierId,
    required String superviseurId,
    required bool accepter,
    TypeRemboursement? typeRemboursementOverride,
    double? montantOverride,
    required String justification,
  }) async {
    final doc = await DossierRetour.collection.doc(dossierId).get();
    if (!doc.exists) return;
    final dossier = DossierRetour.fromFirebaseDocument(doc);

    final decision = DecisionRetour(
      decideurId: superviseurId,
      estAgent: false,
      decision: accepter ? StatutRetour.accepte : StatutRetour.rejete,
      justification: justification,
      typeRemboursement: typeRemboursementOverride ??
          dossier.regle.remboursementParDefaut,
      montantRembourse: montantOverride ?? dossier.montantRemboursable,
      dateDecision: DateTime.now(),
      valideeParHumain: true,
    );

    if (accepter) {
      await _appliquerDecision(dossierId, dossier, decision);
    } else {
      await DossierRetour.collection.doc(dossierId).update({
        'statut': StatutRetour.rejete.name,
        'decision': decision.toMap(),
        'dateDecision': DateTime.now(),
      });
      // Notifier le client du refus
      await _notifierClient(
        clientId: dossier.clientId,
        titre: 'Retour refusé',
        message: justification,
        type: 'retour_refuse',
      );
    }
  }

  // ── Remboursement ─────────────────────────────────────────────────────────

  static Future<void> _appliquerDecision(
    String dossierId,
    DossierRetour dossier,
    DecisionRetour decision,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    final dossierRef = DossierRetour.collection.doc(dossierId);

    // Mise à jour dossier
    batch.update(dossierRef, {
      'statut': dossier.regle.retourArticleRequis
          ? StatutRetour.enCoursDRetour.name
          : StatutRetour.rembourse.name,
      'decision': decision.toMap(),
      'dateDecision': DateTime.now(),
    });

    // Pénalité boutiquier si applicable
    final pctBoutique = dossier.regle.pctRetenuBoutique;
    if (pctBoutique > 0) {
      final penalite = PrixFCFA.arrondirAu50(
        dossier.montantPaye * pctBoutique / 100,
      );
      final boutiqueRef = FirebaseFirestore.instance
          .collection('boutiques')
          .doc(dossier.boutiqueId);
      batch.update(boutiqueRef, {
        'creditBalance': FieldValue.increment(-penalite),
      });
      // Transaction pénalité
      final penaliteRef =
          FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(penaliteRef, {
        'type': 'penalite_retour',
        'boutiqueId': dossier.boutiqueId,
        'dossierId': dossierId,
        'montantBrut': -penalite,
        'montantNet': -penalite,
        'methodePaiement': 'interne',
        'dateCreation': DateTime.now(),
        'statut': 'confirmee',
        'note': 'Pénalité retour ${dossier.motif.name} — ${pctBoutique}%',
      });
    }

    // Pénalité livreur si applicable
    final pctLivreur = dossier.regle.pctRetenuLivreur;
    if (pctLivreur > 0 && dossier.livreurId != null) {
      final penalite = PrixFCFA.arrondirAu50(
        dossier.montantPaye * pctLivreur / 100,
      );
      final livreurRef = FirebaseFirestore.instance
          .collection('livreurs')
          .doc(dossier.livreurId!);
      batch.update(livreurRef, {
        'creditBalance': FieldValue.increment(-penalite),
      });
    }

    await batch.commit();

    // Restituer le stock : l'article retourné revient en inventaire,
    // SAUF s'il est défectueux (invendable → ne pas remettre en stock).
    if (dossier.motif != MotifRetour.pagneDefectueux) {
      await StockService.restituerStock(
          pagneId: dossier.pagneId, quantite: dossier.quantite);
    }

    // Remboursement immédiat si pas de retour article requis
    if (!dossier.regle.retourArticleRequis) {
      await _effectuerRemboursement(dossier, decision);
    } else {
      // Générer QR code retour pour l'article
      await _genererQrRetour(dossierId);
      // Notifier le client des instructions de retour
      await _notifierClient(
        clientId: dossier.clientId,
        titre: 'Retour accepté — à renvoyer',
        message: 'Votre retour a été accepté. '
            'Veuillez renvoyer l\'article avec le QR code fourni. '
            'Remboursement : ${PrixFCFA.formater(decision.montantRembourse)} '
            'après réception.',
        type: 'retour_accepte_renvoi',
      );
    }
  }

  static Future<void> _effectuerRemboursement(
    DossierRetour dossier,
    DecisionRetour decision,
  ) async {
    final batch = FirebaseFirestore.instance.batch();

    // Créer la transaction de remboursement
    final txRef = FirebaseFirestore.instance.collection('transactions').doc();
    batch.set(txRef, {
      'type': 'remboursementClient',
      'clientId': dossier.clientId,
      'boutiqueId': dossier.boutiqueId,
      'dossierId': dossier.id,
      'montantBrut': decision.montantRembourse,
      'montantNet': decision.montantRembourse,
      'methodePaiement': decision.typeRemboursement.name,
      'dateCreation': DateTime.now(),
      'dateConfirmation': DateTime.now(),
      'statut': 'confirmee',
    });

    // Selon le type de remboursement
    if (decision.typeRemboursement == TypeRemboursement.creditsPlateforme) {
      final clientRef = FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(dossier.clientId);
      batch.update(clientRef, {
        'creditBalance': FieldValue.increment(decision.montantRembourse),
      });
    }
    // Mobile Money → à déclencher via CinetPay API (TODO)

    // Mettre à jour le dossier
    batch.update(DossierRetour.collection.doc(dossier.id), {
      'statut': StatutRetour.rembourse.name,
      'dateRemboursement': DateTime.now(),
    });

    await batch.commit();

    await _notifierClient(
      clientId: dossier.clientId,
      titre: 'Remboursement effectué ✅',
      message: '${PrixFCFA.formater(decision.montantRembourse)} '
          'remboursés via ${decision.typeRemboursement.name}.',
      type: 'remboursement_effectue',
    );
  }

  // ── Validation retour article (QR scan en boutique) ───────────────────────

  static Future<void> validerReceptionArticleRetour({
    required String dossierId,
    required String qrCode,
    required String boutiqueId,
  }) async {
    final doc = await DossierRetour.collection.doc(dossierId).get();
    if (!doc.exists) return;

    final dossier = DossierRetour.fromFirebaseDocument(doc);
    if (dossier.qrCodeRetour != qrCode) return; // QR invalide

    await DossierRetour.collection.doc(dossierId).update({
      'statut': StatutRetour.articleRecu.name,
      'dateRetourArticle': DateTime.now(),
    });

    // Déclencher le remboursement maintenant que l'article est reçu
    if (dossier.decision != null) {
      await _effectuerRemboursement(dossier, dossier.decision!);
    }
  }

  // ── Utilitaires privés ────────────────────────────────────────────────────

  static Future<DossierRetour> _creerDossier({
    required String livraisonId,
    required String commandeId,
    required String clientId,
    required String boutiqueId,
    required String pagneId,
    String? livreurId,
    required MotifRetour motif,
    required InitiateurRetour initiateur,
    String? initieurId,
    required double montantPaye,
    required double fraisLivraisonPaye,
    PreuveRetour? preuve,
    String? noteInterne,
    int priorite = 2,
  }) async {
    final ref = DossierRetour.collection.doc();
    final dossier = DossierRetour(
      id: ref.id,
      livraisonId: livraisonId,
      commandeId: commandeId,
      clientId: clientId,
      boutiqueId: boutiqueId,
      pagneId: pagneId,
      livreurId: livreurId,
      motif: motif,
      initiateur: initiateur,
      initieurId: initieurId,
      montantPaye: montantPaye,
      fraisLivraisonPaye: fraisLivraisonPaye,
      preuve: preuve,
      noteInterne: noteInterne,
      priorite: priorite,
      dateCreation: DateTime.now(),
    );

    await ref.set(dossier.toMap());
    return dossier;
  }

  static double _calculerScoreConfiance(DossierRetour dossier) {
    double score = 0.5; // base

    // Preuve fournie → +0.25
    if (dossier.preuve != null && dossier.preuve!.photoUrls.isNotEmpty) {
      score += 0.25;
    }

    // Motif clair et documenté → +0.15
    if (dossier.motif == MotifRetour.retardLivraison) score += 0.20;
    if (dossier.motif == MotifRetour.mauvaiseTaille) score += 0.15;

    // Initié par le boutiquier lui-même → très fiable
    if (dossier.initiateur == InitiateurRetour.boutiquier) score += 0.20;

    // Dans les délais réglementaires
    if (!dossier.estEnRetard) score += 0.10;

    return score.clamp(0.0, 1.0);
  }

  static String _genererJustification(DossierRetour d, RegleRetour regle) {
    return switch (d.motif) {
      MotifRetour.changementAvis =>
        'Client a changé d\'avis dans le délai de ${regle.delaiMaxHeures}h. '
        'Remboursement de ${regle.pctRembourseClient}% (hors frais livraison).',
      MotifRetour.mauvaiseTaille =>
        'Erreur de taille constatée — responsabilité boutique. '
        'Remboursement total + échange proposé.',
      MotifRetour.pagneDefectueux =>
        'Pagne non conforme — responsabilité boutique. '
        'Remboursement total + pénalité ${regle.pctRetenuBoutique}%.',
      MotifRetour.retardLivraison =>
        'Retard de livraison dépassant le délai convenu. '
        'Remboursement total + pénalité livreur ${regle.pctRetenuLivreur}%.',
    };
  }

  static Future<void> _escaladerSuperviseur({
    required String dossierRetourId,
    required String message,
  }) async {
    await FirebaseFirestore.instance.collection('alertes_agent').add({
      'type': 'retour_validation',
      'dossierRetourId': dossierRetourId,
      'niveau': 'aValider',
      'statut': 'en_attente',
      'message': message,
      'dateCreation': DateTime.now(),
    });
  }

  static Future<void> _logDecisionAgentRetour(
    String dossierId,
    DecisionRetour decision,
    double score,
    String mode,
  ) async {
    await FirebaseFirestore.instance.collection('logs_agent').add({
      'type': 'decision_retour_$mode',
      'dossierId': dossierId,
      'decision': decision.toMap(),
      'scoreConfiance': score,
      'dateCreation': DateTime.now(),
      'message': '${mode == 'auto' ? '✅' : '⏳'} Retour traité '
          '(confiance ${(score * 100).round()}%)',
    });
  }

  static Future<void> _genererQrRetour(String dossierId) async {
    final qr = 'SAMI-RETOUR-$dossierId-${DateTime.now().millisecondsSinceEpoch}';
    await DossierRetour.collection.doc(dossierId).update({
      'qrCodeRetour': qr,
    });
  }

  static Future<void> _notifierClient({
    required String clientId,
    required String titre,
    required String message,
    required String type,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'destinataireId': clientId,
      'type': type,
      'titre': titre,
      'message': message,
      'lu': false,
      'dateCreation': DateTime.now(),
    });
  }
}
