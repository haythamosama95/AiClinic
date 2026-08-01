# Flutter Core Review — UI Theme & Design Tokens

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/ui/theme/*`, `frontend/lib/core/ui/motion/app_motion.dart`, theme consumption in `features/` and `app/`, theme-related tests in `frontend/test/`  
**Canonical reference:** `docs/ui/design-system/02-tokens.md`, `03-motion.md`

---

## Executive Summary

The theme layer establishes a sound **three-tier token architecture** (primitives → semantic `ThemeExtension`s → component usage) and keeps presentation concerns in `core/ui`. Core shell and design-system surfaces consistently consume `context.appColors`, `AppSpacing`, `AppTypography`, and `AppRadius`.

However, the implementation is **early-stage relative to the design spec**: roughly half of the documented semantic tokens are missing from `AppSemanticColors`, typography and motion diverge from `02-tokens` / `03-motion`, there are **zero automated theme tests**, and at least one **domain-layer file hardcodes Flutter `Color` values** outside the token system. `AppTheme` also rebuilds `ThemeData` (including `GoogleFonts` resolution) on every root `build`, which is unnecessary work on a Riverpod-driven app that rebuilds frequently.

Remediation priority: complete semantic token coverage, add contrast/token regression tests, memoize themes, wire Material component themes to semantics, and relocate domain color logic behind presentation tokens.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  features/* / app/shell/*  (presentation)                               │
│  context.appColors · AppSpacing · AppTypography · AppRadius · AppMotion │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  core/ui/theme/                                                         │
│  AppTheme ──► ThemeData + extensions [AppSemanticColors, AppElevation]  │
│  AppTypography · AppSpacing · AppRadius · AppShellTokens · AppContrast  │
│  AppColorPrimitives (palette — should not leak to features)              │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  core/ui/motion/app_motion.dart  (motion presets, reduced-motion)     │
│  core/ui/theme/app_motion.dart   (re-export barrel only)                │
└─────────────────────────────────────────────────────────────────────────┘
```

**Intended rule (from `02-tokens.md`):** components consume **semantic** tokens only; primitives are the palette laboratory.

**Actual gaps:** primitives leak into `AppTypography`; showcase constants duplicate primitives; domain code bypasses tokens entirely; many primitives (backdrop, focus rings, status trios) never surface as semantics.

---

## Positive Observations

| Area | Detail |
|------|--------|
| Layering | Theme code lives under `core/ui/theme/` — appropriate for Clean Architecture presentation infrastructure. |
| Semantic extensions | `AppSemanticColors` and `AppElevation` as `ThemeExtension`s enable typed, theme-aware access via `context.appColors` / `context.appElevation`. |
| Motion module | Single implementation in `core/ui/motion/app_motion.dart`; `theme/app_motion.dart` is a re-export (no logic duplication). Reduced-motion handling via `MediaQuery.disableAnimationsOf` is correct. |
| RTL | `AppMotionPreset.slideInline` respects `TextDirection` for horizontal offset. |
| Barrel export | `core/ui/widgets/widgets.dart` centralizes token and component exports for features. |
| Shell consistency | `app/shell/*` navigation chrome consistently uses semantic colors and spacing tokens. |

---

## 1. Critical Issues

*None identified.* No runtime crashes or security issues were found in the theme layer itself. The highest risks are maintainability, spec drift, and future accessibility regressions.

---

## 2. High-Severity Issues

### H-01 — No automated theme or token tests

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/test/` (absent), `frontend/lib/core/ui/theme/*`, `frontend/lib/core/ui/motion/app_motion.dart` |
| **Evidence** | `Glob` over `frontend/test/**/*theme*` returns 0 files. `grep` for `AppTheme`, `AppSemanticColors`, `AppContrast`, `AppSpacing`, `AppTypography`, `AppMotion` in `frontend/test/` returns no matches. Only incidental `import 'package:flutter/material.dart'` in `auth_repository_test.dart`. |
| **Why it's a problem** | The design system claims WCAG 2.2 AA contrast for semantic pairs (`color_section.dart` description), but nothing enforces it in CI. Token renames, primitive drift, and `AppTheme` changes can silently break contrast, dark/light parity, or extension registration. |
| **Potential impact** | Accessibility regressions ship undetected; refactors to `AppSemanticColors` have no safety net; motion reduced-mode behavior untested. |
| **Recommended solution** | Add unit tests: (1) `AppContrast` golden ratios for each semantic pair in `02-tokens.md`; (2) `AppSemanticColors.light`/`dark` field count or snapshot; (3) `AppSpacing.token` / `AppRadius.token` exhaustive cases; (4) `AppMotion.resolveDuration` with `disableAnimations: true`; (5) widget test that `MaterialApp(theme: AppTheme.light())` exposes both extensions via `Theme.of`. |

---

### H-02 — `AppSemanticColors` covers ~40% of documented semantic tokens

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/ui/theme/app_semantic_colors.dart`, `frontend/lib/core/ui/theme/app_color_primitives.dart`, `docs/ui/design-system/02-tokens.md` §3 |
| **Evidence** | `AppSemanticColors` exposes 27 color fields. Primitives exist but are **not** mapped to semantics, including: `surfaceBackdropLight/Dark`, `borderStrongDark`, `textDisabledDark`, full status trios (`statusWarning*`, `statusInfo*`, `statusSuccessSurface/Border`, `statusDangerSurface/Border`), `focusRing*`, `actionDisabledBgDark`. Spec also documents `action-primary-hover/active/fg`, `action-secondary`, `border-focus`, `border-strong`, `text-disabled` — none exist on `AppSemanticColors`. Status coverage is only `statusSuccessFg` and `statusDangerFg` (no warning/info, no surface/border trios). |
| **Why it's a problem** | Features will either (a) import primitives directly, violating the three-tier rule, or (b) hardcode hex values. Both undermine light/dark theming and rebrand safety. |
| **Potential impact** | Inconsistent modals (no `surface-backdrop`), broken status badges, missing focus rings for a11y, duplicated one-off colors across features. |
| **Recommended solution** | Expand `AppSemanticColors` to match `02-tokens.md` §3 tables. Map existing primitives already defined in `app_color_primitives.dart`. Add `copyWith`/`lerp` fields in lockstep. Consider generated code from `tokens.json` as the spec recommends. |

