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
