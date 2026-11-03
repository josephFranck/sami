'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// CONNEXION TELEGRAM / WHATSAPP → jeton personnalisé Firebase
// (décision du 03/11/2026 : « téléphone + email, et WhatsApp, Facebook,
//  Telegram ou autre »). Téléphone (SMS) et Facebook sont des fournisseurs
// natifs Firebase (console → Authentication → Sign-in method) ; Telegram et
// WhatsApp ne le sont pas : le serveur vérifie l'identité puis délivre un
// jeton personnalisé que l'app échange (signInWithCustomToken).
//
// Secrets (Google Cloud → Secret Manager, mêmes noms) :
//   TELEGRAM_BOT_TOKEN  — jeton du bot (BotFather) ; domaine du widget : /setdomain
//   WHATSAPP_TOKEN      — jeton permanent de l'app Meta (WhatsApp Business)
//   WHATSAPP_PHONE_ID   — identifiant du numéro expéditeur (Cloud API)
//   WHATSAPP_TEMPLATE   — nom du modèle « authentication » approuvé (défaut sami_code)
// ═══════════════════════════════════════════════════════════════════════════
const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions/v2');
const admin = require('firebase-admin');

const REGION = 'europe-west1';
const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const TELEGRAM_BOT_TOKEN = defineSecret('TELEGRAM_BOT_TOKEN');
const WHATSAPP_TOKEN = defineSecret('WHATSAPP_TOKEN');
const WHATSAPP_PHONE_ID = defineSecret('WHATSAPP_PHONE_ID');

/** Crée (ou complète) le compte Firebase + le doc utilisateurs pour un uid social. */
async function compteSocial(uid, { nom, prenom, telephone, photo, fournisseur, identifiant }) {
  try {
    await admin.auth().getUser(uid);
  } catch (_) {
    await admin.auth().createUser({ uid, displayName: `${prenom || ''} ${nom || ''}`.trim() || undefined, phoneNumber: telephone || undefined, photoURL: photo || undefined }).catch(async (e) => {
      // phoneNumber déjà pris par un autre compte → on crée sans
      if (String(e.code) === 'auth/phone-number-already-exists') {
        await admin.auth().createUser({ uid, displayName: `${prenom || ''} ${nom || ''}`.trim() || undefined });
      } else throw e;
    });
  }
  const ref = db().collection('utilisateurs').doc(uid);
  const doc = await ref.get();
  if (!doc.exists) {
    await ref.set({
      id: uid,
      nom: nom || '',
      prenom: prenom || '',
      telephone: telephone || '',
      email: '',
      image: photo || '',
      role: 'client',
      roles: ['client'],
      creditBalance: 0,
      pointsFidelite: 0,
      niveau: 1,
      favoris: [],
      fournisseurConnexion: fournisseur,
      identifiantSocial: identifiant,
      dateInscription: FieldValue.serverTimestamp(),
      // CGU : l'app affiche l'écran d'acceptation si cguVersion est absent
    });
  } else {
    await ref.set({ fournisseurConnexion: fournisseur, identifiantSocial: identifiant, derniereConnexion: FieldValue.serverTimestamp() }, { merge: true });
  }
}

// ── TELEGRAM (Login Widget) ─────────────────────────────────────────────────
// L'app ouvre une page (domaine déclaré auprès de BotFather) portant le
// widget ; Telegram renvoie {id, first_name, last_name, username, photo_url,
// auth_date, hash}. Vérification : hash == HMAC_SHA256(data_check_string,
// SHA256(bot_token)) — https://core.telegram.org/widgets/login#checking-authorization
exports.authTelegram = onCall({ region: REGION, secrets: [TELEGRAM_BOT_TOKEN], enforceAppCheck: false }, async (req) => {
  const d = req.data || {};
  const champs = ['id', 'first_name', 'last_name', 'username', 'photo_url', 'auth_date'];
  if (!d.id || !d.hash || !d.auth_date) throw new HttpsError('invalid-argument', 'Données Telegram incomplètes');
  const token = TELEGRAM_BOT_TOKEN.value();
  if (!token) throw new HttpsError('failed-precondition', 'TELEGRAM_BOT_TOKEN non configuré');
  const dataCheck = champs.filter((k) => d[k] != null && d[k] !== '').sort().map((k) => `${k}=${d[k]}`).join('\n');
  const secret = crypto.createHash('sha256').update(token).digest();
  const attendu = crypto.createHmac('sha256', secret).update(dataCheck).digest('hex');
  if (!crypto.timingSafeEqual(Buffer.from(attendu), Buffer.from(String(d.hash)))) {
    throw new HttpsError('permission-denied', 'Signature Telegram invalide');
  }
  if (Date.now() / 1000 - Number(d.auth_date) > 300) throw new HttpsError('deadline-exceeded', 'Connexion Telegram expirée, recommencez');
  const uid = `tg_${d.id}`;
  await compteSocial(uid, { nom: d.last_name, prenom: d.first_name, photo: d.photo_url, fournisseur: 'telegram', identifiant: String(d.id) });
  const jeton = await admin.auth().createCustomToken(uid, { fournisseur: 'telegram' });
  return { token: jeton, uid };
});