---

### H-03 — Domain layer hardcodes Flutter `Color` values (Clean Architecture violation)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/features/appointments/domain/appointment_calendar_display.dart` |
| **Evidence** | `static Color statusColor(AppointmentStatus status)` returns raw `const Color(0xFF…)` values (e.g. `0xFF2563EB`, `0xFFEAB308`) and `filteredOutStatusColor = Color(0xFF9CA3AF)`. These are Tailwind-like hues, not design-system tokens. Domain mapping in `02-tokens.md` §3 says Scheduled → warning, Confirmed/Completed → success, Cancelled/No-show → danger, In progress → info. |
| **Why it's a problem** | Domain should not depend on `dart:ui` / `material.dart` colors. Presentation/theming belongs in `core/ui` or feature presentation mappers. Hardcoded colors bypass dark mode and semantic status trios. |
| **Potential impact** | Calendar colors won't track theme changes; violates dependency rule (domain → Flutter UI); doubles color truth with design tokens. |
| **Recommended solution** | Domain exposes `AppointmentDisplayStatus` enum → semantic status category (`success` / `warning` / `danger` / `info` / `neutral`). Presentation maps category → `context.appColors.status*Fg` (once H-02 is done). Remove `Color` from domain entirely. |

---

### H-04 — `AppTheme.light()` / `dark()` rebuilt on every `AiClinicApp.build`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/app/app.dart`, `frontend/lib/core/ui/theme/app_theme.dart`, `frontend/lib/core/ui/theme/app_typography.dart` |
| **Evidence** | `AiClinicApp.build` passes `theme: AppTheme.light()` and `darkTheme: AppTheme.dark()` inline (`app.dart:65-66`). Each call runs `_build` → `AppTypography.textTheme` → three `GoogleFonts.*TextTheme()` invocations (`app_typography.dart:17-19`). `ref.watch(themeModeProvider)` and `ref.watch(appRouterProvider)` cause rebuilds. |
| **Why it's a problem** | `ThemeData` is immutable and constant for fixed token sets. Rebuilding allocates new objects and may re-resolve Google Fonts on every parent rebuild, even when `themeMode` is unchanged. |
| **Potential impact** | Unnecessary CPU/GC on navigation and session updates; potential font flicker or layout shift on low-end hardware (design target: 8 GB RAM, no GPU). |
| **Recommended solution** | `static final ThemeData light = _build(...)` / `dark` on `AppTheme`, or `late final` in `AiClinicAppState.initState`. Cache `TextTheme` separately. Prefer bundling Inter/JetBrains Mono via `pubspec.yaml` fonts for offline/desktop reliability instead of runtime `google_fonts` fetch. |

