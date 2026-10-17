# R0 region ownership navigation

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; deleted files use baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`.

[Machine inventory](regions.json) assigns contiguous exact line ranges, a primary phase, and whether each range intersects a changed hunk. Imports, declarations, shared helpers and trailing dispatch are retained. Deleted implementations are assigned at baseline coordinates. Relative imports identify unchanged supporting dependencies without opening them.

**Ownership assignment status: complete; supporting dependency discovery bounded.** Each retained/deleted line has exactly one primary owner. Declarations and shared long-file methods were navigated by symbol; complete dispatcher bodies have one owner, with peer flow phases listed as supporting consumers. Owners must review their full assigned range, including any policy inside a dispatcher. Literal relative-import discovery is a navigation aid, not an exhaustive call graph; dynamically resolved and Dart package imports must be traced during source review. Spec provenance is provided separately. No correctness review conclusion follows from this inventory.

Assigned lines (includes supporting runtime artifacts and baseline deletions):

- R1: 7167
- R2: 3885
- R3: 6276
- R4: 4011
- R5: 10537
- R6: 6044
- R7: 7969
- R8: 6420
- R9: 21581

Review-time continuation: follow nonliteral/package imports and SQL final-definition overrides as needed for each owned invariant. Phase packets attach spec provenance separately. Broad dispatcher methods remain owned as a full body; supporting consumers do not relieve the primary owner of that body.

Sizing breakdown (full final regions, not diff additions):

| Phase | Final primary source | Baseline deletion | Supporting runtime metadata |
| --- | ---: | ---: | ---: |
| R1 | 7167 | 0 | 0 |
| R2 | 3885 | 0 | 0 |
| R3 | 6276 | 0 | 0 |
| R4 | 4011 | 0 | 0 |
| R5 | 10234 | 303 | 0 |
| R6 | 6044 | 0 | 0 |
| R7 | 7969 | 0 | 0 |
| R8 | 4469 | 1951 | 0 |
| R9 | 7781 | 0 | 13800 |

Use two fresh sessions within R1 (SQL tenant/issuance definitions; then verifiers/registries and Dart consumers), R5 (DO admission/settlement state; then worker pipeline/capability/cache/error protocol), and R9 (durable recovery/rebuild; then scheduling/operations and runtime configuration). R8 fits one primary packet when its 1,951 baseline deletion lines are counted; inspect replacements as supporting flow context. R7 is near the upper sizing target and can split projection/feed SQL from desktop consumers if supporting reads exceed the budget. Lockfile lines are dependency metadata: inspect relevant resolved production versions/exports rather than treating them as 13,800 handwritten source lines.

The full `handleOps` dispatch body is R8 primary; R2 follows Access/version/HP routes, R3 follows retry/cancel/payment routes, R4 follows complimentary grant routes, R6 follows void/release/transfer/deletion routes, and R9 follows payout/finding routes as supporting seams. ABO worker billing gate (207–226), offers (227–230), subscription/payments (231–238), and contact/checkout (239–293) are separately assigned. Platform worker fetch and terminal/idempotency helpers are R5 primary; R2 validates perimeter/version use, R7 coverage/feed routes, R8 removed control paths, and R9 scheduled recovery as explicit cross-flow consumers.
