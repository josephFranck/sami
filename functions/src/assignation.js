'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// ASSIGNATION D'UN LIVREUR — port de lib/agents/agent_livraison.dart.
//
// Avant : l'agent tournait sur le téléphone du BOUTIQUIER (marquerPrete) ;
// ses écritures (livreurs.statut, alertes, notifications aux admins) ne
// passaient les règles que pour un compte staff. Ici : privilèges serveur,
// mêmes seuils d'autonomie (0,85 autonome / 0,60 proposition / sinon
// escalade), même scoring — distance en km RÉELS (l'app renvoyait un
// carré de distance, bug), rayon ~5 km.
// Activée par app_config/parametres.assignationServeur == true (l'app
// n'appelle alors plus son agent local).
// ═══════════════════════════════════════════════════════════════════════════
const admin = require('firebase-admin');
const { logger } = require('firebase-functions/v2');
const { textes } = require('./i18n');

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const SEUIL_AUTONOMIE_TOTALE = 0.85;
const SEUIL_SUPERVISION = 0.6;
const RAYON_DEGRES = 0.045; // ~5 km

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const normaliser = (v, min, max) => (max === min ? 0 : clamp((v - min) / (max - min), 0, 1));
function distanceKm(lat1, lng1, lat2, lng2) {
  const dlat = (lat2 - lat1) * 111.0;
  const dlng = (lng2 - lng1) * 111.0 * 0.85; // correction latitude 9°N (Garoua)
  return Math.sqrt(dlat * dlat + dlng * dlng);
}

async function prevenirSuperviseurs(message) {
  try {
    const admins = await db().collection('utilisateurs').where('role', 'in', ['admin', 'superadmin']).limit(5).get();
    for (const a of admins.docs) {
      await db().collection('notifications').add({
        destinataireId: a.id,
        titre: 'Supervision livraison 🚨',
        message,
        titreEn: 'Delivery supervision 🚨',
        messageEn: message,
        route: '/supervision',
        lue: false,
        date: FieldValue.serverTimestamp(),
        origine: 'serveur',
      });
    }
  } catch (_) {}
}

async function escalader(livraisonId, message, niveau) {
  await db().collection('alertes_agent').add({
    type: 'escalade_livraison',
    livraisonId,
    niveau,
    statut: 'en_attente',
    dateCreation: new Date(),
    message: `🚨 Action humaine requise : ${message}`,
    origine: 'serveur',
  });
  await prevenirSuperviseurs('Escalade : aucune assignation automatique possible.');
}

async function scoreCommande(sousCommandeId) {
  // Port minimal de NotationService.scoreCompletPourCommande : note de la
  // boutique (et du couturier s'il y en a un), sur 5, défaut 4.
  try {
    if (!sousCommandeId) return 4.0;
    const sc = await db().collection('sous_commandes').doc(sousCommandeId).get();
    const d = sc.data() || {};
    let total = 0;
    let n = 0;
    if (d.boutiqueId) {
      const b = await db().collection('boutiques').doc(d.boutiqueId).get();
      total += Number((b.data() || {}).noteMoyenne || 4.0);
      n++;
    }
    if (d.couturierId) {
      const c = await db().collection('couturiers').doc(d.couturierId).get();
      total += Number((c.data() || {}).noteMoyenne || 4.0);
      n++;
    }
    return n ? total / n : 4.0;
  } catch (_) {
    return 4.0;
  }
}

async function trouverCandidats(l) {
  const snap = await db().collection('livreurs').where('disponible', '==', true).get();
  const heure = new Date(Date.now() + 3600_000).getHours(); // Garoua = UTC+1
  const candidats = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (d.estVerifie === false) continue;
    if (d.statut === 'indisponible') continue;
    const lat = Number(d.latitude || 0);
    const lng = Number(d.longitude || 0);
    const sansPosition = lat === 0 && lng === 0;
    const proche = Math.abs(lat - Number(l.origineLat || 0)) <= RAYON_DEGRES && Math.abs(lng - Number(l.origineLng || 0)) <= RAYON_DEGRES;
    if (!sansPosition && !proche) continue;
    const matin = d.disponibleMatin !== false;
    const aprem = d.disponibleApresmidi !== false;
    const soir = d.disponibleSoir !== false;
    const aucunCreneau = !matin && !aprem && !soir;
    const ok = aucunCreneau || (heure >= 7 && heure < 12 && matin) || (heure >= 12 && heure < 17 && aprem) || (heure >= 17 && heure < 22 && soir);
    if (ok) candidats.push({ id: doc.id, ...d, latitude: lat, longitude: lng });
  }
  return candidats;
}

