# R2 coordinator supporting-source coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; 2026-10-16 Africa/Cairo. These are direct source reads for R2 synthesis, additional to the three delegated primary manifests. They do not complete any later phase.

| Source | Inclusive read ranges / purpose |
| --- | --- |
| `ai-platform/src/vendor/entrypoint.ts` | 918–1001, 1095–1305, 1334–1451: independently verify exact operation matching, ceremony freshness, actor and replay gate, override bypass; 3320–3380: override consumption and dispatch; 3650–3805: paid call tail and beginTransfer seam only |
| `abo/src/ops/index.ts` | 624–790, 1372–1404: independently verify signed operation vs route-selected subject gap and replay insertion boundary |
| `frontend/lib/core/contract_versions.dart` | 1–13, full production constants |
| `frontend/lib/core/ai/usage_summary_client.dart` | full file: outgoing version and incoming success/error handling |
| `frontend/lib/core/ai/discovery_client.dart` | full file: header, 304/cache and JSON/error handling |
| `frontend/lib/core/ai/https_submit_port.dart` | full file: header, pre-stream version failure mapping and stream opening; stream parser read as direct consumer context, no separate R5/R7 completion |
| `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` | full file: actual discovery result consumption |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | 177–218: actual discovery/version exception composition |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | 294–330: actual usage consumer errors; surrounding runtime override branch surfaced incidentally in bounded read and is not test/fixture review |
| `frontend/lib/features/ai/availability/ai_availability.dart` | 1–100: version exception and availability model supporting context |
| `ai-platform/src/vendor/contract-version.ts` | full file: version refusal and header-only response wrapper |
| `ai-platform/src/worker.ts` | 2280–2510: feed page envelope and complete public fetch version dispatch |
| `ai-platform/src/coverage-read/index.ts` | full file: actual Worker-to-DO read request/response and public body |
| `ai-platform/src/discovery/index.ts` | full file: actual discovery receiver and response builder invocation |

Reference reads: complete review plan, root AGENTS.md, constitution, R2 packet/MD manifest and JSON metadata, R0 packet index/system map, R1 canonical report and handoffs, all 33 R2 escalation inventory entries (questions/resolutions), architecture 02 §§1.3–1.4, 2–4, 6 and 04 §§1.1–1.6, 2.3, 7. Expanded source evidence is linked in the aggregate report. Repository metadata verifies HEAD T and B/H commits; T/H differing paths are workflow/captured-artifact metadata only. No excluded implementation files were opened; no tests, services, builds or lint executed.

Final additional source ranges are recorded in aggregate R2-coverage.md. Primary machine manifest reconciled: 243 ranges / 3,885 lines / 22 paths; package is 15 modules / 1,925 lines. No source execution was used for verification.
