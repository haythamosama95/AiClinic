---

description: "Task list for App Notched Card (010) feature implementation"
---

# Tasks: App Notched Card (010)

**Input**: Design documents from `/docs/specs/010-app-notched-card/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/app-notched-card-widget.md, quickstart.md

**Tests**: INCLUDED for automated layout coverage per SC-003 and `quickstart.md`. Widget tests in `frontend/test/widget/core/ui/app_notched_card_test.dart`; path geometry unit tests in `frontend/test/unit/core/ui/notched_card_path_test.dart`. No backend tests (presentation-only feature).

**Organization**: Tasks grouped by user story (US1–US4) per spec.md priorities. US1 and US2 are both P1; US1 ships baseline card chrome first, US2 adds floating actions.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1–US4)
- Exact file paths included

## Path Conventions

- Widgets: `frontend/lib/core/ui/widgets/layouts/`
- Tests: `frontend/test/widget/core/ui/`, `frontend/test/unit/core/ui/`
- Showcase: `frontend/lib/core/ui/demo/theme_showcase_page.dart`
- Docs: `docs/ui/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare directories and confirm `AppCard` baseline for visual parity.

- [X] T001 Create widget test directory `frontend/test/widget/core/ui/` and unit test directory `frontend/test/unit/core/ui/`
- [X] T002 [P] Review `frontend/lib/core/ui/widgets/layouts/app_card.dart` and forui `FCard` header/body padding to record parity targets for title, description, and body insets

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared notch path geometry, clipper, and border painter used by all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Implement `NotchedCardPath.build(...)` with step-down profile (entry/exit fillets downward, open top-trailing corner) per FR-004 in `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart`
- [X] T004 Add `NotchedCardClipper` reusing `NotchedCardPath.build` in `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart`
- [X] T005 [P] Add `NotchedCardBorderPainter` stroking the same path with `semanticColors.border` in `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart`
- [X] T006 [P] Add path unit tests (closed path, bounds, LTR notch on trailing side) in `frontend/test/unit/core/ui/notched_card_path_test.dart`

**Checkpoint**: Path builder, clipper, and painter ready — user story implementation can begin.

---

## Phase 3: User Story 1 - Display a Notched Card with Title, Description, and Body (Priority: P1) 🎯 MVP

**Goal**: Render a notched card with optional title/description, required body, and minimum-width cut-out (no actions) matching `AppCard` chrome on three corners.

**Independent Test**: Render `AppNotchedCard` with title, optional description, and body (no actions). Verify non-notched corners, background, border, padding, and typography parity; cut-out shows minimum width; title/description/body do not overlap notch region.

### Implementation for User Story 1

- [X] T007 [US1] Create `AppNotchedCard` public constructor (`required body`, optional `title`, `description`, `actions`) in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart` per `docs/specs/010-app-notched-card/contracts/app-notched-card-widget.md`
- [X] T008 [US1] Wire `ClipPath` + `NotchedCardBorderPainter` + card fill using `semanticColors.card` and `shapeTokens.lg` on three standard corners in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
- [X] T009 [US1] Implement title, optional description, and body column with `AppCard`-equivalent typography and trailing horizontal inset reserving minimum notch width (FR-009) in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`

### Tests for User Story 1

- [X] T010 [P] [US1] Add widget tests for title/description/body layout and minimum notch without actions in `frontend/test/widget/core/ui/app_notched_card_test.dart`

**Checkpoint**: US1 independently demonstrable — card renders with header/body and static min notch.

---

## Phase 4: User Story 2 - Float Caller-Supplied Actions in the Cut-Out (Priority: P1)

**Goal**: Caller-supplied actions float centered in the notch shelf; cut-out width grows with actions; overflow clips at card boundary.

**Independent Test**: Render with 1–3 action widgets. Verify shelf centering, `SpacingTokens.sm` row spacing, dynamic notch width, and no title/body overlap; wide actions clip at card edge.

### Implementation for User Story 2

