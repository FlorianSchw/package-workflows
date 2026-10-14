"""Extract function definitions, formals and roxygen @param text from R sources.

Usage: python3 -I extract.py <src_root> <versions.tsv> <out.csv>
src_root layout: <src_root>/<package>/<prod|dev>/R/*.R
"""
import csv
import os
import re
import sys

DEF_RE = re.compile(r'([A-Za-z.][A-Za-z0-9._]*|`[^`]+`)\s*(<<-|<-|=)\s*function\s*\(')


def mask(src):
    """Return a copy of src with strings and comments replaced by spaces
    (same length), so bracket matching ignores them. Roxygen lines are kept
    separately by line lookups."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '#':
            j = src.find('\n', i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c in '"\'`':
            q = c
            j = i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == '\\' else 1
            for k in range(i + 1, min(j, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        else:
            i += 1
    return ''.join(out)


def split_top(s):
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    if ''.join(cur).strip():
        parts.append(''.join(cur))
    return parts


def roxygen_block(lines, def_line):
    """Collect contiguous #' lines directly above def_line (0-based)."""
    block = []
    i = def_line - 1
    # tolerate blank lines and plain comments between the block and the definition
    while i >= 0 and (not lines[i].strip() or
                      (lines[i].lstrip().startswith('#') and not lines[i].lstrip().startswith("#'"))):
        i -= 1
    while i >= 0:
        s = lines[i].lstrip()
        if s.startswith("#'"):
            block.append(s[2:])
        elif not s.strip() and i > 0 and lines[i - 1].lstrip().startswith("#'"):
            pass  # blank line inside a roxygen block
        else:
            break
        i -= 1
    return list(reversed(block))


def parse_params(block):
    params, cur, tags = {}, None, set()
    for ln in block:
        m = re.match(r'\s*@(\w+)\s*(.*)', ln)
        if m:
            tag, rest = m.group(1), m.group(2)
            tags.add(tag)
            cur = None
            if tag == 'param':
                pm = re.match(r'([^\s]+)\s*(.*)', rest)
                if pm:
                    names = [x.strip() for x in pm.group(1).split(',') if x.strip()]
                    for nm in names:
                        params[nm] = pm.group(2).strip()
                    cur = names
        elif cur:
            for nm in cur:
                params[nm] = (params[nm] + ' ' + ln.strip()).strip()
    return params, tags


def extract_file(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        src = fh.read()
    msk = mask(src)
    lines = src.split('\n')
    # brace depth per position, to keep top-level definitions only
    depth_at = []
    d = 0
    for ch in msk:
        depth_at.append(d)
        if ch == '{':
            d += 1
        elif ch == '}':
            d -= 1
    out = []
    for m in DEF_RE.finditer(msk):
        if depth_at[m.start()] != 0:
            continue
        name = src[m.start(1):m.end(1)].strip('`')
        # find matching paren of formals
        start = m.end() - 1
        dpt, j = 0, start
        while j < len(msk):
            if msk[j] == '(':
                dpt += 1
            elif msk[j] == ')':
                dpt -= 1
                if dpt == 0:
                    break
            j += 1
        formals_src = src[start + 1:j]
        formals_msk = msk[start + 1:j]
        def_line = src.count('\n', 0, m.start())
        params, tags = parse_params(roxygen_block(lines, def_line))
        # split on masked text, then map back to source spans
        pos = 0
        for idx, part in enumerate(split_top(formals_msk)):
            seg = formals_src[pos:pos + len(part)]
            pos += len(part) + 1
            if '=' in part:
                k = part.index('=')
                argname, default = seg[:k].strip(), seg[k + 1:].strip()
            else:
                argname, default = seg.strip(), ''
            argname = argname.strip('`')
            if not argname:
                continue
            out.append({
                'function': name,
                'position': idx + 1,
                'n_args': len(split_top(formals_msk)),
                'arg': argname,
                'default': re.sub(r'\s+', ' ', default),
                'param_doc': re.sub(r'\s+', ' ', params.get(argname, '')),
                'has_roxygen': bool(params) or bool(tags),
                'exported': 'export' in tags,
                'file': os.path.basename(path),
                'line': def_line + 1,
            })
    return out


def _brace(s, i):
    """s[i] == '{'; return index of matching '}'."""
    d = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s) and s[i + 1] in '{}':
            i += 2
            continue
        if s[i] == '{':
            d += 1
        elif s[i] == '}':
            d -= 1
            if d == 0:
                return i
        i += 1
    return len(s)


def rd_params(man_dir):
    """function name -> {arg: description} from man/*.Rd (fallback docs)."""
    out = {}
    if not os.path.isdir(man_dir):
        return out
    for f in os.listdir(man_dir):
        if not f.endswith('.Rd'):
            continue
        with open(os.path.join(man_dir, f), encoding='utf-8', errors='replace') as fh:
            rd = fh.read()
        rd = re.sub(r'(?m)^%.*$', '', rd)
        aliases = re.findall(r'\\alias\{([^}]*)\}', rd)
        m = re.search(r'\\arguments\{', rd)
        if not m:
            continue
        body = rd[m.end() - 1:_brace(rd, m.end() - 1)]
        params = {}
        for im in re.finditer(r'\\item\{', body):
            e1 = _brace(body, im.end() - 1)
            names = body[im.end():e1]
            if e1 + 1 < len(body) and body[e1 + 1] == '{':
                e2 = _brace(body, e1 + 1)
                desc = re.sub(r'\s+', ' ', body[e1 + 2:e2]).strip()
                for nm in names.split(','):
                    params[nm.strip()] = desc
        for a in aliases:
            out[a.strip()] = params
    return out


def main(src_root, versions_tsv, out_csv):
    versions = {}
    with open(versions_tsv) as fh:
        for row in csv.reader(fh, delimiter='\t'):
            versions[(row[0], row[1])] = (row[2], row[3])
    rows = []
    for pkg in sorted(os.listdir(src_root)):
        for ver in ('prod', 'dev'):
            rdir = os.path.join(src_root, pkg, ver, 'R')
            if not os.path.isdir(rdir):
                continue
            branch, version = versions.get((pkg, ver), ('', ''))
            rd = rd_params(os.path.join(src_root, pkg, ver, 'man'))
            for f in sorted(os.listdir(rdir)):
                if not f.lower().endswith('.r'):
                    continue
                for r in extract_file(os.path.join(rdir, f)):
                    r['doc_source'] = 'roxygen' if r['param_doc'] else ''
                    if not r['param_doc']:
                        d = rd.get(r['function'], {}).get(r['arg'], '')
                        if d:
                            r['param_doc'], r['doc_source'] = d, 'Rd'
                    r.update(package=pkg, track=ver, branch=branch, version=version)
                    rows.append(r)
    cols = ['package', 'track', 'branch', 'version', 'function', 'position', 'n_args',
            'arg', 'default', 'param_doc', 'doc_source', 'has_roxygen', 'exported', 'file', 'line']
    with open(out_csv, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print(len(rows), 'argument rows')


if __name__ == '__main__':
    main(*sys.argv[1:])
