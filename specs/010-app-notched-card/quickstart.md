# Quickstart: App Notched Card (010) Developer Verification

Walkthrough to verify the notched card component and showcase integration after implementation. No backend or auth setup required.

## Preconditions

- Flutter SDK aligned with project `pubspec.yaml`
- From repo root: `cd frontend && flutter pub get`
- Reference assets available: `docs/ui/notch_card_design.md`, `docs/ui/assets/notch_card_reference.png` (add PNG if missing before visual sign-off)

## Steps

### 1. Widget unit / layout tests

```bash
cd frontend
flutter test test/widget/core/ui/app_notched_card_test.dart
```

**Expect**: all tests pass — no title/notch overlap, RTL positions actions on leading top, empty actions preserves layout, wide actions clip at card boundary.

### 2. Theme showcase (manual)

1. Run the desktop app: `flutter run -d windows` (or project default device).
2. Navigate to **Theme Showcase** (route used by existing `ThemeShowcasePage`).
3. Locate the **Notched card** section (adjacent to existing **Card** / `AppCard` demo).

**Expect**:

- Title, description, and body visible with familiar card styling
- Filter/icon actions float inside top-trailing cut-out (LTR)
- No actions row at card bottom
- Cut-out shows page background in recess

### 3. Side-by-side parity with AppCard

In the showcase, compare **Card** (`AppCard`) and **Notched card** sections with equivalent title/description/body text.

**Expect** (SC-001):

- Same background, border color, three corner radii, title/description typography
- Only difference: top-trailing step-down profile on notched variant

### 4. Action width behavior

In showcase (or a temporary dev screen), render `AppNotchedCard` with:

1. No actions
2. One `AppButton`
3. Three controls (e.g. secondary button + icon button + overflow menu)

Resize window narrower than the combined action width.

**Expect**:

- Notch grows with actions up to available trailing width
- Empty actions still show minimum notch width
- Excess action width clips at card edge; title remains readable on leading side

### 5. RTL verification

Wrap showcase section (or use app locale / `Directionality`) with `TextDirection.rtl`.

**Expect** (SC-005):

- Cut-out and actions on top-leading (physical left)
- Title remains on leading (physical right) side
- No manual per-screen direction hacks required

### 6. Accessibility spot check

Use Flutter inspector / platform accessibility tools on showcase actions.

**Expect**:

- Action widgets retain caller-provided labels
- No extra grouping node labeled "toolbar" or "actions" from the card

### 7. Static analysis

```bash
cd frontend
dart analyze lib/core/ui/widgets/layouts/app_notched_card.dart
```

**Expect**: no issues; public API exported from `widgets.dart`.

## Done criteria

- [ ] `app_notched_card_test.dart` green in CI
- [ ] Showcase documents integration with only `title`, `description`, `body`, `actions`
- [ ] Visual review against `notch_card_reference.png` signed off (SC-007)
- [ ] `docs/ui/forui-wrappers.md` lists `AppNotchedCard`

**Next command**: `/speckit-tasks` to generate `tasks.md`.
