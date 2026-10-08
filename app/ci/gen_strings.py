import json, sys
d = json.load(open(sys.argv[1]))
extra = json.load(open(sys.argv[2]))
for lang in ('de', 'en'):
    d[lang].update(extra[lang])
def q(s): return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"
out = ['// Generated from the web app texts (src/i18n.tsx) plus app-only texts (ci/strings_extra.json).',
       '// Edit there and run ci/gen_strings.py, or edit here directly.', '', 'const Map<String, Map<String, String>> strings = {']
for lang in ('de', 'en'):
    out.append(f"  '{lang}': {{")
    for k in sorted(d[lang]):
        out.append(f'    {q(k)}: {q(d[lang][k])},')
    out.append('  },')
out.append('};')
open(sys.argv[3], 'w').write('\n'.join(out) + '\n')
print(len(d['de']), 'keys')
