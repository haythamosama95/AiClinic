# Implementation Plan: App Notched Card (010)

**Branch**: `010-app-notched-card` | **Date**: 2026-06-26 | **Spec**: `docs/specs/010-app-notched-card/spec.md`

**Input**: Feature specification from `docs/specs/010-app-notched-card/spec.md`

## Summary

Deliver a reusable **AppNotchedCard** design-system widget: a presentational sibling to `AppCard` that preserves card chrome (background, border, elevation, padding, typography) on three corners while replacing the top-trailing edge (LTR) with a step-down cut-out. Caller-supplied actions float in the notch shelf on a `Stack` layer above the card; title, optional description, and required body mirror `AppCard` layout with automatic trailing space reservation. Implementation uses a shared `Path` for `ClipPath` and border `CustomPaint`, intrinsic action measurement for dynamic notch width, and `Directionality`-aware mirroring for RTL. Scope is `core/ui` widget, barrel export, theme showcase demo, widget tests, and wrapper docs — no backend, migrations, or screen migrations.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop target per project constitution)

**Primary Dependencies**: Flutter Material layer; existing design tokens (`semanticColors`, `shapeTokens`, `SpacingTokens`); forui `FCard` patterns as visual baseline via `AppCard`; no new pubspec dependencies

**Storage**: N/A — stateless presentational widget

**Testing**: `flutter test` widget tests under `frontend/test/widget/core/ui/`; theme showcase manual/visual check against `docs/ui/assets/notch_card_reference.png`; optional golden tests deferred until reference PNG is in repo

**Target Platform**: Windows desktop (same as V1-0+); component is platform-agnostic Flutter UI

**Project Type**: Flutter presentation layer only (`frontend/lib/core/ui`); no Supabase/PostgreSQL/AI changes

**Performance Goals**: No measurable latency targets; minimize layout passes (single measure for actions + one build); avoid unnecessary repaints (`shouldRepaint`/`shouldReclip` tuned on clipper/painter)

**Constraints**: Public API limited to `title`, `description`, `body`, `actions`; fixed internal fillet/shelf constants; no accessibility wrapper on actions; parity with `AppCard` sizing; clip and border share one path; actions clip at card boundary when overflow

**Scale/Scope**: ~2–3 new Dart files; 1 widget test file; 1 showcase section; 1 contract doc; 1 wrapper doc update; zero backend artifacts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Scope fits small-to-mid-size multi-branch clinics; hospital-grade customizable layout engines out of scope (spec Business Context)
- [x] No microservices, queues, Kubernetes, or custom backend service; Flutter-only UI component
- [x] Layer ownership explicit: Flutter presentation only; no Supabase/PostgreSQL/AI involvement
- [x] No protected writes or domain rules — N/A for presentational widget; constitution database authority gates do not apply
- [x] Security/tenant/audit N/A at component level; callers must not embed sensitive data in action chrome beyond screen context (spec Constitution Alignment)
- [x] No AI dependency; component renders identically offline (spec edge case + Principle V)

### Post-Design Re-Check

- [x] `AppNotchedCard` remains in `core/ui` design system, not feature layer — replaceable without backend changes
- [x] No new RPC, migration, RLS, or permission keys
- [x] Caller-owned action semantics preserved (FR-016); no AI or service failure modes added
- [x] Sibling to `AppCard` — no breaking change to existing card consumers

## Project Structure

### Documentation (this feature)

```text
`docs/specs/010-app-notched-card/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── app-notched-card-widget.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
frontend/lib/core/ui/
├── widgets/
│   ├── layouts/
│   │   ├── app_card.dart              # existing baseline
│   │   ├── app_notched_card.dart      # new public widget
│   │   └── notched_card_path.dart     # path builder, clipper, border painter
│   └── widgets.dart                   # add export
├── demo/
│   └── theme_showcase_page.dart       # add Notched card section

frontend/test/widget/core/ui/
└── app_notched_card_test.dart

docs/ui/
├── notch_card_design.md               # existing design reference
├── assets/notch_card_reference.png    # visual baseline (add if missing)
└── forui-wrappers.md                  # append AppNotchedCard entry
```

**Structure Decision**: All implementation stays in `frontend/lib/core/ui` alongside `AppCard`, following the established design-system layout for forui wrappers. No `features/` code, no `backend/` changes, no `ai/` changes. Tests mirror other widget tests under `frontend/test/widget/`.

## Implementation Phases (high level)

### Phase A — Path geometry and clip/border

1. Implement `NotchedCardPath.build(...)` per FR-004 (step-down profile, downward entry/exit fillets, open top-trailing corner)
2. `NotchedCardClipper` + `NotchedCardBorderPainter` sharing path parameters
3. Unit-test path builder: closed path, bounding box, RTL mirror flag

### Phase B — AppNotchedCard widget

1. `AppNotchedCard` with required `body`, optional `title`, `description`, `actions`
2. `LayoutBuilder` → measure actions → compute `notchWidth` with min/max clamp
3. `Stack`: clipped card body column + `PositionedDirectional` action row on shelf
4. Trailing inset on header for title/description (FR-009)
5. Internal constants tuned against reference PNG (D8 in `research.md`)
6. Export from `widgets.dart`

### Phase C — Showcase and documentation

1. Add **Notched card** `_Section` to `theme_showcase_page.dart` with representative actions
2. Update `docs/ui/forui-wrappers.md` with `AppNotchedCard` API summary
3. Ensure `docs/ui/assets/notch_card_reference.png` exists or export from design for SC-007

### Phase D — Tests

1. Widget tests: layout non-overlap, empty actions min notch, multi-action row spacing, overflow clip, RTL mirror
2. Run `dart analyze` on new files
3. Execute `quickstart.md` verification steps

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status   |
| ------------------------------------------------- | -------- |
| `research.md`                                     | Complete |
| `data-model.md`                                   | Complete |
| `contracts/app-notched-card-widget.md`            | Complete |
| `quickstart.md`                                   | Complete |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated  |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