---

### H-05 — `ThemeData` under-specified; Material 3 widgets won't match design system

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/ui/theme/app_theme.dart` |
| **Evidence** | `_build` sets only `useMaterial3`, `brightness`, `colorScheme`, `scaffoldBackgroundColor`, `textTheme`, `extensions`, `dividerColor`. No `inputDecorationTheme`, `elevatedButtonTheme`, `filledButtonTheme`, `outlinedButtonTheme`, `iconTheme`, `tooltipTheme`, `dialogTheme`, `cardTheme`, `focusColor`, `hoverColor`, `splashFactory`, or `pageTransitionsTheme`. `ColorScheme.fromSeed(seedColor: semantic.actionPrimary, surface: …, onSurface: …)` still algorithmically derives `primaryContainer`, `error`, `outline`, etc. |
| **Why it's a problem** | Any raw `FilledButton`, `TextField`, `Dialog`, or `Card` inherits Material defaults — not AiClinic semantics. `colorScheme.primary` may diverge from `actionPrimary` in edge roles. |
| **Potential impact** | Visual inconsistency as features adopt Material widgets; focus/hover states won't match `03-motion` instant/fast durations; modals won't use elevation tokens. |
| **Recommended solution** | Build `ColorScheme` explicitly from semantic tokens (or `ColorScheme.fromSeed` + `copyWith` for all roles). Add component themes mapping to `AppSemanticColors`, `AppRadius.md`, `AppElevation`, and `AppMotionDuration`. |

---

### H-06 — Typography implementation diverges from `02-tokens.md` §4

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/ui/theme/app_typography.dart`, `frontend/lib/features/design_system/presentation/foundations/typography_section.dart` |
| **Evidence** | Spec: `font-display` = Geist; `font-arabic` = IBM Plex Sans Arabic; tabular nums on data. Code: both `sans` and `display` use `GoogleFonts.interTextTheme()` (`app_typography.dart:17-18`). No `fontFeatures` / `FontFeature.tabularFigures()`. No locale-based Arabic family switch. Typography section description claims Geist + IBM Plex + tabular nums (`typography_section.dart:67`) but implementation does not deliver. |
| **Why it's a problem** | Headings won't match web reference; financial/table data won't align columns; Arabic RTL typography requirements unmet. |
| **Potential impact** | Brand mismatch with web canonical spec; poor data readability in billing/appointments tables; Arabic locale shows Latin metrics. |
| **Recommended solution** | Add Geist (or bundled fallback) for display styles; `Locale`/`Directionality`-aware `textTheme` branch for Arabic; apply `FontFeature.tabularFigures()` to `labelMedium` (mono) and data-specific helpers. Update showcase copy or implementation — not both diverging. |

---

