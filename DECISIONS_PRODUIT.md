# PagneShop — Décisions produit et plan de mise en cohérence

**Date :** 3 novembre 2026 · Fait suite à `ANALYSE_RISQUES_CONFORMITE.md`. Les incohérences ci-dessous sont **constatées dans le code** (fichier:ligne cité) ; les décisions sont celles prises par l'exploitant le 03/11/2026.

---

## 1. Incohérences constatées

| # | Constat | Preuve | Effet |
|---|---|---|---|
| 1 | Deux modèles de livraison coexistent : `EtapeLivraison` (sous-collection `sous_commandes/{id}/livraisons`) et `Livraison` racine (`/livraisons`) | 3 usages vs 37 usages ; `commande_multi_service.dart:192,483,489` | La sous-collection n'est la source de rien (affichage seulement) ; double écriture, règle supplémentaire |
| 2 | Vocabulaires de statut concurrents : `livre`/`livree`, `annule`/`annulee`, `enLivraison`/`enCoursLivraison` | enum `StatutLivraison` vs enum `StatutSousCommande` ; 6 chaînes « orphelines » dans 3 fichiers | Chaque filtre doit tester deux orthographes ; source des bugs « invisible dans Terminées » |
| 3 | Doubles sources de vérité financières : `Panier.fraisBase = 600` (constante) vs paramètre admin `fraisLivraisonBase` ; `PrixFCFA.decomposer` code **commission 8 %** et **part livreur 70 %** en dur | `panierpage.dart:79`, `commander_couture_page.dart:445`, `prix_fcfa.dart:278`, `addpagne_v2.dart:16,204`, `pagnedetail.dart:39` | Un changement de paramètre admin n'est pas reflété sur la fiche pagne ni le récap couture |
| 4 | Collections en doublon : `credit_mouvements`/`mouvements_credits`, `config_taxes`/`app_config/taxes`, `alertes_admin`/`alertes_agent`, `logs_admin`/`app_logs` | 1× vs 2×, 3× vs 2×, 1× vs 12×, 1× vs 3× | Données éparpillées, écrans qui ne lisent pas ce que d'autres écrivent |
| 5 | Couture : le boutiquier reçoit « Pagne à préparer (confection) » mais son tableau de bord ne lit pas `commandes_couturier` | `couture_service.dart:339` ; `dashboard_boutiquier.dart` : 0 lecture | Notification sans écran d'action |
| 6 | Abonnements : 4 systèmes (boutique, couturier, livreur, client), page d'affichage de 1 033 lignes, **aucune écriture de `abonnementFinLe` par l'app** | `abonnements_page.dart` (lecture seule) | Activation manuelle en console ; revenu « abonnement » non exploitable seul |
| 7 | Clé HMAC détenue par le livreur (vérification hors-ligne) ; `genererQRArrivee(livraisonId, cle)` est une fonction pure | `mes_livraisons_page.dart:85`, `livraison_securisee_page.dart:429`, `qr_crypto_service.dart` | Un livreur avec une app modifiée peut fabriquer le « code du client » |
| 8 | Authentification email + mot de passe uniquement (0 usage du téléphone) | `signup_page.dart:288` | Exclut les utilisateurs sans email ; le téléphone est l'identité MoMo |
| 9 | Un seul rôle par compte (`final String role`) ; 30 tests `role == '…'` dans 7 fichiers | `utilisateur.dart` | Un pro ne peut pas acheter |
| 10 | `Langue.ff` déclaré (60 occurrences dans 4 fichiers), 3 écrans traduits ; mode de paiement affiché « Mobile Money » pour `credits` et `momo_declare` | `mes_commandes_page.dart:139` | Promesse non tenue ; libellés trompeurs |
| 11 | Frais de livraison : forfait fixe, aucun paramètre de rayon/supplément | `parametres_service.dart` : aucun champ `rayon*`/`supplement*` | — |

## 2. Décisions (03/11/2026)

