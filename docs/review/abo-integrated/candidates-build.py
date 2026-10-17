#!/usr/bin/env python3
"""Regenerate metadata-only R0 inventory. Reads no excluded file contents."""
import subprocess,re,json,collections,pathlib
T='db9244fddfddc1905335fb8c7105328c15a0cc5e';B='c6cf2c3809a38e2a348f373e926cf2585cfcf291';H='d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f'
OUT=pathlib.Path(__file__).parent

def git(*a):return subprocess.check_output(['git',*a]).decode()
def source(p,rev=T):return git('show',f'{rev}:{p}')
def classify(p):
 if p.startswith('docs/testing/'):return 'excluded','Test/campaign documentation and captured reports excluded by §1.2'
 if p.startswith('e2e/'):return 'excluded','End-to-end campaign/harness tree excluded by §1.2'
 if p.startswith('ai-platform-viewer/'):return 'excluded','Entire viewer excluded by plan §1.2'
 if p.startswith(('docs/','specs/','.specify/','.cursor/')):return 'reference','Architecture/specification/provenance or agent/reference material; no documentation-quality audit'
 if re.search(r'(^|/)(tests?|testkit|fixtures?|goldens?|campaigns?|__tests__|harness|test-results|artifacts)(/|\.)|(?:^|[/_.-])(test|spec|campaign|smoke|acceptance|harness|eval)(?:[_.-]|/)|vitest|playwright|run_campaign|build-platform-for-hxw|setup-campaign|setup-test',p,re.I):return 'excluded','Test/harness/campaign/configuration/captured-evidence path excluded by §1.2'
 if p.startswith('.github/workflows/'):return 'excluded','CI workflow mechanics excluded by §1.2'
 if p.endswith('/settings_rail.dart'):return 'excluded','Incidental settings navigation label overflow fix (Expanded/ellipsis); no ABO state, authority, request or billing behavior'
 if p.endswith('/settings_page.dart'):return 'excluded','Incidental generic settings scroll container; no ABO state, authority, request or billing behavior'
 if re.search(r'app_localizations(?:_\w+)?\.dart$',p):return 'excluded','Generated localization implementation; ARB inputs retained'
 if p.startswith('frontend/lib/') and not any(x in p for x in ['/ai/','/app/','/settings/','/l10n/','/core/rpc/','/core/contract_versions']):return 'excluded','Incidental non-ABO shared UI/product edit; not on ABO flow manifest'
 if p.startswith(('docs/','specs/','.specify/','.cursor/')) or p.endswith(('.md','.png','.svg','.pdf')):return 'reference','Architecture/specification/provenance or agent/reference material; no documentation-quality audit'
 if p.startswith(('abo/src/','abo/migrations/','ai-platform/src/','ai-platform/migrations/','backend/supabase/migrations/','frontend/lib/','packages/vendor-contracts/src/')):return 'primary source','Production source/schema/input in connected ABO surface (§5); removed implementations retained as baseline regions'
 if re.search(r'(package(?:-lock)?\.json|pubspec\.(yaml|lock)|wrangler.*toml|tsconfig.*json|supabase/config.toml|check-import-boundary|control-residue-guard|rebuild-abo)',p):return 'supporting runtime artifact','Dependency/export/binding/runtime configuration or operational security/rebuild executable (§5)'
 return 'excluded','Repository/tooling/nonproduction artifact outside bounded ABO production surface; path-only disposition'
