// ═══════════════════════════════════════════════════════════════════════
// WORKER CLOUDFLARE R2 — PagneShop
// Compatible avec StockageService._uploadBytesCloudflare (l'app Flutter).
// À coller tel quel dans un Worker, avec un binding R2 nommé "BUCKET".
// ═══════════════════════════════════════════════════════════════════════
export default {
  async fetch(request, env) {
    // ═══ AUTH : jeton Firebase de l'utilisateur (aucun secret partagé) ═══
    // L'app envoie `Authorization: Bearer <ID token Firebase>`. On vérifie
    // la signature RS256 contre les clés publiques Google, l'audience
    // (= FIREBASE_PROJECT_ID) et l'expiration. Repli : AUTH_TOKEN si défini
    // (compatibilité des déploiements existants) — à retirer ensuite.
    const auth = request.headers.get('Authorization') || '';
    const jeton = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    let autorise = false;
    if (env.AUTH_TOKEN && jeton === env.AUTH_TOKEN) {
      autorise = true;
    } else if (jeton && env.FIREBASE_PROJECT_ID) {
      autorise = await verifierJetonFirebase(jeton, env.FIREBASE_PROJECT_ID);
    }
    if (!autorise) return new Response('Non autorisé', { status: 401 });
    const url = new URL(request.url);

    // ── UPLOAD : POST /upload?file=<chemin> (corps = octets de l'image)
    if (request.method === 'POST' && url.pathname === '/upload') {
      const chemin = url.searchParams.get('file') ||
                     request.headers.get('X-Filename');
      if (!chemin) return new Response('chemin manquant', { status: 400 });
      const contentType =
        request.headers.get('Content-Type') || 'application/octet-stream';
      await env.BUCKET.put(chemin, request.body, {
        httpMetadata: {
          contentType,
          // CDN : l'image est immuable → cache 1 an au edge Cloudflare
          // (affichages instantanés, moins d'opérations R2 facturées)
          cacheControl: 'public, max-age=31536000, immutable',
        },
      });
      return Response.json({ url: chemin });
    }

    // ── DELETE : DELETE /delete?file=<chemin>
    if (request.method === 'DELETE' && url.pathname === '/delete') {
      const chemin = url.searchParams.get('file');
      if (!chemin) return new Response('chemin manquant', { status: 400 });
      await env.BUCKET.delete(chemin);
      return Response.json({ ok: true });
    }

    return new Response('PagneShop R2 Worker', { status: 200 });
  },
};


// ═══════════════════════════════════════════════════════════════════════
// Vérification d'un ID token Firebase (RS256) — Web Crypto, sans lib.
// Clés publiques : https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com
// Doc : https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
// ═══════════════════════════════════════════════════════════════════════
const CERTS_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
let _certsCache = { exp: 0, certs: null };

function b64urlToBytes(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function chargerCerts() {
  if (_certsCache.certs && Date.now() < _certsCache.exp) return _certsCache.certs;
  const res = await fetch(CERTS_URL, { cf: { cacheTtl: 3600 } });
  if (!res.ok) throw new Error('certs');
  const certs = await res.json();
  const cc = res.headers.get('cache-control') || '';
  const m = /max-age=(\d+)/.exec(cc);
  _certsCache = { certs, exp: Date.now() + (m ? +m[1] : 3600) * 1000 };
  return certs;
}

async function cleDepuisCertPem(pem) {
  // x509 PEM → SubjectPublicKeyInfo : on extrait la clé via WebCrypto en
  // important le certificat DER n'est pas supporté ; on parse donc le PEM
  // pour en sortir le bloc SPKI (RSA) de façon minimale.
  const der = b64urlToBytes(
    pem.replace(/-----BEGIN CERTIFICATE-----/, '')
       .replace(/-----END CERTIFICATE-----/, '')
       .replace(/\s+/g, '')
       .replace(/\+/g, '-').replace(/\//g, '_'));
  // Recherche de l'OID rsaEncryption (06 09 2A 86 48 86 F7 0D 01 01 01)
  const oid = [0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01];
  let idx = -1;
  for (let i = 0; i < der.length - oid.length; i++) {
    let ok = true;
    for (let j = 0; j < oid.length; j++) if (der[i+j] !== oid[j]) { ok = false; break; }
    if (ok) { idx = i; break; }
  }
  if (idx < 0) throw new Error('spki');
  // Le SPKI commence à la SEQUENCE qui englobe l'AlgorithmIdentifier :
  // on remonte de 4 octets (30 len 30 len) pour trouver son début.
  let start = idx - 4;
  while (start > 0 && der[start] !== 0x30) start--;
  // longueur de la SEQUENCE SPKI (forme longue 0x82 xx xx)
  let lenPos = start + 1, len = der[lenPos], hdr = 2;
  if (len & 0x80) { const n = len & 0x7f; len = 0; for (let k = 1; k <= n; k++) len = (len << 8) | der[lenPos+k]; hdr = 1 + n + 1; }
  const spki = der.slice(start, start + hdr + len);
  return crypto.subtle.importKey('spki', spki,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}

async function verifierJetonFirebase(jeton, projectId) {
  try {
    const [h, p, sig] = jeton.split('.');
    if (!h || !p || !sig) return false;
    const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(h)));
    const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(p)));
    if (header.alg !== 'RS256' || !header.kid) return false;
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp <= now || payload.iat > now + 60) return false;
    if (payload.aud !== projectId) return false;
    if (payload.iss !== `https://securetoken.google.com/${projectId}`) return false;
    if (!payload.sub) return false;
    const certs = await chargerCerts();
    const pem = certs[header.kid];
    if (!pem) return false;
    const key = await cleDepuisCertPem(pem);
    const data = new TextEncoder().encode(`${h}.${p}`);
    return await crypto.subtle.verify(
      { name: 'RSASSA-PKCS1-v1_5' }, key, b64urlToBytes(sig), data);
  } catch (_) {
    return false;
  }
}
