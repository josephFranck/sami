#!/usr/bin/env python3
"""Remplace les chaînes d'interface par `Tr.s.<cle>` et retire les `const`
qui les gouvernaient ; génère lib/l10n/tr.dart (FR + EN) à partir de
chaines.json.

  python3 appliquer.py            → applique sur lib/ (sites traduits seulement)
  python3 appliquer.py --dry f.dart → affiche le diff d'un fichier
  python3 appliquer.py --gen      → ne régénère que lib/l10n/tr.dart

Un site n'est transformé que si sa chaîne a une traduction `en` non vide
(sinon il reste tel quel : on avance écran par écran sans casser).
"""
import json, os, re, sys, difflib
sys.path.insert(0, os.path.dirname(__file__))
from dart_tok import tokenize, sig, unescape_dart, KEYWORDS
import extraire as X

ROOT = X.ROOT
LIB = X.LIB
CHAINES = os.path.join(os.path.dirname(__file__), 'chaines.json')
TR_DART = os.path.join(LIB, 'l10n', 'tr.dart')
IMPORT = "import 'package:sami/l10n/tr.dart';"


def consts_gouvernants(ts, src, k):
    """indices (dans ts) des tokens `const` qui gouvernent la chaîne ts[k]"""
    marques = []
    depth = 0
    j = k - 1
    while j >= 0:
        t = ts[j]
        if t[0] == 'punct':
            c = src[t[1]]
            if c in ')]}':
                depth += 1
            elif c in '([{':
                if depth > 0:
                    depth -= 1
                else:
                    # ouvrante englobante
                    i = j - 1
                    if c == '(':
                        # constructeur : [const] Nom(.Nom)*[<…>](
                        i = _sauter_generiques(ts, src, i)
                        while i >= 0 and ((ts[i][0] == 'ident' and src[ts[i][1]:ts[i][2]] not in KEYWORDS)
                                          or (ts[i][0] == 'punct' and src[ts[i][1]] == '.')):
                            i -= 1
                        if i >= 0 and ts[i][0] == 'ident' and src[ts[i][1]:ts[i][2]] == 'const':
                            marques.append(i)
                        # `(` d'un bloc de paramètres / condition : on continue
                    else:
                        # littéral [ ] ou { } : [const][<…>][ / {
                        i = _sauter_generiques(ts, src, i)
                        if i >= 0 and ts[i][0] == 'ident' and src[ts[i][1]:ts[i][2]] == 'const':
                            marques.append(i)
                        elif c == '{':
                            prev = src[ts[i][1]:ts[i][2]] if i >= 0 else ''
                            if prev not in ('=', '(', ',', ':', '[', '>', 'return') and not prev.endswith('=>'):
                                return marques  # bloc : fin de l'expression
            elif depth == 0 and c == ';':
                return marques
        elif depth == 0 and t[0] == 'ident' and src[t[1]:t[2]] in ('return', 'yield'):
            return marques
        elif depth == 0 and t[0] == 'ident' and src[t[1]:t[2]] == 'const' and _est_declaration(ts, src, j):
            # `const x = …` / `static const … =` : déclaration constante
            # gouvernant l'expression → deviendra `final`
            marques.append(-j - 1)  # négatif = déclaration
            return marques
        j -= 1
    return marques


def _est_declaration(ts, src, j):
    """ts[j] est `const` : suivi de `[Type] nom =` ? (sinon : constructeur
    ou littéral frère, `const Nom(` / `const [`)"""
    i = j + 1
    depth = 0
    while i < len(ts):
        t = ts[i]
        if t[0] == 'ident' or (t[0] == 'punct' and src[t[1]] in '.?'):
            i += 1; continue
        if t[0] == 'punct' and src[t[1]] == '<':
            depth += 1; i += 1; continue
        if t[0] == 'punct' and src[t[1]] == '>':
            depth -= 1; i += 1; continue
        if depth > 0:
            i += 1; continue
        return t[0] == 'punct' and src[t[1]] == '='
    return False


