#!/usr/bin/env python3
"""Tokenizer Dart minimal, suffisant pour repérer les chaînes à traduire,
leurs interpolations et le `const` qui les gouverne.

Token : (kind, start, end, extra)
  kind ∈ {'ws','comment','str','ident','num','punct'}
  str  : extra = {'quote': "'"|'"'|"'''"|'\"\"\"', 'raw': bool,
                  'parts': [('txt', s) | ('interp', expr_source)]}
"""
import re

KEYWORDS = set('''abstract as assert async await break case catch class const continue
covariant default deferred do dynamic else enum export extends extension external
factory false final finally for Function get hide if implements import in interface
is late library mixin new null on operator part required rethrow return set show
static super switch sync this throw true try typedef var void while with yield
sealed base when'''.split())

_IDENT = re.compile(r'[A-Za-z_$][A-Za-z0-9_$]*')
_NUM = re.compile(r'0[xX][0-9a-fA-F]+|\d+(\.\d+)?([eE][+-]?\d+)?')
_WS = re.compile(r'\s+')


def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        m = _WS.match(src, i)
        if m:
            toks.append(('ws', i, m.end(), None)); i = m.end(); continue
        if src.startswith('//', i):
            j = src.find('\n', i); j = n if j < 0 else j
            toks.append(('comment', i, j, None)); i = j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2); j = n if j < 0 else j + 2
            toks.append(('comment', i, j, None)); i = j; continue
        raw = False
        if c == 'r' and i + 1 < n and src[i + 1] in '\'"':
            raw = True; i += 1; c = src[i]
        if c in '\'"':
            start = i - 1 if raw else i
            j, extra = _read_string(src, i, raw)
            toks.append(('str', start, j, extra)); i = j; continue
        m = _IDENT.match(src, i)
        if m:
            toks.append(('ident', i, m.end(), None)); i = m.end(); continue
        m = _NUM.match(src, i)
        if m:
            toks.append(('num', i, m.end(), None)); i = m.end(); continue
        toks.append(('punct', i, i + 1, None)); i += 1
    return toks


def _read_string(src, i, raw):
    n = len(src)
    q = src[i]
    triple = src.startswith(q * 3, i)
    quote = q * 3 if triple else q
    j = i + len(quote)
    parts = []
    buf = []
    while j < n:
        if src.startswith(quote, j):
            j += len(quote); break
        ch = src[j]
        if not raw and ch == '\\':
            buf.append(src[j:j + 2]); j += 2; continue
        if not raw and ch == '$':
            if j + 1 < n and src[j + 1] == '{':
                # expression ${ ... } (peut contenir des chaînes imbriquées)
                k = j + 2; depth = 1
                while k < n and depth > 0:
                    if src[k] in '\'"':
                        k2, _ = _read_string(src, k, False); k = k2; continue
                    if src[k] == '{': depth += 1
                    elif src[k] == '}': depth -= 1
                    k += 1
                if buf: parts.append(('txt', ''.join(buf))); buf = []
                parts.append(('interp', src[j + 2:k - 1]))
                j = k; continue
            m = _IDENT.match(src, j + 1)
            if m:
                if buf: parts.append(('txt', ''.join(buf))); buf = []
                parts.append(('interp', m.group(0)))
                j = m.end(); continue
        if not triple and ch == '\n':
            break  # chaîne non terminée : on s'arrête
        buf.append(ch); j += 1
    if buf: parts.append(('txt', ''.join(buf)))
    return j, {'quote': quote, 'raw': raw, 'parts': parts}


def sig(toks):
    """tokens significatifs (sans ws/commentaires) avec index d'origine"""
    return [(k, s, e, x, idx) for idx, (k, s, e, x) in enumerate(toks) if k not in ('ws', 'comment')]


def unescape_dart(s):
    """texte Dart (déjà sans interpolations) → texte brut"""
    out = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            c = s[i + 1]
            out.append({'n': '\n', 't': '\t', "'": "'", '"': '"', '\\': '\\', '$': '$', 'r': '\r'}.get(c, c))
            i += 2
        else:
            out.append(s[i]); i += 1
    return ''.join(out)