### H-07 — `AppTypography` reads primitives, not semantic colors

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/ui/theme/app_typography.dart`, `frontend/lib/core/ui/theme/app_semantic_colors.dart` |
| **Evidence** | `textTheme(brightness:)` selects colors from `AppColorPrimitives.textPrimaryDark` / `neutral900` etc. (`app_typography.dart:9-15`), parallel to but independent of `AppSemanticColors.textPrimary`. |
| **Why it's a problem** | Violates “components consume semantic tokens” (`02-tokens.md` §1). A semantic-only theme swap (e.g. high-contrast variant) would update `appColors` but not `TextTheme` colors. |
| **Potential impact** | Split source of truth for text colors; future `ThemeExtension` overrides won't propagate to typography. |
| **Recommended solution** | `AppTheme._build` should pass `AppSemanticColors` into `AppTypography.textTheme(semantic: semantic)` and derive all text colors from that instance. |

---

## 3. Medium-Severity Issues

### M-01 — `theme/app_motion.dart` is a re-export barrel (naming confusion, not logic duplication)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_motion.dart`, `frontend/lib/core/ui/motion/app_motion.dart`, `frontend/lib/core/ui/widgets/widgets.dart` |
| **Evidence** | `theme/app_motion.dart` is a single line: `export 'package:ai_clinic/core/ui/motion/app_motion.dart';`. No file imports `theme/app_motion.dart` (grep returns 0). `widgets.dart` exports `motion/app_motion.dart` directly. Features import `core/ui/motion/app_motion.dart`. |
| **Why it's a problem** | Two paths suggest duplication; dead barrel may mislead contributors. |
| **Potential impact** | Import inconsistency; accidental re-introduction of duplicate motion constants. |
| **Recommended solution** | Remove `theme/app_motion.dart` OR make it the sole export and update all imports. Document canonical path in `core/ui/README` or widgets barrel. |

---

### M-02 — `AppShellTokens.collapseDuration` not aligned with motion tokens

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_shell_tokens.dart`, `frontend/lib/app/shell/navigation/app_sidebar.dart`, `docs/ui/design-system/03-motion.md` |
| **Evidence** | `collapseDuration = Duration(milliseconds: 200)` (`app_shell_tokens.dart:8`). Motion spec: `motion-collapse` uses `duration-quick` = **160ms** + `ease-standard`. Sidebar uses `AppShellTokens.collapseDuration` for `AnimatedContainer`. |
| **Why it's a problem** | Shell animation is off-spec by 40ms and doesn't use `AppMotion.resolveDurationFromTokens`. |
| **Potential impact** | Subtle UX mismatch vs web; sidebar won't respect reduced-motion cap consistently. |
| **Recommended solution** | `static const collapseDuration = AppMotionDuration.quick;` and resolve curve via `AppMotion` with context where possible. |

---

### M-03 — `AppElevation` static `level1`–`level3` aliases are light-theme only

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_elevation.dart` |
| **Evidence** | `static const level1 = AppElevationShadows.level1Light` (lines 37-40). `forLevel(token, brightness:)` exists but is unused in codebase. Consumers use `context.appElevation.shadowsFor(n)` correctly in design system. |
| **Why it's a problem** | Static aliases invite `AppElevation.level2` in dark mode without brightness context — wrong shadows. |
| **Potential impact** | Dark-mode elevation bugs if a developer uses static aliases. |
| **Recommended solution** | Remove static `level1`–`level3` aliases or rename to `level1Light`. Prefer `context.appElevation` exclusively. |

---

### M-04 — `context.appColors` / `context.appElevation` force-unwrap extensions

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_semantic_colors.dart:226`, `frontend/lib/core/ui/theme/app_elevation.dart:119` |
| **Evidence** | `Theme.of(this).extension<AppSemanticColors>()!` — bang operator with no fallback or assert message. |
| **Why it's a problem** | Widget tests, golden tests, or third-party wrappers that omit `AppTheme` extensions crash at runtime with opaque null errors. |
| **Potential impact** | Hard-to-debug test failures; unsafe for reusable components outside main app tree. |
| **Recommended solution** | `extension<AppSemanticColors>() ?? AppSemanticColors.light` in debug with `assert`; or `late final` provider. Document requirement in `AppTheme`. |

---

### M-05 — Light `statusDangerFg` uses `red600` instead of spec `red700`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_semantic_colors.dart:91`, `docs/ui/design-system/02-tokens.md` §3 |
| **Evidence** | `statusDangerFg: AppColorPrimitives.red600` (`#BC3333`). Spec danger `-fg` light = `red-700` (`#9A2828`). `foundation_constants.dart` contrast demo uses `#9A2828` for danger — inconsistent with semantic token. |
| **Why it's a problem** | Token drift between showcase, spec, and runtime semantic accessor. |
| **Potential impact** | Danger text slightly lighter than designed; contrast on `red-50` surfaces may differ from verified pairs. |
| **Recommended solution** | Align to `red700` per spec; add contrast test (H-01). |

