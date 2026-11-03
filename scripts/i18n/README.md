# Traduction FR / EN (décision du 03/11/2026 : les deux langues au lancement)

**Source unique :** `chaines.json` (clé → `fr`, `en`, `params`, `sites`).
**Code généré :** `lib/l10n/tr.dart` (`Tr.s.cle`, `Tr.s.cle(param)`), suit
`LangueService` (`lib/services/langue_service.dart`, préférence `auth_lang`,
sélecteur dans Mon compte et sur les écrans de connexion).

Aucune dépendance `intl`/`gen-l10n` : les deux langues sont compilées dans
l'app. `flutter_localizations` sert seulement aux textes Material (sélecteurs
de date, boutons système).

## Ajouter / modifier un texte
1. Écrire le texte **en français** dans le code, dans un contexte reconnu
   (`Text('…')`, `labelText:`, `hintText:`, `tooltip:`, `titre:`/`message:`
   d'une notification, branche `=> '…'` ou `? '…' : '…'`, argument d'une aide
   privée `_Nom('…')`).
2. `python3 scripts/i18n/extraire.py` → la clé apparaît dans `chaines.json`
   avec `"en": ""`.
3. Renseigner `en` (les `{param}` doivent être identiques en FR et EN).
4. `python3 scripts/i18n/appliquer.py` → remplace la chaîne par `Tr.s.cle`,
   retire le `const` qui la gouvernait, régénère `lib/l10n/tr.dart`.
   (`--dry fichier.dart` montre le diff sans écrire ; `--gen` ne régénère
   que `tr.dart`.)

Un texte sans traduction `en` n'est **pas** transformé : on peut avancer
écran par écran sans casser la compilation.

## Hors périmètre (français seulement)
Écrans d'administration/staff (`lib/pages/admin/`, superviseur, agents),
pages légales (`lib/pages/legal/` — traduction juridique : avocat, lot D),
`AuthI18n` (déjà bilingue, Fulfulde conservé inerte), écrans couture
`saisie_mesures_page.dart` / `personnalisation_page.dart` (bilingues par
leur propre mécanisme, non routés aujourd'hui).

## Notifications
`NotificationService.envoyer(titre: (t) => t.cle, message: (t) => t.cle(x))`
écrit `titre`/`message` (FR) **et** `titreEn`/`messageEn` ; le destinataire
affiche la langue de SON téléphone (`NotificationService.texte(doc, 'titre')`).
