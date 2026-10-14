"""Classify DataSHIELD function arguments by role and object class.

Usage: python3 -I classify.py <scratch_dir>
Reads args.csv, methods.tsv, exports.tsv, versions.tsv and src/; writes
args_classified.csv.
"""
import csv
import os
import re
import sys
from collections import defaultdict

import pandas as pd

S = sys.argv[1]
args = pd.read_csv(os.path.join(S, 'args.csv'), keep_default_na=False)
methods = pd.read_csv(os.path.join(S, 'methods.tsv'), sep='\t', header=None,
                      names=['package', 'track', 'kind', 'alias', 'target'])
exports = pd.read_csv(os.path.join(S, 'exports.tsv'), sep='\t', header=None,
                      names=['package', 'track', 'fn'])

CLIENT_PKGS = lambda p: p.endswith('Client') or p == 'dsHelper'
PATTERN_EXPORT = {'dsGeo', 'dsSwissKnifeClient'}

args['side'] = args['package'].map(lambda p: 'client' if CLIENT_PKGS(p) else 'server')

# ---------- scope: user-facing DataSHIELD functions ----------
meth_targets = defaultdict(set)
meth_alias = defaultdict(dict)  # (pkg, track) -> alias -> target fn
for r in methods.itertuples():
    tgt = r.target.split('::')[-1].strip()
    meth_targets[(r.package, r.track)].add(tgt)
    meth_alias[(r.package, r.track)][r.alias] = tgt
exp = defaultdict(set)
for r in exports.itertuples():
    exp[(r.package, r.track)].add(r.fn)


def in_scope(row):
    key = (row.package, row.track)
    if row.side == 'server':
        if meth_targets.get(key):
            return row.function in meth_targets[key]
        return row.function in exp.get(key, set())
    if row.package in PATTERN_EXPORT:
        return bool(re.match(r'^[A-Za-z]', row.function))
    return row.function in exp.get(key, set())


args['in_scope'] = [in_scope(r) for r in args.itertuples()]
# drop duplicate definitions (same function defined twice in a package)
args = args.drop_duplicates(['package', 'track', 'function', 'arg'])

# ---------- classification ----------
CLASS_PATTERNS = [
    ('data.frame', r'data[ ._-]?frames?\b|dataframes?\b|\bdf\b|phenotypes? table|\bdata ?sets?\b'),
    ('tibble', r'\btibbles?\b'),
    ('matrix', r'\bmatri(x|ces)\b'),
    ('list', r'\blists?\b(?! of \\code\{\\link\[DSI\])'),
    ('formula', r'\bformulae?\b|\bformulas\b'),
    ('model', r'\bmodels?\b|\bglm(er)?\b|\blmer\b|coxph object|survfit|regression object|fitted object|\bfit\b'),
    ('factor', r'\bfactors?\b|categorical'),
    ('vector', r'\bvectors?\b|\bvariables?\b|\bcolumns?\b|\bcovariates?\b'),
    ('resource', r'\bresources?\b'),
    ('bioc/omics object', r'ExpressionSet|SummarizedExperiment|ExposomeSet|\bGDS\b|\bVCF\b|eSet|SNP|genotype|imaging|image'),
]

NEWOBJ_NAME_RE = re.compile(r'^(new[._]?(df|data|tbl|var|col|obj)[._]?name|newobj|new\.?obj|newobject|new\.object|new\.name|newname|new\.var|newvar|output\.?name|out\.?name|outname|output|newobj\.name|new_obj|newobj_name|output_name|new\.col|new\.df\.name|name\.new)', re.I)
NEWOBJ_DOC_RE = re.compile(r'(name (of|for) the (new|output|created|resulting|generated|assigned)|(new|output|resulting) (object|variable|data ?frame|vector|table|tibble)|object (to be )?(created|assigned|generated|stored)|(created|assigned|stored|saved) (on|in) the (data )?servers?|newobj)', re.I)
CONN_RE = re.compile(r'^(datasources?\w*|conns?|connections?|ds\.?conns?|opals?)$', re.I)
PLUMB_RE = re.compile(r'session|handle|cursor|manifest|_json$|operation_id|request_|chunk|symbol|token|nonce|sha256|batch_', re.I)
CHOICE_DOC_RE = re.compile(r'can be set as|one of the allowable|one of (the following|\")|either \"|\"[^\"]+\",? (or|and) \"|\'[^\']+\',? or \'', re.I)
NUM_DOC_RE = re.compile(r'hyper-?parameter|\blambda\b|threshold|\bnumber of\b|percentage|proportion|tolerance|iterations?|maximum|minimum|\bsize\b|degrees of freedom|confidence level|\balpha\b', re.I)


def norm_doc(d):
    d = re.sub(r'\\(code|link|strong|emph|item|bold|sQuote|dQuote)\{', '', d)
    return d.replace('}', '').replace('{', '')


