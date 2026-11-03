# PagneShop (SAMI)

Marketplace de pagnes et de couture à Garoua (Cameroun) — Flutter + Firebase.

## Structure
- `lib/` — code source Flutter (130 fichiers)
- `firestore.rules` — règles de sécurité Firestore
- `firestore.indexes.json` — index composites
- `worker_r2.js` — Cloudflare Worker (stockage images R2)
- `worker_paiement.js` — Cloudflare Worker (paiement Mobile Money)
- `GUIDE_*.md`, `INSTALLATION.md` — guides de déploiement

## Déploiement
- Règles & index : console Firebase → Firestore → Règles / Index
- Workers : voir `GUIDE_CLOUDFLARE.md`. Le worker R2 authentifie par le **jeton Firebase de l'utilisateur** (variable `FIREBASE_PROJECT_ID`) ; `AUTH_TOKEN` n'est qu'un repli temporaire.
- `firebase_options.dart` est exclu du dépôt : le régénérer avec `flutterfire configure`.

## Sécurité & conformité
Voir **`ANALYSE_RISQUES_CONFORMITE.md`** (audit du 03/11/2026 : règles, secrets, données personnelles, cadre légal camerounais, plan d'action). Avant publication : compléter `kExploitant` dans `lib/pages/legal/mentions_legales_page.dart` et faire valider les textes légaux par un juriste.

## ⚠️ Projet partiel dans ce dépôt
Ce dépôt contient le code source applicatif. Les dossiers natifs
(`android/`, `ios/`) et `google-services.json` sont générés/configurés
localement et volontairement exclus (voir `.gitignore`).
