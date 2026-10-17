# R7 completed source coverage

**Complete with findings.** Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; completed 2026-10-17 Africa/Cairo. Workspace start `a2545299b82fd0c22f92d316fb4790ce47c159c9`; later production changes excluded. All source reads were pinned `git show T:path`. [Canonical report](R7-feed-projection-desktop-state.md) · [exact tuples/dispositions](R7-coverage.json) · [checkpoint](R7-checkpoint.md).

| Slice | Setting | Closed tuples | Lines | Evidence |
| --- | --- | ---: | ---: | --- |
| lead | GPT-6.1 Sol / explicit high | 46 | 1,680 | [coverage](R7-lead-coverage.json) · [report](R7-lead-review.md) |
| platform_sql | GPT-6.1 Sol / explicit medium | 44 | 1,815 | [coverage](R7-platform_sql-coverage.json) · [report](R7-platform_sql-review.md) |
| desktop_ui | GPT-6.1 Sol / explicit medium | 25 | 1,646 | [coverage](R7-desktop_ui-coverage.json) · [report](R7-desktop_ui-review.md) |
| desktop_transport | GPT-6.1 Sol / explicit medium | 89 | 2,828 | [coverage](R7-desktop_transport-coverage.json) · [report](R7-desktop_transport-review.md) |

Total: **204/204 exact primary tuples, 7,969 lines; zero unread; no primary gaps/overlaps**. Machine reconciliation compared every path/revision/start/end against R0 manifest, not just aggregate counts. Additional supporting reads are exact ranges in the slice records, including final SQL overrides/grants and producer/consumer seams. Lead high synthesis confirmed only selected difficult seams, without a duplicate whole-source pass.

Findings: **0 P0, 1 P1, 10 P2, 1 optional P3**. These counts exclude inherited canonical R1–R6 roots. All new recipes are implementation-ready with stated dependencies. Source unchanged; no tests/build/lint/services/live research/usage monitoring. No excluded implementation correctness review. Incidental embedded fixture/architecture navigation text was displayed but not analyzed or used; see slice disclosures. Generated localization implementations were excluded; original `.arb` inputs read at T.

## All 27 escalation dispositions