def classify(row):
    a, doc, dflt = row.arg, norm_doc(row.param_doc), row.default
    low = doc.lower()
    if a == '...':
        return 'dots', '', 'high', 'dots'
    if CONN_RE.match(a) or re.search(r'DSConnection|opal connection|login object', doc):
        return 'connection', '', 'high', 'name/doc'
    if a == 'type' and re.search(r'split|combin', low + ' ' + dflt.lower()) or \
            (re.search(r"\bsplit\b", low) and re.search(r'combine', low)):
        return 'output_type', '', 'high', 'split/combine'
    if re.search(r'check', a, re.I):
        return 'checks_flag', '', 'high', 'name'
    if NEWOBJ_NAME_RE.match(a) or (NEWOBJ_DOC_RE.search(doc) and not re.search(r'^logical', low)):
        cls = obj_class(doc)[0]
        return 'new_object_name', cls, 'high' if NEWOBJ_NAME_RE.match(a) else 'medium', 'name' if NEWOBJ_NAME_RE.match(a) else 'doc'
    if PLUMB_RE.search(a):
        return 'protocol_plumbing', '', 'medium', 'name'
    if CHOICE_DOC_RE.search(doc) and not obj_class(doc)[0]:
        return 'method_choice', '', 'medium', 'doc lists options'
    if a.lower() in ('method', 'methods', 'algorithm', 'option', 'options', 'approach', 'test', 'test.type', 'method.type', 'alternative', 'family', 'link', 'distribution', 'metric', 'mode', 'how') or \
            re.match(r'^c\("[^"]+"\s*,', dflt):
        return 'method_choice', '', 'medium', 'name/default'
    if dflt in ('TRUE', 'FALSE', 'T', 'F') or re.match(r'^(a |an )?(boolean|logical|if true|if false)', low):
        return 'logical_flag', '', 'high', 'default/doc'
    if re.search(r'seed', a, re.I):
        return 'seed', '', 'high', 'name'
    if re.match(r'^(a |an |the )?(single |scalar |positive |non-negative )?(numeric value|integer|number of|length of|real number|numeric scalar|numerical value)', low):
        return 'numeric_param', '', 'high', 'doc'
    # reference to a column inside a data frame (string), as opposed to an object
    if re.search(r'column names?|names? of (the |a )?(columns?|variables?) (in|of|within|that|holding|containing)|variable names?|'
                 r'denoting the column|name of the (outcome|exposure|mediator|treatment|id|time|status|event|grouping|strata) (variable|column)|'
                 r'columns? (to|by) (be )?(select|sort|group|use)', low):
        return 'variable_names', 'column name(s)', 'medium', 'doc'
    # object reference (input object on the servers)
    if re.match(r'^(a |an )?numeric\b(?! (or factor )?(vector|variable))', low):
        return 'numeric_param', '', 'medium', 'doc'
    cls, conf, ev = obj_class(doc)
    if cls:
        # vectors of values passed from the client ("vector of initial values",
        # "numeric vector specifying knot locations") are parameters, not server objects
        if cls in ('vector', 'factor') and not re.search(r'\bnames?\b|variable|server|column|object|covariate', low):
            return 'value_param', '', 'medium', 'doc'
        return 'input_object', cls, conf, ev
    if re.search(r'name of (the |a |an )?(input |server-side )?object', low):
        return 'input_object', 'any object', 'medium', 'doc'
    if NUM_DOC_RE.search(doc):
        return 'numeric_param', '', 'medium', 'doc'
    if re.match(r'^-?[0-9.eE]+L?$', dflt) or re.match(r'^(a |an )?(numeric|integer|number|positive|non-negative|single number)', low):
        return 'numeric_param', '', 'high' if doc else 'medium', 'default/doc'
    # name heuristics (no doc)
    nm = a.lower()
    guess = None
    if re.match(r'^(x|y|z|var|variable|vec|vector|x\d|y\d|var\d|v\d|input\.var|input)$', nm):
        guess = 'vector'
    elif re.match(r'^(df|data|dataframe|data\.frame|df\.name|dataset|table|tbl|data\.name|df\d|.*\.df)$', nm):
        guess = 'data.frame' if 'tbl' not in nm else 'tibble'
    elif re.match(r'^(mat|matrix|m)$', nm):
        guess = 'matrix'
    elif re.match(r'^(formula|form|fml)$', nm):
        guess = 'formula'
    elif re.match(r'^(model|mod|fit|glm\.?obj)$', nm):
        guess = 'model'
    elif re.match(r'^(resource|res)$', nm):
        guess = 'resource'
    if guess:
        return 'input_object', guess, 'low', 'name-only'
    if dflt.startswith('"') or dflt.startswith("'"):
        return 'string_param', '', 'low', 'default'
    if dflt == 'NULL' or dflt == '':
        return 'unknown', '', 'low', 'no doc'
    return 'other_param', '', 'low', 'default'


