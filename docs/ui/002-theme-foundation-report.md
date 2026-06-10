# Theme Foundation & Forui Wrapper Layer

**Branch:** `ui/002-theme-foundation`
**Date:** 2026-06-10
**Scope:** Rebuild the presentation foundation under `frontend/lib/core/ui/` — token-based theming, two design variants, forui integration, and `App*` widget wrappers.

## Summary

| Check                         | Status                   |
| ----------------------------- | ------------------------ |
| `flutter analyze lib/`        | Pass                     |
| Theme variants (light + dark) | Astro Vista, Claude+     |
| Forui isolated to `core/ui/`  | Yes                      |
| Interactive demo route        | `/foundation-demo`       |
| Pre-auth landing route        | `/` (`StartupEntryPage`) |

This branch replaces the minimal `app/theme/` shell from the UI teardown ([001 report](./001-ui-presentation-migration-report.md)) with a production-ready design system: CSS-variable-style tokens, variant-specific palettes, Material 3 `ThemeData`, and a forui bridge so feature code imports `App*` widgets only.

**Approximate diff:** 48 files changed, ~4,100 lines added across 7 commits.

---

## Commit History

| Commit    | Description                                                                                                                                                                                               |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `7c4203d` | **Astro Vista theme** — token model (`ColorTokens`, spacing, radius, shadow, typography), `SemanticColors`, `AppTheme` builder, `google_fonts` dependency                                                 |
| `e2fadbe` | **Demo page** — `ThemeShowcasePage` at `/foundation-demo`; `StartupEntryPage` as `/` landing with link to showcase                                                                                        |
| `af0a356` | **Forui library & wrappers** — `forui` dependency, `ForuiTheme` / `ForuiAppScope`, 14 `App*` widgets, `docs/ui/forui-wrappers.md`                                                                         |
| `c9dcc0d` | **Claude+ theme** — multi-variant architecture (`AppThemeVariant`, `ThemePaletteResolver`), per-variant token files, `themeVariantProvider`, `AppThemeMeta` extension                                     |
| `81c81e8` | **Claude+ destructive color & dialog UX** — parchment destructive token → red; `AppDialog.showConfirmation` swaps button emphasis when `destructive: true`; variant display names (Astro Vista / Claude+) |
| `488d605` | **CodeRabbit review fixes** — typography token hardening, input/sheet/tile edge cases                                                                                                                     |
| `7fc7d8a` | **Test cleanup** — `ShiftRpcTestClient` constructor refactor; simplified long-note assertion in `shift_detail_domain_test.dart`                                                                           |

---

## Architecture

```
features/*  →  AppButton / AppTextField / AppDialog / …
                    ↓
              forui (FButton, FTextFormField, FDialog)  — only in core/ui
                    ↓
MaterialApp  →  AppTheme.light/dark(variant)  →  ColorTokens + SemanticColors
                    ↓
         MaterialApp.builder  →  ForuiAppScope  →  FTheme + FToaster
```

### Theme tokens (`frontend/lib/core/ui/theme/`)

| File                         | Purpose                                                                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `color_tokens.dart`          | `ColorTokens` — mirrors Tailwind v4 CSS custom properties (`:root` / `.dark`)            |
| `semantic_colors.dart`       | `SemanticColors` `ThemeExtension` — success, warning, info, destructive, etc.            |
| `spacing_tokens.dart`        | Layout spacing scale (`xs` … `xxl`)                                                      |
| `radius_tokens.dart`         | Legacy radius constants (superseded by per-variant shapes where applicable)              |
| `shape_tokens.dart`          | `ShapeTokens` extension — `sm` / `md` / `lg` / `xl` corner radii                         |
| `shadow_tokens.dart`         | Elevation shadow color and blur values                                                   |
| `typography_tokens.dart`     | Shared typography helpers                                                                |
| `app_theme.dart`             | Builds `ThemeData` (M3) from resolved tokens — inputs, cards, dialogs, chips, navigation |
| `app_theme_meta.dart`        | `AppThemeMeta` extension carrying active `AppThemeVariant` on `ThemeData`                |
| `forui_theme.dart`           | Maps `ColorTokens` → `FThemeData`                                                        |
| `forui_style_overrides.dart` | Fine-grained forui component style overrides                                             |
| `forui_accent_colors.dart`   | Accent color helpers for forui palette                                                   |
| `forui_app_scope.dart`       | Root `FTheme` + `FToaster` + `FTooltipGroup` wrapper                                     |
| `theme.dart`                 | Barrel export                                                                            |