// ── WHATSAPP (code à usage unique envoyé via l'API Cloud de Meta) ──────────
async function envoyerWhatsapp(phoneId, token, telephone, code) {
  const template = process.env.WHATSAPP_TEMPLATE || 'sami_code';
  const res = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: telephone.replace(/[^0-9]/g, ''),
      type: 'template',
      template: {
        name: template,
        language: { code: 'fr' },
        components: [
          { type: 'body', parameters: [{ type: 'text', text: code }] },
          { type: 'button', sub_type: 'url', index: '0', parameters: [{ type: 'text', text: code }] },
        ],
      },
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    logger.error('whatsapp envoi', { status: res.status, txt });
    throw new HttpsError('unavailable', 'Envoi WhatsApp impossible');
  }
}

/** Étape 1 : {telephone: '+2376XXXXXXXX'} → code envoyé par WhatsApp (valide 5 min). */
exports.authWhatsappEnvoyer = onCall({ region: REGION, secrets: [WHATSAPP_TOKEN, WHATSAPP_PHONE_ID], enforceAppCheck: false }, async (req) => {
  const tel = String((req.data || {}).telephone || '').replace(/\s/g, '');
  if (!/^\+237[26]\d{8}$/.test(tel)) throw new HttpsError('invalid-argument', 'Numéro camerounais attendu (+2376XXXXXXXX)');
  const token = WHATSAPP_TOKEN.value();
  const phoneId = WHATSAPP_PHONE_ID.value();
  if (!token || !phoneId) throw new HttpsError('failed-precondition', 'WhatsApp non configuré');
  // anti-abus : 1 envoi / minute et par numéro
  const ref = db().collection('otp_whatsapp').doc(tel);
  const prev = await ref.get();
  const envoyeLe = prev.exists && prev.data().envoyeLe ? prev.data().envoyeLe.toMillis() : 0;
  if (Date.now() - envoyeLe < 60_000) throw new HttpsError('resource-exhausted', 'Patientez une minute avant un nouvel envoi');
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  await envoyerWhatsapp(phoneId, token, tel, code);
  await ref.set({
    codeHash: crypto.createHash('sha256').update(`${tel}:${code}`).digest('hex'),
    envoyeLe: FieldValue.serverTimestamp(),
    expireLe: Date.now() + 5 * 60_000,
    essais: 0,
  });
  return { ok: true };
});

/** Étape 2 : {telephone, code} → jeton personnalisé. */
exports.authWhatsappVerifier = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const tel = String((req.data || {}).telephone || '').replace(/\s/g, '');
  const code = String((req.data || {}).code || '').trim();
  if (!/^\+237[26]\d{8}$/.test(tel) || !/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument', 'Numéro ou code invalide');
  const ref = db().collection('otp_whatsapp').doc(tel);
  const doc = await ref.get();
  if (!doc.exists) throw new HttpsError('not-found', 'Aucun code envoyé à ce numéro');
  const d = doc.data();
  if (Date.now() > Number(d.expireLe || 0)) throw new HttpsError('deadline-exceeded', 'Code expiré');
  if (Number(d.essais || 0) >= 5) throw new HttpsError('resource-exhausted', 'Trop de tentatives — redemandez un code');
  const hash = crypto.createHash('sha256').update(`${tel}:${code}`).digest('hex');
  if (hash !== d.codeHash) {
    await ref.update({ essais: FieldValue.increment(1) });
    throw new HttpsError('permission-denied', 'Code incorrect');
  }
  await ref.delete();
  // Un compte téléphone Firebase existant (connexion SMS) est réutilisé ;
  // sinon un uid dédié `wa_<numéro>`.
  let uid;
  try {
    uid = (await admin.auth().getUserByPhoneNumber(tel)).uid;
  } catch (_) {
    uid = `wa_${tel.replace('+', '')}`;
  }
  await compteSocial(uid, { telephone: tel, fournisseur: 'whatsapp', identifiant: tel });
  const jeton = await admin.auth().createCustomToken(uid, { fournisseur: 'whatsapp' });
  return { token: jeton, uid };
});
