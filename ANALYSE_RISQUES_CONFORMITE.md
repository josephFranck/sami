# PagneShop (SAMI) — Analyse des risques, de la sécurité et de la conformité

**Date :** 3 novembre 2026 · **Périmètre :** code `lib/` (131 fichiers), `firestore.rules`, workers Cloudflare, données traitées · **Méthode :** audit factuel du code et des règles (scripts reproductibles), recherche des textes camerounais en vigueur, correction immédiate de ce qui relève du code.

> **Avertissement.** Ce document est une analyse technique et une lecture des textes par un non-juriste. Les références légales sont citées avec leurs sources ; **il doit être validé par un avocat camerounais** (droit du numérique / droit des affaires) avant le lancement public. Les textes de CGU et de politique de confidentialité ajoutés à l'application sont des **cadres à compléter**, pas des documents définitifs.

---

## 1. Contexte et contraintes

| Élément | Fait |
|---|---|
| Nature | Place de marché mobile (Flutter + Firebase) : clients, boutiques de pagnes, couturiers, livreurs indépendants — Garoua, Cameroun |
| Exploitant | Marque GOUSNA, **sans société immatriculée (pas de RCCM)** à ce jour ; société en projet |
| Architecture | Firebase Auth + Firestore, logique métier **exécutée sur les appareils des utilisateurs** (pas de Cloud Functions), stockage images Cloudflare R2 via worker, paiement Mobile Money par déclaration de référence (worker de paiement non déployé) |
| Terrain | Smartphones Android d'entrée de gamme, réseau 4G irrégulier, paiement en espèces courant |
| Données traitées | Identité, téléphone, adresse, position GPS, photos de preuve de livraison, signature manuscrite, mesures corporelles, pièce d'identité des livreurs, soldes de crédits, historique de commandes |

**Contrainte structurante :** sans serveur applicatif (Cloud Functions), toute règle métier peut être contournée par une application modifiée ; la seule défense côté serveur est `firestore.rules`. C'est pourquoi cet audit a porté en priorité sur les règles.

---

## 2. Cadre légal applicable (vérifié, sources en fin de document)

