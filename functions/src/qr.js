'use strict';
// ═══════════════════════════════════════════════════════════════════════════
// QR / CODES COURTS — strictement compatible avec lib/services/qr_crypto_service.dart
//
//   clé        : 32 octets aléatoires, base64url AVEC padding (Dart base64Url)
//   payload    : `${livraisonId}:${type}:${timestamp}:${expiration}`  type ∈ depart|arrivee
//   signature  : HMAC-SHA256(cléOctets, payload) en hex, 32 premiers caractères
//   token QR   : base64url(`${livraisonId}|D|A?|${timestamp}|${expiration}|${signature}`)
//   code court : HMAC(`${livraisonId}|CODE_COURT`) → parseInt(hex[0..6],16) % 1e6, 6 chiffres
// ═══════════════════════════════════════════════════════════════════════════
const crypto = require('crypto');

const VALIDITE_S = 48 * 3600;

function b64urlPad(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_');
}
function b64urlDecode(str) {
  const s = String(str).replace(/-/g, '+').replace(/_/g, '/');
  return Buffer.from(s, 'base64');
}

function genererCle() {
  return b64urlPad(crypto.randomBytes(32));
}

function hmacHex32(cle, payload) {
  return crypto.createHmac('sha256', b64urlDecode(cle)).update(payload, 'utf8').digest('hex').substring(0, 32);
}

function payloadToken(livraisonId, type, timestamp, expiration) {
  return `${livraisonId}:${type}:${timestamp}:${expiration}`;
}

function genererToken(livraisonId, type, cle, maintenantS = Math.floor(Date.now() / 1000)) {
  const expiration = maintenantS + VALIDITE_S;
  const signature = hmacHex32(cle, payloadToken(livraisonId, type, maintenantS, expiration));
  const brut = [livraisonId, type === 'depart' ? 'D' : 'A', String(maintenantS), String(expiration), signature].join('|');
  return { livraisonId, type, timestamp: maintenantS, expiration, signature, encode: b64urlPad(Buffer.from(brut, 'utf8')) };
}

function decoderToken(encode) {
  let brut;
  try {
    brut = b64urlDecode(encode).toString('utf8');
  } catch (_) {
    return null;
  }
  const p = brut.split('|');
  if (p.length !== 5) return null;
  const timestamp = Number(p[2]);
  const expiration = Number(p[3]);
  if (!Number.isFinite(timestamp) || !Number.isFinite(expiration)) return null;
  return { livraisonId: p[0], type: p[1] === 'D' ? 'depart' : 'arrivee', timestamp, expiration, signature: p[4] };
}

function comparaisonSecurisee(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

/** Vérifie un token scanné pour une livraison donnée. Retourne {ok, raison}. */
function verifierToken(encode, cle, livraisonIdAttendu, typeAttendu, maintenantS = Math.floor(Date.now() / 1000)) {
  const t = decoderToken(encode);
  if (!t) return { ok: false, raison: 'formatInvalide' };
  if (t.livraisonId !== livraisonIdAttendu) return { ok: false, raison: 'mauvaiseLivraison' };
  if (t.type !== typeAttendu) return { ok: false, raison: 'mauvaisType' };
  if (maintenantS > t.expiration) return { ok: false, raison: 'expire' };
  const attendu = hmacHex32(cle, payloadToken(t.livraisonId, t.type, t.timestamp, t.expiration));
  if (!comparaisonSecurisee(t.signature, attendu)) return { ok: false, raison: 'signatureInvalide' };
  return { ok: true, token: t };
}

function codeCourt(livraisonId, cle) {
  const h = hmacHex32(cle, `${livraisonId}|CODE_COURT`);
  const n = parseInt(h.substring(0, 6), 16) % 1000000;
  return String(n).padStart(6, '0');
}

function verifierCodeCourt(livraisonId, cle, saisi) {
  return comparaisonSecurisee(String(saisi).trim(), codeCourt(livraisonId, cle));
}

module.exports = { genererCle, genererToken, decoderToken, verifierToken, codeCourt, verifierCodeCourt, hmacHex32, VALIDITE_S };
