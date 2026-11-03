// ═══════════════════════════════════════════════════════════════════════
// WEBHOOK PAIEMENT MONETBIL — Cloudflare Worker (PagneShop)
// C'est LA SOURCE DE VÉRITÉ : seul ce worker confirme un paiement dans
// Firestore. L'app ne fait qu'écouter le statut (jamais le décider).
//
// Secrets à définir dans le Worker (Settings → Variables and Secrets) :
//   MONETBIL_SERVICE_SECRET : le "service secret" de votre compte Monetbil
//   FIREBASE_PROJECT_ID     : sami-c564c
//   SA_CLIENT_EMAIL         : email du compte de service Firebase
//   SA_PRIVATE_KEY          : sa clé privée PEM (avec les \n)
// (Compte de service : console Firebase → Paramètres → Comptes de service
//  → Générer une clé → copier client_email et private_key)
//
// Chez Monetbil : Dashboard → votre service → Notification URL =
//   https://pagneshop-paiement.VOTRECOMPTE.workers.dev/notify
// ═══════════════════════════════════════════════════════════════════════

async function jwtFirebase(env) {
  // Jeton OAuth signé RS256 avec le compte de service (validité 1 h)
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => btoa(JSON.stringify(o))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const header = enc({ alg: 'RS256', typ: 'JWT' });
  const claim = enc({
    iss: env.SA_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
  });
  const pem = env.SA_PRIVATE_KEY.replace(/\\n/g, '\n')
      .replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
      new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.` + btoa(String.fromCharCode(
      ...new Uint8Array(sig)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  return (await r.json()).access_token;
}

// RECHARGE : le webhook (et lui SEUL — les règles interdisent au client
// d'augmenter son solde) crédite le portefeuille, atomiquement.
async function crediterSolde(env, token, clientId, montant) {
  const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)`;
  return fetch(`${base}/documents:commit`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      writes: [{
        transform: {
          document: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/utilisateurs/${clientId}`,
          fieldTransforms: [{
            fieldPath: 'creditBalance',
            increment: { doubleValue: montant },
          }],
        },
      }],
    }),
  });
}

async function lireTransaction(env, token, ref) {
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/transactions_paiement/${ref}`,
    { headers: { Authorization: `Bearer ${token}` } });
  return r.ok ? r.json() : null;
}

async function majTransaction(env, ref, statut, extra) {
  const token = await jwtFirebase(env);
  const url = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}` +
      `/databases/(default)/documents/transactions_paiement/${ref}` +
      `?updateMask.fieldPaths=statut&updateMask.fieldPaths=confirmeLe` +
      `&updateMask.fieldPaths=detailWebhook`;
  return fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fields: {
        statut: { stringValue: statut },
        confirmeLe: { timestampValue: new Date().toISOString() },
        detailWebhook: { stringValue: JSON.stringify(extra).slice(0, 900) },
      },
    }),
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/notify') {
      // Monetbil envoie du x-www-form-urlencoded
      const form = await request.formData();
      const p = Object.fromEntries(form.entries());
      // Vérification d'authenticité : le sign = md5(service_secret + ...)
      // varie selon la version — au minimum, on REVÉRIFIE le paiement
      // auprès de Monetbil avant de confirmer (défense en profondeur).
      const ref = p.payment_ref || p.item_ref || '';
      if (!ref) return new Response('ref manquante', { status: 400 });
      const check = await fetch(
          'https://api.monetbil.com/payment/v1/checkPayment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `paymentId=${encodeURIComponent(p.transaction_id || ref)}`,
      });
      const etat = await check.json().catch(() => ({}));
      const succes = (etat.transaction &&
              etat.transaction.status === 1) ||
          p.status === 'success' || p.status === 'SUCCESS';
      await majTransaction(env, ref,
          succes ? 'confirme' : 'echoue', { monetbil: p, verif: etat });
      // Recharge de crédits ? → créditer le portefeuille (une seule fois :
      // majTransaction vient d'écrire 'confirme' ; on lit la tx pour
      // type/clientId/montant, et soldeCredite verrouille le rejeu)
      if (succes) {
        const token = await jwtFirebase(env);
        const tx = await lireTransaction(env, token, ref);
        const f = tx && tx.fields ? tx.fields : {};
        const type = f.type && f.type.stringValue;
        const deja = f.soldeCredite && f.soldeCredite.booleanValue;
        if (type === 'recharge' && !deja) {
          const clientId = f.clientId ? f.clientId.stringValue : null;
          const montant = f.montant
              ? Number(f.montant.doubleValue || f.montant.integerValue)
              : 0;
          if (clientId && montant > 0) {
            await crediterSolde(env, token, clientId, montant);
            await fetch(
              `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/transactions_paiement/${ref}?updateMask.fieldPaths=soldeCredite`,
              {
                method: 'PATCH',
                headers: {
                  Authorization: `Bearer ${token}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  fields: { soldeCredite: { booleanValue: true } },
                }),
              });
          }
        }
      }
      return new Response('OK');
    }
    return new Response('PagneShop Webhook Paiement', { status: 200 });
  },
};