---

### M-06 — Motion presets incomplete vs `03-motion.md`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/motion/app_motion.dart`, `docs/ui/design-system/03-motion.md` §5 |
| **Evidence** | `AppMotionPreset` has: fade, fadeScale, slideUp, slideInline, modal, command, rowEnter. Missing: `motion-drawer`, `motion-collapse`, `motion-tab`, `motion-nav`. `AppSignal` AI pulse uses ad-hoc `1200ms` linear loop, not `duration-deliberate` token. |
| **Why it's a problem** | Shell/sidebar/tab animations won't share preset registry; harder to enforce reduced-motion consistently. |
| **Potential impact** | One-off durations proliferate; web/flutter motion parity gaps. |
| **Recommended solution** | Add missing presets to enum + `_presetConfig`; refactor `AppSignal` pulse to `AppMotionDuration.deliberate`. |

---

### M-07 — `AppSpacing.token` / `AppRadius.token` silent fallback masks typos

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_spacing.dart:36`, `frontend/lib/core/ui/theme/app_radius.dart:18` |
| **Evidence** | Unknown keys return `space4` (16px) and `md` (6px) respectively via `_ =>` default branches. |
| **Why it's a problem** | Invalid token strings from CMS/config silently produce wrong layout — no debug signal. |
| **Potential impact** | Subtle layout bugs in token-driven UIs; harder QA. |
| **Recommended solution** | `assert(() { …; return true; }())` in debug; throw `ArgumentError` in release for unknown tokens, or return nullable `double?`. |

---

### M-08 — `AppTooltip` is an unstyled Material passthrough

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/components/app_tooltip.dart` |
| **Evidence** | `return Tooltip(message: message, child: child);` — no `decoration`, `textStyle`, `waitDuration`, or semantic colors. Spec (`03-motion.md`): fade in after ~400ms hover, `duration-fast`. |
| **Why it's a problem** | Tooltips won't match elevation/typography tokens; timing off-spec. |
| **Potential impact** | Inconsistent chrome vs web; accessibility timing mismatch. |
| **Recommended solution** | Wrap with `TooltipTheme` data from `AppTheme`, or custom overlay using `AppTypography.caption` + `AppElevation.level2` + motion tokens. |

---

### M-09 — Primitive palette incomplete vs `02-tokens.md` §2

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_color_primitives.dart` |
| **Evidence** | Missing neutrals `700`, `800`; partial teal/violet scales (e.g. no `teal100-200`, `violet200`); missing `green600`, `amber600`, `red500`, `blue600` from status tables. |
| **Why it's a problem** | Future semantic mappings require adding primitives ad hoc; risks hex typos. |
| **Potential impact** | Incomplete palette blocks full semantic parity (H-02). |
| **Recommended solution** | Generate primitives from `tokens.json` or complete the table to match §2 exactly. |

---

### M-10 — `AppContrast` exists but is not used for enforcement

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/ui/theme/app_contrast.dart`, `frontend/lib/features/design_system/presentation/foundations/color_section.dart`, `foundation_constants.dart` |
| **Evidence** | `AppContrast` only referenced in design-system showcase. Contrast pairs are **duplicated** as hardcoded `Color(0xFF…)` in `foundation_constants.dart` rather than computed from `AppSemanticColors` / primitives. |
| **Why it's a problem** | Showcase can pass while semantic tokens drift; manual pairs can desync (danger fg already does — M-05). |
| **Potential impact** | False confidence in AA compliance. |
| **Recommended solution** | Drive contrast cards from `AppSemanticColors.light/dark` fields; CI test all documented pairs. |

