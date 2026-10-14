"""Aggregate the classified argument inventory into naming summaries.

Usage: python3 -I aggregate.py <scratch_dir>
Writes summary.json and prints readable tables.
"""
import json
import os
import re
import sys
from collections import Counter

import pandas as pd

S = sys.argv[1]
d = pd.read_csv(os.path.join(S, 'args_classified.csv'), keep_default_na=False)
d = d[d.in_scope]

# "latest" view: dev where a dev track exists, else prod
has_dev = set(d[d.track == 'dev'].package)
latest = d[((d.track == 'dev') & d.package.isin(has_dev)) | ((d.track == 'prod') & ~d.package.isin(has_dev))].copy()
prod = d[d.track == 'prod'].copy()

out = {}


def style(name):
    if name == '...':
        return 'dots'
    if re.fullmatch(r'[a-z][a-z0-9]*', name):
        return 'single lowercase word'
    if '.' in name and '_' in name:
        return 'mixed . and _'
    if re.fullmatch(r'[a-z0-9]+(\.[a-z0-9]+)+', name, re.I) and not re.search(r'[a-z][A-Z]', name):
        return 'dot.case'
    if re.fullmatch(r'[a-z0-9]+(_[a-z0-9]+)+', name, re.I) and not re.search(r'[a-z][A-Z]', name):
        return 'snake_case'
    if re.fullmatch(r'[a-z]+([A-Z][a-z0-9]*)+', name):
        return 'camelCase'
    if re.search(r'[a-z][A-Z]', name) and ('.' in name or '_' in name):
        return 'camel + separator'
    if re.fullmatch(r'[A-Z][A-Za-z0-9]*', name):
        return 'Capitalised / UPPER'
    return 'other'


latest['argstyle'] = latest.arg.map(style)
nd = latest[latest.arg != '...']

# ---- scale ----
fn = latest.drop_duplicates(['package', 'function'])
out['scale'] = {
    'packages': int(latest.package.nunique()),
    'functions': int(len(fn)),
    'client_functions': int((fn.side == 'client').sum()),
    'server_functions': int((fn.side == 'server').sum()),
    'arguments': int(len(latest)),
    'distinct_arg_names': int(latest.arg.nunique()),
}

# ---- names per object class (input objects) ----
obj = latest[latest.role == 'input_object']
per_class = {}
for cls, g in obj.groupby('object_class'):
    c = g.groupby('arg').agg(n=('function', 'size'), pkgs=('package', 'nunique'),
                             client=('side', lambda s: int((s == 'client').sum())),
                             server=('side', lambda s: int((s == 'server').sum()))).sort_values('n', ascending=False)
    per_class[cls] = {
        'total_args': int(len(g)),
        'distinct_names': int(len(c)),
        'top': [dict(name=i, **{k: int(v) for k, v in r.items()}) for i, r in c.head(15).iterrows()],
        'high_conf_share': round(float((g.confidence == 'high').mean()), 2),
    }
out['per_class'] = per_class

# ---- other roles ----
roles = {}
for role in ['new_object_name', 'connection', 'output_type', 'checks_flag', 'method_choice', 'variable_names', 'seed']:
    g = latest[latest.role == role]
    c = g.groupby('arg').agg(n=('function', 'size'), pkgs=('package', 'nunique')).sort_values('n', ascending=False)
    roles[role] = {'total': int(len(g)), 'distinct_names': int(len(c)),
                   'top': [dict(name=i, n=int(r.n), pkgs=int(r.pkgs)) for i, r in c.head(15).iterrows()]}
out['roles'] = roles

# ---- collisions: same name, different object classes ----
coll = []
o2 = obj[obj.object_class != 'any object']
for name, g in o2.groupby('arg'):
    cc = g.object_class.value_counts()
    if len(cc) >= 2 and len(g) >= 3:
        coll.append({'name': name, 'n': int(len(g)), 'classes': {k: int(v) for k, v in cc.items()}})
coll.sort(key=lambda x: -x['n'])
out['collisions'] = coll[:20]

# ---- style ----
st = nd['argstyle'].value_counts()
out['style_overall'] = {k: int(v) for k, v in st.items()}
by_pkg = nd.groupby('package')['argstyle'].value_counts(normalize=True).unstack(fill_value=0).round(2)
out['style_by_package'] = by_pkg.to_dict(orient='index')
# style restricted to multi-word names (single words carry no separator info)
mw = nd[~nd['argstyle'].isin(['single lowercase word', 'dots'])]
out['style_multiword'] = {k: int(v) for k, v in mw['argstyle'].value_counts().items()}
out['style_multiword_by_package'] = {
    p: {k: int(v) for k, v in g['argstyle'].value_counts().items()} for p, g in mw.groupby('package')}

# ---- survey rules: current compliance ----
def share(mask, total):
    return {'compliant': int(mask.sum()), 'total': int(total), 'share': round(float(mask.mean()), 2) if total else None}


