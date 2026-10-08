# P7.1 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Residue guard scan roots

**Question:** The residue guard is one CI job running a checked-in script over the tracked tree, skipping only paths with a `migrations` segment, and it must pass. A literal scan still hits 335 tracked files: 139 under `specs/`, 56 under `ai-platform/` outside `scripts/`, 19 other docs including `docs/architecture/ai-billing-orchestration/` (01–06), 15 under `backend/` (tests, not migrations), and 2 under `frontend/`. This unit may change only the viewer, `ai-platform/scripts`, `docs/architecture/ai-platform/`, `docs/testing/catalog/`, and CI. Which of those other paths may still contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`, or is the scan limited to the named trees?

**Assumption:** The scan is limited to the four dependent-path trees: `ai-platform-viewer/`, `ai-platform/scripts/`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`. Inside those trees the guard still skips any path with a `migrations` segment and treats each needle as a literal substring. The checked-in script lives with the CI job, outside those four trees. `specs/`, `ai-platform/` outside `scripts/`, every other docs tree including `docs/architecture/ai-billing-orchestration/` (01–06), `backend/` (tests included), and `frontend/` may still contain `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, and `installation_key`, and the guard does not scan them. Superseded pages in the two doc trees are rewritten so those needles are gone.

**Why:** 04 §6.6 and rule V2 assign P7.1 the viewer, `bootstrap-routing-policy.sh`, `docs/architecture/ai-platform/`, and `docs/testing/catalog/`. The unit codebase is those trees plus CI. "Outside migrations" is the skip for historical SQL, not a scan of every other tree. P3.10 keeps `ai-platform/src/control/` and owns platform removal. P5.1 and P5.2a own the backend drops of `installation_keys` and `set_ai_availability`. P6.x owns the frontend row of 04 §6.6. The v2 documents 01–06 and the unit specs name the removed symbols on purpose. 05 §6.2's second bullet is a production-state condition evidenced on these dependent paths. CP-F in P7.3 is the later diff of 02–05 against the code.

**Amended:** `specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/spec.md` (Clarifications, Session 2026-10-08; §2.2; FR-004; FR-005; §4.1; §5; §7 Assumptions).
