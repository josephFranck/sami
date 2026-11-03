'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// LIVRAISONS — validation des scans CÔTÉ SERVEUR (décision du 03/11/2026 :
// « réseau acceptable au scan → vérification serveur »).
//
//   onLivraisonCreee : la clé HMAC naît ICI et n'en sort jamais. Les tokens à
//                      AFFICHER vont dans qr_depart/{id} (gérant de la boutique)
//                      et qr_arrivee/{id} (client). Le livreur ne détient rien.
//   validerScan      : le livreur envoie le code scanné (ou le code court) ;
//                      le serveur vérifie puis fait TOUTE la propagation (port
//                      de LivraisonService.validerRecuperationQR /
//                      validerLivraisonQR / _synchroniserCommande, fidélité,
//                      parrainage, reçu, alertes, encours cash).
//   ajouterSignature : preuve COMPLÉMENTAIRE après remise (jamais une clôture).
//
// Mode legacy : tant que app_config/parametres.scansServeur != true, l'app
// garde son ancien flux (clé partagée) ; la fonction ne touche pas aux
// livraisons qui portent déjà des codes générés côté app.
// ═══════════════════════════════════════════════════════════════════════════
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const qr = require('./qr');
const { textes } = require('./i18n');
const { creerRecu } = require('./recus');
const { crediterFidelite, validerParrainage } = require('./fidelite');
const { traiterNouvelleLivraison } = require('./assignation');

const REGION = 'europe-west1';
const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

// ── Paramètres (app_config/parametres), cache 60 s ─────────────────────────
let _params = null;
let _paramsLe = 0;
async function parametres() {
  if (_params && Date.now() - _paramsLe < 60_000) return _params;
  const d = await db().collection('app_config').doc('parametres').get();
  _params = d.data() || {};
  _paramsLe = Date.now();
  return _params;
}

async function estStaff(uid, permission) {
  if (!uid) return false;
  const u = await db().collection('utilisateurs').doc(uid).get();
  const d = u.data() || {};
  if (['admin', 'superadmin'].includes(d.role)) return true;
  return Array.isArray(d.permissions) && d.permissions.includes(permission);
}

async function notifier(destinataireId, cleTitre, cleMessage, { route, refId, args = [] } = {}) {
  if (!destinataireId) return;
  try {
    await db().collection('notifications').add({
      destinataireId,
      ...textes(cleTitre, cleMessage, ...args),
      route: route || null,
      refId: refId || null,
      lue: false,
      date: FieldValue.serverTimestamp(),
      origine: 'serveur',
    });
  } catch (e) {
    logger.warn('notification non envoyée', { destinataireId, e: String(e) });
  }
}

function distanceMetres(lat1, lng1, lat2, lng2) {
  const r = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. CRÉATION : clé + tokens côté serveur
// ═══════════════════════════════════════════════════════════════════════════
exports.onLivraisonCreee = onDocumentCreated({ document: 'livraisons/{id}', region: REGION }, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const id = event.params.id;
  const l = snap.data() || {};
  const p = await parametres();
  // Mode legacy : l'app a déjà généré ses codes et qr_secrets → on n'interfère pas.
  const legacy = p.scansServeur !== true || (l.qrCode && l.qrCode.codeOrigine);
  if (!legacy) await genererSecrets(snap, id, l);
  else logger.info('livraison créée en mode legacy (clés côté app)', { id });
  // Assignation d'un livreur côté serveur (l'app n'appelle plus son agent)
  if (p.assignationServeur === true && (l.statut === 'enAttente' || !l.statut)) {
    await traiterNouvelleLivraison(snap.ref, l);
  }
});

