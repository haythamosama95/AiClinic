#!/usr/bin/env python3
"""SQL declaration/override navigation, not SQL correctness analysis."""
import subprocess,json,re,pathlib,collections
T='db9244fddfddc1905335fb8c7105328c15a0cc5e';B='c6cf2c3809a38e2a348f373e926cf2585cfcf291';out=pathlib.Path(__file__).parent
def git(*a):return subprocess.check_output(['git',*a]).decode()
changed={l.split('\t')[-1] for l in git('diff','--name-status',B,T).splitlines()}
paths=[p for p in git('ls-tree','-r','--name-only',T,'backend/supabase/migrations').splitlines() if p.endswith('.sql')]
# Only production migration declarations are inspected. Signatures are retained to
# distinguish overloads; CREATE OR REPLACE history remains explicit.
all=[]
for p in sorted(paths):
 text=git('show',f'{T}:{p}')
 for m in re.finditer(r'(?im)^\s*CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([\w.\"]+)\s*\((.*?)\)\s*(?:RETURNS|LANGUAGE)',text,re.S):
  all.append(dict(path=p,line=text.count('\n',0,m.start())+1,name=m.group(1),arguments=' '.join(m.group(2).split()),changed=p in changed))
names={d['name'] for d in all if d['changed']};tracked=[d for d in all if d['name'] in names]
by=collections.defaultdict(list)
for d in tracked:by[d['name']].append(d)
# Last-by-name is a navigation hint only; overloads and DROP FUNCTION must be read
# in migration order by R1/R7/R9, rather than pretending name equals signature.
obj=dict(target=T,baseline=B,scope='Production backend migration function declarations matching changed function names',definitions=tracked,limitations='Name-grouped history; overload signatures retained. DROP/ALTER/grants/RLS/trigger effects require primary region reading. Final resolution is per PostgreSQL signature and migration order, not this name-grouped last occurrence.')
(out/'regions-sql-definitions.json').write_text(json.dumps(obj,indent=2)+'\n')
s=f'# SQL definition navigation\n\nTarget `{T}`; baseline `{B}`.\n\nChanged SQL function names are traced through all production backend migration declarations. [Machine data](regions-sql-definitions.json) retains argument text and definition locations. No SQL correctness review was performed. R1 reviews issuer/tenant/auth functions and their grants/RLS; R7 reviews projection/status functions; R9 reads full migration consistency. Last declaration by name is only a locator: overloaded signatures and DROP/ALTER must be resolved in migration order.\n\n'
for name,ds in sorted(by.items()):
 s+=f'## `{name}`\n\n'+ '\n'.join(f'- `{d["path"]}:{d["line"]}`'+(' — changed migration' if d['changed'] else ' — unchanged supporting prior definition') for d in ds)+'\n\n'
s+='Coverage-feed puller/status migration remains R7 primary, with R1 supporting review of issuer helper calls and R9 migration/scheduling context. Canonical feed JWT migration is R1 primary. Read-time migration overrides `auth_internal.get_ai_status` and `public.get_ai_status`; R7 must read final read-time definitions instead of stopping at the earlier puller migration. This is navigation, not a finding.\n'
(out/'regions-sql-definitions.md').write_text(s)
print(len(tracked),len(names))
