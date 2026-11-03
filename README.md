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
- Workers : voir `GUIDE_CLOUDFLARE.md` (le token vit dans `env.AUTH_TOKEN`, jamais dans le code)

## ⚠️ Projet partiel dans ce dépôt
Ce dépôt contient le code source applicatif. Les dossiers natifs
(`android/`, `ios/`) et `google-services.json` sont générés/configurés
localement et volontairement exclus (voir `.gitignore`).