### Theme variants (`frontend/lib/core/ui/theme/variants/`)

| Enum value                  | Display name | Palette character                                                          |
| --------------------------- | ------------ | -------------------------------------------------------------------------- |
| `AppThemeVariant.clinic`    | Astro Vista  | Orange primary (`#DF6035`), blue secondary (`#2F4B79`), cool gray surfaces |
| `AppThemeVariant.parchment` | Claude+      | Terracotta primary (`#C96442`), cream surfaces (`#FAF9F5`), warm neutrals  |

Each variant owns isolated token files:

- `clinic/clinic_color_tokens.dart`, `clinic_shape_tokens.dart`, `clinic_typography_tokens.dart`
- `parchment/parchment_color_tokens.dart`, `parchment_shape_tokens.dart`, `parchment_typography_tokens.dart`

`ThemePaletteResolver` selects the correct palette for color, shape, and typography without cross-contaminating variants.

### State & wiring

| File                                | Change                                                                                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `app/providers/theme_provider.dart` | `themeModeProvider` (from startup session), `themeVariantProvider` (`NotifierProvider`), `setAppThemeMode` / `setAppThemeVariant` helpers |
| `app/app.dart`                      | `AppTheme.light/dark(themeVariant)`; `MaterialApp.builder` wraps tree in `ForuiAppScope`                                                  |
| `app/router.dart`                   | `/` → `StartupEntryPage`; `/foundation-demo` → `ThemeShowcasePage`                                                                        |
| `core/auth/auth_route_guard.dart`   | `/` and `/foundation-demo` registered as public unauthenticated routes                                                                    |

---

## Widget Wrappers (`frontend/lib/core/ui/widgets/`)

Feature layers import `package:ai_clinic/core/ui/widgets/widgets.dart` — never `package:forui/forui.dart`.

| Category | Widget                                             | Forui / Material target                                                    |
| -------- | -------------------------------------------------- | -------------------------------------------------------------------------- |
| Buttons  | `AppButton`                                        | `FButton` — primary, secondary, destructive; loading, icon, sizes          |
| Input    | `AppTextField`                                     | `FTextFormField` — validator, controller, obscureText                      |
| Input    | `AppLabel`                                         | Field labels with required indicator                                       |
| Input    | `AppFieldSize`                                     | Shared size enum for inputs and dialog actions                             |
| Input    | `AppDateField`                                     | Date picker field with calendar popover                                    |
| Input    | `AppAutocomplete`                                  | Typeahead / autocomplete                                                   |
| Input    | `AppSelectTileGroup`, `AppSelectOption`            | Radio and multi-select tile groups                                         |
| Layouts  | `AppCard`                                          | `FCard` — title, description, child, actions                               |
| Tiles    | `AppItemTile`, `AppItemSpec`, `AppSelectTileGroup` | List tiles, action items, selectable tiles                                 |
| Feedback | `AppAlert`                                         | Inline alert banners                                                       |
| Overlays | `AppDialog`                                        | `FDialog` — `show`, `showConfirmation` (destructive-aware button emphasis) |
| Overlays | `AppPopover`                                       | Popover menus                                                              |
| Overlays | `AppSheets`                                        | Bottom sheets                                                              |
| Overlays | `AppToast`                                         | Toast notifications via `FToaster`                                         |

Detailed usage, parameters, and phase-2 roadmap: [forui-wrappers.md](./forui-wrappers.md).