rules = {}
df_args = obj[obj.object_class == 'data.frame']
rules['data.frame -> df'] = share(df_args.arg == 'df', len(df_args))
vec = obj[obj.object_class.isin(['vector', 'factor'])]
rules['vector -> x'] = share(vec.arg == 'x', len(vec))
mat = obj[obj.object_class == 'matrix']
rules['matrix -> mat'] = share(mat.arg == 'mat', len(mat))
tb = obj[obj.object_class == 'tibble']
rules['tibble -> tbl'] = share(tb.arg == 'tbl', len(tb))
mo = obj[obj.object_class == 'model']
rules['model -> model'] = share(mo.arg == 'model', len(mo))
nw = latest[latest.role == 'new_object_name']
rules['new object -> newobj'] = share(nw.arg == 'newobj', len(nw))
cn = latest[latest.role == 'connection']
rules['connection -> datasources'] = share(cn.arg == 'datasources', len(cn))
# datasources last (or second to last before ...)
last_ok = []
for (p, f), g in latest[latest.side == 'client'].groupby(['package', 'function']):
    if 'datasources' not in set(g.arg):
        continue
    names = list(g.sort_values('position').arg)
    tail = names[-2:] if names[-1] == '...' else names[-1:]
    last_ok.append(tail[0] == 'datasources' if names[-1] != '...' else 'datasources' in tail)
rules['datasources is last argument (client)'] = share(pd.Series(last_ok), len(last_ok))
ck = latest[latest.role == 'checks_flag']
rules['checks flag -> checks'] = share(ck.arg == 'checks', len(ck))
mc = latest[(latest.role == 'method_choice')]
rules['method/algorithm -> method'] = share(mc.arg == 'method', len(mc))
ty = latest[latest.role == 'output_type']
rules['split/combined -> type'] = share(ty.arg == 'type', len(ty))
out['survey_rules'] = rules

# ---- function naming ----
fnl = latest.drop_duplicates(['package', 'function'])
cl = fnl[fnl.side == 'client']
sv = fnl[fnl.side == 'server']
out['function_naming'] = {
    'client ds.camelCase': share(cl['function'].str.match(r'^ds\.[a-z][A-Za-z0-9]*$'), len(cl)),
    'client other prefixes': {k: int(v) for k, v in cl['function'].str.extract(r'^([A-Za-z]+[._]?)')[0].value_counts().head(8).items()},
    'server *DS (exact pattern)': share(sv['function'].str.match(r'^[a-z][A-Za-z0-9]*DS[0-9]*$'), len(sv)),
    'server *DS.* or *DS* anywhere': share(sv['function'].str.contains('DS'), len(sv)),
}

# ---- prod -> dev renames ----
diffs = []
for p in sorted(has_dev):
    a = d[(d.package == p) & (d.track == 'prod')]
    b = d[(d.package == p) & (d.track == 'dev')]
    fa = a.groupby('function').arg.apply(list).to_dict()
    fb = b.groupby('function').arg.apply(list).to_dict()
    for f in sorted(set(fa) & set(fb)):
        if fa[f] != fb[f]:
            removed = [x for x in fa[f] if x not in fb[f]]
            added = [x for x in fb[f] if x not in fa[f]]
            diffs.append({'package': p, 'function': f, 'removed': removed, 'added': added,
                          'reordered': not removed and not added})
    diffs += [{'package': p, 'function': f, 'new_function': True} for f in sorted(set(fb) - set(fa))]
    diffs += [{'package': p, 'function': f, 'dropped_function': True} for f in sorted(set(fa) - set(fb))]
out['prod_dev_diffs'] = diffs

# ---- coverage of the classifier ----
out['classifier'] = {
    'roles': {k: int(v) for k, v in latest.role.value_counts().items()},
    'confidence': {k: int(v) for k, v in latest.confidence.value_counts().items()},
    'doc_coverage': round(float((latest.param_doc != '').mean()), 2),
}

with open(os.path.join(S, 'summary.json'), 'w') as fh:
    json.dump(out, fh, indent=1, default=str)

# ---- print ----
print(json.dumps(out['scale']))
for cls, v in sorted(per_class.items(), key=lambda kv: -kv[1]['total_args']):
    print(f"\n## {cls}: {v['total_args']} args, {v['distinct_names']} names, high-conf {v['high_conf_share']}")
    print('  ' + ', '.join(f"{t['name']}({t['n']}/{t['pkgs']}p)" for t in v['top'][:12]))
for role, v in roles.items():
    print(f"\n## role {role}: {v['total']} args, {v['distinct_names']} names")
    print('  ' + ', '.join(f"{t['name']}({t['n']}/{t['pkgs']}p)" for t in v['top'][:12]))
print('\n## collisions')
for c in out['collisions']:
    print(' ', c)
print('\n## style overall', out['style_overall'])
print('## style multiword', out['style_multiword'])
for p, v in out['style_multiword_by_package'].items():
    print('  ', p, v)
print('\n## survey rules')
for k, v in rules.items():
    print(f'  {k}: {v}')
print('\n## function naming', json.dumps(out['function_naming'], indent=1))
print('\n## prod->dev diffs:', len(diffs))
for x in diffs:
    print('  ', x)
print('\n', out['classifier'])
