'use strict';
// PagneShop (SAMI) — Cloud Functions (lot C). Déploiement : voir ../DEPLOIEMENT_FUNCTIONS.md
const admin = require('firebase-admin');
admin.initializeApp();

const livraisons = require('./src/livraisons');
const recus = require('./src/recus');
const auth = require('./src/auth_social');

// Livraisons : clés QR côté serveur, validation des scans, signature, assignation
exports.onLivraisonCreee = livraisons.onLivraisonCreee;
exports.validerScan = livraisons.validerScan;
exports.ajouterSignature = livraisons.ajouterSignature;

// Reçus signés (clé serveur)
exports.creerRecu = recus.creerRecuCallable;
exports.verifierRecu = recus.verifierRecu;

// Connexion Telegram / WhatsApp (jetons personnalisés)
exports.authTelegram = auth.authTelegram;
exports.authWhatsappEnvoyer = auth.authWhatsappEnvoyer;
exports.authWhatsappVerifier = auth.authWhatsappVerifier;
