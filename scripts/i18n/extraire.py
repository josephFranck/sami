#!/usr/bin/env python3
"""Extrait les chaînes d'interface à traduire des fichiers Dart.

Sortie : chaines.json  {cle: {fr, en, params:[...], sites:[fichier:ligne,…]}}
(fusionné avec un chaines.json existant : les traductions `en` déjà
renseignées sont conservées).

Repérage (voir SITES dans appliquer.py — même logique) :
  a) 1er argument positionnel de Text( / SelectableText( / Tab(text:
  b) arguments nommés : labelText, hintText, helperText, tooltip, texte,
     label, title (si la valeur est une chaîne), text
  c) titre: / message: d'un appel NotificationService.envoyer(
  d) branche droite `=> 'chaîne'` d'un switch-expression
  e) branches d'un ternaire `? 'a' : 'b'`
  f) arguments positionnels de constructeurs/aides privés `_Nom(`
Exclusions : chaînes sans lettre, identifiants (`cle`, `orange`), routes
(`/x`), URLs, chaînes réduites à une interpolation.
"""
import json, os, re, sys, unicodedata
sys.path.insert(0, os.path.dirname(__file__))
from dart_tok import tokenize, sig, unescape_dart

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LIB = os.path.join(ROOT, 'lib')
OUT = os.path.join(os.path.dirname(__file__), 'chaines.json')

# Périmètre : écrans client et partenaires + services qui parlent aux
# utilisateurs. Hors périmètre : administration/staff (exploitant, FR).
EXCLUS = [
    'lib/pages/admin/', 'lib/agents/', 'lib/pages/livraison/dashboard_superviseur.dart',
    'lib/l10n/', 'lib/services/log_service.dart', 'lib/utils/auth_i18n.dart',
    'lib/services/resilience_service.dart', 'lib/services/version_service.dart',
    'lib/services/taxes_service.dart', 'lib/services/analyse_service.dart',
    'lib/pages/commandes/analyse_page.dart', 'lib/pages/livreur/livreur_list_page.dart',
    'lib/pages/livreur/ajout_livreur_page.dart', 'lib/pages/addcategorie.dart',
    'lib/pages/editcategorie.dart', 'lib/models/', 'lib/pages/legal/',
    # déjà bilingues par leur propre mécanisme (_t(fr, en, ff) / Langue)
    'lib/pages/couturier/saisie_mesures_page.dart', 'lib/pages/couturier/personnalisation_page.dart',
    # techniques (URLs, MIME, clés)
    'lib/services/stockage_service.dart', 'lib/services/partage_service.dart',
    'lib/services/qr_crypto_service.dart', 'lib/services/sms_service.dart',
]
# aides privées dont les chaînes ne sont PAS des libellés à traduire
PRIVES_EXCLUS = {'_t', '_texte', '_menuItemLangue', '_option', '_maj', '_champNum', '_champTxt'}
TEXTES_EXCLUS = {'Français', 'English', 'PagneShop', 'SAMI', 'GOUSNA', 'Garoua', 'Cameroun', 'FCFA', 'MoMo', 'Orange Money', 'MTN MoMo'}
NOMMES = {'labelText', 'hintText', 'helperText', 'tooltip', 'texte', 'label', 'title', 'text',
          'semanticsLabel', 'sousTitre', 'titre', 'message'}
TEXT_WIDGETS = {'Text', 'SelectableText'}


def dans_perimetre(rel):
    return not any(rel.startswith(e) or rel == e for e in EXCLUS)


def est_traduisible(txt):
    sans = re.sub(r'\{[^}]*\}', '', txt)
    if not re.search(r'[A-Za-zÀ-ÖØ-öø-ÿ]', sans):
        return False  # emoji, symbole, nombre, interpolations seules
    s = txt.strip()
    if s in TEXTES_EXCLUS:
        return False
    if ' ' not in s and re.search(r'[_{}/]', s):
        return False  # clé, chemin, mime : mesures_{p1}, image/webp
    if re.fullmatch(r'[a-z][A-Za-z0-9_]*', s):
        return False  # identifiant / clé
    if s.startswith('/') or s.startswith('http') or s.startswith('+237'):
        return False
    if re.fullmatch(r'[A-Z0-9_\- ]{1,12}', s) and ' ' not in s:
        return False  # 'XAF', 'CM', 'OK' → codes
    return True