async function genererSecrets(snap, id, l) {
  const cle = qr.genererCle();
  const depart = qr.genererToken(id, 'depart', cle);
  const arrivee = qr.genererToken(id, 'arrivee', cle);
  const code = qr.codeCourt(id, cle);
  const batch = db().batch();
  batch.set(db().collection('qr_secrets').doc(id), {
    cle,
    expiration: depart.expiration,
    serveur: true, // ← règles : personne ne lit
    creeLe: FieldValue.serverTimestamp(),
  });
  batch.set(db().collection('qr_depart').doc(id), {
    token: depart.encode,
    codeCourt: code,
    expiration: depart.expiration,
    livraisonId: id,
  });
  batch.set(db().collection('qr_arrivee').doc(id), {
    token: arrivee.encode,
    codeCourt: code,
    expiration: arrivee.expiration,
    livraisonId: id,
  });
  batch.set(
    snap.ref,
    {
      qrCode: {
        codeOrigine: '', // jamais de code en clair sur la livraison
        codeDestination: '',
        dateExpiration: Timestamp.fromMillis(depart.expiration * 1000),
        origineScanne: false,
        destinationScanne: false,
        serveur: true,
      },
    },
    { merge: true },
  );
  await batch.commit();
  logger.info('secrets QR générés côté serveur', { id });
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. SCAN : vérification + propagation
// ═══════════════════════════════════════════════════════════════════════════
exports.validerScan = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Connexion requise');
  const { livraisonId, type, code, codeCourt, lat, lng, photoUrl, montantCash } = req.data || {};
  if (!livraisonId || !['depart', 'arrivee'].includes(type)) {
    throw new HttpsError('invalid-argument', 'livraisonId et type (depart|arrivee) requis');
  }
  if (!code && !codeCourt) throw new HttpsError('invalid-argument', 'code ou codeCourt requis');

  const ref = db().collection('livraisons').doc(livraisonId);
  const doc = await ref.get();
  if (!doc.exists) throw new HttpsError('not-found', 'Livraison introuvable');
  const l = doc.data();

  // Qui scanne : le livreur ASSIGNÉ (ou le staff livraisons)
  const staff = await estStaff(uid, 'livraisons');
  if (!staff && l.livreurId !== uid) {
    throw new HttpsError('permission-denied', "Vous n'êtes pas le livreur assigné à cette course");
  }

  // Secret serveur
  const sec = await db().collection('qr_secrets').doc(livraisonId).get();
  const cle = sec.exists ? sec.data().cle : null;
  if (!cle) throw new HttpsError('failed-precondition', 'Secret de livraison absent (livraison créée hors mode serveur ?)');

  // Vérification
  let modeValidation = 'qrCode';
  let aVerifierSecours = false;
  if (code) {
    const v = qr.verifierToken(code, cle, livraisonId, type);
    if (!v.ok) {
      const msg = {
        formatInvalide: 'QR illisible ou corrompu',
        mauvaiseLivraison: 'Ce QR appartient à une autre livraison',
        mauvaisType: type === 'depart' ? 'Utilisez le QR de départ (boutique)' : 'Utilisez le CODE DU CLIENT',
        expire: 'QR expiré — contactez le support',
        signatureInvalide: 'QR invalide — signature incorrecte',
      }[v.raison];
      await journal('scan_refuse', { livraisonId, type, uid, raison: v.raison });
      throw new HttpsError('invalid-argument', msg || 'QR invalide');
    }
  } else {
    if (!qr.verifierCodeCourt(livraisonId, cle, codeCourt)) {
      await journal('scan_refuse', { livraisonId, type, uid, raison: 'codeCourtInvalide' });
      throw new HttpsError('invalid-argument', 'Code incorrect');
    }
    modeValidation = 'codeCourt';
    aVerifierSecours = true; // validation de secours → contrôle conseillé
  }

  // Cohérence d'état (idempotent : rejouer un scan déjà validé ne casse rien)
  const statut = l.statut || '';
  if (type === 'depart') {
    if (['enLivraison', 'articleRecupere', 'livre'].includes(statut)) {
      return { ok: true, deja: true, statut };
    }
    await validerDepart(ref, l, uid, { lat, lng, photoUrl, modeValidation });
    return { ok: true, statut: 'enLivraison' };
  }
  if (statut === 'livre') return { ok: true, deja: true, statut };
  if (!['enLivraison', 'articleRecupere', 'pretRetrait'].includes(statut) && !staff) {
    throw new HttpsError('failed-precondition', `Le colis n'a pas été pris en charge (statut ${statut})`);
  }
  await validerArrivee(ref, l, uid, { lat, lng, photoUrl, montantCash, modeValidation, aVerifierSecours });
  return { ok: true, statut: 'livre' };
});

async function journal(evenement, details) {
  try {
    await db().collection('app_logs').add({ evenement, details, utilisateurId: details.uid || null, origine: 'serveur', date: FieldValue.serverTimestamp() });
  } catch (_) {}
}

// ── DÉPART (boutique → livreur) — port de validerRecuperationQR ────────────
async function validerDepart(ref, l, livreurId, { lat, lng, photoUrl, modeValidation }) {
  const now = new Date();
  await ref.update({
    statut: 'enLivraison',
    dateRecuperation: now,
    preuveRecuperation: {
      mode: modeValidation,
      dateValidation: now,
      valideePar: livreurId,
      photoUrl: photoUrl || null,
      latitudeValidation: lat ?? null,
      longitudeValidation: lng ?? null,
    },
    'qrCode.origineScanne': true,
    'qrCode.dateScannOrigine': now,
    'qrCode.scannePar': livreurId,
    ...(lat != null ? { livreurLatActuelle: lat, livreurLngActuelle: lng } : {}),
    valideParServeur: true,
  });
  // Propagation au boutiquier : « Prête » → « En livraison »
  if (l.commandeId) {
    await db().collection('sous_commandes').doc(l.commandeId).set({ statut: 'enCoursLivraison' }, { merge: true });
  }
  // Le client apprend que son colis voyage
  await notifier(l.clientId, 'colisPrisCharge', 'livreurRecupere', { route: '/commandes', refId: l.commandeId });
  await journal('scan_depart_valide', { livraisonId: ref.id, uid: livreurId, mode: modeValidation });
}

