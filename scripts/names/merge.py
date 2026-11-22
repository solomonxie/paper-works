"""base.json + meta/*.jsonl + meta/chinese.jsonl -> src/content/names/{en,zh}.json. argv: work dir, out dir."""
import glob, json, os, re, sys

work, out = sys.argv[1], sys.argv[2]
TAGS = {'bible', 'saint', 'mythology', 'nature', 'flower', 'gem', 'virtue', 'royal', 'literary', 'celestial', 'place', 'surname', 'nickname', 'word'}
ZH_TAGS = {'nature', 'virtue', 'celestial', 'gem', 'flower', 'literary', 'classic', 'modern'}

base = {r['name']: r for r in json.load(open(os.path.join(work, 'base.json')))['names']}
meta = {}
for f in sorted(glob.glob(os.path.join(work, 'meta', 'batch-*.jsonl'))):
    for line in open(f):
        r = json.loads(line)
        meta[r['name']] = r
missing = [n for n in base if n not in meta]
assert not missing, f'{len(missing)} names without meaning, e.g. {missing[:5]}'

def root_meaning(meaning, depth=0):
    m = re.match(r'^(Form of|Short for) ([A-Z][a-z]+)$', meaning)
    if not m or depth > 3 or m.group(2) not in meta:
        return None
    root = meta[m.group(2)]['meaning']
    return root_meaning(root, depth + 1) or (None if re.match(r'^(Form of|Short for|Modern coinage|Origin uncertain)', root) else root)

en = []
for name, b in base.items():
    m = meta[name]
    meaning = m['meaning'].strip()
    root = root_meaning(meaning)
    if root:
        meaning = f'{meaning} · {root}'
    tags = [t for t in m.get('tags', []) if t in TAGS][:3]
    en.append([name, b['gender'], b['rank'], b['peak'], m['origin'], m['language'], meaning, ' '.join(tags)])

ZH_TAGS |= {'poetry', 'solarterm', 'idiom', 'popular', 'historical', 'famous', 'bible'}
zh, by_hanzi = [], {}
files = [os.path.join(work, 'meta', 'chinese.jsonl')] + sorted(glob.glob(os.path.join(work, 'meta', 'zh-*.jsonl')))
for f in files:
    for line in open(f):
        r = json.loads(line)
        tags = [t for t in r.get('tags', []) if t in ZH_TAGS]
        if r['hanzi'] in by_hanzi:
            row = by_hanzi[r['hanzi']]
            row[4] = ' '.join(dict.fromkeys(row[4].split() + tags))
            if r.get('source') and not row[5]:
                row[5] = r['source']
            continue
        row = [r['pinyin'], r['hanzi'], r['gender'], r['meaning'], ' '.join(tags), r.get('source', '')]
        by_hanzi[r['hanzi']] = row
        zh.append(row)

for fname, rows in (('en.json', en), ('zh.json', zh)):
    rows = [r[:5] if len(r) == 6 and not r[5] else r for r in rows] if fname == 'zh.json' else rows
    with open(os.path.join(out, fname), 'w') as f:
        f.write('[\n' + ',\n'.join(json.dumps(r, ensure_ascii=False) for r in rows) + '\n]\n')
print(len(en), 'English,', len(zh), 'Chinese')