| ID | Disposition | Specific result |
| --- | --- | --- |
| 066:3 | inherited / propagated | First-tenant refusal remains 401 unauthenticated; desktop discovery/submit treats authentication failure as AI-only degraded state. R1-C2 owns cap defects; no clinical routing lock. |
| 067:4 | verified with findings | Queued unheld ascending and recent last12 descending-position fields match getCoverage/HTTP. PS1/PS2 snapshot fidelity and T2 snapshot.term consumer findings qualify live display. |
| 067:7 | verified / inherited roots | Feed carries ordered full snapshots and SQL lexicographic pairs; ABO atomicity gap A1. Final post-grant state R4-D1, band/lifecycle R5 and suspension kind R6-DM5 remain canonical. |
| 067:8 | verified / inherited roots | Receipt ledger_seq derives grant_applied clinic_seq; feed producer helper finds grant_applied snapshot. Receipt authority/application remains R4/R6; not recounted. |
| 067:9 | verified | Plan snapshot string-array capabilities copied through mirror; companion list display fields retain snapshot names. No new capability shape defect established. |
| 067:10 | verified | Vendor method rejects missing/noninteger/outside1..200 with limit_invalid and no events/receipt;200 accepted. HTTP feed default normalization is a separate route contract. |
| 067:12 | reference-only / excluded effect | Clarification transcription/workflow amendment; no additional production behavior. No workflow implementation reviewed. |
| 071:3 | verified / inherited roots | Pre-grant nil-identity tombstone emits no coverage event intentionally. Existing-grant void snapshots consumed; R6 reversal/lineage findings remain canonical. |
| 072:1 | verified with findings / inherited roots | Transfer events/new epochs dominate older sequence in SQL; A1 fixes ABO race; PS1 missing held-deletion publication. R6 owns package/import/retry/conservation roots, including original-grant lineage. |
| 073:1 | verified with findings | HTTP queued/recent list shapes match vendor list; current used from hot, historical from used_final. T2 rejects valid snapshot.term in desktop. |
| 073:2 | verified | Platform/shared helper and backend deterministic AIC reference use org-derived SHA-256/Crockford recipe; no lookup or token-provided display reference authority. |
| 079:2 | verified with findings | ABO live snapshot/fallback/null and five commercial notice predicates match; tenant/reference payment cursor and20-row ordering match. A2 historical plan name depends on current catalogue; UI2 refresh gap; R3-M6 amount formatter inherited. |
| 079:3 | verified with minor finding | Producer emits duplicate_payment,late_payment_honoured,payment_withheld,reversal_recorded,terms_held only. UI3 raw code rendering; no invented grant/denial authority. |
| 079:5 | verified | Missing fallback row yields snapshot null; no terms_held notice without held_count>0; flat nullable backend billing fields keep summary safe. |
| 088:1 | verified with finding / inherited limits | Administrator membership guard and accepted-version refusal/timestamp shape match. PS3 SELECT/upsert races throttle. R1 membership lifecycle authority roots remain canonical. |
| 088:2 | verified with findings | SQL emits member/in_app records and grace-only integer grace_days_left; model parses them. T1 disconnected fresh notices; UI3 raw administrator code/grace omission. |
| 088:3 | verified | Final SQL floors days toward ends_at only; absent/past dates null; no ends_soon from null. No consumer recomputes grace into term days. |
| 088:4 | verified with upstream finding | Final SQL stores snapshot reason, reads suspended before clock, nulls available/suspended reason and uses expired at read-time lapse. PS2 incorrect producer terminal reasons propagate unchanged. |
| 088:5 | verified | Billing guards membership administrator then extends shared status with flat nullable plan/dates/allowance/used/counts/reference/URLs. Desktop uses flat fields; no nested term or remaining wire field invented. |
| 088:6 | verified / inherited decoder limit | Projection deliberately stores no snapshot version; copies retain version. RPC echo uses request. Nested decoder compatibility remains R2-C3 canonical. |
| 088:7 | reference-only provenance; both production effects reviewed | P5.2a/b split changes ownership only. Both effective migrations reviewed together; no test/campaign implementation inspected. |
| 088b:1 | verified | Shared status as_of is read-time now(), present even absent projection, reused by billing; no write/readback timestamp confusion. |
| 089:1 | verified with finding | Exact allowance_exhausted/coverage_lapsed/coverage_unknown raw codes survive HTTP/SSE to callback. T1 shows successful refresh updates disconnected state, not open host. |
| 091:1 | verified / inherited limit | Checkout detail/open list parsed and resumed via CK reference; snapshot fields and null references handled. UI2 completion read refresh; lost redirect remains R3 frozen-contract recovery limit. |
| 092:1 | reference-only / excluded effect | Harness local cancellation/backdating/30-payments setup only. No harness/fixture implementation correctness review. |
| 095:1 | verified / inherited decoder limit | N to N+1 accepted/echoed N is intended; no false rollout failure claim. Unsupported/malformed DO reply handling remains R2-C2/C3; T2 separately fixes shape. |
| 095:2 | reference-only / excluded effect | Test-only public RPC receiver replacement changes no published production gate. Final published gates reviewed; no variant implementation inspected. |

## Completion and forward limits

Producer-to-display field mapping, page/order/freshness/error table and R9/R10 ownership are in the canonical report. R2-C2/C3 own envelope/version drift; R6-DM5 aliases are consumed here and historical rebuild handling remains R9. Later HEAD source was not substituted, so findings are tied to T even where later layout changes may repair them. Static review does not establish deployed ownership/ACLs, configuration, key registration, cron liveness or runtime behavior. R8–R10 remain unstarted; overall review in progress.
