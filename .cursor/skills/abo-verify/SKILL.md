---
name: abo-verify
description: Implement band verification scenarios directly from the ABO delivery plan (§3.2.1–§3.10.1 and §3.13), without Spec Kit. Parallelize scenarios, layers, and independent bands where dependencies allow. Use after slice implementation or when the user asks to run band verification or MC chain tests.
disable-model-invocation: true
---

# ABO — Verify (direct implementation)

Band verification is **not** Spec Kit work. Do **not** run specify/plan/tasks for `M1-V7`,
`Q-E2`, `MC-14`, etc. Read the delivery plan, write tests and harness code, run them, update §8
status.

## User Input

```text
$ARGUMENTS
```

First argument:

- **Band letter** — `M`, `N`, `O`, `P`, `Q`, `R`, `S`, `T`, or `U` → implement that band's
  verification subsection (§3.2.1–§3.10.1).
- **`chain`** or **`master`** → §3.13 master chain `MC-01`…`MC-22` and negatives `MC-N1`…`MC-N9`
  (requires full local stack).
- **Optional filters** — `M unit`, `Q x-e2e`, `R-E` (e2e-seq only), `O2-V` (rows for one slice).

If empty, list bands with slice **Impl** status from §8.1 and recommend the highest band whose slices
are complete but Unit/E2E-seq/X-E2E columns are open.

## Sources

1. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` — the band's §3.x.1 table,
   §3.11 coverage rules, §3.13 when doing `chain`, §8 implementation status.
2. ABO architecture sections referenced by scenarios (read minimally per row).
3. Existing test layout in the codebase — extend files; do not duplicate §3.12 floor tests unless a
   matrix row explicitly extends them.

Do not create `specs/<NNN>/` entries for verification rows.

## Subagent models

- **Orchestration, unit batches, x-e2e batches, parallel bands:** Grok 4.7 High —
  `model: "grok-4.7-high"`, `subagent_type: "generalPurpose"`.
- **`## ESCALATION` (architecture/plan conflict):** Kimi K3 High — `model: "kimi-k3-high"`. After
  resolution, continue implementation batches on Grok.

## Layer rules

| Layer | ID pattern | Ordering | Parallelism |
| --- | --- | --- | --- |
| `unit` | `<slice>-V<n>` | Independent rows parallelize by default | Spawn parallel subagents per file or per row batch |
| `e2e-seq` | `<band>-E<n>` | **Strict order** within the band — each step uses prior state | One sequential owner; parallel only prep/fixtures |
| `x-e2e` | `<band>-X<n>` | Depends on stack; MC chain has global order | Parallel only across bands when stacks are isolated |

§3.11 rules apply: verification-order step failures, contract artifacts executable on both sides, 409
"already committed" paths tested as success.

## Workflow

```text
Verify:
- [ ] 1. Parse band/filter; load §3.x.1 (or §3.13) rows
- [ ] 2. Map rows → test files (reuse plan Test Layout where slice already planned)
- [ ] 3. Batch rows for parallel implementation (unit/x-e2e); keep e2e-seq serial
- [ ] 4. Implement tests first where production code already exists; otherwise test+code together
- [ ] 5. Run layer suites; fix until green
- [ ] 6. Update §8.1 / §8.2 / §8.3 in 04-abo-delivery-plan.md in the same commit as tests
```

### Parallel implementation (required)

- **Unit rows:** group by target deployable and test file; assign each group to a dedicated **Grok 4.7
  High** subagent (`model: "grok-4.7-high"`, `subagent_type: "generalPurpose"`).
- **Multiple bands:** when §3.1 allows (e.g. **M** and **N** after prerequisites), run
  `/abo-verify M` and `/abo-verify N` in parallel orchestrations.
- **Within band:** `unit` and `x-e2e` rows parallelize; `e2e-seq` runs as a single ordered pipeline.

Subagent prompt must include: band id, row ids, expected result column verbatim, target test path,
and "do not edit Spec Kit specs unless fixing a typo in test traceability."

### Status updates (§8)

- Tick **Unit** / **E2E-seq** / **X-E2E** only when **every** row of that layer in the band table
  passes — not a subset.
- Tick band roll-up §8.3 when all slices and all layers for the band are green.
- Master chain §8.2: tick steps only on real four-deployable local stack runs.

## Commands (examples — use plan/quickstart paths when present)

```bash
cd ai-platform && npm test
cd ai-billing-orchestrator && npm test
bash backend/tests/run_ai_platform_trust_tests.sh   # when band S
cd frontend && flutter test …
```

Run the **narrowest** command that proves the row; run full deployable suite before marking a layer
done.

## Prohibitions

- No Spec Kit phase for verification rows.
- No weakening/skipping tests to green.
- No architecture edits — escalate instead.
- Do not tick §8 without evidence (date · commit · test run).

## Escalation

When a row's **Expected result** contradicts code or architecture, or §3.13.3 open question blocks
implementation, output `## ESCALATION` and assign resolution to **Kimi K3 High** (`kimi-k3-high`).
Do not continue parallel Grok batches until Kimi resolves or the user amends architecture.

```markdown
## ESCALATION

**Band:** Q
**Row:** Q2-V7
**Conflict:** …
**Should be answered by:** ABO architecture §… or delivery plan amendment
**Blocked until:** architecture / plan update
```