def groupe_chaines(toks_sig, k):
    """chaînes adjacentes à partir de l'index k dans la liste sig"""
    g = [toks_sig[k]]
    while k + 1 < len(toks_sig) and toks_sig[k + 1][0] == 'str':
        k += 1
        g.append(toks_sig[k])
    return g


def texte_et_params(groupe):
    """texte source (avec {p}) et liste des expressions interpolées"""
    out = []
    params = []
    for t in groupe:
        x = t[3]
        if x['raw']:
            return None, None
        for kind, val in x['parts']:
            if kind == 'txt':
                out.append(unescape_dart(val))
            else:
                expr = val.strip()
                nom = expr if re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_]*', expr) else None
                if nom in ('context', 'this') or nom is None:
                    nom = f'p{len(params) + 1}'
                # doublon de nom → suffixe
                base = nom; i = 2
                while nom in [p[0] for p in params]:
                    nom = f'{base}{i}'; i += 1
                params.append((nom, expr))
                out.append('{' + nom + '}')
    return ''.join(out), params


def contexte(ts, k):
    """quel site ? retourne ('text'|'nomme'|'notif'|'fleche'|'ternaire'|'prive', info) ou None"""
    if k == 0:
        return None
    prev = ts[k - 1]
    pprev = ts[k - 2] if k >= 2 else None
    ppprev = ts[k - 3] if k >= 3 else None
    # a) Text('…')  → ident Text, '('
    if prev[0] == 'punct' and prev[2] - prev[1] == 1 and SRC[prev[1]] == '(' and pprev and pprev[0] == 'ident':
        nom = SRC[pprev[1]:pprev[2]]
        if nom in TEXT_WIDGETS:
            return ('text', nom)
        if nom.startswith('_') and nom[1:2].isupper() or nom.startswith('_') and len(nom) > 1:
            return ('prive', nom)
    # b/c) nommé : ident ':'  '…'
    if prev[0] == 'punct' and SRC[prev[1]] == ':' and pprev and pprev[0] == 'ident':
        nom = SRC[pprev[1]:pprev[2]]
        # ternaire déguisé ? (`x ? y : 'b'` → ident y précédé de '?')
        if ppprev and ppprev[0] == 'punct' and SRC[ppprev[1]] == '?':
            return ('ternaire', ':')
        if nom in NOMMES:
            if nom in ('titre', 'message'):
                return ('notif', nom) if appel_envoyer(ts, k) else ('nomme', nom)
            if nom == 'text':
                # Tab(text: '…') oui ; TextEditingController(text: 'Garoua') non
                ouv = ouvrante(ts, k)
                if ouv is None or ts[ouv - 1][0] != 'ident' or SRC[ts[ouv - 1][1]:ts[ouv - 1][2]] != 'Tab':
                    return None
            return ('nomme', nom)
        return None
    # f) argument positionnel suivant d'un appel privé : ',' '…' — on remonte à l'ouvrante
    if prev[0] == 'punct' and SRC[prev[1]] == ',':
        ouv = ouvrante(ts, k)
        if ouv is not None:
            j = ouv - 1
            if j >= 0 and ts[j][0] == 'ident':
                nom = SRC[ts[j][1]:ts[j][2]]
                if nom.startswith('_') and len(nom) > 1:
                    return ('prive', nom)
        return None
    # d) `=> '…'`
    if prev[0] == 'punct' and SRC[prev[1]] == '>' and pprev and pprev[0] == 'punct' and SRC[pprev[1]] == '=' and pprev[2] == prev[1]:
        return ('fleche', '=>')
    # e) `? '…'`
    if prev[0] == 'punct' and SRC[prev[1]] == '?':
        return ('ternaire', '?')
    # e) `: '…'` après une chaîne/paren/num elle-même après '?'
    if prev[0] == 'punct' and SRC[prev[1]] == ':' and pprev:
        if pprev[0] in ('str', 'num') or (pprev[0] == 'punct' and SRC[pprev[1]] in ')]'):
            # on remonte jusqu'au '?' correspondant au même niveau
            if trouve_interrogation(ts, k - 2):
                return ('ternaire', ':')
    return None


def ouvrante(ts, k):
    """index (dans ts) de la parenthèse ouvrante non fermée la plus proche avant k"""
    depth = 0
    j = k - 1
    while j >= 0:
        t = ts[j]
        if t[0] == 'punct':
            c = SRC[t[1]]
            if c in ')]}':
                depth += 1
            elif c in '([{':
                if depth == 0:
                    return j if c == '(' else None
                depth -= 1
        j -= 1
    return None


