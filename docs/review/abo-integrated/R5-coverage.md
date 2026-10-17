# R5 coverage — complete with findings

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; date2026-10-17 Africa/Cairo. Lead GPT-6.1 Sol/high; two explicitly GPT-6.1 Sol/medium reviewers.

| Slice | Exact regions | Final T lines | Deleted B lines | Evidence |
| --- | ---: | ---: | ---: | --- |
| Admission/request/discovery |225|5,153|0|[Report](R5-admission-medium.md) · [Exact reads](R5-admission-medium-coverage.json) |
| DO/accounting/stream/routing |330|5,081|303|[Report](R5-accounting-medium.md) · [Exact reads](R5-accounting-medium-coverage.json) |
| Union |555|10,234|303|[Canonical report](R5-admission-accounting-fallback.md) · [JSON](R5-coverage.json) |

Verified union equals all indices0–554 of [manifest](manifest-R5.json), no overlaps, no missing ranges or revision substitutions. Each assignment tuple path/start/end/symbol/revision matches the manifest. Deleted period-close/usage-summary source was read at B and replacement reachability checked. Primary line totals count each owned region once; lead targeted rereads receive supporting credit only. Exact slice supporting reads and lead confirmations are linked in JSON. No unread assigned source remains.

All nine routed escalation IDs have explicit dispositions in canonical report/JSON:066:6,066:8,066:10,067:1,067:7,067:9,068:1,089:1,095:1. Reference-only excluded effects were not implementation-reviewed. Architecture/specs were reference material, not doc-quality review.

0 P0,6 P1,5 P2. R5-ADM3's outage replay authority requires architecture/maintainer decision; safe containment is coverage_unknown. Historical ambiguous accounting repair requires evidence-based maintainer/frontier/R9 adjudication. These are remediation limits, not missing source coverage. R6/R7/R9 handoffs are explicit; those phases are not started. Source unchanged; no tests/build/lint/services/live research/excluded implementation review.
