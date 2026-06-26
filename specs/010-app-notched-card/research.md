# Research: App Notched Card (010)

Phase 0 research resolves implementation choices for the notched card UI component. No backend, storage, or AI dependencies apply. All Technical Context items are resolved; nothing blocks Phase 1.

## Decisions

### D1. Base card implementation strategy

- **Decision**: Implement `AppNotchedCard` as a **standalone sibling widget** to `AppCard` — do **not** extend or modify `AppCard` / `FCard`. Reuse the same theme tokens (`context.semanticColors`, `context.shapeTokens.lg` for the three standard corners, `SpacingTokens` for gaps and padding) and mirror `FCard` header/body spacing by inspecting `AppCard` / forui `FCard` layout during implementation.
- **Rationale**: `FCard` applies a uniform `BorderRadius.circular(shapeTokens.lg)`; a top-trailing step-down cut-out requires a custom `Path` for clip and stroke. Wrapping `FCard` would fight its built-in decoration and corner radii.
- **Alternatives considered**: Subclass `FCard` with custom decoration (forui API does not expose per-corner radius or clip override); fork `FCard` internals (fragile across forui upgrades); `ClipRRect` + overlay mask (hard to keep border continuous at fillets).

### D2. Cut-out path construction

- **Decision**: Centralize geometry in a single pure-Dart helper (e.g. `NotchedCardPath.build(...)`) that returns a closed `Path` from card `Size`, `BorderRadius` (three corners), notch width, shelf depth, and fillet radius. Trace segments per spec FR-004: leading top → entry fillet (down) → shelf → exit fillet (down) → trailing edge → bottom-trailing arc → bottom → leading arc → close. Use `Path.arcToPoint` or `quadraticBezierTo` for fillets with one shared radius constant.
- **Rationale**: FR-013 requires the same path for clip and border; a single builder prevents drift. Pure functions are easy to unit-test (path bounds, segment count) without pumping widgets.
- **Alternatives considered**: `CustomClipper` only with duplicated border `CustomPainter` logic (duplicate math); SVG asset clip (not resolution-independent, harder to size to actions); `ShapeBorder` subclass (viable but less explicit for step-down profile).

### D3. Border and clip rendering

- **Decision**: `ClipPath(clipper: ...)` around the filled card body; draw the 1 logical-pixel border with a `CustomPaint` foreground painter (or parent `CustomPaint` with `child:`) using the **same** `Path` and `PaintingStyle.stroke` with `colors.border`. Avoid putting `Border.all` on a `BoxDecoration` with standard `borderRadius` — it cannot follow the notch.
- **Rationale**: Matches design doc clipping requirements; eliminates gap/overlap between clip and stroke (FR-003, FR-013).
- **Alternatives considered**: `PhysicalShape` + `ShapeBorder` (possible but team has existing `CustomPainter` precedent in timeline gutter); stacked `DecoratedBox` with mask (anti-aliasing artifacts at fillets).

### D4. Notch width measurement

- **Decision**: Two-phase layout inside `LayoutBuilder`:
  1. Measure action row intrinsic width via `Row` with `spacing: SpacingTokens.sm` wrapped in `IntrinsicWidth` or offstage `RenderParagraph`-free `Row` measure (prefer `Wrap`/`Row` in a `OverflowBox` offstage pass only when actions non-empty).
  2. Compute `notchWidth = clamp(minNotchWidth, actionsWidth + horizontalPadding, trailingAvailableWidth)` where `trailingAvailableWidth` derives from card width minus leading corner radius and minimum title reserve.
- **Rationale**: FR-006/FR-015 require action-driven width with min/max caps; intrinsic measurement is the standard Flutter pattern for caller-supplied widgets.
- **Alternatives considered**: Fixed notch width (violates FR-006); `GlobalKey` measure after first frame (extra layout pass, flicker risk).

### D5. Actions layer positioning

- **Decision**: Root `Stack(clipBehavior: Clip.none)` with (1) clipped card + content column, (2) `Positioned` action row centered in the shelf rectangle computed from path geometry. Clip overflowing actions with `ClipRect` aligned to the card's bounding box (not the notch interior) so FR-015 clipping occurs at the card boundary.
- **Rationale**: Design doc hierarchy (`Stack` → card + floating actions); actions must not be re-themed (FR-007); shelf centering is specified in acceptance scenarios.
- **Alternatives considered**: Actions inside the clipped card (would be clipped by notch recess); `Overlay` portal (unnecessary complexity).

### D6. Title / description / body layout parity

- **Decision**: Column inside card padding matching `AppCard`/`FCard` content insets: optional `title`, optional `description`, required `body`. Apply **trailing padding** (or `Padding` with asymmetric `EdgeInsets`) equal to `notchWidth` on the header row so title/description never draw under the cut-out (FR-009). Body uses full width below the header block (same as `AppCard` — only header competes horizontally with notch).
- **Rationale**: Clarifications require full `AppCard` parity; long titles wrap within leading width reserved by trailing inset.
- **Alternatives considered**: `Table`/`Flex` with `Expanded` title (more complex than padding); separate `Stack` for title (harder to match FCard baseline alignment).

