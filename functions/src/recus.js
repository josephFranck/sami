'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// REÇUS SIGNÉS — port de lib/services/recu_service.dart, clé côté serveur.
//
// Canonique (IDENTIQUE à Dart jsonEncode d'une Map triée par clé) :
//   {"beneficiaireId":"…","beneficiaireNom":"…","contrepartie":"SAMI",
//    "dateISO":"…","detail":"…","montant":12000.0,"numero":"…","refId":"…","type":"vente"}
//   — montant : un double Dart s'encode « 12000.0 » (entier → suffixe .0)
// Signature : HMAC-SHA256(utf8(cle), canonique) en hex complet.
//
// En mode serveur, la règle `app_config/recus` interdit la lecture de la clé
// à l'app : un reçu ne peut plus être forgé avec une app décompilée.
// ═══════════════════════════════════════════════════════════════════════════
const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const REGION = 'europe-west1';

async function cleRecus() {
  const ref = db().collection('app_config').doc('recus');
  const d = await ref.get();
  const data = d.data() || {};
  let cle = data.cle;
  if (!cle) {
    cle = crypto.randomBytes(32).toString('base64');
    await ref.set({ cle, serveur: true }, { merge: true });
  } else if (data.serveur !== true) {
    // clé créée autrefois par l'app : on la garde (anciens reçus restent
    // vérifiables) mais plus personne ne la lit côté client (règle)
    await ref.set({ serveur: true }, { merge: true });
  }
  return cle;
}

function encoderValeur(v) {
  if (typeof v === 'number') {
    // Dart : double → « 12000.0 » si entier, sinon représentation courte
    return Number.isInteger(v) ? v.toFixed(1) : String(v);
  }
  return JSON.stringify(v);
}

/** JSON canonique, clés triées, sans espace — compatible Dart. */
function canonique(corps) {
  const cles = Object.keys(corps).sort();
  return '{' + cles.map((k) => JSON.stringify(k) + ':' + encoderValeur(corps[k])).join(',') + '}';
}

function signer(contenu, cle) {
  return crypto.createHmac('sha256', Buffer.from(cle, 'utf8')).update(contenu, 'utf8').digest('hex');
}

/** Crée (ou retourne) le reçu d'une référence. Idempotent (type, refId, beneficiaireId). */
async function creerRecu({ type, refId, beneficiaireId, beneficiaireNom, montant, detail, contrepartie }) {
  if (!beneficiaireId) return null;
  const exist = await db().collection('recus').where('refId', '==', refId).where('beneficiaireId', '==', beneficiaireId).where('type', '==', type).limit(1).get();
  if (!exist.empty) return { id: exist.docs[0].id, ...exist.docs[0].data() };
  const now = new Date();
  const numero = `SAMI-${now.getFullYear()}-${String(refId).substring(0, 6).toUpperCase()}${String(now.getTime()).substring(8)}`;
  const corps = {
    numero,
    type,
    refId,
    beneficiaireId,
    beneficiaireNom: beneficiaireNom || '',
    contrepartie: contrepartie || 'SAMI',
    montant: Number(montant || 0),
    detail: detail || '',
    dateISO: now.toISOString(),
  };
  const signature = signer(canonique(corps), await cleRecus());
  const data = { ...corps, signature, date: FieldValue.serverTimestamp(), origine: 'serveur' };
  const ref = await db().collection('recus').add(data);
  return { id: ref.id, ...data };
}

/** Callable : l'app demande un reçu (couture livrée, reversement) — contrôle d'accès minimal. */
exports.creerRecuCallable = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Connexion requise');
  const d = req.data || {};
  if (!d.type || !d.refId || !d.beneficiaireId) throw new HttpsError('invalid-argument', 'type, refId, beneficiaireId requis');
  // Un utilisateur ne crée que SON reçu ; le staff peut en créer pour un tiers
  if (d.beneficiaireId !== uid) {
    const u = await db().collection('utilisateurs').doc(uid).get();
    const ud = u.data() || {};
    const staff = ['admin', 'superadmin'].includes(ud.role) || (Array.isArray(ud.permissions) && ud.permissions.includes('reversements'));
    if (!staff) throw new HttpsError('permission-denied', 'Reçu pour un tiers : staff uniquement');
  }
  const r = await creerRecu(d);
  return r || {};
});

/** Callable : vérifie un QR de reçu scanné ({c: canonique, s: signature} en base64). */
exports.verifierRecu = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Connexion requise');
  const { qr } = req.data || {};
  if (!qr) throw new HttpsError('invalid-argument', 'qr requis');
  try {
    const m = JSON.parse(Buffer.from(String(qr), 'base64').toString('utf8'));
    const ok = signer(String(m.c || ''), await cleRecus()) === String(m.s || '');
    return { valide: ok, contenu: ok ? JSON.parse(m.c) : null };
  } catch (_) {
    return { valide: false, contenu: null };
  }
});

module.exports.creerRecu = creerRecu;
module.exports.canonique = canonique;
module.exports.signer = signer;
