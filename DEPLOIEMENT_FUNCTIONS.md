# Lot C — Cloud Functions : ce que c'est, comment déployer

## Ce que font les fonctions (`functions/`)
| Fonction | Déclencheur | Rôle |
|---|---|---|
| `onLivraisonCreee` | création d'une livraison | génère la clé HMAC **côté serveur** et les tokens à afficher (`qr_depart/{id}` pour le gérant, `qr_arrivee/{id}` pour le client) — le livreur ne détient rien ; assigne un livreur si `assignationServeur` |
| `validerScan` | appel de l'app (livreur) | vérifie le QR ou le code court avec la clé serveur, puis fait **toute** la propagation : livraison, sous-commande, session, encours cash, transaction cash, reçu, fidélité, parrainage, notifications FR/EN, livreur disponible, clôture des alertes |
| `ajouterSignature` | appel de l'app | signature du client = preuve complémentaire après validation par son code |
| `creerRecu` / `verifierRecu` | appel de l'app | reçus signés avec une clé que l'app ne lit plus |
| `authTelegram`, `authWhatsappEnvoyer`, `authWhatsappVerifier` | appel de l'app | connexion Telegram (widget) et WhatsApp (code à usage unique) → jeton personnalisé Firebase |

Tests unitaires (crypto compatible avec l'app) : `cd functions && npm test`.

## Interrupteurs (console Firestore → `app_config/parametres`)
| Champ | Effet |
|---|---|
| `scansServeur: true` | l'app ne génère plus de clé ; les scans passent par `validerScan` ; les reçus par `creerRecu`/`verifierRecu` |
| `assignationServeur: true` | l'agent d'assignation tourne sur le serveur (l'app n'appelle plus le sien) |

Tant qu'ils sont absents/faux, l'app garde son fonctionnement actuel : on peut déployer les fonctions, puis basculer.

## Déployer sans CLI locale : GitHub Actions
Le workflow `.github/workflows/firebase-deploy.yml` déploie **règles, index et fonctions** à chaque push sur `main` (ou à la demande). À faire une fois :
1. **Plan Blaze** (console Firebase → Mettre à niveau).
2. **Compte de service** (Google Cloud Console → IAM et administration → Comptes de service → Créer) : rôles *Firebase Admin*, *Cloud Functions Admin*, *Utilisateur du compte de service*, *Éditeur Cloud Build*, *Administrateur Artifact Registry*, *Accesseur de secrets Secret Manager*. Onglet *Clés* → Ajouter une clé → JSON.
3. **GitHub** → dépôt `sami` → Settings → Secrets and variables → Actions → *New repository secret* : nom `FIREBASE_SERVICE_ACCOUNT`, valeur = contenu du fichier JSON.
4. Onglet *Actions* du dépôt → « Firebase — règles, index, fonctions » → *Run workflow*.

Les règles Firestore n'ont alors plus besoin d'être collées dans la console.

## Secrets des connexions sociales (Google Cloud → Secret Manager → Créer un secret)
- `TELEGRAM_BOT_TOKEN` : jeton du bot (BotFather) ; déclarer le domaine du widget (`/setdomain`, ex. gousna.com).
- `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID` : application Meta (WhatsApp Business Cloud API), modèle de message « authentication » nommé `sami_code` (ou variable d'environnement `WHATSAPP_TEMPLATE`).
Sans ces secrets, les trois fonctions d'authentification répondent « non configuré » ; le reste fonctionne.

## Téléphone (SMS) et Facebook
Fournisseurs natifs : console Firebase → Authentication → Sign-in method → activer *Téléphone* et *Facebook* (identifiant d'app + secret Meta). Côté app : écrans de connexion à compléter (lot C, partie app).

## App Check (Play Integrity)
Console Firebase → App Check → enregistrer l'app Android (Play Integrity). Quand les attestations passent, mettre `enforceAppCheck: true` dans les `onCall` (`functions/src/*.js`) et redéployer.