def owner(p,s=''):
 n=s.lower();q=p.lower()
 if q=='ai-platform/src/worker.ts':return 'R9' if s=='scheduled' else 'R5'
 if q=='abo/src/worker.ts':
  if n in ['stampscheduledjobrun','pingheartbeat','signingkeygatemissing','mayberefreshsigningkeycheck','scheduled','env','preamble / imports / shared declarations']:return 'R9'
  return 'R2'
 if q.endswith('work/runner.ts'):return 'R9' if n in ['backoffms','newid','raisestaleconfirmalerts'] else 'R3'
 if q.endswith('vendor/entrypoint.ts'):
  if any(x in n for x in ['planversion','grantbinding','complimentarygrant','applygrant','grantrejected','granttransient','grantvoided','durationscale']):return 'R4'
  if n in ['getcoverage','inspectcoverage','listgrants','readcoverageevents','feedconsumerhealth']:return 'R7'
  if n in ['refreshcoveragesnapshot','loadplatformsigningkey']:return 'R9'
  if n in ['preamble / imports / shared declarations','method_class','isrecord','parserequestedversion','rejected','ok','conflict','bytesEqual'.lower(),'imported25519verifykey','isstringarray','base64urldecode','rowtodetail','operatorcredentialcount','readoperatorcredential','promotecredentialifdue','promoteallduecredentials','importsignerpublickey','stablejson','operationparamsmatch','hpaudittarget','bootstrapregister','envelopefromcontrolresult']:return 'R2'
 if q.endswith('quota-do/coverage.ts'):
  if any(x in n for x in ['snapshot','mirror','hydrate','reapply','restore','ledger','sqlnullable','loadplatformsigningkey']):return 'R9' if any(x in n for x in ['rebuild','refresh','hydrate','reapply','restore','ledger','snapshotentry','syncdoterms','hotactiveusage','snapshotused','snapshottermsinclude','snapshottermp','snapshottermused','mirrormatches','normaliz','loadplatformsigningkey']) else 'R7'
  if any(x in n for x in ['void','hpreplay','transfer','suspend','held','wipecoverage','adjustment']):return 'R6'
  if any(x in n for x in ['outbox','sql','updatehot','hotrow']):return 'R9'
  if any(x in n for x in ['term','boundary','boundaries','grant','grace','ceiling','receipt','allowance','coveragethrough','hotfields','coveragealarm']):return 'R4'
 if q.endswith('ops/index.ts'):
  if n=='handleops':return 'R8'
  if n=='handlehppost' or any(x in n for x in ['jwt','access','certs','assertion','credential','verifyhp','commitacceptedhp','parsehprequest','refusehp','decode','base64']):return 'R2'
  if any(x in n for x in ['transfer','chargeback','releasepayment','erase','deletetenant','deleteinstallation','suspend','resume','grantsforvoid','granthprelay']):return 'R6'
  if any(x in n for x in ['complimentary','grantrequest','grants','relayoutcome']):return 'R4'
  if any(x in n for x in ['payout','finding','periodfromsettled']):return 'R9'
  if n in ['handlepostretry','handlepostcancel','paymentfullyreversed']:return 'R3'
  return 'R8'
 if 'vendor-contracts/src/' in q:return 'R2'
 if 'backend/supabase/migrations/' in q:return 'R7' if any(x in q for x in ['coverage_feed_puller','read_time']) else 'R1'
 if '/migrations/' in q:
  for words,r in [(['issuer_key'],'R1'),(['checkout','notify_work'],'R3'),(['paid_grant','plan_version','grant.sql'],'R4'),(['usage_term','fallback','fingerprint'],'R5'),(['void','transfer','reversal'],'R6'),(['operator','hp_actions'],'R8')]:
   if any(x in q for x in words):return r
  return 'R9'
 if q.startswith('frontend/'):
  if any(x in q for x in ['billing_token','mint_port','app_rpc_invoker']):return 'R1'
  if any(x in q for x in ['contract_versions']):return 'R2'
  if any(x in q for x in ['checkout','billing_contact','offers_screen']):return 'R3'
  if 'abo_client' in q:
   return 'R3' if any(x in n for x in ['checkout','offer','contact']) else ('R2' if any(x in n for x in ['request','header','error']) else 'R7')
  return 'R7'
 if '/identity/' in q:return 'R1'
 if any(x in q for x in ['/control/','/support/']):return 'R8'
 if any(x in q for x in ['period-close','usage-summary']):return 'R5'
 if any(x in q for x in ['/coverage-read/','/coverage/view','billing-reads']):return 'R7'
 if '/coverage/calendar' in q or '/work/grant' in q:return 'R4'
 if any(x in q for x in ['/coverage/transfer','/work/reversal','/work/sweep']):return 'R6'
 if '/clinic-api/auth' in q:return 'R1'
 if '/clinic-api/version' in q or 'contract-version' in q:return 'R2'
 if any(x in q for x in ['/provider/','/notify/','/clinic-api/','inquiry-budget']):return 'R3'
 if any(x in q for x in ['/alert/','/records/','/rebuild','/reconciliation/','/digest/','/watch/','/housekeeping/','/retention/','/rollup/','/dashboards/','/journal/']):return 'R9'
 if any(x in q for x in ['/vendor/entrypoint','/quota-do/','/ops/index','/work/runner','/worker.ts']):
  for words,r in [(['rebuild','reconcil','export','payout','finding','retention','housekeep','scheduled','recover'],'R9'),(['transfer','delete','void','reversal','held','sweep','adjust','suspend'],'R6'),(['issuer','tenantbinding','tenant_binding','servicekey','keyregistry','identity'],'R1'),(['passkey','ceremony','assertion','webauthn','access','authenticate','verify','version','replay','jws','canonical','operationhash'],'R2'),(['admit','admission','reserv','settle','fallback','alarm','usage','consume'],'R5'),(['feed','snapshotread','coverageview','readcoverage','billingread'],'R7'),(['grant','term','planversion','coverage','purchase','renew','calendar'],'R4'),(['checkout','payment','inquir','confirm','notify','lease','intention'],'R3')]:
   if any(x in n for x in words):return r
  if '/ops/' in q:return 'R8'
  if '/vendor/' in q:return 'R8'
  if '/quota-do/' in q:return 'R5'
  return 'R9' if q.startswith('abo/') else 'R5'
 if q.startswith('ai-platform/src/'):return 'R5'
 return 'R9'