- [X] T011 [US2] Add action row intrinsic width measurement (`Row` + `SpacingTokens.sm`) inside `LayoutBuilder` in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
- [X] T012 [US2] Compute `notchWidth` clamp (min constant, actions + padding, max trailing available) and derive shelf rect in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
- [X] T013 [US2] Add root `Stack` with `PositionedDirectional` action row centered in shelf; render actions without re-theming (FR-007) in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
- [X] T014 [US2] Clip overflowing action row at card boundary with `ClipRect` (FR-015) in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
- [X] T015 [US2] Tune internal constants (`_kNotchFilletRadius`, `_kNotchShelfDepth`, `_kNotchMinWidth`, `_kNotchHorizontalPadding`) against `docs/ui/assets/notch_card_reference.png` in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart` and `notched_card_path.dart`

### Tests for User Story 2

- [X] T016 [P] [US2] Extend widget tests for single/multiple actions, spacing, and overflow clipping in `frontend/test/widget/core/ui/app_notched_card_test.dart`

**Checkpoint**: US1 + US2 complete — distinguishing notched card with floating actions works in LTR.

---

## Phase 5: User Story 3 - RTL Layout (Priority: P2)

**Goal**: Cut-out and actions mirror to top-leading edge in RTL without per-screen workarounds.

**Independent Test**: Wrap card in `Directionality(textDirection: TextDirection.rtl)`. Verify cut-out and actions on physical top-left; title on leading side; vertical spacing unchanged.

### Implementation for User Story 3

- [X] T017 [US3] Add RTL horizontal mirroring to `NotchedCardPath.build` via `textDirection` parameter in `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart`
- [X] T018 [US3] Mirror trailing inset and `PositionedDirectional` shelf positioning for RTL in `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`

### Tests for User Story 3

- [X] T019 [P] [US3] Add RTL mirror widget tests (cut-out on leading top, actions positioned correctly) in `frontend/test/widget/core/ui/app_notched_card_test.dart`

**Checkpoint**: US3 independently verifiable via directionality tests.

---

## Phase 6: User Story 4 - Adopt the Component in Feature Screens (Priority: P3)

**Goal**: Developers integrate via public API only; theme showcase demonstrates representative usage.

**Independent Test**: Showcase section uses only `title`, `description`, `body`, `actions`; widget exported from design-system barrel; wrapper docs updated.

### Implementation for User Story 4

- [X] T020 [P] [US4] Export `AppNotchedCard` from `frontend/lib/core/ui/widgets/widgets.dart`
- [X] T021 [US4] Add **Notched card** `_Section` beside existing `AppCard` demo with title, description, body, and 1–3 representative actions in `frontend/lib/core/ui/demo/theme_showcase_page.dart`
- [X] T022 [P] [US4] Append `AppNotchedCard` API summary to `docs/ui/forui-wrappers.md`

**Checkpoint**: US4 complete — component discoverable and documented for feature teams.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Visual baseline, static analysis, and quickstart validation.

- [X] T023 [P] Add or verify reference asset `docs/ui/assets/notch_card_reference.png` for SC-007 visual sign-off
- [X] T024 Run `dart analyze` on `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart` and `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart`
- [X] T025 Run `flutter test test/widget/core/ui/app_notched_card_test.dart test/unit/core/ui/notched_card_path_test.dart` from `frontend/`
- [X] T026 Execute manual steps in `docs/specs/010-app-notched-card/quickstart.md` (showcase side-by-side with `AppCard`, narrow-width clip, RTL spot check)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — **blocks all user stories**
- **US1 (Phase 3)**: Depends on Phase 2
- **US2 (Phase 4)**: Depends on US1 (builds on `AppNotchedCard` scaffold)
- **US3 (Phase 5)**: Depends on US2 (actions positioning must exist to mirror)
- **US4 (Phase 6)**: Depends on US1 minimum; best after US2 for full showcase demo
- **Polish (Phase 7)**: Depends on US1–US4 completion

### User Story Dependencies

| Story | Priority | Depends on | Independent test |
| ----- | -------- | ---------- | ---------------- |
| US1 | P1 | Phase 2 | Title/description/body + min notch, no actions |
| US2 | P1 | US1 | Actions in shelf, dynamic width, overflow clip |
| US3 | P2 | US2 | RTL mirror via `Directionality` |
| US4 | P3 | US1 (US2 recommended) | Showcase + export + docs |

### Within Each User Story

- Implementation tasks before story checkpoint
- Story-specific widget tests can run after implementation tasks in that phase
- Path unit tests (T006) after T003, parallel with T004/T005

### Parallel Opportunities

- **Phase 1**: T002 parallel with T001
- **Phase 2**: T005 and T006 parallel after T003; T004 sequential on T003
- **Phase 3**: T010 parallel after T009
- **Phase 4**: T016 parallel after T015
- **Phase 5**: T019 parallel after T018
- **Phase 6**: T020 and T022 parallel; T021 after T020
- **Phase 7**: T023 parallel with T024

---

## Parallel Example: User Story 2

```bash
# After T015 (constants tuned), run widget tests in parallel with doc prep:
Task T016: "Extend widget tests in frontend/test/widget/core/ui/app_notched_card_test.dart"
Task T022: "Append AppNotchedCard to docs/ui/forui-wrappers.md"  # if US4 started early
```

---

## Parallel Example: Foundational Phase

```bash
# After T003 path builder lands:
Task T004: "NotchedCardClipper in notched_card_path.dart"
Task T005: "NotchedCardBorderPainter in notched_card_path.dart"
Task T006: "Path unit tests in notched_card_path_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (path geometry)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Card with title/description/body and min notch renders correctly
5. Demo internally before adding actions

### Incremental Delivery

1. Setup + Foundational → path infrastructure ready
2. US1 → baseline notched card (MVP chrome)
3. US2 → floating actions (core product value)
4. US3 → RTL support
5. US4 → showcase + developer adoption
6. Polish → reference asset, analyze, full test suite, quickstart

### Suggested MVP Scope

**User Story 1 only** (Phases 1–3): Delivers scannable card layout with cut-out geometry but without dynamic actions. Acceptable interim demo; full feature requires US2.

**Recommended ship target**: Through **User Story 2** (Phases 1–4) for complete P1 acceptance scenarios.

---

## Notes

- Do not modify `AppCard` — `AppNotchedCard` is a sibling widget (research D1)
- Do not add `Semantics` wrappers around actions (FR-016)
- No backend, migration, or feature-screen migration tasks in this feature
- Commit after each phase checkpoint
- `[P]` tasks = different files, no incomplete dependencies