// ── ARRIVÉE (livreur → client) — port de validerLivraisonQR + sync ─────────
async function validerArrivee(ref, l, livreurId, { lat, lng, photoUrl, montantCash, modeValidation, aVerifierSecours }) {
  const now = new Date();
  // Contrôle de cohérence GPS (détection, pas blocage)
  let aVerifier = aVerifierSecours;
  let motifVerif = aVerifierSecours ? 'Validé par code court (secours)' : null;
  if (lat != null && lng != null && l.destinationLat && l.destinationLng) {
    const dist = distanceMetres(lat, lng, l.destinationLat, l.destinationLng);
    if (dist > 500) {
      aVerifier = true;
      motifVerif = `Scan à ${dist.toFixed(0)} m de la destination`;
    }
  } else if (lat == null || lng == null) {
    aVerifier = true;
    motifVerif = motifVerif || 'Aucune position GPS au moment du scan';
  }

  await ref.update({
    statut: 'livre',
    dateLivraison: now,
    preuveLivraison: {
      mode: modeValidation,
      dateValidation: now,
      valideePar: livreurId,
      photoUrl: photoUrl || null,
      latitudeValidation: lat ?? null,
      longitudeValidation: lng ?? null,
    },
    paiementConfirme: true,
    'qrCode.destinationScanne': true,
    'qrCode.dateScannDestination': now,
    aVerifier,
    ...(motifVerif ? { motifVerification: motifVerif } : {}),
    valideParServeur: true,
  });

  const prixClient = Number((l.decompositionFinanciere || {}).prixClient || 0);

  // Sous-commande → livree ; session → touteLivree / partiellementLivree
  let sc = null;
  if (l.commandeId) {
    const scRef = db().collection('sous_commandes').doc(l.commandeId);
    sc = await scRef.get();
    if (sc.exists) {
      await scRef.set({ statut: 'livree', dateLivraison: FieldValue.serverTimestamp() }, { merge: true });
      const sessionId = (sc.data() || {}).sessionId;
      if (sessionId) await synchroniserSession(sessionId);
    }
  }

  // Encours cash du livreur (plafond anti-fraude) + transaction cash
  if (l.methodePaiementChoisi === 'cash' && l.livreurId) {
    await db().collection('livreurs').doc(l.livreurId).set({ encoursCash: FieldValue.increment(prixClient) }, { merge: true });
    await db().collection('transactions').add({
      type: 'paiementCash',
      statut: 'confirmee',
      clientId: l.clientId || null,
      boutiqueId: l.origineId || null,
      livreurId: l.livreurId,
      livraisonId: ref.id,
      commandeId: l.commandeId || null,
      montantBrut: montantCash != null ? Number(montantCash) : prixClient,
      montantNet: montantCash != null ? Number(montantCash) : prixClient,
      decomposition: l.decompositionFinanciere || null,
      methodePaiement: 'cash',
      dateCreation: now,
      dateConfirmation: now,
      devise: 'XAF',
      note: 'Cash encaissé par livreur à la livraison (validé serveur)',
    });
  }

  // Reçu de vente signé pour le client
  await creerRecu({
    type: 'vente',
    refId: ref.id,
    beneficiaireId: l.clientId || '',
    beneficiaireNom: 'Client',
    montant: prixClient,
    detail: `Achat livré - ${l.destinationAdresse || ''}`,
  });

  // Synchronisation commande (couture ou classique), notifications, livreur
  await synchroniserCommande(ref, l, sc);

  // Alertes de l'agent sur cette livraison : closes
  await cloreAlertes(ref.id, 'livraison_validee', livreurId);

  await journal('scan_arrivee_valide', { livraisonId: ref.id, uid: livreurId, mode: modeValidation, aVerifier });
}

async function synchroniserSession(sessionId) {
  try {
    const freres = await db().collection('sous_commandes').where('sessionId', '==', sessionId).get();
    const fini = (st) => ['livree', 'terminee', 'annulee'].includes(st);
    const tous = freres.docs.map((d) => (d.data() || {}).statut || '');
    const statut = tous.every(fini) ? 'touteLivree' : tous.some(fini) ? 'partiellementLivree' : 'enCours';
    await db().collection('sessions_commande').doc(sessionId).set({ statut }, { merge: true });
  } catch (e) {
    logger.warn('sync session', { sessionId, e: String(e) });
  }
}

