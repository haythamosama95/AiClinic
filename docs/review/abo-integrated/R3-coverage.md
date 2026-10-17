# R3 source coverage and escalation closure

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; 2026-10-16 Africa/Cairo. **Complete with findings: 0 P0, 7 P1, 6 P2.** All 288 assigned regions are accounted for; no unread R3 region remains. Exact inclusive ranges and named readers are in [JSON](R3-coverage.json). This records actual reads, not inference from inventory or passing campaigns.

## Primary actual reads

| Path | Inclusive read ranges | Reader |
| --- | --- | --- |
| `abo/migrations/0002_checkout.sql` | 1–97 | coordinator + checkout reviewer |
| `abo/migrations/0003_notify_work.sql` | 1–115 | coordinator |
| `abo/src/clinic-api/billing-contact.ts` | 1–151 | checkout reviewer |
| `abo/src/clinic-api/checkouts.ts` | 1–922 | checkout reviewer + coordinator spot checks |
| `abo/src/clinic-api/offers.ts` | 1–145 | checkout reviewer |
| `abo/src/clinic-api/rate.ts` | 1–63 | checkout reviewer + coordinator |
| `abo/src/notify/intake.ts` | 1–532 | provider reviewer + coordinator spot checks |
| `abo/src/ops/index.ts` | 864–882, 1965–2095 | coordinator |
| `abo/src/provider/paymob/adapter.ts` | 1–960 | provider reviewer + coordinator spot checks |
| `abo/src/provider/paymob/client.ts` | 1–424 | provider reviewer + coordinator spot checks |
| `abo/src/provider/port.ts` | 1–138 | provider reviewer |
| `abo/src/provider/registry.ts` | 1–24 | provider reviewer |
| `abo/src/work/inquiry-budget.ts` | 1–246 | provider reviewer + coordinator |
| `abo/src/work/runner.ts` | 1–1009 | coordinator |
| `abo/src/worker.ts` | 1–446 | coordinator |
| `ai-platform/src/quota-do/index.ts` | 301–321, 1795–1806, 1836–1894 | coordinator; navigation misroute, R5 retains business review |
| `frontend/lib/features/ai/billing/abo_client.dart` | 1–338, 580–782 | checkout reviewer |
| `frontend/lib/features/ai/billing/billing_contact_form.dart` | 1–192 | checkout reviewer |
| `frontend/lib/features/ai/billing/checkout_screen.dart` | 1–433 | checkout reviewer + coordinator spot checks |
| `frontend/lib/features/ai/billing/offers_screen.dart` | 1–232 | checkout reviewer + coordinator spot checks |

## Supporting boundaries

| Path | Inclusive read ranges | Boundary |
| --- | --- | --- |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | 1–173 | actual step parent and layout |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 1–142 | polling token reuse |
| `frontend/lib/features/ai/billing/abo_client.dart` | 386–515 | 079:2 DTO mapping only, R7 full history consumer |
| `abo/src/work/sweep.ts` | 1–445 | checkout recovery and all inquiry call boundaries; not full reversal population review |
| `abo/src/work/grant.ts` | 350–398, 640–745, 926–975 | eligibility and scheduler only; R4 full grant |
| `abo/src/work/reversal.ts` | 430–562, 604–704, 865–912 | inquiry budget/callback evidence consumers only; R6 lifecycle |
| `abo/src/rebuild.ts` | 600–705 | provider inquiry budget call sites only; R9 algorithm |
| `abo/src/records/append.ts` | 1–38 | production insertFactLog helper only; excluded fixture helpers incidentally displayed, not analyzed |
| `abo/migrations/0001_records.sql` | 47–64 | contact schema |
| `abo/migrations/0004_grant.sql` | 1–72 | payment eligibility supporting schema |
| `abo/migrations/0005_reversal.sql` | 1–53 | inquiry spend/reversal identity schema |
| `abo/src/clinic-api/billing-reads.ts` | 1–312 | 079:2 response producer mapping; R7 full visible-history behavior |
| `abo/src/ops/index.ts` | 535–593 | 081:1 audit producer/helper |
| `ai-platform/src/vendor/entrypoint.ts` | 5040–5070 | 081:1 recordOperatorAction receiver only; inherited R2 auth |
| `abo/wrangler.toml` | 1–80, 105–105 | provider base values only outside first80; no full config audit |