---

### M-11 — `foundation_constants.dart` duplicates palette hex values

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/features/design_system/presentation/foundations/foundation_constants.dart` |
| **Evidence** | `colorPairs` embeds 32 raw `Color(0xFF…)` values matching primitives, not referencing `AppColorPrimitives`. |
| **Why it's a problem** | Second source of truth in presentation layer; already diverging on danger fg (M-05). |
| **Potential impact** | Design system page misrepresents actual theme tokens. |
| **Recommended solution** | Build pairs from `AppSemanticColors` + status surface tokens once H-02 is complete. |

---

## 4. Low-Severity Issues

### L-01 — `AppElevation.lerp` uses step function, not shadow interpolation

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/ui/theme/app_elevation.dart:107-114` |
| **Evidence** | `if (t < 0.5) return this; return other;` — discrete swap at midpoint. |
| **Why it's a problem** | Animated theme transitions may flash elevation levels. |
| **Potential impact** | Minor visual artifact during theme-mode animation (rare). |
| **Recommended solution** | Document as intentional (shadow lerp is hard) or interpolate blur/color per shadow. |

---

### L-02 — Magic number `6` used instead of spacing token

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `app_command_bar_trigger.dart:38`, `app_branch_switcher.dart:54`, `motion_section.dart:213,245`, `foundations_content.dart:35` |
| **Evidence** | `vertical: 6` — not `AppSpacing.space1` (4) or `space2` (8). No `space-1.5` (6px) in scale. |
| **Why it's a problem** | Off-scale spacing breaks 4px grid alignment. |
| **Potential impact** | 2px visual inconsistency on compact controls. |
| **Recommended solution** | Add `space1_5 = 6.0` to spec/tokens or use `space2` consistently. |

---

### L-03 — Signal component hardcodes thickness/glow constants

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/ui/components/app_signal.dart`, `docs/ui/design-system/02-tokens.md` §9 |
| **Evidence** | `_thickness = 2.0`, `_thicknessHero = 3.0`, glow `blurRadius: 8`, alpha `0.35` inline. Spec defines `signal-thickness`, `signal-glow` tokens. |
| **Why it's a problem** | Signature motif not centrally tokenized. |
| **Potential impact** | Signal tweaks require component edit, not token swap. |
| **Recommended solution** | `AppSignalTokens` abstract class in theme folder. |

---

### L-04 — Missing ancillary token files from spec

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | N/A (not implemented) |
| **Evidence** | No `AppZIndex`, `AppBorderWidth`, `AppIconSize`, `radius-none` in `AppRadius`. Spec §8, §10, §12. |
| **Why it's a problem** | Contributors will invent local constants. |
| **Potential impact** | Z-index stacking bugs; inconsistent icon sizes. |
| **Recommended solution** | Add minimal token files as features need them. |

---

### L-05 — Shell density variants not implemented

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/ui/theme/app_shell_tokens.dart`, `02-tokens.md` §11 |
| **Evidence** | Only comfortable defaults (`topBarHeight: 56`, `navItemHeight: 36`). No compact/comfortable density switch. |
| **Why it's a problem** | Spec promises density-scoped shell; Flutter has single static values. |
| **Potential impact** | Cannot match web `data-density` modes. |
| **Recommended solution** | `AppShellTokens.forDensity(Density)` when settings feature lands. |

---

