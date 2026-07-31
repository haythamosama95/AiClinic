# Flutter Core — Second-Cycle UI Theme & Motion Review

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/ui/theme/*`, `frontend/lib/core/ui/motion/*`, theme consumption in `features/` and `app/`, `frontend/test/`  
**Baseline:** [flutter-core-review-ui-theme.md](flutter-core-review-ui-theme.md), [flutter-core-code-review.md](flutter-core-code-review.md)  
**Canonical reference:** `docs/ui/design-system/02-tokens.md`, `03-motion.md`  
**Method:** Re-read every theme/motion file; cross-check spec; grep hardcoded colors; verify first-cycle Critical/High/Medium status.

---

## Summary Counts

| Category | First-cycle | Second-cycle status | New this cycle |
|----------|-------------|---------------------|----------------|
| Critical | 0 | 0 open | 0 |
| High | 7 | **7 STILL OPEN** | **3** |
| Medium | 11 (theme) | **10 STILL OPEN** (M-08 is components) | **3** |
| Fixed since first cycle | — | **0** | — |

**Verdict:** No remediation landed in theme/motion since the first review. Semantic coverage, typography, motion alignment, performance, and test gaps are unchanged. Second-cycle scrutiny surfaced **active test lock-in** of wrong calendar colors and a **false WCAG gate** in the design-system showcase.

**C-04 (theme slice):** Zero automated tests for `AppTheme`, `AppSemanticColors`, `AppContrast`, `AppMotion`, or extension registration. Severity **High** for theme infrastructure (cross-ref consolidated **C-04**).

---

## Critical Issues

*None in theme/motion layer. No runtime crashes from theme code; risks are spec drift, false a11y confidence, and blocked token migration.*

---

## High Priority Issues

### First-Cycle High — Status Tracker

| ID | Issue | First-cycle status | Evidence |
|----|-------|-------------------|----------|
| H-01 | No automated theme/token/contrast/motion tests | **STILL OPEN** | `grep` over `frontend/test/` for `AppTheme`, `AppSemanticColors`, `AppContrast`, `AppMotion` → **0 matches**; no `*theme*` test files |
| H-02 | `AppSemanticColors` ~40% of spec | **STILL OPEN** | 27 semantic fields; primitives exist for `surfaceBackdrop*`, status trios, `focusRing*`, `textDisabledDark`, `borderStrongDark` but are **not** mapped to semantics |
| H-03 | Domain hardcodes `Color(0xFF…)` | **STILL OPEN** | `appointment_calendar_display.dart:283-304` still returns raw hex values |
| H-04 | `AppTheme.light()/dark()` rebuilt every `build` | **STILL OPEN** | `app.dart:65-66` calls factories inline; `app_theme.dart:9-11` are methods, not cached `static final` |
| H-05 | `ThemeData` under-specified | **STILL OPEN** | `app_theme.dart:21-29` sets only base fields; no component themes; `ColorScheme.fromSeed` at lines 14-19 |
| H-06 | Typography diverges from spec | **STILL OPEN** | `app_typography.dart:17-19` — Inter for both sans and display; no Geist, IBM Plex Arabic, or `FontFeature.tabularFigures()` |
| H-07 | `AppTypography` reads primitives, not semantics | **STILL OPEN** | `app_typography.dart:9-15` uses `AppColorPrimitives.*`; `app_theme.dart:26` does not pass `semantic` into typography |

---

### H-01 — No automated theme or token tests (first-cycle; STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `frontend/lib/core/ui/theme/*`, `frontend/lib/core/ui/motion/app_motion.dart`, `frontend/test/` |
| **Evidence** | No test references to theme APIs. `shell_dev_security_test.dart` covers dev routing only — not tokens, contrast, or motion. |
| **Why** | WCAG claims in `color_section.dart:26` are unenforced in CI. Token renames, `red600` vs `red700` drift, reduced-motion behavior, and extension registration have no safety net. |
| **Impact** | Accessibility and design-system regressions ship silently; refactors to `AppSemanticColors` are unsafe. |
| **Solution** | Add `test/unit/core/ui/`: contrast ratios from `AppSemanticColors.light/dark`; extension presence on `MaterialApp(theme: AppTheme.light())`; `AppMotion.resolveDuration` with `disableAnimations`; `AppSpacing`/`AppRadius` exhaustive cases. |

**C-04 note:** Theme-specific portion of C-04 is **High** — shell depends on `context.appColors` / extensions on every route; zero theme tests.

---

### H-02 — `AppSemanticColors` covers ~40% of documented semantic tokens (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `app_semantic_colors.dart`, `app_color_primitives.dart`, `02-tokens.md` §3 |
| **Evidence** | Implemented: 27 fields (lines 8-64). Missing vs spec: `surface-backdrop`, `text-disabled`, `border-strong`, `border-focus`, `action-primary-hover/active/fg`, `action-secondary*`, `action-disabled-bg`, `focus-ring*`, full status trios (warning/info surfaces+borders; light-mode success/danger/warning/info surfaces+borders). Primitives already defined e.g. `surfaceBackdropLight` (`app_color_primitives.dart:61-62`), `statusWarningFgDark` (`:82-84`), `focusRingLight` (`:94-97`) — unmapped. |
| **Why** | Forces features to hardcode or import primitives, breaking three-tier rule and dark-mode parity. |
| **Impact** | Modals lack backdrop token; badges/chips cannot use status trios; focus rings unavailable for a11y. |
| **Solution** | Expand `AppSemanticColors` to match `02-tokens.md` §3; keep `copyWith`/`lerp` in sync. |

---

### H-03 — Domain layer hardcodes Flutter `Color` values (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `features/appointments/domain/appointment_calendar_display.dart` |
| **Evidence** | ```283:304:frontend/lib/features/appointments/domain/appointment_calendar_display.dart``` |
| **Why** | Clean Architecture violation; bypasses tokens and dark mode. |
| **Impact** | Calendar is first major feature consumer of colors outside the design system. |
| **Solution** | Domain exposes status **category** enum; presentation maps to `context.appColors.status*`. |

---

### H-04 — `AppTheme` rebuilt on every `AiClinicApp.build` (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `app.dart`, `app_theme.dart`, `app_typography.dart` |
| **Evidence** | ```65:66:frontend/lib/app/app.dart``` — `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()` inside `build` with `ref.watch(appRouterProvider)` and `ref.watch(themeModeProvider)`. Each call runs three `GoogleFonts.*TextTheme()` (`app_typography.dart:17-19`). |
| **Why** | `ThemeData` is immutable for fixed token sets; unnecessary allocation and font resolution on unrelated rebuilds. |
| **Impact** | CPU/GC on navigation and session updates; possible font flicker on 8 GB / no-GPU targets. |
| **Solution** | `static final` cached themes; bundle fonts via `pubspec.yaml` (currently commented out at `pubspec.yaml:111-118`). |

---

### H-05 — `ThemeData` under-specified (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `app_theme.dart` |
| **Evidence** | ```13:29:frontend/lib/core/ui/theme/app_theme.dart``` — only `useMaterial3`, `colorScheme`, `scaffoldBackgroundColor`, `textTheme`, `extensions`, `dividerColor`. No `inputDecorationTheme`, button themes, `tooltipTheme`, `dialogTheme`, `focusColor`, `pageTransitionsTheme`. |
| **Why** | Raw Material widgets inherit M3 defaults, not AiClinic semantics. `ColorScheme.fromSeed` algorithmically derives `primary`, `error`, `outline` — may diverge from `actionPrimary`. |
| **Impact** | Visual inconsistency as features adopt Material widgets. |
| **Solution** | Explicit `ColorScheme` from semantic tokens + component themes wired to `AppRadius`, `AppElevation`, `AppMotionDuration`. |

---

### H-06 — Typography diverges from `02-tokens.md` §4 (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `app_typography.dart`, `typography_section.dart` |
| **Evidence** | Code: Inter for sans **and** display (`app_typography.dart:17-18`). Showcase claims Geist + IBM Plex + tabular nums (`typography_section.dart:67`) — implementation does not deliver. No `FontFeature` usage anywhere under `frontend/lib/`. |
| **Why** | Brand mismatch with web; Arabic RTL typography unmet; financial columns won't align. |
| **Impact** | Billing/appointments tables readability; locale `ar` shows Latin metrics. |
| **Solution** | Geist display, locale-aware Arabic family, `FontFeature.tabularFigures()` on mono/data styles. |

---

### H-07 — `AppTypography` reads primitives, not semantic colors (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | STILL OPEN |
| **Files** | `app_typography.dart`, `app_theme.dart` |
| **Evidence** | ```8:15:frontend/lib/core/ui/theme/app_typography.dart``` vs ```75:91:frontend/lib/core/ui/theme/app_semantic_colors.dart``` — parallel color sources. `_build` passes only `brightness`, not `semantic`. |
| **Why** | Violates “components consume semantic tokens” (`02-tokens.md` §1). High-contrast or semantic overrides won't propagate to `TextTheme`. |
| **Impact** | Split source of truth for text colors. |
| **Solution** | `AppTypography.textTheme(semantic: semantic)` called from `_build`. |

---

### NH-01 — Calendar status mapping contradicts spec domain-status mapping (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | New (escalates H-03) |
| **Files** | `appointment_calendar_display.dart`, `02-tokens.md` §3 (lines 179-183) |
| **Evidence** | Spec: Scheduled → **warning**; Confirmed/Completed → **success**; Cancelled/No-show → **danger**; In progress → **info**. Code: per-status Tailwind hues — `confirmed` → blue `0xFF2563EB`, `inProgress` → orange `0xFFEA580C`, `scheduled` → slate `0xFF8B9CB3`, etc. |
| **Why** | Not only a layer violation — semantics are **wrong** relative to the canonical domain mapping, so token migration alone won't fix UX without remapping. |
| **Impact** | Calendar legend and tiles won't match badges, web reference, or status chips when those ship. |
| **Solution** | Map statuses to semantic categories per spec; presentation reads `statusWarningFg` / `statusSuccessFg` / etc. once H-02 is done. |

---

### NH-02 — Calendar unit tests lock hardcoded hex as contract (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | New |
| **Files** | `frontend/test/unit/appointments/appointment_calendar_display_test.dart` |
| **Evidence** | ```137:144:frontend/test/unit/appointments/appointment_calendar_display_test.dart``` — asserts exact `Color(0xFF2563EB)`, `0xFFEAB308`, etc. |
| **Why** | CI **actively prevents** migrating to semantic tokens; fixing H-03/NH-01 requires test rewrites and will look like regressions. |
| **Impact** | Design-system adoption blocked for the first feature that needs status colors at scale. |
| **Solution** | Replace hex assertions with semantic category mapping tests; widget/golden tests against themed colors. |

---

### NH-03 — Design-system contrast showcase validates duplicate constants, not runtime semantics (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | New (escalates M-05, M-10) |
| **Files** | `color_section.dart`, `foundation_constants.dart`, `app_semantic_colors.dart` |
| **Evidence** | Showcase: “WCAG 2.2 AA contrast verification” (`color_section.dart:26`) using `colorPairs` from `foundation_constants.dart:37-93`. Danger pair uses `fg: Color(0xFF9A2828)` (red-700). Runtime: `statusDangerFg: AppColorPrimitives.red600` (`app_semantic_colors.dart:91`). Showcase can pass while production tokens fail spec intent. |
| **Why** | False confidence in AA compliance; manual pairs already diverge from `AppSemanticColors`. |
| **Impact** | Accessibility regressions in real UI undetected by the design-system page. |
| **Solution** | Drive contrast cards from `AppSemanticColors.light/dark`; CI tests all documented pairs against live semantics. |

---

## Medium Priority Issues

### First-Cycle Medium — Status Tracker

| ID | Issue | First-cycle status | Evidence |
|----|-------|-------------------|----------|
| M-01 | `theme/app_motion.dart` dead re-export | **STILL OPEN** | Single-line export; **0 imports** of `theme/app_motion` in `frontend/lib/` |
| M-02 | `AppShellTokens.collapseDuration` off-spec | **STILL OPEN** | `app_shell_tokens.dart:8` = 200ms; spec `motion-collapse` = 160ms (`03-motion.md`); used in `app_sidebar.dart:97` |
| M-03 | `AppElevation.level1–3` light-only static aliases | **STILL OPEN** | `app_elevation.dart:37-40` |
| M-04 | Extension force-unwraps | **STILL OPEN** | `app_semantic_colors.dart:226`, `app_elevation.dart:119` — `extension<...>()!` |
| M-05 | Light `statusDangerFg` uses `red600` not spec `red700` | **STILL OPEN** | `app_semantic_colors.dart:91` |
| M-06 | Motion presets incomplete; Signal pulse ad-hoc | **STILL OPEN** | `AppMotionPreset` missing drawer/collapse/tab/nav; `app_signal.dart:62` uses `1200ms` not `AppMotionDuration.deliberate` (480ms) |
| M-07 | `AppSpacing`/`AppRadius` silent fallback | **STILL OPEN** | `app_spacing.dart:36` → `space4`; `app_radius.dart:18` → `md` |
| M-08 | `AppTooltip` passthrough | **Out of scope** (components) | — |
| M-09 | Primitive palette incomplete vs spec §2 | **STILL OPEN** | Missing `neutral700/800`, partial teal/violet scales, `green600`, `amber600`, `red500`, `blue600` |
| M-10 | `AppContrast` not used for enforcement | **STILL OPEN** | Only referenced from `color_section.dart`; not applied to `AppSemanticColors` |
| M-11 | `foundation_constants.dart` duplicates palette | **STILL OPEN** | 32 hardcoded hex values; danger fg already diverges (M-05) |

---

### M-01 — Dead `theme/app_motion.dart` re-export (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | ```1:1:frontend/lib/core/ui/theme/app_motion.dart``` — re-export only. Canonical path is `core/ui/motion/app_motion.dart` via `widgets.dart:9`. |
| **Solution** | Remove dead barrel or make it sole export; document canonical path. |

---

### M-02 — Shell collapse duration off-spec (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `AppShellTokens.collapseDuration = Duration(milliseconds: 200)` vs `AppMotionDuration.quick` = 160ms; sidebar does not call `AppMotion.resolveDurationFromTokens` or respect reduced-motion cap. |
| **Solution** | `static const collapseDuration = AppMotionDuration.quick`; resolve with context in `AnimatedContainer`. |

---

### M-03 — Light-only elevation static aliases (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | ```37:40:frontend/lib/core/ui/theme/app_elevation.dart``` |
| **Solution** | Remove or rename to `level1Light`; prefer `context.appElevation`. |

---

### M-04 — Theme extension force-unwraps (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | ```225:227:frontend/lib/core/ui/theme/app_semantic_colors.dart```, ```118:120:frontend/lib/core/ui/theme/app_elevation.dart``` |
| **Solution** | Debug assert + fallback to `.light`/`.dark`; document `AppTheme` requirement. |

---

### M-05 — `statusDangerFg` token drift (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `statusDangerFg: AppColorPrimitives.red600` vs spec `red-700` (`#9A2828`); showcase uses `#9A2828` (`foundation_constants.dart:82`). |
| **Solution** | Align to `red700`; add contrast test (H-01). |

---

### M-06 — Motion presets incomplete (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `AppMotionPreset` (`app_motion.dart:25-33`): 7 presets; spec `03-motion.md` §4 lists 11 including `motion-drawer`, `motion-collapse`, `motion-tab`, `motion-nav`. Signal pulse: `1200ms` linear (`app_signal.dart:62`) vs `duration-deliberate` (480ms) token. |
| **Solution** | Add missing presets; tokenize Signal pulse duration. |

---

### M-07 — Token lookup silent fallbacks (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `AppSpacing.token` / `AppRadius.token` default branches mask typos. |
| **Solution** | Debug `assert` or `ArgumentError` on unknown keys. |

---

### M-09 — Primitive palette incomplete (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `app_color_primitives.dart` — no `neutral700/800`; incomplete teal/violet scales; missing mid-status primitives from `02-tokens.md` §2. |
| **Solution** | Complete palette or generate from `tokens.json`. |

---

### M-10 — `AppContrast` not driving enforcement (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `AppContrast` (`app_contrast.dart`) only consumed by showcase; pairs are hardcoded duplicates (NH-03). |
| **Solution** | CI contrast suite over `AppSemanticColors` fields. |

---

### M-11 — Showcase duplicates palette (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | STILL OPEN |
| **Evidence** | `foundation_constants.dart:37-93` — second source of truth; already diverges on danger fg. |
| **Solution** | Build pairs from semantics once H-02 is complete. |

---

### NM-01 — `widgets.dart` publicly exports primitives (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | New |
| **Files** | `frontend/lib/core/ui/widgets/widgets.dart` |
| **Evidence** | Line 12 exports `app_color_primitives.dart` alongside semantic tokens. Spec rule: components must not consume primitives (`02-tokens.md` §1). Barrel is the documented public API but is **unused** in production imports today. |
| **Why** | Invites primitive leak when features adopt the barrel. |
| **Impact** | Three-tier architecture eroded at the front door. |
| **Solution** | Remove primitive export from public barrel; keep primitives theme-internal only. |

---

### NM-02 — `AppTypography.forToken` silent fallback (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | New |
| **Files** | `app_typography.dart` |
| **Evidence** | ```97:113:frontend/lib/core/ui/theme/app_typography.dart``` — unknown token → `body(context)` (same anti-pattern as M-07). |
| **Why** | Token-driven UIs (design-system, CMS) hide typos. |
| **Solution** | Assert in debug; throw or return nullable in release. |

---

### NM-03 — No bundled fonts; runtime `google_fonts` only (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **First-cycle status** | New (extends H-04/H-06) |
| **Files** | `pubspec.yaml`, `app_typography.dart` |
| **Evidence** | `google_fonts: ^6.2.1` in use; `pubspec.yaml` fonts section commented out (`# fonts:`). Every theme build resolves fonts at runtime. |
| **Why** | Desktop clinic targets may be offline or block font CDN; first launch depends on network. |
| **Impact** | FOUT, fallback fonts, or startup delay on constrained networks. |
| **Solution** | Bundle Inter, JetBrains Mono (and Geist/IBM Plex when added) in `pubspec.yaml`. |

---

## Consolidation Summary

| Theme | Count |
|-------|-------|
| First-cycle High still open | 7 |
| First-cycle Medium still open (theme scope) | 10 |
| First-cycle fixes | **0** |
| New High | 3 (NH-01–NH-03) |
| New Medium | 3 (NM-01–NM-03) |
| New Critical | 0 |

**Highest-risk cluster (unchanged + new):**

1. **No CI guardrails** (H-01, C-04 theme slice) — entire design system unprotected.
2. **Incomplete semantics** (H-02) — blocks badges, modals, focus rings; primitives exist but unmapped.
3. **Calendar color debt** (H-03, NH-01, NH-02) — wrong spec mapping, domain leak, tests cement bad hex.
4. **False a11y confidence** (NH-03, M-05, M-10) — showcase passes on duplicate constants while runtime uses `red600`.
5. **Performance + typography debt** (H-04, H-06, H-07) — per-build `GoogleFonts`, no semantic typography wiring.

**Recommended second-cycle priority:** (1) NH-02 + H-03 + NH-01 together before calendar UI ships; (2) H-01/NH-03 contrast tests on real `AppSemanticColors`; (3) H-04 quick cache win; (4) H-02 status trios + backdrop for upcoming shell components.