## Ten escalation dispositions

| ID | Disposition | Producer → consumer evidence |
| --- | --- | --- |
| 076:1 | bounded source propagation closed; inherited R2 common version gate; ledger name R9 | worker.ts179–225 cross-host 404 and version/auth order; checkout snapshot carries negotiated version; exporter identity remains R9 |
| 077:1 | source propagation closed | checkouts.ts120–127 builds current integer browser v and606–634 stores claims.jti; provider preserves return URL; intake return validates/schedules only |
| 077:2 | external assumption retained | client intention expiration1800; adapter111–118,175–215 uses 30-minute intent; no live evidence of provider honoring expiry or ambiguity/discovery. C2/C4 explicit decision gates |
| 078:1 | source reviewed; defects C5/M2/M5 | POST 1MiB/60-per-IP constants; byte and admission races; runner76–104 conditional60s lease, C5 commit fencing/atomicity |
| 079:2 | bounded producer/consumer mapping closed; full business display owned R4/R6/R7/R9 | billing-reads.ts1–312 response shapes/cursor/tenant; abo_client.dart386–515 exact payment/subscription DTO fields; payment producer runner/classification boundary C6. No claim full history/reversal UI reviewed |
| 080:1 | reference-only/excluded scenario effect; source recovery evaluated | no scenario implementation read; source notify/runner/sweep crash traces C4/C5 |
| 080:2 | bounded identity producer read; effect decision handed to R6 | adapter418–609 parent/cumulative/fullness; intake420 and reversal supporting call consumer. R6 must resolve unsigned cumulative and child-parent selection with actual effects; no full R6 review claimed |
| 080:3 | source defect C7 | cap2 producer and all inquiry call-site consumers inline/confirm/sweep/reversal/rebuild; no excluded budget tests read |
| 081:1 | bounded producer/receiver propagation checked; recovery owner R9 | ops retry/cancel → operator_action then recordPlatformOperatorAction535–593 → entrypoint5040–5070 invokeClassH/audit; R2 already owns Access verification; crash audit outbox/dedupe concurrency remains R9/R8 |
| 091:1 | source mapping closed | checkouts.ts778–922 JSON shown-state/offer/null fields, reference open-list → abo_client18–338 and checkout screen polling/resume; missing hosted-page resume is frozen-contract limit |

## Completion and source-only limits

Reviewed AGENTS, complete review plan, R0 packet index/system map, R3 packet/manifest/escalation entries, R1/R2 canonical reports and compact handoffs, constitution and relevant amended architecture contracts/lifecycles/scheduling. Primary evidence comes from source at T. Supporting boundaries are deliberately limited; named later owners retain algorithmic closure. The quota-do admission release assignment is a navigation misroute: read as assigned, but full admission business review stays R5.

Static traces cover displayed offer/contact → snapshot/key → intention → authenticated notification hint → authoritative inquiry → payment/next-work; same/different-key retries, concurrent workers, lease loss, every durable-write crash edge, missing/forged/duplicate/late notifications, multiple capture identity, stored-order/amount/currency binding, all inquiry entry points and hosted return behavior. Findings/fix sequencing are canonical in [R3 report](R3-checkout-confirmed-payment.md); subreports retain detailed independent read evidence.

No application source changed, no tests/builds/lint/service/campaign/live provider research ran. No excluded implementation was analyzed. A mixed production helper file read incidentally displayed fixture-helper content after insertFactLog; that content was not used as correctness evidence. C2/C4 explicitly require provider integration owner decisions, with safe local containment and stop points. Actual provider expiration/account/deployment assumptions remain external. R0/R1/R2 status preserved; R4–R10 not executed.
