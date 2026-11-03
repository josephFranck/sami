# SAMI — Installation de la version à jour

Cette archive contient la version cohérente et à jour du projet SAMI.

## Contenu
- `lib/` — tout le code source (83 fichiers Dart)
- `pubspec.yaml` — dépendances (vérifie les versions)

## Comment l'installer dans ton projet

1. **Sauvegarde d'abord ton projet actuel** (par sécurité).

2. **IMPORTANT — garde ton `firebase_options.dart`** : ce fichier est propre à TON projet Firebase. 
   - Avant de remplacer, copie ton `lib/firebase_options.dart` actuel quelque part.
   - Le `firebase_options.dart` inclus ici est un placeholder — NE L'UTILISE PAS.

3. **Remplace ton dossier `lib/`** par celui de l'archive.

4. **Remets ton `firebase_options.dart`** dans `lib/`.

5. **Compare ton `pubspec.yaml`** avec celui fourni. Assure-toi d'avoir au minimum :
   - flutter_image_compress
   - connectivity_plus ^6.0.5
   - flutter_map, latlong2, location
   - cloud_firestore, firebase_auth, firebase_core
   - image_picker, shared_preferences

6. **Lance :**
   ```
   flutter clean
   flutter pub get
   flutter run
   ```

## Vérifié dans cette version
- 0 import cassé, 0 fichier legacy
- 33 routes, toutes les pages du drawer accessibles
- Stock (saisie + décrément commande + réappro + restitution retour)
- Livraison complète (commande → agent → livreur → suivi GPS temps réel → retrait possible)
- Coordonnées GPS (boutiques + clients)
- Analyse boutiquier, config marketing, favoris, catégories cliquables
- Édition cohérente (pagne, boutique, profil)
- Ajout livreur, messagerie admin


## Liens profonds (partage WhatsApp)

Pour que les liens `https://sami-c564c.web.app/p/{id}` ouvrent l'app,
ajouter dans `android/app/src/main/AndroidManifest.xml`, à l'intérieur de
`<activity android:name=".MainActivity" ...>` :

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="sami-c564c.web.app" />
</intent-filter>
```

Puis, sur Firebase Hosting (même projet), publier un fichier
`.well-known/assetlinks.json` avec l'empreinte SHA-256 de la clé de
signature (générée par `./gradlew signingReport`). Sans app installée,
le lien affiche la page web (mettre une page « Télécharger SAMI »
comme index de Hosting).


## Compilation multiplateforme

### Web (Cloudflare Pages / Firebase Hosting)
`flutter build web --release` → déployer le dossier `build/web`.
Les uploads et prévisualisations d'images passent désormais par les octets
(XFile.readAsBytes) : compatibles navigateur. Le partage sur web envoie le
texte + lien (l'aperçu image vient du lien). Fonctions à réserver au mobile :
scan QR caméra (support navigateur inégal) — la vitrine client (parcourir,
commander, suivre, payer) est la cible web.

### iOS (iPhone)
Ajouter dans `ios/Runner/Info.plist` :
```xml
<key>NSCameraUsageDescription</key>
<string>Photographier les pagnes, pièces et preuves de livraison</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Choisir des photos de pagnes et de modèles</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Guider les livraisons et localiser boutiques et ateliers</string>
```
Aucun changement de code requis : image_picker, location, mobile_scanner,
signature et share_plus supportent iOS nativement.


## Réglages Android issus du premier test appareil

**1. Bouton retour prédictif (Android 13+)** — dans `AndroidManifest.xml`,
sur la balise `<application ...>` ajouter :
```xml
android:enableOnBackInvokedCallback="true"
```

**2. Index Firestore composites** — deux requêtes (avis, conversations) les
exigent. Deux options :
- Cliquer les liens donnés dans le log d'exécution (console Firebase, un clic) ;
- OU déployer le fichier `firestore.indexes.json` fourni :
  `firebase deploy --only firestore:indexes`
La construction prend quelques minutes ; les avis et la messagerie
fonctionneront ensuite.

**3. applicationId avant le Play Store** — l'app tourne en
`com.example.sami` : à renommer (ex. `cm.sami.app`) dans
`android/app/build.gradle` AVANT la première publication (impossible de
changer après sans casser les mises à jour des utilisateurs).

**4. Anciennes images Firebase Storage (erreurs 402)** — les pagnes/photos
de profil créés avant la bascule en stockage local pointent vers Firebase
Storage, qui répond 402 (facturation requise). Ce ne sont pas des bugs de
code : ces URLs sont mortes. Pour le pilote : re-photographier ces pagnes
de test (les nouveaux uploads passent en base64 et s'affichent), ou purger
les données de test. L'app affiche déjà le placeholder à la place.

## Règles de sécurité Firestore (OBLIGATOIRE avant ouverture publique)
Le fichier `firestore.rules` est fourni. Déploiement :
`firebase deploy --only firestore:rules`
Réponse à la question clé : NON, la configuration (app_config) ne doit pas
être modifiable par tous — seul l'admin écrit (clés de paiement, clé des
reçus, paramètres). Lecture authentifiée uniquement (l'app en a besoin).
Un utilisateur ne peut PAS s'auto-promouvoir admin/agent. Tout ce qui n'est
pas explicitement autorisé est REFUSÉ.

## Icône de lancement PagneShop (écran du téléphone)
Les images sont fournies (`assets/icon.png` + `assets/icon_foreground.png`)
et la configuration est dans `pubspec.yaml`. Deux commandes :
```
flutter pub get
dart run flutter_launcher_icons
```
Puis désinstaller/réinstaller l'app sur le téléphone pour voir la nouvelle
icône (Android met l'icône en cache). Le nom sous l'icône se change dans
`android/app/src/main/AndroidManifest.xml` → `android:label="PagneShop"`.
