"""Hitchcock's Bible Names Dictionary (1869, public domain, CCEL text) -> {name: meaning}. argv: txt, out."""
import json, re, sys

lines = open(sys.argv[1], encoding='utf-8', errors='ignore').read().splitlines()
out, name = {}, None
for line in lines:
    m = re.match(r'^ {3}([A-Z][a-z]+(?:-[a-z]+)*)\s*$', line)
    if m:
        name = m.group(1)
        continue
    m = re.match(r'^ {10}(\S.*)$', line)
    if m and name:
        out.setdefault(name, m.group(1).strip().rstrip('.'))
        name = None
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False, indent=0)
print(len(out), 'bible names')
