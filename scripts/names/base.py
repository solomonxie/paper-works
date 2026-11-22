"""Base list from SSA counts: names.zip unzipped to argv[1]; writes base.json to argv[2].

Recent (last 5 years) names by popularity, plus names that were common in any year since 1950.
"""
import collections, json, os, sys

src, out = sys.argv[1], sys.argv[2]
years = sorted(int(f[3:7]) for f in os.listdir(src) if f.startswith('yob'))
last = years[-1]
recent = collections.Counter()
by_sex = collections.defaultdict(collections.Counter)
peak = {}
classic = set()
for y in years:
    if y < 1950:
        continue
    rows = [l.strip().split(',') for l in open(os.path.join(src, f'yob{y}.txt'))]
    for sex in 'FM':
        ranked = [r for r in rows if r[1] == sex]
        for i, (name, _, n) in enumerate(ranked[:400]):
            classic.add(name)
    for name, sex, n in rows:
        n = int(n)
        if y > last - 5:
            recent[name] += n
            by_sex[name][sex] += n
        if n > peak.get(name, (0, 0))[1]:
            peak[name] = (y, n)

top = [n for n, _ in recent.most_common(4200)]
names = list(dict.fromkeys(top + sorted(classic)))
rank = {n: i + 1 for i, (n, _) in enumerate(recent.most_common())}
rows = []
for n in names:
    f, m = by_sex[n]['F'], by_sex[n]['M']
    share = f / (f + m) if f + m else None
    gender = 'u' if share is None or 0.15 < share < 0.85 else 'f' if share >= 0.85 else 'm'
    rows.append({'name': n, 'gender': gender, 'rank': rank.get(n), 'peak': peak[n][0]})
json.dump({'year': last, 'names': rows}, open(out, 'w'), indent=0)
print(len(rows), 'names; latest year', last)