---

## Demo & Routes

### `StartupEntryPage` (`/`)

Pre-auth landing screen with:

- Link to theme showcase
- Link to sign-in (`/login`)
- Live **theme variant** selector (Astro Vista / Claude+)
- Live **appearance** selector (System / Light / Dark)

Unauthenticated users are redirected here instead of the startup-check placeholder.

### `ThemeShowcasePage` (`/foundation-demo`)

Interactive gallery covering:

- Theme variant and appearance toggles
- Brightness indicator
- Color token swatches
- Typography scale
- Buttons (all variants, loading state)
- Form inputs (text field, date, autocomplete)
- Selectors (role, tags, plan, notifications)
- Tiles & items (navigation, destructive)
- Feedback alerts
- Overlays (confirmation dialog, popover, sheet, toast)
- Card component

---

## Dependencies Added

| Package        | Version   | Purpose                                                       |
| -------------- | --------- | ------------------------------------------------------------- |
| `google_fonts` | `^6.2.1`  | Variant-specific typography (Inter for Astro Vista, etc.)     |
| `forui`        | `^0.22.3` | Desktop-oriented component library (isolated behind wrappers) |

---

## Notable Design Decisions

1. **Variant isolation** — Color, shape, and typography live in per-variant files resolved at build time. Adding a third theme means a new folder under `variants/`, not edits to shared palettes.

2. **Dual theme stack** — Material `ThemeData` drives Flutter primitives; `ForuiAppScope` mirrors the active variant into `FThemeData` so forui components stay in sync.

3. **Destructive dialog UX** — When `AppDialog.showConfirmation(destructive: true)`, the confirm button uses destructive styling and cancel uses primary styling so the safe action is visually prominent.

4. **Claude+ destructive color** — Parchment light destructive was changed from near-black (`#141413`) to standard red (`#EF4444`) for clearer danger signaling.

5. **forui boundary** — `package:forui/forui.dart` is imported only inside `lib/core/ui/**`, keeping features design-system-agnostic.

---

## Files Outside `core/ui/` (touched)

| File                                             | Change                                         |
| ------------------------------------------------ | ---------------------------------------------- |
| `app/app.dart`                                   | Variant-aware theming + `ForuiAppScope`        |
| `app/providers/theme_provider.dart`              | New — variant and mode providers               |
| `app/presentation/startup_entry_page.dart`       | New — pre-auth landing                         |
| `app/router.dart`                                | `/` and `/foundation-demo` route builders      |
| `test/support/shift_rpc_test_client.dart`        | Constructor simplification (unrelated cleanup) |
| `test/unit/shifts/shift_detail_domain_test.dart` | Long-note test simplification                  |

---

## Verification Commands

```bash
cd frontend
flutter analyze lib/
flutter test test/unit test/integration
flutter run -d linux   # navigate to / or /foundation-demo
```

---

## Relationship to Prior Work

| Prior state ([001 report](./001-ui-presentation-migration-report.md)) | This branch                                 |
| --------------------------------------------------------------------- | ------------------------------------------- |
| `app/theme/app_theme.dart`, `app_colors.dart` (minimal shell)         | Replaced by `core/ui/theme/` token system   |
| `/foundation-demo` → placeholder                                      | Live `ThemeShowcasePage`                    |
| No design-system widgets                                              | 14 `App*` wrappers + forui bridge           |
| Single implicit theme                                                 | Two switchable variants + light/dark/system |

---

## Next Steps

1. Persist `themeVariantProvider` selection (currently in-memory; resets on restart).
2. Build first feature screen (e.g. shifts) using `App*` widgets only.
3. Extend wrappers per [forui-wrappers.md](./forui-wrappers.md) phase-2 list (`AppSelect`, loading states, badges).
4. Reintroduce `AuthenticatedShell` navigation using sidebar color tokens from `ColorTokens`.
5. Add widget tests for critical wrappers (dialog destructive layout, form validation).
