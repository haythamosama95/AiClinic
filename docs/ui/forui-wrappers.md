# Forui UI Abstraction Layer

Production-grade UI wrappers around the [forui](https://forui.dev) design system, isolated under `frontend/lib/core/ui/`. Feature layers import `App*` widgets only — never `package:forui/forui.dart`.

**Status:** Phase 1 complete (2026-06-09)

---

## Goals

- Isolate forui behind `lib/core/ui/widgets/` so feature code stays design-system-agnostic.
- Bridge existing `ColorTokens` / `AppTheme` into `FThemeData` (single source of truth).
- Provide dense SaaS primitives for forms, actions, panels, and confirmations.

## Architecture

```
features/*  →  AppButton / AppTextField / AppCard / AppDialog
                    ↓
              FButton / FTextFormField / FCard / FDialog  (forui, core/ui only)
                    ↓
              ForuiAppScope (FTheme)  ←  ForuiTheme ← ColorTokens
```

`package:forui/forui.dart` is imported **only** inside `lib/core/ui/**`.

---

## Phase 1 — Core wrappers (shipped)

| File                                                                                                     | Wrapper        | Forui target              |
| -------------------------------------------------------------------------------------------------------- | -------------- | ------------------------- |
| [`core/ui/widgets/buttons/app_button.dart`](../frontend/lib/core/ui/widgets/buttons/app_button.dart)     | `AppButton`    | `FButton`                 |
| [`core/ui/widgets/input/app_text_field.dart`](../frontend/lib/core/ui/widgets/input/app_text_field.dart) | `AppTextField` | `FTextFormField`          |
| [`core/ui/widgets/layouts/app_card.dart`](../frontend/lib/core/ui/widgets/layouts/app_card.dart)         | `AppCard`      | `FCard`                   |
| [`core/ui/widgets/feedback/app_dialog.dart`](../frontend/lib/core/ui/widgets/feedback/app_dialog.dart)   | `AppDialog`    | `FDialog` + `showFDialog` |

### Supporting infrastructure

| File                                                                                       | Purpose                                              |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| [`core/ui/theme/forui_theme.dart`](../frontend/lib/core/ui/theme/forui_theme.dart)         | Maps `ColorTokens` → `FThemeData` (desktop variant)  |
| [`core/ui/theme/forui_app_scope.dart`](../frontend/lib/core/ui/theme/forui_app_scope.dart) | `FTheme` + `FToaster` + `FTooltipGroup` root wrapper |
| [`core/ui/widgets/widgets.dart`](../frontend/lib/core/ui/widgets/widgets.dart)             | Barrel export for feature imports                    |
| [`app/app.dart`](../frontend/lib/app/app.dart)                                             | `MaterialApp.builder` → `ForuiAppScope`              |

### Demo

[`core/ui/demo/theme_showcase_page.dart`](../frontend/lib/core/ui/demo/theme_showcase_page.dart) — route `/foundation-demo` — includes a **Forui wrappers** section with buttons, validated text field, card, and confirmation dialog.

### Phase 1 checklist

- [x] Add `forui: ^0.22.3` to `pubspec.yaml`
- [x] `ForuiTheme` + `ForuiAppScope`
- [x] `AppButton` (primary / secondary / destructive, loading, icon)
- [x] `AppTextField` (validator, controller, obscureText, keyboardType)
- [x] `AppCard` (title, description, child, actions)
- [x] `AppDialog.showConfirmation`
- [x] Theme showcase section
- [x] `flutter analyze` clean on changed files
- [x] `flutter test` — 900 passed; 16 pre-existing boundary harness failures (Supabase not initialized locally)

---

## Phase 2 — Recommended follow-ups

Prioritized by reuse across clinic features (shifts, patients, billing, settings).

| Priority | Wrapper                        | Forui target            | Rationale                                       |
| -------- | ------------------------------ | ----------------------- | ----------------------------------------------- |
| High     | `AppSelect`                    | `FSelect`               | Branch/doctor/staff/enum fields everywhere      |
| High     | `AppToast` / `SnackbarService` | `FToaster`              | Replace raw `SnackBar` (e.g. permission denied) |
| High     | `AppLoadingState`              | `FCircularProgress`     | Consistent async screen loading                 |
| High     | `AppBadge`                     | `FBadge`                | Shift/appointment/billing status chips          |
| Medium   | `AppDataTable`                 | forui table pattern     | Admin lists (patients, staff, billing)          |
| Lower    | `AppCheckbox` / `AppSwitch`    | `FCheckbox` / `FSwitch` | Settings, provisioning forms                    |
| Lower    | `AppTabs`                      | `FTabs`                 | Patient detail, settings sections               |
| Defer    | `AppScaffold`                  | `FScaffold`             | Full shell migration — incremental only         |
| Defer    | `AppCalendar`                  | forui calendar          | Shifts uses `calendar_view` per spec            |

**Recommendation:** Add `AppSelect` first when building V1-7 shifts UI.

---

## Usage (feature layers)

```dart
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

AppButton(
  label: 'Save',
  variant: AppButtonVariant.primary,
  onPressed: _save,
);

AppDialog.showConfirmation(
  context: context,
  title: 'Delete shift?',
  message: 'This cannot be undone.',
  onConfirm: _delete,
);
```

### `AppButton`

| Parameter   | Type               | Notes                                             |
| ----------- | ------------------ | ------------------------------------------------- |
| `label`     | `String`           | Button text                                       |
| `onPressed` | `VoidCallback?`    | Disabled when null or `isLoading`                 |
| `icon`      | `Widget?`          | Shown as prefix; replaced by spinner when loading |
| `isLoading` | `bool`             | Shows `FCircularProgress`, disables press         |
| `variant`   | `AppButtonVariant` | `primary`, `secondary`, `destructive`             |
| `expand`    | `bool`             | Full-width when true                              |

### `AppTextField`

Uses `FTextFormField` for built-in validator error slots. Pass `validator` to enable `AutovalidateMode.onUserInteraction`.

### `AppCard`

Maps `description` → forui `subtitle`. Optional `actions` render in a trailing row inside the card body.

### `AppDialog.showConfirmation`

Horizontal layout with confirm (primary or destructive) and cancel (secondary) `AppButton` actions. Pops navigator before calling `onConfirm`.

---

## Implementation log

| Date       | Change                                                                 |
| ---------- | ---------------------------------------------------------------------- |
| 2026-06-09 | Phase 1 shipped: four wrappers, theme bridge, app scope, showcase demo |
