# R0 packet index

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Completed 2026-10-16 Africa/Cairo. **R0 complete — inventory only, no correctness conclusion.**

## Exit gate

- Revision/instructions/initial-state verification: [revision verification](revision-verification.json); HEAD remains T, authorized existing untracked plan preserved; T/H differ only in workflow and captured artifacts. Only root AGENTS.md applies.
- Exhaustive `B..T` metadata: [candidate inventory](candidates.md) / [JSON](candidates.json), raw name-status and numstat preserved within machine inventory. **1,180 candidates:** 155 primary source, 15 supporting runtime, 351 references, 659 excluded. Incidental UI, generated localization, all excluded test/campaign/viewer paths receive explicit dispositions.
- [Exact region ownership](regions-details.md) / [JSON](regions.json) and [navigation summary](regions.md): 2,540 contiguous retained/baseline-deletion ranges, one primary R1–R9 owner per line, no holes/overlaps; shared dispatch owners and supporting consumers retained. Literal relative-import dependencies listed separately; dynamic/package imports must be followed during correctness review.
- [SQL definition navigation](regions-sql-definitions.md) / [JSON](regions-sql-definitions.json): 146 declarations across 54 changed names, including prior unchanged definitions. Name ordering is navigation; reviewers resolve overload/drop/grant/ownership behavior.
- [Escalations](escalations.md) / [JSON](escalations.json): all **75 entries / 30 files**, stable IDs, questions/resolutions/amended spans/consumers/dispositions/phase routes. Excluded effects remain indexed; external Paymob assumption remains explicit.
- [Delivery/later-fix provenance](provenance.md) / [JSON](provenance.json): 39 units, final path histories/deletions and post-delivery changes, including staff RLS, canonical JWT, fingerprint, intake, grants and runtime decoding.
- [System map and dependency order](system-map.md). Execution order is R0 → R1 → R2 → R3 → R4 → R5 → R6 → R7 → R8 → R9 → R10. Only R1 is authorized to execute next.

## Phase packets

Each packet includes question, source manifest, relevant architecture sections, exact escalation subset, interface/consumer obligations, initial seam questions and context-sizing instructions. Nothing in the inventory asserts source was reviewed.

- [R1 packet](packet-R1.md) · [bounded manifest](manifest-R1.md) · [escalation subset](escalations-R1.json)
- [R2 packet](packet-R2.md) · [bounded manifest](manifest-R2.md) · [escalation subset](escalations-R2.json)
- [R3 packet](packet-R3.md) · [bounded manifest](manifest-R3.md) · [escalation subset](escalations-R3.json)
- [R4 packet](packet-R4.md) · [bounded manifest](manifest-R4.md) · [escalation subset](escalations-R4.json)
- [R5 packet](packet-R5.md) · [bounded manifest](manifest-R5.md) · [escalation subset](escalations-R5.json)
- [R6 packet](packet-R6.md) · [bounded manifest](manifest-R6.md) · [escalation subset](escalations-R6.json)
- [R7 packet](packet-R7.md) · [bounded manifest](manifest-R7.md) · [escalation subset](escalations-R7.json)
- [R8 packet](packet-R8.md) · [bounded manifest](manifest-R8.md) · [escalation subset](escalations-R8.json)
- [R9 packet](packet-R9.md) · [bounded manifest](manifest-R9.md) · [escalation subset](escalations-R9.json)

R1 and R5 use named fresh same-phase contexts because of source/dependency sizing. R9 separates platform recovery, ABO operations and runtime/dependency artifacts. Other phases start with one context and checkpoint with exact coverage if expansion exceeds the plan target. Future reviews must expand discovered dependencies and update coverage; bounded static preparation cannot pre-prove an exhaustive runtime call graph.

No application source changes, commits, branch switches, fixes, tests, builds, lint, service operation, excluded implementation content reads or R2–R10 correctness reviews occurred during preparation.
