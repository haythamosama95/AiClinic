---
name: abo-resolve-review
description: Resolve every comment in an ABO slice review document — merge ai/master, test-first fixes, update Spec Kit docs, append resolution, commit, push, squash-merge to ai/master. Use for docs/review/abo-slices/ or when the user runs abo-resolve-review.
disable-model-invocation: true
---

# ABO — Resolve Review Comments

Handle **every** finding in a slice review report. Same workflow as `ai-platform-resolve-review`, with
ABO paths and scope rules.

**Input:** path under `docs/review/abo-slices/` (create the directory when the first review lands).
Resolve from `$ARGUMENTS` or `@`-mention.

## Subagent models

- **Each review stage `<slice>-R<n>`** (and parallel stages that touch different files): **Grok 4.7
  High** — `model: "grok-4.7-high"`, `subagent_type: "generalPurpose"`.
- **Escalation gate** (fix requires architecture meaning change): **Kimi K3 High** —
  `model: "kimi-k3-high"`. Stop other stages until resolved.

## Key paths

| Document | Path |
| --- | --- |
| Delivery plan | `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` |
| Architecture | `docs/architecture/ai-billing-orchestration/architecture/00-index.md` + cited parts |
| AP-ARCH (platform slices only) | `docs/architecture/ai-platform/01-ai-platform.md` — cited sections only |
| Review index | `docs/review/abo-slices/README.md` (when present) |

## Workflow

Same checklist as `ai-platform-resolve-review`:

1. Parse slice id, branch, spec path, canonical sections from review header.
2. Read delivery-plan slice row + band intro only; read architecture sections named in review +
   `Canonical` column only.
3. `git fetch` + **real merge** `origin/ai/master` into slice branch; push.
4. Group comments into stages `<slice>-R<n>`.
5. Per stage: escalation gate → test first → fix → full suite for **every deployable the stage
   touches** → update Spec Kit docs. Band-matrix tests: extend via `/abo-verify` rows if the fix
   changes behavioural coverage — still no new Spec Kit feature for `-V`/`-E`/`-X` ids.
6. Append **Review Resolution** section (style: `docs/review/ai-platform-slices/A2-diagnostic-envelope.md`).
7. Commit + push on slice branch.
8. Squash-merge to `ai/master`; push.

Resolve spec directory:

```bash
.specify/scripts/bash/abo-paths.sh --json --paths-only
```

## Full suite commands

Run all deployables affected by the slice:

```bash
cd ai-platform && npm test          # bands M–P
cd ai-billing-orchestrator && npm test   # bands Q–R
# backend pgTAP / trust scripts for band S
# flutter test for band T
```

## Escalation

Fixing a comment requires changing ABO `architecture/*.md` or AP-ARCH meaning → `## ESCALATION`, stop.
Allowed: implementation, tests, Spec Kit doc sync, contract **extension** per delivery plan §2.3.

## Rules

- Tests before fixes; no deferred comments.
- Architecture and delivery plan are read-only in this skill.
- Real merge in step 3; squash only in step 8.
- No PR unless the user asks.