def trouve_interrogation(ts, j):
    """en remontant depuis j (même niveau), trouve-t-on un '?' avant ',' '(' ':' '=' ';' ?"""
    depth = 0
    while j >= 0:
        t = ts[j]
        if t[0] == 'punct':
            c = SRC[t[1]]
            if c in ')]}':
                depth += 1
            elif c in '([{':
                if depth == 0:
                    return False
                depth -= 1
            elif depth == 0 and c == '?':
                return True
            elif depth == 0 and c in ',;=':
                return False
        j -= 1
    return False


def appel_envoyer(ts, k):
    ouv = ouvrante(ts, k)
    if ouv is None:
        return False
    j = ouv - 1
    noms = []
    while j >= 0 and (ts[j][0] == 'ident' or (ts[j][0] == 'punct' and SRC[ts[j][1]] == '.')):
        if ts[j][0] == 'ident':
            noms.append(SRC[ts[j][1]:ts[j][2]])
        j -= 1
    return 'envoyer' in noms and 'NotificationService' in noms


def slug(txt, existants):
    s = unicodedata.normalize('NFKD', txt)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r'\{[^}]*\}', ' ', s)
    mots = re.findall(r'[A-Za-z0-9]+', s)
    mots = [m for m in mots if m.lower() not in ('le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'et', 'a', 'au', 'aux', 'en', 'l', 'd', 'the', 'of')][:5] or mots[:5]
    if not mots:
        mots = ['txt']
    base = mots[0].lower() + ''.join(m.capitalize() for m in mots[1:])
    base = base[:48]
    if not re.match(r'[a-z]', base):
        base = 'k' + base
    cle = base; i = 2
    while cle in existants:
        cle = f'{base}{i}'; i += 1
    return cle


def main():
    global SRC
    existant = {}
    if os.path.exists(OUT):
        existant = json.load(open(OUT, encoding='utf-8'))
    par_fr = {v['fr']: k for k, v in existant.items()}
    chaines = {k: dict(v, sites=[]) for k, v in existant.items()}
    fichiers = []
    for d, _, fs in os.walk(LIB):
        for f in sorted(fs):
            if f.endswith('.dart'):
                p = os.path.join(d, f)
                rel = os.path.relpath(p, ROOT)
                if dans_perimetre(rel):
                    fichiers.append((p, rel))
    nb_sites = 0
    for p, rel in sorted(fichiers):
        SRC = open(p, encoding='utf-8').read()
        toks = tokenize(SRC)
        ts = sig(toks)
        k = 0
        while k < len(ts):
            t = ts[k]
            if t[0] != 'str':
                k += 1; continue
            g = groupe_chaines(ts, k)
            ctx = contexte(ts, k)
            k += len(g)
            if ctx is None:
                continue
            if ctx[0] == 'prive' and ctx[1] in PRIVES_EXCLUS:
                continue
            fr, params = texte_et_params(g)
            if fr is None or not est_traduisible(fr):
                continue
            if re.fullmatch(r'\s*\{[^}]*\}\s*', fr):
                continue
            ligne = SRC[:g[0][1]].count('\n') + 1
            if fr in par_fr:
                cle = par_fr[fr]
            else:
                cle = slug(fr, chaines)
                par_fr[fr] = cle
                chaines[cle] = {'fr': fr, 'en': '', 'params': [n for n, _ in params], 'sites': []}
            chaines[cle]['sites'].append(f'{rel}:{ligne}:{ctx[0]}')
            nb_sites += 1
    # purge des clés sans site NI référence dans le code (Tr.s.cle / t.cle) :
    # une clé déjà appliquée n'a plus de littéral FR, elle doit survivre.
    refs = set()
    for p, _ in fichiers:
        refs |= set(re.findall(r'\b(?:Tr\.s|Tr\.fr|Tr\.en|t)\.([A-Za-z0-9]+)', open(p, encoding='utf-8').read()))
    for p in [os.path.join(LIB, 'l10n', 'tr.dart')]:
        pass  # (généré : ne compte pas comme référence)
    chaines = {k: v for k, v in chaines.items() if v['sites'] or k in refs}
    json.dump(chaines, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    sans_en = sum(1 for v in chaines.values() if not v['en'])
    print(f'{len(fichiers)} fichiers, {nb_sites} sites, {len(chaines)} chaînes uniques, {sans_en} sans traduction EN')


if __name__ == '__main__':
    main()