### L-06 — `AppMotionEasing.emphasized` identical to `standard`

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/ui/motion/app_motion.dart:17,21` |
| **Evidence** | Both `Cubic(0.2, 0, 0, 1)`. Spec distinguishes emphasized by longer duration pairing, not different bezier. |
| **Why it's a problem** | None functionally — matches spec note. |
| **Potential impact** | None. |
| **Recommended solution** | Add comment referencing `03-motion.md` §2 to prevent “fixing” into a different curve. |

---

## 5. Feature Consumption Audit

| Location | Pattern | Assessment |
|----------|---------|------------|
| `app/shell/*` | `context.appColors`, `AppSpacing`, `AppTypography`, `AppRadius`, `AppShellTokens` | **Good** — canonical usage |
| `core/ui/components/*` | Semantic colors + radius; motion in `AppSignal` | **Good** |
| `features/design_system/*` | Tokens + showcase constants | **Mixed** — hardcoded `colorPairs` (M-11) |
| `features/appointments/domain/*` | Raw `Color(0xFF…)` | **Bad** — H-03 |
| Other features | No theme imports yet | **N/A** — early codebase |

**Import path consistency:** Motion imported from `core/ui/motion/` (3 files). Theme tokens imported from `core/ui/theme/` or via `widgets.dart`. No feature imports `app_color_primitives.dart` directly — **good**.

---

## 6. Accessibility & Contrast Notes

| Pair | Spec intent | Code status |
|------|-------------|-------------|
| Primary text on canvas | AA required | Mapped correctly via semantics |
| Action primary fg on action primary | `action-primary-fg` | **No semantic field** — consumers must guess `textInverse` |
| Text link on surface | `teal-700` / `teal-300` | Present as `textLink` — **not contrast-tested in CI** |
| Danger on danger surface | `red-700` on `red-50` | Semantic uses `red600` (M-05); showcase uses `red-700` |
| Focus visibility | `focus-ring` tokens in primitives | **Not exposed** — Material focus defaults only |

`AppContrast.meetsAA` supports `large: true` (3:1) but `color_section.dart` always calls `meetsAA(ratio)` with default `large: false` — correct for body text samples.

---

## 7. Performance Notes

| Item | Assessment |
|------|------------|
| Token classes | `const` primitives and semantic statics — **good** |
| `AppSpacing` / `AppRadius` | `const` doubles — **good** |
| `AnimatedBuilder` in `AppMotion.animatedPreset` | Uses `child:` caching — **good** |
| `GoogleFonts` in theme build | Called per `AppTheme._build` — **bad** (H-04) |
| `Theme.of(context)` in `AppTypography.*(context)` | Lookup per call; acceptable if text styles cached on `ThemeData` |
| Extension force-unwrap | No perf impact |

---

## 8. Recommended Remediation Order

1. **H-04** — Memoize `AppTheme.light` / `dark` (quick win, immediate perf).
2. **H-01** — Contrast + extension registration tests.
3. **H-02 + H-07** — Complete `AppSemanticColors`; wire typography to semantics.
4. **H-05** — Material component themes.
5. **H-03** — Remove `Color` from appointments domain.
6. **H-06** — Typography fonts/features (Geist, Arabic, tabular nums).
7. **M-01–M-11** — Motion path cleanup, shell duration, elevation aliases, token fallbacks.
8. **L-*** — Polish spacing grid, signal tokens, density.

---

## 9. Files Reviewed

| File | Lines | Role |
|------|-------|------|
| `app_color_primitives.dart` | 98 | Primitive palette |
| `app_semantic_colors.dart` | 227 | Semantic `ThemeExtension` |
| `app_motion.dart` (theme) | 1 | Re-export barrel |
| `app_motion.dart` (motion) | 225 | Motion presets & utilities |
| `app_elevation.dart` | 121 | Elevation `ThemeExtension` |
| `app_typography.dart` | 115 | Text theme builder |
| `app_spacing.dart` | 39 | Spacing scale |
| `app_theme.dart` | 31 | `ThemeData` factory |
| `app_contrast.dart` | 30 | WCAG contrast math |
| `app_radius.dart` | 21 | Radius scale |
| `app_shell_tokens.dart` | 9 | Shell layout constants |
| `app.dart` | 72 | Theme application |
| `widgets.dart` | 20 | Barrel exports |
| `foundation_constants.dart` | 165 | Showcase duplicates |
| `color_section.dart` | 183 | Contrast demo |
| `appointment_calendar_display.dart` | 400+ | Domain color leak |

---

*Review performed by static analysis and cross-reference against `docs/ui/design-system/02-tokens.md` and `03-motion.md`. No runtime golden or contrast tests were executed.*
