# Quickstart: `context_required` self-healing round trip (J2)

J2 adds the Flutter client's one automatic `context_required` self-healing round trip for
`single_shot` capabilities: refresh the manifest cache, resolve missing keys through the Context
Resolver, and resubmit once with the same idempotency key. A second `context_required` surfaces the
request reference; conversational capabilities never enter this path.

## 1. Architecture context

- **Delivery plan row J2** ([§3.9](../../docs/architecture/17b-ai-platform-delivery-plan.md)) implements
  **§8.4 Self-healing** and **§5.2 Self-healing vs Negotiation** from
  [`17-ai-platform.md`](../../docs/architecture/17-ai-platform.md).
- **Spec** (`spec.md`) froze the one-resubmission bound, same idempotency key reuse, second-rejection
  surfacing, and conversational exclusion for the §8.4 client handshake against C2's missing-key
  manifest payload.
- **Plan** (`plan.md`) scoped a sibling orchestration module under `frontend/lib/core/ai/` composing
  E2 SDK transport, E3 Context Resolver, and an injectable `ManifestRefreshPort` — plus optional C2
  fields on `PlatformHttpException` and a four-case Flutter integration suite.

## 2. What was implemented

- **`ContextRequiredSelfHeal`** (`context_required_self_heal.dart`) — `single_shot`-only heal helper:
  on first `context_required`, refresh once → resolve `missing_keys` → resubmit once with the same
  idempotency key; on second `context_required`, stop and surface the request reference (no third
  attempt); conversational `interaction_mode` bypasses the heal path entirely.
- **`ManifestRefreshPort`** — injectable manifest-cache refresh seam (production wires to C1
  discovery revalidation; tests spy the single call).
- **`PlatformHttpException` C2 fields** (`ports.dart`) — optional `missingKeys`, `shapes`,
  `manifestVersion`, and `manifestCapabilityId` when `code` is `context_required`.
- **Test suite** — `context_required_self_heal_test.dart` (tests 1–4) with extended `fakes.dart`
  substrate for C2 error steps and refresh spy.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/lib/core/ai/context_required_self_heal.dart` | §8.4 self-heal orchestration sibling; `ManifestRefreshPort`; `InteractionMode` gate |
| `frontend/lib/core/ai/ports.dart` | Extended `PlatformHttpException` with optional C2 missing-key manifest fields |
| `frontend/test/unit/core/ai/context_required_self_heal_test.dart` | Named tests 1–4 (happy path, second rejection, no third attempt, conversational exclusion) |
| `frontend/test/unit/core/ai/fakes.dart` | C2 `SubmitHttpErrorStep` fields; `FakeManifestRefreshPort` spy; `contextRequiredErrorStep` helper |

## 4. Prerequisites

- Flutter / Dart SDK as declared in `frontend/pubspec.yaml` (`sdk: ^3.11.5`).
- No live AI gateway Worker required — tests use injectable fakes.

## 5. Run the automated suite

From the repository root:

```bash
cd frontend
flutter test test/unit/core/ai/context_required_self_heal_test.dart
```

Expected: **4 passing tests** (tests 1–4 from the spec Test plan).

## 6. Inspect the changes

```bash
ls frontend/lib/core/ai/context_required_self_heal.dart
ls frontend/test/unit/core/ai/context_required_self_heal_test.dart
```

Open `context_required_self_heal.dart` for the refresh → resolve → same-key resubmit loop and
second-rejection bound. Open `ports.dart` for the optional C2 fields on `PlatformHttpException`.
Skim `context_required_self_heal_test.dart` for the four named cases. Confirm
`frontend/lib/core/ai/` remains covered by the E1 architecture guard:

```bash
cd frontend
dart run tool/architecture_guard/architecture_guard.dart
```

Expected: `architecture_guard: clean — no forbidden content detected.`