### 2.1 Loi n° 2024/017 du 23 décembre 2024 — protection des données à caractère personnel
- **En vigueur depuis le 23 juin 2026** (délai de mise en conformité de 18 mois, art. 73). Elle s'applique à PagneShop *aujourd'hui*.
- Consentement **explicite, libre, informé, non pré-coché**, retirable à tout moment ; une finalité = un consentement.
- Minimisation : ne collecter que le strictement nécessaire.
- **Traitement soumis à autorisation préalable** de l'Autorité de protection des données (art. 19) ; **transfert hors du Cameroun soumis à autorisation préalable et à des garanties adéquates** — directement concerné : Firebase héberge les données hors du Cameroun.
- Droits : accès, rectification, opposition (y compris au profilage et à la prospection), effacement (« droit à l'oubli »).
- Sécurité : mesures techniques (chiffrement, audits) ; notification des incidents.
- Sanctions : amendes administratives proportionnelles au chiffre d'affaires, peines d'emprisonnement pour les cas graves (détournement de finalité, vente de fichiers).

### 2.2 Loi n° 2010/021 du 21 décembre 2010 — commerce électronique
- **Art. 30** : accès facile, direct et permanent à l'identité de l'éditeur (nom/raison sociale, adresse, courriel, téléphone, n° au registre du commerce si inscrit, n° de contribuable si assujetti à la TVA).
- **Art. 31** : prix clairs, en précisant si taxes et frais de livraison sont inclus.
- **Art. 15** : information précontractuelle (étapes, prix, livraison, délais, droit de rétractation…).
- **Art. 12 / 17** : vérification de la commande avant confirmation ; **accusé de réception sous 5 jours**.
- **Art. 20** : **droit de rétractation de 15 jours** à compter du lendemain de la réception ; remboursement sous 15 jours après retour ; frais de retour à la charge du consommateur.
- **Art. 22** : **exception pour les produits confectionnés selon des caractéristiques personnalisées** (→ couture sur mesure non rétractable).
- **Art. 21** : non-conformité / retard — restitution sous 15 jours.
- **Art. 26** : le vendeur doit **prouver** l'information préalable, la confirmation et le consentement.
- **Art. 7** : **prospection directe interdite sans consentement préalable** (→ notifications promotionnelles).
- **Art. 32** : conservation des données de transaction.
- **Art. 43** : amende de **250 000 à 2 500 000 FCFA** pour violation des art. 15, 17, 19, 21, 24, 25.

### 2.3 Loi-cadre n° 2011/012 du 6 mai 2011 — protection du consommateur
Droit à l'information, à la sécurité, à la réparation ; encadrement des contrats d'adhésion (les CGU en sont un). Les clauses doivent être lisibles et non abusives.

### 2.4 Règlement n° 04/18/CEMAC/UMAC/COBAC du 21 décembre 2018 — services de paiement
- L'**émission et la gestion de monnaie électronique** et la transmission de fonds sont des services de paiement réservés aux établissements agréés ; « le commerce de l'argent relève du monopole des seules personnes morales régulièrement agréées ».
- La voie praticable pour une plateforme : **partenariat contractuel avec un établissement agréé** (banque, établissement de paiement, opérateur de mobile money), le contrat prévoyant les contrôles de la COBAC.
- Au Cameroun, Orange Money et MTN Mobile Money Corporation disposent d'un agrément d'établissement de paiement.

### 2.5 Loi n° 2010/012 du 21 décembre 2010 — cybersécurité et cybercriminalité
Obligations de sécurité des systèmes et de confidentialité, notification des attaques et intrusions à l'ANTIC, conservation des données de connexion ; infractions d'accès frauduleux et d'atteinte aux données. La loi de 2024 reprend/complète son volet données personnelles.

---

## 3. Audit de sécurité — constats et corrections

Légende : **🔴 critique** (exploitable, perte d'argent ou de données) · **🟠 élevé** · **🟡 moyen** · ✅ corrigé dans ce commit · ⏳ à faire (hors code ou décision).

### 3.1 Règles Firestore (le mur de sécurité)

| # | Constat (fichier:ligne avant correction) | Gravité | Statut |
|---|---|---|---|
| 1 | `qr_secrets` : `allow write: if connecte()` — **tout utilisateur pouvait réécrire la clé HMAC de n'importe quelle livraison** et forger des validations | 🔴 | ✅ update réservé aux participants (client, livreur) et au staff |
| 2 | `livreurs` : `allow update: if connecte()` — tout utilisateur pouvait modifier `creditBalance`, `estVerifie`, `cniVerifiee`, `abonnementLivreur`, `nombreLivraisons` de n'importe quel livreur | 🔴 | ✅ champs financiers/vérification/abonnement réservés au staff (`touche()`) |
| 3 | `couturiers` : idem (`typeAbonnement`, `abonnementFinLe`, `estVerifie`, `creditBalance`) | 🔴 | ✅ idem |
| 4 | `sessions_commande` : `allow update: if connecte()` — **un client pouvait marquer son propre paiement « vérifié »** (MoMo déclaré) | 🔴 | ✅ champs de paiement réservés au staff |
| 5 | `sous_commandes` : montants (`sousTotal`, `totalClient`, `netBoutique`), `boutiqueReversee` modifiables par les parties | 🟠 | ✅ montants et flag de reversement réservés au staff |
| 6 | `transactions` : `create, update: connecte()` — historique financier modifiable | 🟠 | ✅ update réservé au staff |
| 7 | `livraisons` : `create/update: connecte()` — champs financiers modifiables ; création par n'importe qui | 🟠 | ✅ create par le client de la commande ; update par les parties ; champs financiers staff |
| 8 | `modeles_couture` : règle de création évaluant `resource.data` (inexistant en create) → **toute création refusée** (`PERMISSION_DENIED` observé dans les logs) | 🟠 (bug) | ✅ create/update séparés |
| 9 | **10 collections utilisées par le code SANS règle** → refus silencieux : `paniers` (panier jamais sauvegardé), `securite_livreurs` (profil CNI/caution), `pagnes/{id}/reservations` (réservations de stock), `scores_clients`, `credit_mouvements`, `saisies_caution`, `profils_boutique`, `config_taxes`, `alertes_admin`, `logs_admin` | 🟠 (bug) | ✅ règles ajoutées, champs sensibles de `securite_livreurs` réservés au staff |
| 10 | `alertes_agent` : clôture possible par tout connecté | 🟡 | ✅ update réservé au staff |
| 11 | `app_config/stockage` sans règle → token R2 jamais chargé ; et le rendre lisible aurait **exposé le secret à tous les utilisateurs** | 🔴 (conception) | ✅ voir 3.2 |
| 12 | `estStaff()` utilisée 12× sans être définie (fichier non compilable) | 🟠 (bug) | ✅ définie, alignée sur la liste `permissions` de l'app |
| — | Lectures publiques (`if true`) sur pagnes, boutiques, catégories, événements, couturiers, modèles, avis | ℹ️ voulu | Vitrine du marketplace ; aucune écriture publique |

**Reste structurel (⏳)** : tant que la logique métier tourne sur les appareils, un livreur avec une application modifiée peut encore passer une livraison en `livree` sans scan (la vérification HMAC est côté client). Les règles bloquent désormais la **fraude financière** (montants, soldes, paiements), pas la fraude d'état. **Recommandation n° 1 : migrer la validation des QR, les reversements et l'assignation vers Cloud Functions (plan Blaze).**

### 3.2 Secrets et authentification

| Constat | Gravité | Statut |
|---|---|---|
| Token R2 lu depuis un document Firestore : un secret dans une base lisible par les clients n'est pas un coffre | 🔴 | ✅ **Supprimé.** Le worker vérifie désormais le **jeton Firebase de l'utilisateur** (signature RS256 contre les clés publiques Google, audience = projet, expiration). Aucun secret partagé. Vérificateur testé : clé extraite identique à l'extraction officielle, jetons expirés / falsifiés / mauvaise audience refusés. Repli `AUTH_TOKEN` conservé pour les déploiements existants. |
| `firebase_options.dart` (clés API Firebase) | ℹ️ | Exclu du dépôt par prudence (à régénérer avec `flutterfire configure`). Ces clés ne sont pas secrètes par conception : la sécurité repose sur les règles. |
| App Check non installé (`No AppCheckProvider installed` dans les logs) : les requêtes d'applications modifiées ou de scripts ne sont pas filtrées | 🟠 | ⏳ Activer **Play Integrity** avant le lancement |
| Aucun mot de passe ni compte en dur ; règle anti-auto-promotion de rôle et anti-auto-crédit présentes | ✅ | — |
| Build non obfusqué | 🟡 | ⏳ `flutter build apk --obfuscate --split-debug-info=build/symbols` |

### 3.3 Bugs fonctionnels corrigés par la même occasion
- **Compensation des crédits** : si une commande échouait après débit, l'application tentait de re-créditer le client lui-même → refusé par la règle anti-auto-crédit → **le client perdait ses crédits en silence**. ✅ La compensation passe par la file `remboursements_a_faire` (validée par le staff, tracée) et le client en est informé.
- **Compteur de courses** (`nombreLivraisons`) écrit par l'appareil du livreur → falsifiable, et il conditionne sa quote-part. ✅ La quote-part effective **compte** désormais les livraisons réellement `livree` (validées par le code HMAC du client).
- **Flux de notifications** actif après déconnexion (`Listen … PERMISSION_DENIED` dans les logs). ✅ Le flux suit l'état d'authentification.

---

## 4. Données personnelles — inventaire et conformité

| Donnée | Finalité | Base | Constat | Statut |
|---|---|---|---|---|
| Nom, prénom, téléphone, courriel, quartier | Compte, commandes, livraison | Contrat + consentement | Aucun écran CGU / confidentialité, **aucune case de consentement, aucune vérification de majorité** | ✅ Page légale 3 onglets ; à l'inscription : 2 cases obligatoires (CGU + confidentialité, majorité) **jamais pré-cochées** ; preuve horodatée (`cguVersion`, `cguAccepteeLe`, `majeurDeclare`) sur le compte et **sur chaque commande** (art. 26) |
| Position GPS du client | Point de livraison | Consentement | Permission demandée sans explication | ✅ Boîte d'information *avant* la demande système |
| Position du livreur pendant la course | Suivi par le client | Contrat livreur | Toutes les 30 s pendant la course uniquement | ⏳ Faire figurer dans le contrat livreur (finalité, durée, droit d'accès) |
| Photos de preuve (colis, repère) | Preuve de remise | Contrat | Consigne « le colis, pas le visage » en place | ✅ |
| Signature manuscrite | Preuve complémentaire | Contrat | Ne clôture plus seule ; n'est pas une signature électronique certifiée | ✅ Qualifiée comme telle dans les CGU |
| Mesures corporelles | Confection | Consentement | Sous-collection personnelle, règle `uid == moi()` | ✅ Transmise au seul couturier choisi |
| Pièce d'identité des livreurs | Vérification | Obligation contractuelle | `securite_livreurs` était sans règle | ✅ Règle posée ; vérification réservée au staff. ⏳ **Ne stocker aucune image de CNI en base ni en clair** : vérification visuelle par le staff puis conservation hors ligne, ou stockage chiffré à accès restreint |
| Prospection (promotions) | Marketing | **Consentement préalable (art. 7)** | Aucun opt-in | ✅ Case facultative à l'inscription + interrupteur dans « Mon compte » (`consentMarketing`) |
| Droit à l'effacement | — | Loi 2024/017 | **Aucune suppression de compte** (également exigée par Google Play) | ✅ « Supprimer mon compte » : effacement des mesures et du panier, **anonymisation** du compte (les transactions sont conservées anonymisées pour la durée légale, art. 32), suppression de l'identité Firebase |
| Hébergement hors Cameroun (Firebase) | — | Autorisation préalable + garanties (loi 2024/017) | Non déclaré | ⏳ **Démarche auprès de l'Autorité de protection des données** avant lancement ; mention ajoutée dans la politique de confidentialité |
| Durée de conservation | — | Minimisation | Purges existantes (codes QR 48 h, etc.) | ⏳ Formaliser une politique écrite (comptes inactifs, logs, photos de preuve) |

---

## 5. Risques juridiques et commerciaux (hors code)

| Risque | Gravité | Analyse | Recommandation |
|---|---|---|---|
| **Crédits prépayés (`creditBalance`) = valeur stockée** | 🔴 | Détenir des soldes prépayés de clients peut être qualifié d'émission de monnaie électronique, activité réservée aux établissements agréés (règl. 04/18 CEMAC). L'application a déjà les garde-fous techniques (non transférable, anti-auto-crédit). | **Avant le lancement, avis d'un avocat fintech CEMAC.** Options : (a) limiter les crédits à des *avoirs* issus de remboursements/parrainage, non rechargeables en argent ; (b) rechargement uniquement via un établissement agréé qui conserve les fonds ; (c) supprimer le portefeuille. Les CGU livrées qualifient les crédits de moyen interne non retirable — cadre minimal, pas suffisant seul. |
| **Encaissement pour compte des boutiques** (le client paie PagneShop, qui reverse) | 🟠 | Flux de fonds de tiers transitant par la plateforme. | Contrat de mandat d'encaissement avec chaque boutique ; privilégier l'**API marchand** d'un opérateur agréé (Orange Money / MTN MoMo) plutôt que des transferts déclarés manuellement ; compte dédié aux fonds des partenaires. |
| **Espèces collectées par les livreurs** + caution | 🟠 | Fonds en transit détenus par des indépendants ; caution prélevée sur des partenaires. | Contrat de prestation écrit (statut d'indépendant, mandat d'encaissement, caution, plafond d'encours, assurance) ; vérifier avec un juriste la licéité de la caution selon le statut retenu. |
| **Exploitant non immatriculé** | 🔴 | Art. 30 exige l'identité de l'éditeur ; une activité commerciale régulière, l'émission de reçus/factures, la TVA (19,25 %) et tout partenariat de paiement supposent une entité immatriculée (RCCM, NIU). | **Immatriculer la société (projet « studio ») avant l'ouverture au public** ; d'ici là, l'éditeur est la personne physique, à nommer dans les mentions légales (`kExploitant`). |
| Droit de rétractation 15 jours | 🟠 | Non mentionné nulle part auparavant. | ✅ CGU (art. 20/21/22) + rappel dans l'accusé de réception ; ⏳ aligner le module « retours » sur le délai de 15 jours et le remboursement sous 15 jours ; frais de retour à la charge du client. |
| Avis en ligne | 🟡 | Réservés aux acheteurs ayant reçu la commande (garde `livree`). | ✅ ; conserver la modération. |
| Mineurs | 🟡 | Aucune vérification d'âge. | ✅ Déclaration de majorité obligatoire (déclarative — niveau standard pour une marketplace). |
| Déclaration du traitement | 🟠 | Loi 2024/017 art. 19. | ⏳ Dossier auprès de l'Autorité dès qu'elle reçoit les demandes ; désigner un référent données (DPO non obligatoire à cette taille, recommandé). |

---

## 6. Risques techniques et opérationnels

| Risque | Gravité | Statut |
|---|---|---|
| Logique métier côté client (voir 3.1) | 🔴 | ⏳ Cloud Functions pour : validation QR, reversements, assignation, calcul des parts |
| Worker de paiement non déployé ; paiement MoMo par déclaration manuelle | 🟠 | ⏳ Intégrer l'API d'un établissement agréé ; d'ici là, vérification humaine systématique (en place) |
| Images en base64 dans Firestore (performances, coût, limite 1 Mo/doc) | 🟡 | ⏳ Migration vers R2 (worker désormais sécurisé par jeton) |
| Index composites non déployés (CLI indisponible localement) | 🟡 | ⏳ Créer via les liens imprimés dans les logs (`create_composite`) |
| Pas de sauvegarde Firestore | 🟠 | ⏳ Exports planifiés (Firestore → Cloud Storage) |
| Journalisation (`app_logs`) : événements commande, annulations, erreurs — pas de données bancaires | ✅ | Conserver ; ne jamais y logger de numéro de téléphone complet |
| ANR / gel au démarrage sur appareils bas de gamme | 🟡 | Corrigé pour la couture (layout) ; ⏳ profiler en `--release` |

---

## 7. Plan d'action priorisé

**Immédiat (ce commit, à déployer)**
1. Publier `firestore.rules` dans la console Firebase (Règles → coller → Publier).
2. Déployer `worker_r2.js` avec la variable `FIREBASE_PROJECT_ID = sami-c564c` (et retirer `AUTH_TOKEN` une fois l'app mise à jour).
3. Compléter `kExploitant` dans `lib/pages/legal/mentions_legales_page.dart` (identité réelle de l'éditeur).
4. Reconstruire et distribuer l'application (consentements, suppression de compte, info GPS).

**Avant l'ouverture au public**
5. Faire valider CGU / politique de confidentialité / contrats partenaires par un avocat camerounais.
6. Trancher la question des crédits prépayés avec un conseil fintech CEMAC.
7. Immatriculer la société ; mettre à jour les mentions légales.
8. Démarche auprès de l'Autorité de protection des données (traitement + transfert Firebase).
9. Activer App Check (Play Integrity) ; build obfusqué.
10. Contrats écrits : boutiques (mandat d'encaissement, commissions), couturiers, livreurs (indépendants, caution, encours, données).

**Trimestre suivant**
11. Cloud Functions pour la logique sensible.
12. API de paiement agréée ; suppression du MoMo « déclaré ».
13. Politique de conservation écrite + exports de sauvegarde.
14. Migration des images vers R2.

---

## 8. Sources

- Loi n° 2024/017 du 23 décembre 2024 — entrée en vigueur et obligations : [Droit Médias Finance](https://droitmediasfinance.com/index.php/actualites/droit-tech-fintech/1297-cameroun-la-loi-sur-la-protection-des-donnees-a-caractere-personnel-entre-en-vigueur-ce-23-juin-2026) · analyse par un avocat (art. 2, 5, 19, 32, 73) : [CIO Mag](https://cio-mag.com/?p=59861) · création de l'Autorité : [Digital Business Africa](https://www.digitalbusiness.africa/cameroun-lautorite-de-protection-des-donnees-a-caractere-personnel-creee/)
- Loi n° 2010/021 du 21 décembre 2010 régissant le commerce électronique — texte officiel : [MINCOMMERCE (PDF)](https://www.mincommerce.gov.cm/sites/default/files/documents/loi-n-2010-021-du-21-decembre-2010-regissant-le-commerce-electronique-au-cameroun.pdf)
- Loi-cadre n° 2011/012 du 6 mai 2011 portant protection du consommateur : [analyse](https://www.memoireonline.com/04/15/9081/m_Les-contrats-d-adhesion-a-l-epreuve-de-la-loi-cadre-n2011012-du-06-mai-2011-portant-protection-d16.html)
- Règlement n° 04/18/CEMAC/UMAC/COBAC sur les services de paiement — texte : [SGG Congo (PDF)](https://www.sgg.cg/txts-droit-reg/cemac-reglement-2018-04-services-paiement.pdf) · cadre des fintechs : [Me Landry Mballa, Droit Médias Finance](https://droitmediasfinance.com/index.php/actualites/droit-tech-fintech/987-tribune-fintech-le-cadre-reglementaire-des-fintechs-finance-numerique-en-zone-cemac-me-landry-mballa) · agréments Orange Money / MTN MoMo : [EcoMatin](https://ecomatin.net/orange-money-decroche-le-tout-premier-agrement-detablissement-de-paiement-au-cameroun), [EcoMatin](https://ecomatin.net/mobile-money-corporation-obtient-a-son-tour-son-agrement-detablissement-de-paiement)
- Loi n° 2010/012 du 21 décembre 2010 relative à la cybersécurité et à la cybercriminalité : [texte (PDF)](https://database.cyberpolicyportal.org/api/files/166367990584329pspck8evk.pdf), [synthèse](https://www.consentstack.io/regulations/cm-law2010012)
- Vérification des jetons Firebase côté serveur : [documentation Firebase](https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library)
