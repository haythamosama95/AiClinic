# P8.2 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Untracked local noise does not block specify

**Question:** Untracked paths sit outside `docs/architecture/ai-billing-orchestration/` and `specs/097-abo-p8-2-staging-acceptance-a1-a36/`: `.wrangler/`, `abo/.hxw-platform/`, `abo/.wrangler/`, `abo/node_modules/`, `e2e/fullstack/.wrangler/`, `e2e/fullstack/node_modules/`, `e2e/fullstack/test/_flow-test.mjs`, `e2e/fullstack/test/_startworker-smoke.mjs`. The working tree must be clean except the allowed paths before specify occupies spec 097.

**Assumption:** Those paths are pre-existing local noise (wrangler cache, node_modules, smoke files). They are not part of P8.2. They are not deleted, not staged, and `.cursor/skills/` is not edited. They do not count as a dirty-tree stop for this unit. Specify continues on branch `ai/097-abo-p8-2-staging-acceptance-a1-a36` and occupies spec 097.

**Why:** The paths are local wrangler cache, installed dependencies, and smoke files already present in the working tree. They are outside the P8.2 deliverable. Cleaning or excluding them by deletion would discard unrelated local state. Recording them as excluded noise on the P8.2 delivery-plan section lets Spec Kit proceed without treating that noise as a stop.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P8.2 — Staging acceptance A1–A36).
