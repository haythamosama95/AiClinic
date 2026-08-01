# Flutter Core UI Components Review

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/ui/components/*`, `frontend/lib/core/ui/widgets/widgets.dart`, `frontend/lib/core/ui/motion/app_motion.dart`, `frontend/lib/core/ui/theme/app_motion.dart`  
**Cross-checks:** Feature usage under `frontend/lib/features/`, shell integration (`app/shell/navigation/`), web reference (`web-reference/src/`), design spec (`docs/ui/design-system/04-components.md`)  
**Tests searched:** `frontend/test/**` — no widget tests for scoped components

---

## Executive Summary

The five scoped primitives (`AppIconButton`, `AppSignal`, `AppBadge`, `AppAvatar`, `AppTooltip`) are **thin, readable Material wrappers** with correct token wiring for colors, radius, and typography. `AppSignal` is the most complete implementation: it honors reduced motion, matches web pulse timing (1.2s linear), and is used consistently in shell navigation and the design-system showcase.

However, the set is **far below design-system and web-reference parity**. Four of five components implement only a single visual variant. `AppBadge` cannot express the `AppBadgeTone` enum already defined in the appointments domain. `AppTooltip` adds no design-system behavior beyond renaming `Tooltip`. The `widgets.dart` barrel is **never imported** by production code; shell and features import `core/ui/components/*` directly, diverging from documented import conventions.

`core/ui/theme/app_motion.dart` is a **re-export only** — no logic duplication with `core/ui/motion/app_motion.dart`. Motion tokens are substantive and well-aligned with the web `motion.ts` preset model.

**There are zero widget or golden tests** for any scoped component despite shell-critical usage (nav active indicator, icon actions, avatar menu trigger).

| Category | Count |
|----------|-------|
| Critical | 2 |
| High | 9 |
| Medium | 11 |
| Low | 8 |
| Accessibility gaps | 7 |
| Design-system parity gaps | 6 |
| Test coverage gaps | 5 |
| Architecture / convention drift | 4 |

**Recommended action:** Extend `AppBadge` with tone/variant API before appointments UI ships; add widget tests for shell-used primitives; unify tooltip usage and barrel imports; flesh out `AppIconButton` variants and `AppAvatar` a11y before feature screens proliferate ad-hoc copies (notification count pill is already a precedent).

---

## Architecture Overview

```
features/*  ──direct import──►  core/ui/components/app_*.dart
app/shell/* ──direct import──►  core/ui/components/app_*.dart

core/ui/widgets/widgets.dart  (barrel: components + motion + theme)
         │
         └── not imported by any production Dart file

core/ui/motion/app_motion.dart  ◄── canonical motion tokens & presets
core/ui/theme/app_motion.dart   ◄── re-export shim (single source of truth)

Material 3 (ThemeData + AppSemanticColors)  ◄── all components read context.appColors
```

**Intended pattern (from `docs/ui/forui-wrappers.md`):** Features import `package:ai_clinic/core/ui/widgets/widgets.dart` only.  
**Actual pattern:** Components live under `core/ui/components/` (not `core/ui/widgets/`). Forui wrappers referenced in docs **do not exist** in the current tree (`AppButton`, `ForuiAppScope`, `package:forui` absent from `pubspec.yaml`). The barrel exports the new primitives but is unused.

---

## File Inventory

| File | Lines | Type | Design ref |
|------|-------|------|------------|
| `app_icon_button.dart` | 49 | StatelessWidget | `04-components` A2 |
| `app_signal.dart` | 124 | StatefulWidget | Signal primitive (nav, AI pulse) |
| `app_badge.dart` | 26 | StatelessWidget | `04-components` D7 |
| `app_avatar.dart` | 39 | StatelessWidget | `04-components` D9 |
| `app_tooltip.dart` | 15 | StatelessWidget | `04-components` D10 |
| `widgets/widgets.dart` | 21 | Barrel | Documented feature entrypoint |
| `motion/app_motion.dart` | 225 | Tokens + helpers | `03-motion`, web `motion.ts` |
| `theme/app_motion.dart` | 1 | Re-export | Convenience path only |

---

## Feature & Shell Usage Map

| Component | Production consumers | Notes |
|-----------|---------------------|-------|
| `AppIconButton` | `app_top_bar.dart`, `app_sidebar.dart` | Notifications, theme toggle, sidebar collapse |
| `AppSignal` | `app_sidebar.dart`, `dev_tabs.dart` | Active nav edge; tab underline in dev page |
| `AppBadge` | `app_sidebar.dart` | Nav item count only |
| `AppAvatar` | `app_user_menu.dart` | Menu trigger |
| `AppTooltip` | `app_sidebar.dart` | Collapsed nav labels only |
| `AppBadgeTone` (enum) | `appointment_queue_display.dart` | **Domain enum only** — widget has no `tone` parameter |

**Design-system showcase:** `signal_section.dart` demos standard/hero/AI pulse variants.

**Not used in `features/`:** `AppIconButton`, `AppBadge`, `AppAvatar`, `AppTooltip` have zero feature-layer consumers. Early feature work will either import shell patterns or reinvent primitives.

---

## Motion Files Comparison

| Aspect | `core/ui/motion/app_motion.dart` | `core/ui/theme/app_motion.dart` |
|--------|----------------------------------|----------------------------------|
| Content | Full implementation (durations, easings, presets, `prefersReducedMotion`, `animatedPreset`) | `export '.../motion/app_motion.dart';` |
| Duplication | None — single implementation | Shim for theme-folder discoverability |
| Import usage | `app_signal.dart`, `motion_section.dart`, `foundation_constants.dart` | Available via `widgets.dart` barrel only |

**Verdict:** No harmful duplication. Prefer one canonical import path in style guide (`motion/` or `theme/`, not both) to avoid reviewer confusion.

---

## 1. Critical Issues

### C-01 — `AppBadgeTone` domain enum has no widget counterpart

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `features/appointments/domain/appointment_queue_display.dart` (`AppBadgeTone`, `scheduleBadgeTone`); `core/ui/components/app_badge.dart` |
| **Evidence** | Domain defines `AppBadgeTone { neutral, info, success, warning, destructive, muted }` and maps `AppointmentStatus` → tone. `AppBadge` accepts only `label` with fixed `surfaceSunken` styling — no `tone`, `variant`, or `color` parameter. |
| **Why it's a problem** | When appointments queue UI ships, developers will either (a) ignore `AppBadgeTone` and hard-code colors, (b) duplicate badge styling inline (as `app_top_bar.dart` already does for notifications), or (c) place presentation enum mapping inside a widget wrapper — inverting Clean Architecture. |
| **Potential impact** | Inconsistent status chips across features; domain/presentation contract drift; repeated inline `DecoratedBox` badge copies. |
| **Recommended solution** | Add `AppBadgeVariant`, `AppBadgeTone` (or `AppBadgeColor`) to `app_badge.dart` with soft/solid/outline/dot variants per `04-components` D7. Move or re-export tone enum from core (presentation), map domain status → tone in presentation layer only. |

---

### C-02 — Zero automated tests for shell-critical primitives

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | All scoped `app_*.dart`; `app/shell/navigation/*` |
| **Evidence** | `grep` across `frontend/test/` finds no references to `AppIconButton`, `AppSignal`, `AppBadge`, `AppAvatar`, or `AppTooltip`. No golden files under `test/goldens/` for these widgets. |
| **Why it's a problem** | Active nav indicator, accessibility labels on collapsed sidebar, avatar initials edge cases, and AI pulse lifecycle (`AnimationController` create/dispose on `thinking` toggle) are untested. Regressions in shell affect every route. |
| **Potential impact** | Silent a11y breakage; animation controller leaks; visual drift from web reference undetected in CI. |
| **Recommended solution** | Add `test/widget/core/ui/` suite: pump each component in light/dark theme; `AppSignal` thinking on/off/dispose; `AppAvatar` initials matrix (`''`, `'A'`, `'Ada Lovelace'`, RTL names); `AppIconButton` disabled + semantics; golden for badge tones once implemented. |

---

## 2. High Priority Issues

### H-01 — `AppBadge` implements ~5% of design-system D7

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_badge.dart`; spec `04-components.md` D7; web `Badge.tsx` |
| **Evidence** | Flutter: single neutral pill, `AppRadius.sm`, 12px label. Spec: variants `solid` · `soft` · `outline` · `dot`; colors from status set + neutral + teal + violet(AI); sizes `sm` · `md`; dot variant requires accessible label. Web implements full matrix. |
| **Why it's a problem** | Component name promises design-system badge; implementation is a count chip only. Features will not get status semantics from this primitive. |
| **Recommended solution** | Port web `Badge` API surface; default `soft` + `neutral`; map semantic colors from `AppSemanticColors` (extend with status surface tokens if missing). |

---

### H-02 — Notification count reimplements badge styling inline

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_top_bar.dart` (lines 96–118); `app_badge.dart` |
| **Evidence** | `Stack` + `PositionedDirectional` + `Container` with `statusDangerFg` background, 10px text, `9+` cap — parallel responsibility to `AppBadge` but visually distinct (circular vs rounded-sm pill). |
| **Why it's a problem** | First precedent for bypassing `AppBadge`; duplicates sizing, cap logic, and color tokens. |
| **Recommended solution** | Add `AppBadge` variant for numeric notification overlay or `AppNotificationBadge` composed from shared badge tokens; use in top bar. |

---

### H-03 — `AppIconButton` missing spec variants, states, and press motion

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_icon_button.dart`; spec A2; web `IconButton.tsx` |
| **Evidence** | Flutter: ghost-only styling via `IconButton.styleFrom`. Spec: variants `ghost` · `secondary` · `danger` · `ai`; `aria-busy` when loading; press scale 0.98. Web: `variant`, `error`, `disabled` tooltip skip, `active:scale-[0.98]`. |
| **Why it's a problem** | Toolbar actions for destructive/AI contexts will use raw `IconButton` or duplicate styles. |
| **Recommended solution** | Add `AppIconButtonVariant`, optional `loading` (`SizedBox` + `CircularProgressIndicator`), `Semantics(label: tooltip, button: true, enabled: onPressed != null)`; wrap with `ScaleTransition` or `InkWell` splash matching `AppMotion.fast`. |

---

### H-04 — `AppIconButton` uses raw `Tooltip`; shell uses `AppTooltip` elsewhere

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_icon_button.dart`; `app_sidebar.dart`; `app_tooltip.dart` |
| **Evidence** | `AppIconButton` wraps `Tooltip` directly. Collapsed sidebar nav uses `AppTooltip`. `AppTooltip` is itself a one-line `Tooltip` passthrough. |
| **Why it's a problem** | Three tooltip call sites with no shared wait duration, decoration, or `TooltipTheme` — design spec requires ~400ms delay and elevated surface styling. `AppTheme` does not configure `tooltipTheme`. |
| **Recommended solution** | Make `AppTooltip` the single wrapper; configure `ThemeData.tooltipTheme` in `AppTheme`; have `AppIconButton` use `AppTooltip` internally. |

---

### H-05 — `AppAvatar` missing image, size tokens, deterministic color, and semantics

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_avatar.dart`; spec D9; web `Avatar.tsx` |
| **Evidence** | Flutter: initials only, `double size` default 32, fixed `surfaceSunken`. Web: `src` image, sizes `xs`–`xl`, hashed initials surface palette, `role="img"` + `aria-label`, optional status dot. |
| **Why it's a problem** | Patient/staff photos cannot be shown; all avatars look identical; screen readers get `CircleAvatar` default semantics (initials letters, not person name) unless ancestor provides label. |
| **Recommended solution** | Add `AppAvatarSize` enum, optional `imageUrl`/`ImageProvider`, `Semantics(label: name, image: true)`, initials color hash from name. |

---

### H-06 — `AppUserMenu` avatar trigger lacks accessible name

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_user_menu.dart` |
| **Evidence** | `InkWell` → `AppAvatar(name: user.name)` with no `Tooltip`, `Semantics`, or `MergeSemantics`. Menu opens on tap but trigger is announced as initials text, not "Account menu" or user name as control. |
| **Why it's a problem** | WCAG 4.1.2 — purpose of control not programmatically determinable for assistive tech. |
| **Recommended solution** | Wrap trigger in `Semantics(button: true, label: 'Account menu for ${user.name}')` or `Tooltip` + `AppAvatar` with explicit semantics. |

---

### H-07 — `AppSignal` not marked decorative for accessibility

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `app_signal.dart`; web `Signal.tsx` |
| **Evidence** | Web: `role="presentation"`, `aria-hidden={true}` default. Flutter: no `ExcludeSemantics` or `Semantics(container: true, excludeSemantics: true)`. Vertical signal in nav may be traversed separately from nav item label. |
| **Why it's a problem** | Redundant focusable/announceable element adjacent to labeled nav button; duplicate "decoration" for screen readers. |
| **Recommended solution** | Wrap built signal in `ExcludeSemantics(child: ...)` or `Semantics(label: '', excludeSemantics: true)`; document that active state is conveyed by nav item `selected` semantics, not the signal. |

---

### H-08 — `widgets.dart` barrel unused; import convention diverges

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `widgets/widgets.dart`; all shell/component import sites |
| **Evidence** | `grep` for `core/ui/widgets/widgets` in `frontend/lib` — zero matches. Shell imports five separate `components/` paths. `forui-wrappers.md` instructs `import '.../widgets/widgets.dart'`. |
| **Why it's a problem** | Barrel becomes stale; new contributors unsure which path is canonical; theme/motion exports in barrel provide no value if unused. |
| **Recommended solution** | Enforce barrel import via lint rule or migrate shell to `widgets.dart`; update docs to reflect `components/` path if deliberate. |

---

### H-09 — Documentation claims Forui wrappers that do not exist

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `docs/ui/forui-wrappers.md`; `frontend/lib/core/ui/` tree; `pubspec.yaml` |
| **Evidence** | Doc lists `AppButton`, `AppTextField`, `AppCard`, `AppDialog` under `core/ui/widgets/` — directories absent. No `forui` dependency. Current primitives are Material-based under `components/`. |
| **Why it's a problem** | Misleading architecture guidance; reviewers and implementers expect abstraction layer that was removed or never merged. |
| **Recommended solution** | Archive or rewrite `forui-wrappers.md` to describe Material + `AppSemanticColors` approach; align Phase 2 `AppBadge` note with actual `app_badge.dart`. |

---

## 3. Medium Priority Issues

### M-01 — `AppTooltip` is a zero-value passthrough (SRP / abstraction leak)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_tooltip.dart` |
| **Evidence** | Entire implementation: `return Tooltip(message: message, child: child);` — no `waitDuration`, `showDuration`, `decoration`, `textStyle`, `preferBelow`, `enableFeedback`, or `excludeFromSemantics`. |
| **Why it's a problem** | Fails reason to exist as application-owned primitive; any Material `Tooltip` API change or theming gap hits all call sites inconsistently. |
| **Recommended solution** | Centralize spec defaults (`waitDuration: 400ms`, max width, `AppTypography.bodySm`, `surfaceRaised` decoration); mirror web `TooltipProvider` delay. |

---

### M-02 — `AppSignal.active == false` still renders full-opacity bar

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_signal.dart` |
| **Evidence** | When `active` is false, only `boxShadow` is cleared; `signal(1, shadows, constraints)` uses opacity `1`. Web still shows color but removes glow — Flutter matches for glow only. No API docs on `active`. |
| **Why it's a problem** | Callers may expect inactive = hidden or muted; behavior is undocumented. |
| **Recommended solution** | Document semantics; consider `opacity: active ? 1 : 0.35` or hide entirely when `!active`. |

---

### M-03 — `AppSignal` pulse runs when `active: false` and `thinking: true`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_signal.dart` |
| **Evidence** | Animated branch checks `thinking && variant == ai && !reducedMotion`; `active` only gates shadows inside animation, not opacity pulse. |
| **Why it's a problem** | Inconsistent "inactive" semantics during AI thinking state. |
| **Recommended solution** | Gate pulse on `widget.active`; add widget test. |

---

### M-04 — `AppAvatar` initials algorithm diverges from web

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_avatar.dart`; web `Avatar.tsx` |
| **Evidence** | Single word: Flutter `parts.first[0]` (1 char); web `slice(0, 2)` (up to 2 chars). |
| **Why it's a problem** | Cross-platform visual inconsistency for mononymous users. |
| **Recommended solution** | Align to web: first two graphemes of single token. |

---

### M-05 — `AppAvatar` unsafe indexing on malformed graphemes

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_avatar.dart` |
| **Evidence** | `parts.first[0]` and `parts.last[0]` assume ASCII letters; empty string after filter guarded, but combining characters / emoji-only names may throw `RangeError` on `[0]` if a "part" is empty after trim edge cases. |
| **Recommended solution** | Use `characters` package or `String.characters.first` with fallback `'?'`. |

---

### M-06 — `AppBadge` does not guard empty `label`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_badge.dart` |
| **Evidence** | `required this.label` with no `assert(label.isNotEmpty)` — renders invisible padded pill. |
| **Recommended solution** | Assert in debug; return `SizedBox.shrink()` for empty in release, or require non-empty via constructor assert. |

---

### M-07 — `AppIconButton` accepts generic `Widget icon` without size contract

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_icon_button.dart`; call sites |
| **Evidence** | `iconSize` set on `IconButton` but callers pass `Icon(..., size: 16)` in sidebar vs `const Icon(...)` (default 24) in top bar — inconsistent visual weight inside same `lg` button. |
| **Recommended solution** | Accept `IconData` + optional override, or document that icon must not set size (let `iconSize` control). |

---

### M-08 — `AppSignal` creates `LayoutBuilder` + `AnimatedBuilder` per instance

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_signal.dart` |
| **Evidence** | AI thinking rebuilds every frame; no `RepaintBoundary`. Currently one pulse in showcase and one per active nav item — acceptable now. |
| **Potential impact** | Command bar or multi-AI indicators could jank. |
| **Recommended solution** | Wrap animated signal in `RepaintBoundary`; consider `AnimatedOpacity` preset when only opacity changes. |

---

### M-09 — Dual import paths for motion tokens

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `motion/app_motion.dart`, `theme/app_motion.dart`, `widgets.dart` |
| **Evidence** | Components import `motion/`; barrel exports `motion/`; theme folder has re-export unused by current code except potential future imports. |
| **Recommended solution** | Pick one public path; deprecate the other with a comment. |

---

### M-10 — `AppSemanticColors` lacks status surface tokens for badges

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_semantic_colors.dart`; `app_badge.dart` |
| **Evidence** | Only `statusSuccessFg` and `statusDangerFg` exist — no `statusInfoSurface`, `statusWarningSurface`, etc. Web badge soft variants need paired fg/surface. |
| **Recommended solution** | Extend semantic colors per `02-tokens` before badge tones land. |

---

### M-11 — `dev_tabs.dart` is sole non-shell `AppSignal` consumer outside showcase

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `dev_tabs.dart` |
| **Evidence** | Tab underline uses horizontal signal; production tabs component (`AppTabs` per spec C5) does not exist yet — dev-only pattern may not migrate. |
| **Recommended solution** | Extract shared `AppTabUnderline` or plan `AppTabs` to own signal placement. |

---

## 4. Low Priority Issues

### L-01 — Missing `const` on some `AppSignal` shell usages

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_sidebar.dart` line 270 |
| **Evidence** | `const PositionedDirectional(..., child: AppSignal(...))` — good. `dev_tabs.dart` line 86 uses const. No widespread missed const opportunities in scoped files themselves (all component constructors are const-capable). |

---

### L-02 — `AppIconButton` disabled state relies on Material defaults only

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_icon_button.dart` |
| **Evidence** | `onPressed: null` — no explicit `disabledForegroundColor` from semantic tokens. |
| **Recommended solution** | Set `disabledForegroundColor: colors.iconMuted` in `styleFrom`. |

---

### L-03 — `AppBadge` uses hard-coded padding and fontSize

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_badge.dart` |
| **Evidence** | `horizontal: 6, vertical: 2`, `fontSize: 12` — not from `AppSpacing` / typography scale tokens. |
| **Recommended solution** | Map to `AppSpacing` and `AppTypography.caption` when sizes added. |

---

### L-04 — `AppSignalSize.defaultSize` naming

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_signal.dart` |
| **Evidence** | `defaultSize` avoids `default` keyword — correct but verbose vs web `default`. |
| **Recommended solution** | Acceptable; document in component doc comment. |

---

### L-05 — No `Key` propagation pattern documented for list badges/avatars

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | All components |
| **Evidence** | Components accept `super.key` — sufficient. List usage not yet present. |

---

### L-06 — `widgets.dart` exports entire theme surface

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `widgets.dart` |
| **Evidence** | Exporting `app_theme.dart`, primitives, shell tokens may encourage features to depend on low-level tokens instead of components. |
| **Recommended solution** | Split `widgets.dart` (components only) vs `theme.dart` barrel. |

---

### L-07 — `AppMotion.animatedPreset` not used by scoped components

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_motion.dart`; `app_signal.dart` |
| **Evidence** | Signal uses bespoke `AnimationController` — appropriate for infinite pulse; no issue. |

---

### L-08 — Sidebar nav count badge shows zero if passed

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_sidebar.dart` |
| **Evidence** | `if (item.count != null) AppBadge(...)` — `count: 0` would display "0". |
| **Recommended solution** | Presentation rule: hide when zero (in nav model, not badge). |

---

## 5. Component Deep-Dives

### `AppIconButton`

**Strengths:** Size map matches spec (28/32/40); required tooltip enforces A2 rule; uses semantic colors and `AppRadius.md`; `const` constructor.

**Weaknesses:** Ghost-only; no loading/error; no press scale; inconsistent tooltip wrapper vs `AppTooltip`; icon sizing left to caller.

**State management:** Stateless — correct for present scope.

```22:44:frontend/lib/core/ui/components/app_icon_button.dart
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // ...
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        iconSize: size == AppIconButtonSize.lg ? 24 : 20,
        // ...
      ),
    );
  }
```

---

### `AppSignal`

**Strengths:** Reduced motion via `AppMotion.prefersReducedMotion`; controller lifecycle synced on `thinking`/`variant` change; layout adapts horizontal/vertical bounded constraints; matches web 1.2s linear AI pulse.

**Weaknesses:** No semantics exclusion; `active` under-specified; potential per-frame repaints without `RepaintBoundary`.

**State management:** Stateful with `SingleTickerProviderStateMixin` — appropriate. `didUpdateWidget` correctly disposes controller when pulse stops.

```59:68:frontend/lib/core/ui/components/app_signal.dart
  void _syncPulseController() {
    final shouldPulse = widget.thinking && widget.variant == AppSignalVariant.ai;
    if (shouldPulse && _pulseController == null) {
      _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
      _pulseAnimation = CurvedAnimation(parent: _pulseController!, curve: AppMotionEasing.linear);
    } else if (!shouldPulse && _pulseController != null) {
      _pulseController!.dispose();
      // ...
    }
  }
```

---

### `AppBadge`

**Strengths:** Minimal count chip for nav; `const`; token-based background.

**Weaknesses:** Not a status pill; no variants; name collision with domain `AppBadgeTone`.

```14:24:frontend/lib/core/ui/components/app_badge.dart
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: AppTypography.bodySm(context).copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
```

---

### `AppAvatar`

**Strengths:** Initials helper handles empty/whitespace; `const` constructor; uses typography tokens.

**Weaknesses:** No photo; no size enum; no hashed colors; weak a11y; single-char mononym rule.

```28:37:frontend/lib/core/ui/components/app_avatar.dart
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
```

---

### `AppTooltip`

**Strengths:** Stable app-owned name for future theming.

**Weaknesses:** No defaults; does not justify separate file today.

---

### `widgets.dart` barrel

**Strengths:** Single export surface for components, motion, and theme — good DX if adopted.

**Weaknesses:** Unused; mixes abstraction levels; docs out of sync with repo layout.

---

### `app_motion.dart` (motion/)

**Strengths:** Comprehensive preset system; RTL-aware `slideInline`; reduced-motion policy; `animatedPreset` helper; aligned with web reference.

**Weaknesses:** None within review scope; not duplicated in theme shim.

---

## 6. SOLID & Clean Architecture

| Principle | Assessment |
|-----------|------------|
| **Single responsibility** | `AppTooltip` violates — no distinct responsibility yet. Others OK for current scope. |
| **Open/closed** | `AppBadge` / `AppIconButton` not open for extension without modification — enums needed. |
| **Liskov** | N/A — no inheritance hierarchies. |
| **Interface segregation** | Components expose minimal APIs — good, but too minimal for badge/button variants. |
| **Dependency inversion** | Components depend on theme extensions (`context.appColors`) — correct for Flutter presentation layer. Domain `AppBadgeTone` should not live in appointments domain if it describes presentation; move to core or presentation when widget supports it. |

---

## 7. Accessibility Checklist

| Check | AppIconButton | AppSignal | AppBadge | AppAvatar | AppTooltip |
|-------|---------------|-----------|----------|-----------|------------|
| Semantics label | Via `Tooltip` only | Missing exclude | No status role | Initials only | Via Material |
| Focus | Material `IconButton` | N/A decorative | N/A | None on avatar alone | Child inherits |
| Reduced motion | N/A | Yes | N/A | N/A | N/A |
| Color-alone status | N/A | N/A | Fail (when tones added, need text) | N/A | N/A |
| Touch target ≥32px | sm=28 visual, IconButton constraints tight — verify hit test | N/A | N/A | size default 32 OK | N/A |
| RTL | Material handles | `PositionedDirectional` in shell | OK | OK | Material handles |

---

## 8. Performance Notes

| Item | Finding |
|------|---------|
| `const` constructors | All five components support `const` — used correctly in several shell/showcase sites. |
| `RepaintBoundary` | Not used anywhere in `frontend/lib`. Consider for `AppSignal` AI pulse only. |
| `ListView` rebuild isolation | Not applicable yet — low nav item count. |
| Animation disposal | `AppSignal` disposes controller — good. |

---

## 9. Test Coverage Gaps

| Gap | Priority |
|-----|----------|
| No widget tests for any scoped component | P0 |
| No goldens for badge/signal/avatar | P1 |
| No test for `AppSignal` controller leak on rapid `thinking` toggle | P1 |
| No semantics tester coverage (`SemanticsTester`) for icon button + collapsed nav | P1 |
| No test that `AppMotion.prefersReducedMotion` disables signal pulse | P2 |

---

## 10. Remediation Roadmap

### Phase 1 — Before appointments / patient UI (blocking)

1. Implement `AppBadge` variants + tones; align with `AppBadgeTone` or relocate enum to `core/ui`.
2. Add widget tests for shell primitives (minimum: signal pulse lifecycle, avatar initials, icon button semantics).
3. `ExcludeSemantics` on `AppSignal`; fix `AppUserMenu` trigger semantics.

### Phase 2 — Design-system parity

4. Extend `AppIconButton` variants + loading; unify tooltip via `AppTooltip` + `tooltipTheme`.
5. Extend `AppAvatar` (image, sizes, hashed colors).
6. Replace top-bar notification inline badge with shared primitive.

### Phase 3 — Hygiene

7. Adopt or remove `widgets.dart` barrel; update `forui-wrappers.md`.
8. Add semantic status surface colors to `AppSemanticColors`.
9. Golden tests in CI for core components light/dark.

---

## 11. Issue Index

| ID | Title | Severity |
|----|-------|----------|
| C-01 | `AppBadgeTone` without widget API | Critical |
| C-02 | Zero component tests | Critical |
| H-01 | `AppBadge` spec parity | High |
| H-02 | Inline notification badge | High |
| H-03 | `AppIconButton` variants/states | High |
| H-04 | Split tooltip implementations | High |
| H-05 | `AppAvatar` incomplete | High |
| H-06 | User menu a11y | High |
| H-07 | `AppSignal` semantics | High |
| H-08 | Unused barrel | High |
| H-09 | Stale Forui docs | High |
| M-01 | `AppTooltip` passthrough | Medium |
| M-02 | `active` opacity semantics | Medium |
| M-03 | Pulse when inactive | Medium |
| M-04 | Initials algorithm | Medium |
| M-05 | Grapheme safety | Medium |
| M-06 | Empty badge label | Medium |
| M-07 | Icon size contract | Medium |
| M-08 | Signal repaint scope | Medium |
| M-09 | Dual motion import paths | Medium |
| M-10 | Missing status surface tokens | Medium |
| M-11 | Dev tabs signal only | Medium |
| L-01–L-08 | See §4 | Low |

---

## References

- Design system: `docs/ui/design-system/04-components.md` (A2, D7, D9, D10, Signal)
- Web reference: `web-reference/src/components/actions/IconButton.tsx`, `badge/Badge.tsx`, `avatar/Avatar.tsx`, `primitives/Signal.tsx`, `components/tooltip/Tooltip.tsx`
- Motion: `frontend/lib/core/ui/motion/app_motion.dart`
- Prior feature review (badge tone in domain): `docs/review/appointments-feature-code-review.md`