function scorer(candidats, l, scoreCmd) {
  let meilleur = null;
  let meilleurScore = 0;
  let raisonnement = '';
  for (const lv of candidats) {
    const dist = distanceKm(lv.latitude, lv.longitude, Number(l.origineLat || 0), Number(l.origineLng || 0));
    const scoreProximite = normaliser(5 - dist, 0, 5);
    const scoreNote = Number(lv.noteMoyenne || 0) / 5;
    const scoreCmdNorm = scoreCmd / 5;
    const scoreDelai = Number(lv.tauxRespectDelai == null ? 100 : lv.tauxRespectDelai) / 100;
    const scoreExp = normaliser(Number(lv.nombreLivraisons || 0), 0, 200);
    const bonusVehicule = l.typeLivraison === 'glace' && lv.typeVehicule === 'tricycle' ? 0.15 : 0;
    const score = scoreProximite * 0.35 + scoreNote * 0.25 + scoreCmdNorm * 0.15 + scoreDelai * 0.2 + scoreExp * 0.1 + bonusVehicule;
    const r = `Livreur ${lv.nom || lv.id}: proximité=${dist.toFixed(1)}km, note=${lv.noteMoyenne || 0}/5, scoreCommande=${scoreCmd.toFixed(1)}, délais=${lv.tauxRespectDelai ?? 100}%, score=${(score * 100).toFixed(0)}%`;
    if (score > meilleurScore) {
      meilleurScore = score;
      meilleur = lv;
      raisonnement = r;
    }
  }
  return { livreur: meilleur, score: meilleurScore, raisonnement };
}

async function assigner(livraisonRef, l, livreur, decision, niveau) {
  const batch = db().batch();
  batch.update(livraisonRef, {
    livreurId: livreur.id,
    statut: 'livreurAssigne',
    dateAssignation: new Date(),
    decisionAgent: decision,
    niveauAutonomie: niveau,
    assigneParServeur: true,
  });
  batch.set(db().collection('livreurs').doc(livreur.id), { statut: 'enCourse' }, { merge: true });
  if (l.commandeId) batch.set(db().collection('sous_commandes').doc(l.commandeId), { livreurId: livreur.id }, { merge: true });
  await batch.commit();
  const uid = livreur.utilisateurId || livreur.id;
  await db().collection('notifications').add({
    destinataireId: uid,
    ...textes('nouvelleCourse', 'courseAssignee', l.origineAdresse || l.origineNom || '', l.destinationAdresse || l.destinationQuartier || ''),
    route: '/mes-livraisons',
    refId: livraisonRef.id,
    lue: false,
    date: FieldValue.serverTimestamp(),
    origine: 'serveur',
  });
  if (l.clientId) {
    await db().collection('notifications').add({
      destinataireId: l.clientId,
      ...textes('livreurTrouve', 'livreurEnRoute'),
      route: '/commandes',
      refId: l.commandeId || null,
      lue: false,
      date: FieldValue.serverTimestamp(),
      origine: 'serveur',
    });
  }
}

/** Point d'entrée : traite une livraison nouvellement créée (statut enAttente). */
async function traiterNouvelleLivraison(livraisonRef, l) {
  try {
    if (l.livreurId) return; // déjà assignée (ex. assignation manuelle)
    await livraisonRef.update({ statut: 'rechercheLibreur' });
    let candidats = await trouverCandidats(l);
    // dérogation admin : `autoriseJusquau` dans le futur garde un livreur non dispo
    const now = Date.now();
    candidats = candidats.filter((c) => {
      if (c.statut === 'disponible' || c.statut == null) return true;
      const derog = c.autoriseJusquau && c.autoriseJusquau.toMillis ? c.autoriseJusquau.toMillis() : null;
      return derog != null && derog > now;
    });
    const p = (await db().collection('app_config').doc('parametres').get()).data() || {};
    const plafond = Number(p.plafondCashLivreur == null ? 25000 : p.plafondCashLivreur);
    if (plafond > 0 && l.methodePaiementChoisi === 'cash') {
      candidats = candidats.filter((c) => Number(c.encoursCash || 0) < plafond);
    }
    if (!candidats.length) {
      await escalader(livraisonRef.id, `Aucun livreur disponible dans le secteur ${l.destinationQuartier || ''}`, 'urgent');
      return;
    }
    const sCmd = await scoreCommande(l.commandeId);
    const { livreur, score, raisonnement } = scorer(candidats, l, sCmd);
    const decision = { livreurId: livreur.id, raisonnement, scoreConfiance: score, timestamp: new Date(), valideeParHumain: false };
    if (score >= SEUIL_AUTONOMIE_TOTALE) {
      await assigner(livraisonRef, l, livreur, decision, 'auto');
      await db().collection('logs_agent').add({ type: 'decision_autonome', livraisonId: livraisonRef.id, decision, dateCreation: new Date(), message: `✅ Assignation autonome : ${raisonnement}`, origine: 'serveur' });
    } else if (score >= SEUIL_SUPERVISION) {
      await db().collection('alertes_agent').add({
        type: 'proposition_assignation',
        livraisonId: livraisonRef.id,
        decisionProposee: decision,
        niveau: 'aValider',
        statut: 'en_attente',
        dateCreation: new Date(),
        message: `⏳ Validation requise : ${raisonnement}`,
        origine: 'serveur',
      });
      await prevenirSuperviseurs('Proposition à valider — un livreur attend votre feu vert.');
      await livraisonRef.update({ statut: 'rechercheLibreur', decisionAgent: decision, niveauAutonomie: 'supervised' });
    } else {
      await escalader(livraisonRef.id, `Score de confiance insuffisant (${score.toFixed(2)}). Candidats : ${candidats.length}. ${raisonnement}`, 'aValider');
    }
  } catch (e) {
    logger.error('assignation', { id: livraisonRef.id, e: String(e) });
    await escalader(livraisonRef.id, `Erreur technique agent : ${e}`, 'urgent');
  }
}

module.exports = { traiterNouvelleLivraison, distanceKm, scorer, normaliser };