def _sauter_generiques(ts, src, i):
    """si ts[i] est '>' fermant des génériques, renvoie l'index avant le '<'"""
    if i >= 0 and ts[i][0] == 'punct' and src[ts[i][1]] == '>':
        depth = 0
        while i >= 0:
            c = src[ts[i][1]] if ts[i][0] == 'punct' else ''
            if c == '>': depth += 1
            elif c == '<':
                depth -= 1
                if depth == 0:
                    return i - 1
            i -= 1
    return i


def expression_tr(cle, params_exprs, notif):
    args = ', '.join(e for _, e in params_exprs)
    appel = f'Tr.s.{cle}' + (f'({args})' if params_exprs else '')
    if notif:
        # typée (Tr t) : NotificationService._dans teste `is String Function(Tr)`
        return f'(Tr t) => t.{cle}' + (f'({args})' if params_exprs else '')
    return appel


def transformer(src, chaines, par_fr):
    X.SRC = src
    toks = tokenize(src)
    ts = sig(toks)
    edits = []   # (start, end, replacement)
    consts = set()
    k = 0
    nb = 0
    while k < len(ts):
        t = ts[k]
        if t[0] != 'str':
            k += 1; continue
        g = X.groupe_chaines(ts, k)
        ctx = X.contexte(ts, k)
        k0 = k
        k += len(g)
        if ctx is None or (ctx[0] == 'prive' and ctx[1] in X.PRIVES_EXCLUS):
            continue
        fr, params = X.texte_et_params(g)
        if fr is None or not X.est_traduisible(fr) or re.fullmatch(r'\s*\{[^}]*\}\s*', fr):
            continue
        cle = par_fr.get(fr)
        if cle is None or not chaines[cle]['en']:
            continue
        rep = expression_tr(cle, params, ctx[0] == 'notif')
        edits.append((g[0][1], g[-1][2], rep))
        for ci in consts_gouvernants(ts, src, k0):
            consts.add(ci)
        nb += 1
    if not edits:
        return src, 0
    for ci in consts:
        if ci < 0:
            t = ts[-ci - 1]
            edits.append((t[1], t[2], 'final'))  # déclaration : const → final
            continue
        t = ts[ci]
        # supprimer `const` + l'espace qui suit
        end = t[2]
        while end < len(src) and src[end] in ' \t':
            end += 1
        edits.append((t[1], end, ''))
    edits.sort(key=lambda e: e[0], reverse=True)
    out = src
    for s, e, r in edits:
        out = out[:s] + r + out[e:]
    if IMPORT not in out:
        # après le dernier import
        m = list(re.finditer(r"^import [^\n]*;\n", out, re.M))
        if m:
            pos = m[-1].end()
            out = out[:pos] + IMPORT + '\n' + out[pos:]
        else:
            out = IMPORT + '\n' + out
    return out, nb


def verifier(src):
    """après transformation : aucun Tr.s/… gouverné par un const ; équilibre"""
    X.SRC = src
    toks = tokenize(src)
    ts = sig(toks)
    pb = []
    for k, t in enumerate(ts):
        if t[0] == 'ident' and src[t[1]:t[2]] == 'Tr' and k + 2 < len(ts) and src[ts[k + 2][1]:ts[k + 2][2]] == 's':
            if consts_gouvernants(ts, src, k):
                pb.append(src[:t[1]].count('\n') + 1)
    return pb


def dart_str(txt):
    """texte (avec {param}) → littéral Dart entre apostrophes avec $param"""
    out = []
    i = 0
    while i < len(txt):
        c = txt[i]
        if c == '{':
            j = txt.index('}', i)
            out.append('${' + txt[i + 1:j] + '}')
            i = j + 1; continue
        if c == '\\': out.append('\\\\')
        elif c == "'": out.append("\\'")
        elif c == '$': out.append('\\$')
        elif c == '\n': out.append('\\n')
        elif c == '\t': out.append('\\t')
        else: out.append(c)
        i += 1
    return "'" + ''.join(out) + "'"


