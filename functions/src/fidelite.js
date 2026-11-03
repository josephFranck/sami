'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// FIDÉLITÉ + PARRAINAGE côté serveur — port de FideliteService.reclamerPoints
// et ParrainageService.reclamerSiPremiereLivraison (mêmes documents, mêmes
// ids déterministes : l'app et le serveur peuvent coexister sans doublon).
// ═══════════════════════════════════════════════════════════════════════════
const admin = require('firebase-admin');
const { logger } = require('firebase-functions/v2');
const { textes } = require('./i18n');

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const PALIERS_DEFAUT = [
  { nom: 'Découvreur', emoji: '🌱', pointsRequis: 0, reductionLivraison: 0, cashback: 0 },
  { nom: 'Habitué', emoji: '⭐', pointsRequis: 500, reductionLivraison: 10, cashback: 1 },
  { nom: 'Connaisseur', emoji: '🏆', pointsRequis: 2000, reductionLivraison: 25, cashback: 2 },
  { nom: 'Expert', emoji: '💎', pointsRequis: 5000, reductionLivraison: 50, cashback: 3 },
  { nom: 'Ambassadeur', emoji: '👑', pointsRequis: 10000, reductionLivraison: 100, cashback: 5 },
];

const arrondirAu50 = (v) => Math.round(v / 50) * 50;

async function configMarketing() {
  const d = await db().collection('config_marketing').doc('parametres').get();
  const m = d.data() || {};
  const paliers = Array.isArray(m.paliers) && m.paliers.length ? m.paliers : PALIERS_DEFAUT;
  return { fcfaParPoint: Number(m.fcfaParPoint || 100) || 100, paliers };
}

function palierPour(paliers, points) {
  let p = paliers[0];
  for (const x of paliers) if (points >= Number(x.pointsRequis || 0)) p = x;
  return p;
}

/** Crédite les points d'UNE sous-commande livrée (idempotent via fideliteCreditee). */
async function crediterFidelite(scRef, clientId, totalClient) {
  if (!clientId) return;
  try {
    const c = await configMarketing();
    const gagnes = Math.floor(totalClient / c.fcfaParPoint);
    const userRef = db().collection('utilisateurs').doc(clientId);
    let cashback = 0;
    const ok = await db().runTransaction(async (tx) => {
      const sc = await tx.get(scRef);
      if ((sc.data() || {}).fideliteCreditee === true) return false;
      const u = await tx.get(userRef);
      const actuels = Number((u.data() || {}).pointsFidelite || 0);
      const nouveaux = actuels + gagnes;
      const palier = palierPour(c.paliers, nouveaux);
      cashback = arrondirAu50((totalClient * Number(palier.cashback || 0)) / 100);
      tx.update(scRef, { fideliteCreditee: true, pointsFidelite: gagnes });
      tx.set(userRef, { pointsFidelite: nouveaux, niveau: c.paliers.indexOf(palier) + 1 }, { merge: true });
      return true;
    });
    if (ok && cashback > 0) {
      await db().collection('remboursements_a_faire').doc(`CASHBACK_${scRef.id}`).create({
        clientId,
        montant: cashback,
        type: 'cashback',
        sousCommandeId: scRef.id,
        refPaiement: `CASHBACK_${scRef.id}`,
        statut: 'a_traiter',
        dateCreation: FieldValue.serverTimestamp(),
        origine: 'serveur',
      }).catch(() => {});
    }
  } catch (e) {
    logger.warn('fidélité', { clientId, e: String(e) });
  }
}

/** Première livraison d'un filleul : lien valide + primes en file staff. */
async function validerParrainage(clientId, sousCommandeId) {
  if (!clientId) return;
  try {
    const p = (await db().collection('app_config').doc('parametres').get()).data() || {};
    if (p.parrainageActif !== true) return;
    const q = await db().collection('parrainages').where('filleulId', '==', clientId).where('statut', '==', 'enAttente').limit(1).get();
    if (q.empty) return;
    const d = q.docs[0];
    const lien = d.data() || {};
    await d.ref.update({ statut: 'valide', valideLe: FieldValue.serverTimestamp(), premiereLivraisonId: sousCommandeId, valideParServeur: true });
    const primes = [
      ['parrain', lien.parrainId, Number(lien.recompenseParrain || 0), 'parrainageReussi'],
      ['filleul', clientId, Number(lien.recompenseFilleul || 0), 'bienvenueRecompensee'],
    ];
    for (const [suffixe, qui, montant, cleTitre] of primes) {
      if (!qui || montant <= 0) continue;
      try {
        await db().collection('remboursements_a_faire').doc(`PARRAINAGE_${d.id}_${suffixe}`).create({
          clientId: qui,
          montant,
          type: 'parrainage',
          parrainageId: d.id,
          refPaiement: `PARRAINAGE_${d.id}`,
          statut: 'a_traiter',
          dateCreation: FieldValue.serverTimestamp(),
          origine: 'serveur',
        });
      } catch (_) {
        continue; // déjà créée (replay)
      }
      await db().collection('notifications').add({
        destinataireId: qui,
        ...textes(cleTitre, 'avoirArrive', Math.round(montant)),
        route: '/moncompte',
        lue: false,
        date: FieldValue.serverTimestamp(),
        origine: 'serveur',
      });
    }
  } catch (e) {
    logger.warn('parrainage', { clientId, e: String(e) });
  }
}

module.exports = { crediterFidelite, validerParrainage, palierPour, PALIERS_DEFAUT };
