import json
from pathlib import Path
root=Path(__file__).parent
r=json.loads((root/'regions.json').read_text())
for n in range(1,10):
 phase=f'R{n}'
 rows=[x for x in r['regions'] if x['primary_owner']==phase]
 deps=[x for x in r['unchanged_dependencies'] if x['owner']==phase]
 out={'target':r['target'],'baseline':r['baseline'],'phase':phase,'regions':rows,'unchanged_dependencies':deps}
 (root/f'manifest-{phase}.json').write_text(json.dumps(out,indent=2)+'\n')
 lines=[f'# {phase} bounded source manifest', '',f"Target: `{r['target']}`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.",'','| Path | Lines | Symbol / region | Revision |','| --- | --- | --- | --- |']
 for x in rows:
  lines.append(f"| `{x['path']}` | {x['start']}–{x['end']} | {x['symbol'].replace('|','/')} | {'T' if x['revision']==r['target'] else 'B deleted'} |")
 lines+=['','## Unchanged supporting dependencies','']
 for x in deps: lines.append(f"- `{x['path']}` ← `{x['caller']}`: {x['disposition']}")
 (root/f'manifest-{phase}.md').write_text('\n'.join(lines)+'\n')