def generer_tr(chaines):
    lignes = [
        "// GÉNÉRÉ par scripts/i18n/appliquer.py à partir de scripts/i18n/chaines.json",
        "// — ne pas éditer à la main : corriger chaines.json puis régénérer.",
        "//",
        "// Usage : Tr.s.cle  /  Tr.s.cle(param)  — suit LangueService (fr | en).",
        "// Les deux langues sont dans le code : aucune dépendance intl/gen-l10n.",
        "import 'package:sami/services/langue_service.dart';",
        "",
        "abstract class Tr {",
        "  const Tr();",
        "  static const Tr fr = _TrFr();",
        "  static const Tr en = _TrEn();",
        "  /// Traductions dans la langue courante.",
        "  static Tr get s => LangueService.instance.langue == 'en' ? en : fr;",
        "  /// Traductions pour une langue donnée ('fr' | 'en').",
        "  static Tr pour(String langue) => langue == 'en' ? en : fr;",
        "",
    ]
    cles = [k for k, v in chaines.items() if v['en']]
    for k in cles:
        p = chaines[k]['params']
        if p:
            lignes.append(f"  String {k}({', '.join('Object ' + n for n in p)});")
        else:
            lignes.append(f"  String get {k};")
    lignes.append("}")
    for cls, lang in (('_TrFr', 'fr'), ('_TrEn', 'en')):
        lignes += ["", f"class {cls} extends Tr {{", f"  const {cls}();"]
        for k in cles:
            v = chaines[k]
            p = v['params']
            txt = dart_str(v[lang])
            if p:
                lignes.append(f"  @override String {k}({', '.join('Object ' + n for n in p)}) => {txt};")
            else:
                lignes.append(f"  @override String get {k} => {txt};")
        lignes.append("}")
    os.makedirs(os.path.dirname(TR_DART), exist_ok=True)
    open(TR_DART, 'w', encoding='utf-8').write('\n'.join(lignes) + '\n')
    return len(cles)


def main():
    chaines = json.load(open(CHAINES, encoding='utf-8'))
    par_fr = {v['fr']: k for k, v in chaines.items()}
    # cohérence : les {params} du texte EN doivent être ceux du FR
    for k, v in chaines.items():
        if v['en']:
            pf = set(re.findall(r'\{([^}]*)\}', v['fr']))
            pe = set(re.findall(r'\{([^}]*)\}', v['en']))
            if pf != pe:
                print(f'✗ paramètres différents FR/EN pour {k}: {pf} vs {pe}'); sys.exit(1)
    if '--gen' in sys.argv:
        print('tr.dart :', generer_tr(chaines), 'clés'); return
    if '--dry' in sys.argv:
        f = sys.argv[sys.argv.index('--dry') + 1]
        src = open(f, encoding='utf-8').read()
        out, nb = transformer(src, chaines, par_fr)
        print(''.join(difflib.unified_diff(src.splitlines(1), out.splitlines(1), f, f + ' (traduit)')))
        print(f'{nb} sites ; const résiduels :', verifier(out)); return
    total = 0
    for d, _, fs in os.walk(LIB):
        for f in sorted(fs):
            if not f.endswith('.dart'): continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, ROOT)
            if not X.dans_perimetre(rel): continue
            src = open(p, encoding='utf-8').read()
            out, nb = transformer(src, chaines, par_fr)
            if nb:
                pb = verifier(out)
                if pb:
                    print(f'✗ {rel} : const résiduel aux lignes {pb}'); sys.exit(1)
                open(p, 'w', encoding='utf-8').write(out)
                total += nb
                print(f'{rel}: {nb}')
    print('tr.dart :', generer_tr(chaines), 'clés ;', total, 'sites transformés')


if __name__ == '__main__':
    main()