num={}
for l in git('diff','--numstat',B,T).splitlines():
 a,d,p=l.split('\t');num[p]=(a,d)
items=[];regions=[];dependencies=[]
for l in git('diff','--name-status','--no-renames',B,T).splitlines():
 status,p=l.split('\t');cl,reason=classify(p);it=dict(path=p,status=status,classification=cl,reason=reason,additions=num.get(p,['?','?'])[0],deletions=num.get(p,['?','?'])[1]);items.append(it)
 if cl not in ['primary source','supporting runtime artifact']:continue
 rev=B if status=='D' else T;txt=source(p,rev);lines=txt.splitlines();it['line_count']=len(lines);it['primary_owner']=owner(p)
 # Symbol-delimited contiguous navigation partitions. Every line, including imports/schema/dispatch, gets an owner.
 marks=[(1,'preamble / imports / shared declarations')]
 for i,line in enumerate(lines,1):
  m=re.match(r'^(?:(?:export|default|async|abstract)\s+)*(?:function|class|interface|type|enum|const)\s+(\w+)',line)
  if not m and ('vendor/entrypoint.ts' in p or p.endswith('worker.ts') or p.endswith('quota-do/index.ts')):m=re.match(r'^  (?:(?:private|public|protected|static|async|override|readonly)\s+)*(\w+)\s*\([^;]*',line)
  if not m:m=re.match(r'(?i)^create\s+(?:or\s+replace\s+)?(?:table|function|view|policy|trigger|index)\s+(?:if\s+not\s+exists\s+)?([^\s(]+)',line)
  if m and i>1 and m.group(1) not in ['if','for','while','switch','catch','return','throw','await','else','try','do','super']:marks.append((i,m.group(1)))
 marks=sorted(dict(marks).items())
 diff=git('diff','--unified=0','--no-renames',B,T,'--',p);hunks=[]
 for old,oc,new,nc in re.findall(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',diff,re.M):
  start,count=(int(old),int(oc or 1)) if status=='D' else (int(new),int(nc or 1));hunks.append((start,count))
 for j,(start,symbol) in enumerate(marks):
  end=marks[j+1][0]-1 if j+1<len(marks) else len(lines)
  changed=any((a<=end and a+max(c,1)-1>=start) for a,c in hunks)
  regions.append(dict(path=p,revision=rev,start=start,end=end,symbol=symbol,primary_owner=owner(p,symbol),changed=changed,ownership_basis='§5 path/symbol routing; inventory assignment, not correctness evidence'))
 # Resolve literal relative imports only, without opening supporting contents.
 for imp in re.findall(r'''(?:from\s*|import\s*)['"](\.[^'"]+)['"]''',txt):
  base=pathlib.PurePosixPath(p).parent/imp
  import posixpath
  base=posixpath.normpath(str(base));options=[base,base+'.ts',base+'.dart',base+'/index.ts',re.sub(r'\.js$','.ts',base)]
  for dp in options:
   if subprocess.run(['git','cat-file','-e',f'{T}:{dp}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
    if dp not in [x['path'] for x in items] and dp not in [x.split('\t')[-1] for x in git('diff','--name-status','--no-renames',B,T).splitlines()]:dependencies.append(dict(path=dp,caller=p,owner=owner(p),disposition='unchanged supporting dependency; read only as required by owned invariant'))
    break
# Billing dispatch has distinct wire gates and read/write routes, navigated at T.
newregions=[]
for r in regions:
 if r['path']=='abo/src/worker.ts' and r['symbol']=='handleBillingV1':
  for a,b,n,o in [(207,226,'handleBillingV1: version/auth/rate gate','R2'),(227,230,'handleBillingV1: offers route','R3'),(231,238,'handleBillingV1: subscription/payments read routes','R7'),(239,293,'handleBillingV1: contact/checkout routes and tail','R3')]:
   rr=dict(r);rr.update(start=a,end=b,symbol=n,primary_owner=o);newregions.append(rr)
 else:newregions.append(r)
regions=newregions
# A dispatcher/helper has one primary owner for the complete body. Other flow
# owners follow their call sites as supporting context; no line is unowned.
for r in regions:
 p=r['path']; peers=[]
 if 'vendor/entrypoint.ts' in p:peers=['R1','R2','R4','R6','R7','R8','R9']
 elif 'quota-do/' in p:peers=['R4','R5','R6','R7','R9']
 elif p.endswith('ops/index.ts'):peers=['R2','R3','R4','R6','R8','R9']
 elif p.endswith('worker.ts'):peers=['R2','R3','R5','R7','R8','R9']
 r['supporting_consumers']=[v for v in peers if v!=r['primary_owner']]
for it in items:
 if 'primary_owner' in it:it['region_owners']=sorted({r['primary_owner'] for r in regions if r['path']==it['path']})
meta=dict(target=T,baseline=B,history=H,scope='Static R0 metadata/source navigation only; excluded contents not read',ownership_status='Complete primary assignment by contiguous symbol/SQL-definition ranges; shared helpers and dispatcher bodies have one accountable owner plus supporting consumers',candidates=items)
(OUT/'candidates.json').write_text(json.dumps(meta,indent=2)+'\n');(OUT/'regions.json').write_text(json.dumps(dict(target=T,baseline=B,regions=regions,unchanged_dependencies=dependencies),indent=2)+'\n')
counts=collections.Counter(x['classification'] for x in items);owners=collections.Counter()
for r in regions:owners[r['primary_owner']]+=r['end']-r['start']+1
(OUT/'candidates.md').write_text(f'# R0 candidate inventory\n\nTarget `{T}`; baseline `{B}`; history `{H}`.\n\nGenerated by [candidates-build.py](candidates-build.py); machine data: [candidates.json](candidates.json), [regions.json](regions.json). All {len(items)} B..T candidates receive an explicit classification/reason, including deletions. No excluded contents were read. No correctness review or tests/builds performed.\n\nCounts: '+', '.join(f'{k}: {v}' for k,v in sorted(counts.items()))+'.\n\n'+ '\n'.join(f'- {x["status"]} `{x["path"]}` — **{x["classification"]}**: {x["reason"]}'+(f'; default owner {x["primary_owner"]}, {x["line_count"]} lines' if 'primary_owner' in x else '') for x in items)+'\n')
(OUT/'regions.md').write_text(f'# R0 region ownership navigation\n\nTarget `{T}`; deleted files use baseline `{B}`.\n\n[Machine inventory](regions.json) assigns contiguous exact line ranges, a primary phase, and whether each range intersects a changed hunk. Imports, declarations, shared helpers and trailing dispatch are retained. Deleted implementations are assigned at baseline coordinates. Relative imports identify unchanged supporting dependencies without opening them.\n\n**Ownership assignment status: complete; supporting dependency discovery bounded.** Each retained/deleted line has exactly one primary owner. Declarations and shared long-file methods were navigated by symbol; complete dispatcher bodies have one owner, with peer flow phases listed as supporting consumers. Owners must review their full assigned range, including any policy inside a dispatcher. Literal relative-import discovery is a navigation aid, not an exhaustive call graph; dynamically resolved and Dart package imports must be traced during source review. Spec provenance is provided separately. No correctness review conclusion follows from this inventory.\n\nAssigned lines (includes supporting runtime artifacts and baseline deletions):\n\n'+ '\n'.join(f'- {k}: {v}' for k,v in sorted(owners.items()))+'\n\nReview-time continuation: follow nonliteral/package imports and SQL final-definition overrides as needed for each owned invariant. Phase packets attach spec provenance separately. Broad dispatcher methods remain owned as a full body; supporting consumers do not relieve the primary owner of that body.\n')
print(json.dumps(dict(counts=counts,regions=len(regions),dependencies=len(dependencies),assigned_lines=owners)))

with (OUT/'regions-details.md').open('w') as f:
 f.write(f'# Exact region assignments\n\nTarget `{T}`; deleted implementations at `{B}`. Full bodies include imports, shared helpers and dispatch tails. `changed` means intersection with a B..T hunk, not the only source to read.\n\n| Path | Lines | Symbol/declaration | Primary | Changed |\n| --- | --- | --- | --- | --- |\n')
 for r in regions:f.write(f'| `{r["path"]}` | {r["start"]}–{r["end"]} | `{r["symbol"]}` | {r["primary_owner"]} | {r["changed"]} |\n')
# Structural inventory validation only; no application tests are run.
for it in items:
 if 'line_count' not in it:continue
 rr=[r for r in regions if r['path']==it['path']]
 assert rr[0]['start']==1 and rr[-1]['end']==it['line_count'],it['path']
 assert all(a['end']+1==b['start'] for a,b in zip(rr,rr[1:])),it['path']
 assert all(r['primary_owner'] in ['R'+str(i) for i in range(1,10)] for r in rr),it['path']
# Distinguish review source sizing from lock/config metadata and baseline removals.
ci={x['path']:x for x in items};sizing=collections.defaultdict(collections.Counter)
for r in regions:
 sizing[r['primary_owner']]['deleted' if ci[r['path']]['status']=='D' else ci[r['path']]['classification']]+=r['end']-r['start']+1
(OUT/'regions-summary.json').write_text(json.dumps(dict(target=T,counts=sizing,candidate_counts=counts),indent=2)+'\n')
with (OUT/'regions.md').open('a') as f:
 f.write('\nSizing breakdown (full final regions, not diff additions):\n\n| Phase | Final primary source | Baseline deletion | Supporting runtime metadata |\n| --- | ---: | ---: | ---: |\n')
 for k,v in sorted(sizing.items()):f.write(f'| {k} | {v["primary source"]} | {v["deleted"]} | {v["supporting runtime artifact"]} |\n')
 f.write('\nUse two fresh sessions within R1 (SQL tenant/issuance definitions; then verifiers/registries and Dart consumers), R5 (DO admission/settlement state; then worker pipeline/capability/cache/error protocol), and R9 (durable recovery/rebuild; then scheduling/operations and runtime configuration). R8 fits one primary packet when its 1,951 baseline deletion lines are counted; inspect replacements as supporting flow context. R7 is near the upper sizing target and can split projection/feed SQL from desktop consumers if supporting reads exceed the budget. Lockfile lines are dependency metadata: inspect relevant resolved production versions/exports rather than treating them as 13,800 handwritten source lines.\n\nThe full `handleOps` dispatch body is R8 primary; R2 follows Access/version/HP routes, R3 follows retry/cancel/payment routes, R4 follows complimentary grant routes, R6 follows void/release/transfer/deletion routes, and R9 follows payout/finding routes as supporting seams. ABO worker billing gate (207–226), offers (227–230), subscription/payments (231–238), and contact/checkout (239–293) are separately assigned. Platform worker fetch and terminal/idempotency helpers are R5 primary; R2 validates perimeter/version use, R7 coverage/feed routes, R8 removed control paths, and R9 scheduled recovery as explicit cross-flow consumers.\n')