| Sujet | Décision | Conséquence technique |
|---|---|---|
| Scans QR | **Réseau acceptable au moment du scan** → vérification côté serveur | Cloud Functions (plan Blaze). La clé ne quitte plus le serveur ; le livreur n'a rien à forger. Le préchargement hors-ligne est retiré. |
| Connexion | **Téléphone + email, et connexion via WhatsApp, Facebook, Telegram ou autre** | Téléphone (SMS) et Facebook : fournisseurs Firebase natifs. WhatsApp et Telegram : **pas natifs** → code envoyé via l'API WhatsApp Business (Meta) / Telegram Login, vérifié par une Cloud Function qui délivre un jeton personnalisé. Nécessite un compte Meta Business et un bot Telegram. |
| Crédits prépayés | **Avoirs seulement** : issus des remboursements et du parrainage, jamais rechargeables en argent, non retirables | Retirer tout flux de rechargement ; conserver `creditBalance` comme avoir ; CGU déjà alignées |
| Rôles | **Tout pro est aussi client** | Passer de `role` (String) à `roles` (liste) avec `role` conservé comme rôle principal ; helper `aRole('x')` ; 30 sites à migrer ; règles Firestore adaptées |
| Frais de livraison | **Forfait + supplément hors zone** | Paramètres admin : `rayonZoneKm`, `supplementHorsZone` ; calcul par distance GPS origine→destination (fonction Haversine déjà présente, `livraison_service.dart:585`) ; affiché au panier avant validation (art. 31) |
| Couture | **Comme une commande normale** | La commande de couture crée une sous-commande boutique « à livrer chez le couturier X » ; même flux Confirmer → Prête → scan ; supprime la notification orpheline |
| Abonnements | **Souscription dans l'app maintenant, paiement MoMo déclaré** | Écran S'abonner → référence de transfert → file de vérification staff (existante) → à la validation, écriture automatique de `abonnementFinLe` (+ durée) et du palier |
| Langues | **Français et anglais au lancement** | Retirer `Langue.ff` des catalogues (60 occurrences) ou le garder inerte ; compléter l'anglais sur les écrans client |

## 3. Plan de mise en cohérence (par lots)

### Lot A — Cohérence du code (aucune dépendance externe, aucun coût)
1. Dictionnaire de statuts unique (`livree`, `annulee`, `enCoursLivraison`) ; suppression des orthographes orphelines ; un seul helper de comparaison.
2. Suppression de `EtapeLivraison` et de la sous-collection ; « Mes commandes » affiche les étapes depuis `/livraisons`.
3. Fusion des collections en doublon (garder : `mouvements_credits`, `app_config/taxes`, `alertes_agent`, `app_logs`).
4. Une seule source pour chaque paramètre financier : `fraisLivraisonBase`, `commissionDefautPct`, `gainLivreurPct` lus partout (suppression de `Panier.fraisBase` et des 8 %/70 % codés en dur).
5. Forfait + supplément hors zone (paramètres + calcul + affichage panier).
6. Couture → sous-commande boutique dans « Commandes reçues ».
7. Multi-rôles (`roles`) + `aRole()` + règles.
8. Libellés de paiement (4 valeurs → 4 libellés) ; langues FR/EN ; retrait de `ff`.
9. Crédits = avoirs (retrait du rechargement).

### Lot B — Abonnements (dépend de A.9)
10. Écran de souscription (4 profils) → MoMo déclaré → vérification staff → activation automatique (`abonnementFinLe`, palier, reçu).