### D7. RTL mirroring

- **Decision**: Derive `isRtl = Directionality.of(context) == TextDirection.rtl`. Pass `textDirection` into path builder to mirror horizontal coordinates (cut-out on physical leading side in RTL). Position actions with `PositionedDirectional` (`end` / `top`) so the shelf tracks the mirrored notch.
- **Rationale**: FR-010; Flutter directional positioning avoids manual left/right swaps in widgets.
- **Alternatives considered**: `Transform.flip` on entire card (would mirror text); caller-supplied `Directionality` overrides (anti-pattern).

### D8. Internal constants (fillet, depth, padding)

- **Decision**: Private top-level or class constants in `app_notched_card.dart` (and path helper), tuned against `docs/ui/assets/notch_card_reference.png` during implementation:
  - `_kNotchFilletRadius` — start with `8.0` logical px (or `shapeTokens.sm` if visually closer)
  - `_kNotchShelfDepth` — start with `28.0` logical px
  - `_kNotchMinWidth` — start with `56.0` logical px
  - `_kNotchHorizontalPadding` — `SpacingTokens.sm` (8 px) each side
  Not exposed in public API (FR-005, FR-011).
- **Rationale**: Spec assumes implementer tuning to reference screenshot; constants colocated with path builder for single place to adjust after visual review.
- **Alternatives considered**: ThemeExtension tokens (spec says not caller-configurable; premature theming); scaling fillet with card width (spec FR-014 says fixed constants scale only with overall card/zoom, not independent notch aspect changes).

### D9. Elevation / shadow

- **Decision**: Match `AppCard`/`FCard` elevation behavior observed at implementation time. If `FCard` applies no explicit shadow in current theme delta, use flat `colors.card` fill only; if shadow is present, apply equivalent `BoxShadow` on the clipped `DecoratedBox` (shadow may approximate on bounding rect — acceptable if `AppCard` uses the same).
- **Rationale**: FR-002 parity with standard card; avoid inventing new elevation.
- **Alternatives considered**: Custom shadow following notch path (over-engineered unless `AppCard` already does path-accurate shadow).

### D10. Testing strategy

- **Decision**:
  - **Widget tests** under `frontend/test/widget/core/ui/app_notched_card_test.dart`: no overlap (title vs notch region via `tester.getRect`), RTL mirror (find `PositionedDirectional`), empty actions preserves min notch, wide actions clip at card width, required `body` enforced at compile time.
  - **Golden tests** optional follow-up: project has no existing goldens; add `matchesGoldenFile` for LTR + actions case once reference PNG is checked in (`docs/ui/assets/notch_card_reference.png` — **asset referenced by spec but not yet in repo**; implementer adds or exports from design).
  - **Theme showcase**: new `_Section` in `theme_showcase_page.dart` beside existing `AppCard` demo (US4).
- **Rationale**: SC-001–SC-007; widget tests give CI signal without golden infrastructure blocker.
- **Alternatives considered**: Showcase-only manual QA (insufficient for FR-009/FR-015 regressions); integration test via full app shell (heavy for one widget).

### D11. Accessibility

- **Decision**: No `Semantics` wrapper, `MergeSemantics`, or toolbar role around the action row (FR-016). Do not wrap caller actions in `ExcludeSemantics` or modified themes.
- **Rationale**: Clarifications and `AppCard` caller-responsibility pattern.
- **Alternatives considered**: `Semantics(container: true)` on notch (explicitly rejected).

### D12. File placement and exports

- **Decision**:
  - `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart` — public widget
  - `frontend/lib/core/ui/widgets/layouts/notched_card_path.dart` — path builder + clipper/painter (private to layouts or same library)
  - Export from `frontend/lib/core/ui/widgets/widgets.dart`
  - Document in `docs/ui/forui-wrappers.md` (append row to implementation log)
- **Rationale**: Mirrors `app_card.dart` location; keeps design-system widgets discoverable.
- **Alternatives considered**: `features/` placement (wrong layer — shared design system); single monolithic 500-line file (path math deserves separation).

## Resolved unknowns

| Item | Resolution |
| ---- | ---------- |
| Custom clip vs FCard | Custom path + sibling widget (D1, D2) |
| Border alignment | Shared path clip + stroke (D3) |
| Dynamic notch width | Intrinsic measure + clamp (D4) |
| RTL | Directional layout + mirrored path (D7) |
| Testing | Widget tests + showcase; optional goldens (D10) |
| Reference asset | Tune constants against PNG when added (D8) |

**Phase 0 complete.** Proceed to Phase 1 design artifacts.
