# Migration des images vers Cloudflare R2 — PagneShop

## 🗺️ VOCABULAIRE CLOUDFLARE (pour ne pas se perdre dans le dashboard)

| Produit | C'est quoi | On l'utilise ? |
|---|---|---|
| **R2** | L'**entrepôt** : stockage de fichiers (tes images). Équivalent de Firebase Storage. | ✅ OUI — c'est là que vivent les photos |
| **Worker** | Le **portier** : un petit programme qui tourne chez Cloudflare. Il reçoit l'image envoyée par l'app, vérifie le mot de passe (token), et la range dans R2. Ce n'est PAS une base de données. | ✅ OUI — le fichier `worker_r2.js` fourni |
| **KV** | Un stockage **clé-valeur** (petites données texte). Souvent confondu avec les Workers car ils sont dans le même menu. | ❌ NON — n'y touche pas |
| **D1** | Une base de données SQL. | ❌ NON — Firestore reste ta base |
| **Pages** | Hébergement de sites web. | ⏳ Plus tard (version web de l'app) |
| **Binding** | Le **câble** qui relie ton Worker à ton bucket R2 (pour qu'il puisse y écrire). | ✅ OUI — étape 4 |

En résumé : l'app envoie la photo → le **Worker** (portier) vérifie le token
→ la range dans **R2** (entrepôt) → l'app enregistre l'URL dans Firestore.

## Ce qui BASCULE vers Cloudflare (maintenant)
- **Toutes les images** : photos de pagnes, modèles, logos, confections,
  pièces d'identité. R2 = 10 Go gratuits puis ~0,015 $/Go, et **0 $ de
  sortie** (les téléchargements de tes clients ne coûtent jamais rien).
  → Firestore ne stocke plus que des URLs : documents légers, plus de
  limite 1 Mo, app plus rapide.

## Ce qui RESTE chez Firebase (ne pas toucher)
- **Firestore** : ta base temps réel (streams, règles, synchronisation).
- **Firebase Auth** : les comptes et connexions.
- Les index et règles déjà déployés.

## Plus tard (quand tu actives les paiements réels)
- **Webhook Monetbil → un autre Worker** (gratuit, remplace les Cloud
  Functions payantes de Firebase).
- **Version web → Cloudflare Pages**.

## 🔧 MISE EN PLACE (15 minutes, pas à pas)

1. **Créer l'entrepôt (R2)**
   dash.cloudflare.com → menu gauche **R2 Object Storage** →
   *Create bucket* → nom : `pagneshop-media` → *Create*.

2. **Rendre l'entrepôt lisible publiquement**
   Ouvre le bucket → onglet *Settings* → section **Public access** →
   *R2.dev subdomain* → **Allow Access** →
   📝 note l'URL affichée : `https://pub-XXXXXXXX.r2.dev`

3. **Créer le portier (Worker — PAS KV !)**
   Menu gauche **Workers & Pages** → *Create application* →
   onglet **Workers** → *Create Worker* → nom : `pagneshop-upload` →
   *Deploy* → puis *Edit code* → **efface tout** et colle le contenu
   de `worker_r2.js` (fourni dans l'archive) → *Save and deploy*.
   📝 note l'URL du Worker : `https://pagneshop-upload.TONCOMPTE.workers.dev`

4. **Brancher le câble (Binding R2)**
   Dans ton Worker → *Settings* → *Bindings* → *Add* →
   choisis **R2 bucket** → Variable name : `BUCKET` (exactement, en
   majuscules) → Bucket : `pagneshop-media` → *Save*.

5. **Le mot de passe (Secret)**
   Toujours dans *Settings* → *Variables and Secrets* → *Add* →
   Type **Secret** → Name : `AUTH_TOKEN` → Value : une longue chaîne
   aléatoire que tu inventes (ex. 40 caractères mélangés) → *Save*.
   📝 garde cette chaîne, l'app en a besoin.

6. **Configurer l'app** — `lib/services/stockage_service.dart`,
   classe `_R2Config` (en haut du fichier) :
   - `urlPublique` = l'URL de l'étape 2 (pub-XXXX.r2.dev)
   - `workerUrl`   = l'URL de l'étape 3 (….workers.dev)
   - `authToken`   = la chaîne de l'étape 5

7. **Basculer** : recompile l'app → Mon compte (connecté en admin) →
   section **Stockage** → activer Cloudflare.
   Les NOUVELLES images partent sur R2 ; les anciennes (base64)
   continuent de s'afficher — aucune migration forcée.

## ✅ Vérification
Ajoute un pagne avec 4-5 photos : plus aucune limite de poids.
Dans le dashboard R2 → ton bucket → les fichiers apparaissent.
Ouvre une des URLs pub-XXXX.r2.dev/... dans un navigateur : l'image s'affiche.

## 🆘 Si ça échoue
- Erreur 401 → le `authToken` de l'app ≠ le secret `AUTH_TOKEN` du Worker.
- Erreur 500 "BUCKET is not defined" → le binding de l'étape 4 manque
  ou n'est pas nommé exactement `BUCKET`.
- Image uploadée mais ne s'affiche pas → l'accès public (étape 2)
  n'est pas activé, ou `urlPublique` est mal recopiée.

---

# 🗺️ OSRM (itinéraires) dans l'architecture Cloudflare

## Le schéma d'ensemble
```
App PagneShop ──HTTPS──> Cloudflare (proxy/tunnel) ──> VPS : OSRM :5000
                              │
                              └── cache edge des itinéraires répétés
```
OSRM est la SEULE pièce qui exige un vrai serveur (il charge la carte du
Cameroun en RAM) — tout le reste de ton architecture reste serverless
(Workers, R2, Pages). Cloudflare joue devant : HTTPS, cache, protection,
IP du VPS cachée.

## ⭐ Méthode recommandée : Cloudflare TUNNEL (zéro port ouvert)
Le tunnel sort DU VPS VERS Cloudflare — pas de pare-feu à configurer,
pas de certificat à gérer, l'IP du serveur n'est jamais exposée.

1. Dashboard → **Zero Trust** → Networks → **Tunnels** → *Create* →
   nom `pagneshop-osrm` → choisir **Docker** → copier la commande
   affichée (elle contient ton token) et la lancer sur le VPS :
   ```bash
   docker run -d --restart always --network host \
     cloudflare/cloudflared:latest tunnel run --token TON_TOKEN
   ```
2. Dans le tunnel → **Public Hostname** → *Add* :
   - Subdomain : `osrm` · Domain : ton domaine
   - Service : **HTTP** · URL : `localhost:5000`
3. C'est tout. Teste :
   `https://osrm.TONDOMAINE.com/route/v1/driving/13.3958,9.3265;13.40,9.33`

## Brancher l'app (sans recompiler)
Firestore → `app_config/parametres` → champ `osrmUrl` :
`https://osrm.TONDOMAINE.com` — toutes les cartes suivent aussitôt.

## Bonus : cache des itinéraires au edge
Dashboard → ton domaine → **Caching** → *Cache Rules* → nouvelle règle :
- Si `URI Path` contient `/route/v1/` → **Cache eligible**,
  Edge TTL **1 heure**.
Les trajets identiques (boutique→quartier fréquents) sont servis depuis
le edge Cloudflare : plus rapide, et ton VPS respire.

## Variante sans domaine propre
Le tunnel fournit aussi une URL `*.cfargotunnel.com` gratuite — moins
jolie, parfaitement fonctionnelle pour démarrer.

## Maintenance
- Carte : re-télécharger `cameroon-latest.osm.pbf` + relancer les 3
  commandes de préparation tous les 1-2 mois.
- Le conteneur cloudflared ET le conteneur OSRM ont `--restart always` :
  le VPS peut redémarrer, tout revient seul.