### Lot C — Serveur (nécessite le plan Blaze — décision de facturation de l'exploitant)
11. Cloud Functions : validation des scans (clé côté serveur), reversements, assignation de l'agent, calcul des parts, clôture des alertes.
12. Authentification téléphone (SMS) et Facebook ; WhatsApp/Telegram par jeton personnalisé (comptes Meta Business / bot Telegram à créer par l'exploitant).
13. App Check (Play Integrity).

### Lot D — Hors code (exploitant)
14. Avocat : CGU, confidentialité, contrats partenaires, question des avoirs.
15. Immatriculation (RCCM, NIU) ; mentions légales (`kExploitant`).
16. Autorité de protection des données : déclaration du traitement et du transfert Firebase.
17. Comptes Meta Business (WhatsApp) et Telegram ; plan Blaze.

**Ordre recommandé :** A → B → C (C démarre dès que Blaze est activé ; A et B n'en dépendent pas).

---

## 4. Journal d'exécution

### Lot A (1/4 → 3/4) — fait le 03/11/2026
| # | Fait | Preuve |
|---|---|---|
| A4-A5 | Devis unique (`DevisCommandeService`) + forfait/supplément hors zone | commit `a4114b4` |
| A6 | Couture → sous-commande boutique | commit `be92e37` |
| A7 | Multi-rôles : `Utilisateur.roles` + `aRole()`, `Droits`, drawer, promotion `arrayUnion`, règle « roles inchangeables par soi-même » | `utilisateur.dart`, `droits.dart`, `accueil_pagneshop.dart`, `gestion_utilisateurs_page.dart`, `firestore.rules` |
| A8 | Libellés de paiement : 4 valeurs → 4 libellés (`ConfigPaiement.libelleMethode`) ; Fulfulde retiré du sélecteur (enum `Langue.ff` conservé inerte) | `config_paiement.dart`, `mes_commandes_page.dart`, `saisie_mesures_page.dart` |
| A9 | Crédits = avoirs : rechargement retiré (`moncompte`), page « Mes crédits » (achat d'offres) → « Mes avoirs » (solde, sources, avoirs en attente, historique), `OffreCredit`/`acheterCredits` supprimés, débit du panier tracé (`mouvements_credits`), avoirs sans frais Mobile Money, contrôle « solde suffisant » aligné sur le montant débité | `abonnements_page.dart`, `panierpage.dart`, `credit_service.dart`, `devis_commande_service.dart` |

### Constats faits en exécutant A9 (corrigés dans le même lot)
| Constat | Preuve | Correction |
|---|---|---|
| La fidélité n'avançait jamais : `_crediterFidelite` écrivait `points` (champ lu par personne — l'app lit `pointsFidelite`) depuis le téléphone du **livreur**, écriture sur le doc d'un tiers refusée par les règles ; deux tables de paliers (constantes `NiveauFidelite` ≠ config admin lue par le devis) ; l'accueil affichait `niveau × 500` points | `livraison_service.dart` (ancien), `strategies_marketing.dart`, `accueil_pagneshop.dart:799` | `FideliteService` : le **client** réclame ses points (`reclamerTout` à l'ouverture de l'accueil, de Mon compte et de Mes commandes) ; une seule table (config admin) ; règles : hausse de `pointsFidelite` bornée par la sous-commande citée (`scFidelite`), drapeau `fideliteCreditee` jamais remis à false, statut de sous-commande jamais changé par le client seul, création toujours `enAttente` |
| Le parrainage n'était jamais validé : lecture de `parrainages` et création des primes depuis le téléphone du livreur → refusées (sauf livreur staff) | `parrainage_service.dart` (ancien `validerSiPremiereLivraison`) | `reclamerSiPremiereLivraison` côté filleul ; règles : passage `enAttente → valide` par le filleul avec `premiereLivraisonId` (sous-commande à son nom, livrée) ; primes à ids déterministes `PARRAINAGE_<lien>_parrain/_filleul` (montants relus sur le lien) |
| Historique des crédits refusé au client : la règle testait `clientId`, le document porte `utilisateurId` | `firestore.rules` (ancien), `credit_service.dart:toMap` | règle corrigée + index `mouvements_credits (utilisateurId, date desc)` |
| Le staff « reversements » ne pouvait pas créditer un avoir (règle `utilisateurs` : staff `utilisateurs` seulement) ; l'admin créditait sans mouvement (historique client muet) ; `_showCodeParrainage` inventait un code et affichait 500/1 000 F en dur | `remboursements_admin_page.dart`, `moncompte.dart` | règle : staff reversements → `creditBalance` seul ; crédit via `CreditService.crediterClient` (mouvement tracé) ; code réel + montants des paramètres |
| `ComptabiliteService.confirmerReversementsApresLivraison` (seul appel vivant du service) créditait le livreur d'un forfait 600 × 70 % à chaque scan, depuis son téléphone (refusé : `creditBalance` protégé) et en doublon du reversement staff (`gainLivreur` du devis) ; `enregistrerVente` jamais appelé | `livraison_service.dart:340` (ancien), `comptabilite_service.dart` | appel retiré ; service supprimé ; `ReversementService` (staff) = seule source des parts |
| `StrategiesMarketingService` (jamais appelé) augmentait `creditBalance` en direct et codait 500/1 000 F ; `OffreCredit`/`config_credits` (achat de crédits) sans écran | `strategies_marketing.dart`, `abonnements.dart` | supprimés |

### Lot B — Abonnements — fait le 03/11/2026
| Élément | Détail | Fichiers |
|---|---|---|
| Service | `AbonnementService` : `plans(profil)` (avantages = uniquement ce que le code applique), `fiches`, `actuel` (lu exactement comme le reste de l'app), `demander` → `abonnements_demandes` (statut `a_verifier`), `valider` (transaction : plan + `abonnementFinLe` sur la fiche — prolongation si même plan encore actif — `transactions` tracée, demande close, notification), `refuser` | `abonnement_service.dart` |
| Écran abonné | `PageAbonnements` : un onglet par profil (multi-rôles) ; `PageSouscription` : plan actuel, plans, bloc « transférez puis déclarez la référence » (mêmes numéros plateforme que le panier), mes demandes | `abonnements_page.dart` |
| Écran staff | Vérification des paiements → onglet **Abonnements** (Valider / Refuser avec motif) | `verification_paiements_page.dart` |
| Paramètres | `abonnementDureeJours` (30), `abonnementClientPrix` (0 = non proposé), `abonnementLivreurPrix` (0 = non proposé) ; plans boutique/couturier dans le code | `parametres_service.dart`, `parametres_admin_page.dart` |
| Règles | `abonnements_demandes` (création par l'abonné, traitement staff « paiements ») ; champs plan/échéance/commission/solde/facturation des 4 fiches réservés au staff ; `profils_couturier` ne porte plus le plan | `firestore.rules` |
| Effets rendus réels | Commission du plan boutique appliquée par le devis (avant : défaut admin pour tous) ; net boutique = prix − commission dans tous les modes (avant : mode « prépayé » = commission jamais prélevée, code mort) ; photos HD = plan payant actif (avant : `abonnement != null`, même « gratuit ») | `devis_commande_service.dart`, `addpagne_v2.dart` |
| Supprimé | `souscrireAbonnementBoutique/Couturier`, `inscrireLivreur`, `verifierExpirations`, `_initierPaiementMoMo` (paiement simulé puis plan écrit depuis le téléphone de l'abonné ; boutique ciblée par l'id utilisateur) ; écran couturier embarqué qui activait un plan payant sans paiement ; catalogue `AbonnementLivreur` (gains par course, assurance, priorité : jamais appliqués) ; `ProfilAbonnementBoutique` | `credit_service.dart`, `dashboard_couturier.dart`, `abonnements.dart` |
| Notation | Constaté en chemin : l'auteur d'un avis recalcule la moyenne de la cible depuis son téléphone → refusé par les règles (boutiques/couturiers/livreurs/pagnes). Règle `majNotation()` : agrégats seuls, bornés 0–5 (limite connue : écriture par un tiers sans avis — Cloud Function, lot C) | `firestore.rules` |

**À décider par l'exploitant** : les prix des abonnements client et livreur (0 = non proposés) ; les avantages non codés des plans boutique/couturier (badge, boosts, analytics, support) ne sont plus affichés — à réintroduire quand ils existeront.

### Lot E — Français / anglais — fait le 03/11/2026
| Élément | Détail |
|---|---|
| Mécanisme | `LangueService` (fr/en, préférence `auth_lang`, recopiée sur `utilisateurs.langue`) ; `MaterialApp` se reconstruit au changement ; `flutter_localizations` pour les textes Material |
| Textes | `scripts/i18n/chaines.json` → `lib/l10n/tr.dart` généré (`Tr.s.cle`) ; 1 009 textes, 1 225 sites dans 81 fichiers (écrans client, boutiquier, couturier, livreur, services) |
| Sélecteur | Mon compte → « Langue / Language » ; écrans de connexion (🇫🇷/🇬🇧, Fulfulde retiré) |
| Notifications | écrites en FR **et** EN à l'envoi, lues dans la langue du destinataire |
| Hors périmètre | administration/staff, pages légales (traduction juridique → avocat), écrans couture non routés |

### Lot C — Serveur (Cloud Functions) — code prêt le 04/11/2026, déploiement à l'activation de Blaze
| Élément | Détail |
|---|---|
| Fonctions | `onLivraisonCreee` (clé HMAC côté serveur, tokens dans `qr_depart`/`qr_arrivee`, assignation), `validerScan` (vérification + toute la propagation), `ajouterSignature`, `creerRecu`/`verifierRecu`, `authTelegram`, `authWhatsappEnvoyer`/`Verifier` — `functions/`, tests `npm test` |
| App | `ScanServeurService` (cloud_functions) ; `LivraisonService`, `RecuService`, pages QR/scan basculent selon `scansServeur` ; agent local muet si `assignationServeur` ; connexion **SMS / WhatsApp** (`connexion_telephone_page.dart`) ; **Compléter mon profil** (`_AuthGate` : tout compte sans consentement CGU y passe) ; interrupteurs dans Paramètres |
| Déploiement | sans CLI locale : GitHub Actions (`.github/workflows/firebase-deploy.yml`) avec un compte de service — règles, index et fonctions ; guide `DEPLOIEMENT_FUNCTIONS.md` |
| Constats corrigés | fiches couturier/livreur créées avec id ≠ uid par la candidature → scan de départ, tableau de bord livreur et règles en échec (id = uid désormais) ; gérant ne pouvait pas lire la clé de départ (« QR indisponible ») ; agent : distance au carré |
| Reste (exploitant) | Blaze ; compte de service + secret GitHub ; fournisseurs Téléphone/Facebook dans la console ; compte Meta (WhatsApp), bot Telegram (+ page du widget sur gousna.com, côté app à faire) ; Facebook côté app (`flutter_facebook_auth`) ; App Check |

### Reste à faire
- **Lot C** (Blaze) : voir §3 — les limites restantes (statut de sous-commande modifiable par le livreur/gérant, devis calculé côté client) ne se ferment qu'avec des Cloud Functions.
- **Exploitant** : publier `firestore.rules` (console → Règles → coller → Publier) et créer l'index `mouvements_credits` via le lien du log, ou le fichier `firestore.indexes.json`.