def obj_class(doc):
    hits = []
    for cls, pat in CLASS_PATTERNS:
        m = re.search(pat, doc, re.I)
        if m:
            hits.append((m.start(), cls))
    if not hits:
        return '', '', ''
    hits.sort()
    distinct = {c for _, c in hits}
    # factor/vector are both "vector-like"; treat co-occurrence as not ambiguous
    conf = 'high' if len(distinct - {'vector', 'factor'}) <= 1 and len(distinct) <= 2 else 'medium'
    return hits[0][1], conf, 'doc'


res = [classify(r) for r in args.itertuples()]
args['role'] = [x[0] for x in res]
args['object_class'] = [x[1] for x in res]
args['confidence'] = [x[2] for x in res]
args['evidence'] = [x[3] for x in res]

# ---------- inherit classes for undocumented server args from calling client fns ----------
# map server fn -> client fn(s) that reference its alias, via client source scan
calls = defaultdict(set)  # (server_pkg, track, server_fn) -> {(client_pkg, client_fn)}
client_rows = args[(args.side == 'client') & args.in_scope].drop_duplicates(['package', 'track', 'function'])
all_alias = {}
for (pkg, trk), amap in meth_alias.items():
    for alias, tgt in amap.items():
        all_alias.setdefault((alias, trk), []).append((pkg, tgt))
file_cache = {}
for r in client_rows.itertuples():
    path = os.path.join(S, 'src', r.package, r.track, 'R', r.file)
    if path not in file_cache:
        with open(path, encoding='utf-8', errors='replace') as fh:
            file_cache[path] = fh.read()
    txt = file_cache[path]
    for m in re.finditer(r'([A-Za-z][A-Za-z0-9._]*DS[A-Za-z0-9._]*|[A-Za-z][A-Za-z0-9._]*)\s*\(', txt):
        name = m.group(1)
        for trk in (r.track, 'prod'):
            for spkg, tgt in all_alias.get((name, trk), []):
                calls[(spkg, trk, tgt)].add((r.package, r.function))
            if (name, trk) in all_alias:
                break

client_cls = {}
for r in args[(args.side == 'client') & args.in_scope & (args.object_class != '')].itertuples():
    client_cls[(r.package, r.track, r.function, r.arg)] = (r.role, r.object_class)

inherited = 0
for idx, r in args[(args.side == 'server') & args.in_scope & (args.confidence == 'low')].iterrows():
    for (cpkg, cfn) in calls.get((r.package, r.track, r['function']), set()):
        hit = client_cls.get((cpkg, r.track, cfn, r.arg)) or client_cls.get((cpkg, 'prod', cfn, r.arg))
        if hit:
            args.at[idx, 'role'], args.at[idx, 'object_class'] = hit
            args.at[idx, 'confidence'] = 'medium'
            args.at[idx, 'evidence'] = f'inherited from {cfn}'
            inherited += 1
            break
print('inherited server classes:', inherited)

# docs that point elsewhere: "see help for ds.lmerSLMA", "argument <x> in the call to ds.rep"
client_any = {}
for r in args[(args.side == 'client') & (args.role != 'unknown')].itertuples():
    client_any.setdefault((r.function, r.arg), (r.role, r.object_class))
ref_hits = 0
for idx, r in args[args.in_scope & (args.role == 'unknown')].iterrows():
    m = re.search(r'(?:see help for|call to|calls? to|argument of|argument in|for function)\s*\\?(?:code\{)?((?:ds|dh|dss)[A-Za-z0-9._]+)', r['param_doc'])
    if not m:
        continue
    fn = m.group(1).rstrip('.')
    am = re.search(r'<([A-Za-z0-9._]+)>', r['param_doc'])
    for cand in [r.arg] + ([am.group(1)] if am else []):
        hit = client_any.get((fn, cand))
        if hit:
            args.at[idx, 'role'], args.at[idx, 'object_class'] = hit
            args.at[idx, 'confidence'], args.at[idx, 'evidence'] = 'medium', f'doc refers to {fn}'
            ref_hits += 1
            break
print('resolved via doc references:', ref_hits)

args['called_from'] = ''
for idx, r in args[(args.side == 'server') & args.in_scope].iterrows():
    c = calls.get((r.package, r.track, r['function']))
    if c:
        args.at[idx, 'called_from'] = ';'.join(sorted(f'{p}::{f}' for p, f in c))

args.to_csv(os.path.join(S, 'args_classified.csv'), index=False)
sc = args[args.in_scope]
print('in-scope functions:', sc.drop_duplicates(['package', 'track', 'function']).shape[0],
      'args:', len(sc))
print(sc.groupby(['role']).size().sort_values(ascending=False).to_string())
print(sc.groupby(['confidence']).size().to_string())