// Port de LivraisonService._synchroniserCommande (verrou idempotent inclus)
async function synchroniserCommande(ref, l, sc) {
  const dejaFait = await db().runTransaction(async (tx) => {
    const d = await tx.get(ref);
    if ((d.data() || {}).fideliteCreditee === true) return true;
    tx.update(ref, { fideliteCreditee: true });
    return false;
  });
  if (dejaFait) return;
  const commandeCouturierId = l.commandeCouturierId || null;
  const livreurDisponible = async () => {
    if (l.livreurId) await db().collection('livreurs').doc(l.livreurId).set({ statut: 'disponible' }, { merge: true });
  };

  if (sc && sc.exists && commandeCouturierId) {
    // COUTURE trajet 1 : le pagne est à l'atelier (vente livrée pour le
    // boutiquier ; le client n'est pas notifié « livré » ici)
    await sc.ref.update({ statut: 'livree', dateTerminaison: FieldValue.serverTimestamp() });
    await livreurDisponible();
  } else if (sc && sc.exists) {
    await sc.ref.update({ statut: 'livree' });
    // FIDÉLITÉ + PARRAINAGE : écrits ICI (serveur) — l'app ne peut pas écrire
    // sur le doc du client depuis le téléphone du livreur.
    const scData = sc.data() || {};
    await crediterFidelite(sc.ref, scData.clientId || l.clientId, Number(scData.totalClient || 0));
    await validerParrainage(scData.clientId || l.clientId, sc.id);
    await notifier(l.clientId, 'commandeLivree', 'colisArrive', { route: '/commandes', refId: l.commandeId });
    await livreurDisponible();
    return;
  }

  // Couture : trajet 1 (tissu reçu) ou trajet 2 (vêtement livré) ?
  const ccRef = db().collection('commandes_couturier').doc(commandeCouturierId || l.commandeId);
  const cc = await ccRef.get();
  if (!cc.exists) return;
  const d = cc.data() || {};
  if (d.livraisonRetourId === ref.id) {
    await ccRef.update({ statut: 'livree', dateLivraisonReelle: FieldValue.serverTimestamp() });
    await notifier(d.clientId, 'vetementLivre', 'confectionArrivee', { route: '/mes-recus', refId: l.commandeId });
    await livreurDisponible();
  } else if (d.livraisonPagneId === ref.id) {
    await ccRef.update({ statut: 'enConfection' });
    await notifier(d.couturierId, 'tissuRecu', 'pagneArriveAtelier', { route: '/dashboard_couturier', refId: l.commandeId });
  }
}

async function cloreAlertes(livraisonId, resolution, par) {
  try {
    const q = await db().collection('alertes_agent').where('livraisonId', '==', livraisonId).get();
    for (const d of q.docs) {
      if ((d.data() || {}).statut !== 'en_attente') continue;
      await d.ref.update({ statut: 'traitee', resolution, traiteePar: par || null, traiteeLe: FieldValue.serverTimestamp() });
    }
  } catch (e) {
    logger.warn('clôture alertes', { livraisonId, e: String(e) });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. SIGNATURE : preuve complémentaire (jamais une clôture)
// ═══════════════════════════════════════════════════════════════════════════
exports.ajouterSignature = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Connexion requise');
  const { livraisonId, signatureBase64 } = req.data || {};
  if (!livraisonId || !signatureBase64) throw new HttpsError('invalid-argument', 'livraisonId et signatureBase64 requis');
  if (String(signatureBase64).length > 400_000) throw new HttpsError('invalid-argument', 'Signature trop volumineuse');
  const ref = db().collection('livraisons').doc(livraisonId);
  const doc = await ref.get();
  if (!doc.exists) throw new HttpsError('not-found', 'Livraison introuvable');
  const l = doc.data();
  if (l.livreurId !== uid && !(await estStaff(uid, 'livraisons'))) {
    throw new HttpsError('permission-denied', 'Livreur assigné uniquement');
  }
  if (l.statut !== 'livre') {
    // Règle : la signature seule ne clôture pas — le CODE DU CLIENT d'abord.
    throw new HttpsError('failed-precondition', "La signature s'ajoute après la validation par le code du client");
  }
  await ref.update({
    signatureClient: signatureBase64,
    'preuveLivraison.signatureBase64': signatureBase64,
    signatureLe: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

module.exports.cloreAlertes = cloreAlertes;
module.exports.notifier = notifier;
module.exports.parametres = parametres;
module.exports.estStaff = estStaff;
module.exports.REGION = REGION;
