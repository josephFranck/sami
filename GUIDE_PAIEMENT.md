# GUIDE — Activer les paiements Mobile Money réels (SAMI)

Ce guide explique comment passer du paiement **simulé** au paiement **réel**
(Orange Money / MTN MoMo au Cameroun).

---

## Vue d'ensemble du flux

```
1. App SAMI : client clique "Payer"
2. PaiementService.initier() → API Monetbil/CinetPay
3. Le fournisseur renvoie une URL de paiement
4. L'app ouvre cette URL (WebView) → le client paie sur son mobile
5. Le fournisseur débite le client puis appelle votre WEBHOOK (notify_url)
6. Le WEBHOOK (Cloudflare Worker — worker_paiement.js fourni) REVÉRIFIE le paiement auprès de Monetbil puis met à jour Firestore
7. L'app, qui écoute Firestore en temps réel, voit le statut "confirmé"
8. Le crédit / l'abonnement est activé
```

**Point clé :** le crédit définitif doit être donné par le WEBHOOK (étape 6),
jamais par l'app seule (un client pourrait fermer l'app avant de payer).

---

## Étape 1 — Ouvrir un compte marchand

### Option A : Monetbil (recommandé pour le Cameroun)
1. Aller sur https://www.monetbil.com → créer un compte
2. Fournir les documents KYC (pièce d'identité, RCCM si entreprise)
3. Une fois validé : Dashboard → récupérer votre **Service Key**
4. Configurer l'URL de notification (webhook) dans le dashboard

### Option B : CinetPay
1. Aller sur https://cinetpay.com → "Commencez maintenant"
2. Un commercial vous contacte pour le KYC
3. Compte validé → Back-office → menu **Intégration** → récupérer **API Key** + **Site ID**

> Les deux supportent Orange Money CM et MTN MoMo CM. Monetbil est plus simple
> et plus orienté Cameroun ; CinetPay couvre plus de pays.

---

## Étape 2 — Renseigner les clés

Dans `lib/utils/config_paiement.dart`, remplacer les `'A_RENSEIGNER'` :

```dart
static const String monetbilServiceKey = 'votre_vraie_cle';
// ou
static const String cinetpayApiKey = 'votre_api_key';
static const String cinetpaySiteId = 'votre_site_id';
```

---

## Étape 3 — Déployer le Webhook (Cloud Function)

C'est l'étape la plus technique. Le webhook reçoit la confirmation du
fournisseur et crédite réellement le compte. Exemple en **Firebase Cloud
Functions** (Node.js) :

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Webhook Monetbil
exports.webhookMonetbil = functions.https.onRequest(async (req, res) => {
  const { item_ref, status, payment_ref } = req.body; // item_ref = notre transactionId

  // 1. Vérifier l'authenticité (Monetbil envoie un sign / à vérifier selon doc)
  //    → comparer avec votre service_key, voir doc Monetbil

  // 2. Trouver la transaction
  const txRef = admin.firestore().collection('transactions_paiement').doc(item_ref);
  const tx = await txRef.get();
  if (!tx.exists) return res.status(404).send('Transaction inconnue');
  if (tx.data().statut === 'confirme') return res.status(200).send('Déjà traité');

  // 3. Si payé, créditer
  if (status === 'SUCCESS') {
    await txRef.update({ statut: 'confirme', refPaiement: payment_ref });
    // Créditer le compte client (selon le type de transaction)
    // ex: incrémenter creditBalance, activer l'abonnement, etc.
    const data = tx.data();
    await admin.firestore().collection('utilisateurs').doc(data.clientId).update({
      creditBalance: admin.firestore.FieldValue.increment(data.montant),
    });
  } else {
    await txRef.update({ statut: 'echoue' });
  }
  res.status(200).send('OK');
});
```

Déployer :
```bash
firebase deploy --only functions:webhookMonetbil
```

Récupérer l'URL générée (ex: `https://us-central1-sami-c564c.cloudfunctions.net/webhookMonetbil`)
et la mettre dans `config_paiement.dart` → `monetbilWebhookUrl`.

---

## Étape 4 — Activer

Dans `config_paiement.dart` :
```dart
static const bool paiementsActifs = true;  // active les vrais paiements
static const bool modeTest = false;        // false = production
```

---

## Étape 5 — Tester AVANT la production

1. Garder `modeTest = true` d'abord (sandbox du fournisseur)
2. Faire un vrai test avec un petit montant (ex: 100 FCFA)
3. Vérifier que : le débit a lieu, le webhook est appelé, le solde est crédité
4. Seulement ensuite passer `modeTest = false`

---

## ⚠️ Sécurité — IMPORTANT pour la production

**Les clés ne devraient PAS rester dans l'app mobile en production.**
Une app Flutter peut être décompilée et les clés volées.

Architecture recommandée pour la prod :
- L'app n'appelle PAS directement Monetbil/CinetPay
- L'app appelle une **Cloud Function `initierPaiement`** (qui détient les clés)
- Cette fonction appelle le fournisseur et renvoie l'URL à l'app

Pour le développement et les premiers tests, les clés dans l'app sont
tolérables. Mais planifiez ce déplacement avant un vrai lancement public.

---

## État actuel du code

| Composant | État |
|-----------|------|
| `PaiementService.initier()` | ✅ Implémenté (Monetbil + CinetPay, HTTP réel) |
| `PaiementService.verifierStatut` | ✅ Implémenté |
| `PaiementService.streamStatut` | ✅ Temps réel via Firestore |
| `credit_service` (abonnements) | ✅ Branché sur PaiementService |
| `config_paiement.dart` | ✅ Clés centralisées |
| Webhook Cloud Function | ❌ À déployer (vous) |
| Compte marchand + clés | ❌ À obtenir (vous) |

Le code est **prêt**. Il manque le compte marchand, les clés et le webhook.


---

## ⚡ NOUVEAU — Webhook en Cloudflare Worker (gratuit, fourni)

Le fichier `worker_paiement.js` remplace la Cloud Function payante :

1. **Workers & Pages** → Create Worker → nom `pagneshop-paiement` →
   coller `worker_paiement.js` → Deploy.
2. **Secrets** (Settings → Variables and Secrets, type Secret) :
   - `FIREBASE_PROJECT_ID` = sami-c564c
   - `SA_CLIENT_EMAIL` + `SA_PRIVATE_KEY` : console Firebase →
     ⚙️ Paramètres → Comptes de service → *Générer une nouvelle clé
     privée* → copier `client_email` et `private_key` du JSON.
   - `MONETBIL_SERVICE_SECRET` = votre service secret Monetbil.
3. **Chez Monetbil** : Notification URL =
   `https://pagneshop-paiement.VOTRECOMPTE.workers.dev/notify`
4. **Défense en profondeur** : le worker ne croit pas la notification
   sur parole — il REVÉRIFIE via l'API checkPayment avant d'écrire
   `statut: confirme` sur `transactions_paiement/{ref}`.
5. **Dans l'app** : Mon compte (admin) → Paiements → coller la clé de
   service Monetbil → activer. Le panier bascule automatiquement :
   Mobile Money → push USSD sur le téléphone du client → la commande
   n'est créée qu'après confirmation.

**Test de bout en bout (mode sandbox Monetbil)** : activer modeTest,
commander, valider le push fictif, vérifier que transactions_paiement
passe à `confirme` PUIS que la session de commande est créée.
