# Flutter Core UI Components — Second-Cycle Skeptical Review

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/ui/components/*`, `frontend/lib/core/ui/widgets/widgets.dart`  
**Baseline:** [flutter-core-code-review.md](flutter-core-code-review.md) · [flutter-core-review-ui-components.md](flutter-core-review-ui-components.md)  
**Method:** Re-read every component file; grep production/test usage; cross-validate shell (`app/shell/navigation/`), a11y, `AppSignal` lifecycle, inline badge duplication.

---

## Summary Counts

| Severity | First-cycle | Fixed | Partially fixed | Still open | New this cycle |
|----------|-------------|-------|-----------------|------------|----------------|
| Critical | 2 | 0 | 0 | 2 | 0 |
| High | 9 | 0 | 1 | 8 | 0 |
| Medium | 11 | 0 | 0 | 11 | 2 |
| **Total** | **22** | **0** | **1** | **21** | **2** |

**Verdict:** No material remediation since first cycle. Domain `AppBadgeTone` + `scheduleBadgeTone()` now exist in appointments, widening the C-03 gap. Shell usage unchanged; zero widget/golden tests; a11y and duplicate-badge precedents persist.

---

## Critical Issues

| ID | Title | Status | Evidence |
|----|-------|--------|----------|
| C-01 | `AppBadgeTone` domain enum has no widget counterpart | **STILL OPEN** | Domain defines tone enum + status→tone mapper; `AppBadge` accepts only `label` with fixed neutral styling |
| C-02 | Zero automated tests for shell-critical primitives | **STILL OPEN** | No matches in `frontend/test/` for any scoped component; no `test/widget/` tree |

### C-01 — `AppBadgeTone` without widget API

**Status:** STILL OPEN

Domain owns presentation contract; widget cannot express it.

```388:410:frontend/lib/features/appointments/domain/appointment_queue_display.dart
  static AppBadgeTone scheduleBadgeTone(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => AppBadgeTone.neutral,
      AppointmentStatus.confirmed => AppBadgeTone.info,
      AppointmentStatus.checkedIn => AppBadgeTone.success,
      AppointmentStatus.inProgress => AppBadgeTone.warning,
      AppointmentStatus.completed => AppBadgeTone.muted,
      AppointmentStatus.cancelled || AppointmentStatus.noShow => AppBadgeTone.destructive,
      AppointmentStatus.unknown => AppBadgeTone.neutral,
    };
  }
  // ...
enum AppBadgeTone { neutral, info, success, warning, destructive, muted }
```

```7:24:frontend/lib/core/ui/components/app_badge.dart
class AppBadge extends StatelessWidget {
  const AppBadge({required this.label, super.key});

  final String label;

  @override
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
}
```

**Cross-check:** `grep AppBadge|AppBadgeTone` under `features/appointments/presentation/` — no presentation UI; only domain mapper. Queue UI will bypass `AppBadge` or duplicate styling (precedent in top bar).

**Impact:** CA violation (domain owns presentation enum); inconsistent status chips; drift from web `Badge.tsx`.

---

### C-02 — Zero component widget/golden tests

**Status:** STILL OPEN

```bash
# frontend/test/ — zero matches for AppIconButton, AppSignal, AppBadge, AppAvatar, AppTooltip
# frontend/test/widget/ — directory absent
```

`shell_dev_security_test.dart` covers dev-route gating only — not shell widgets.

**Impact:** `AppSignal` pulse/dispose, avatar initials, icon-button semantics, and badge rendering unguarded in CI. Shell regressions affect every route.

**Note:** `AppSignal` dispose logic is correct in source (see Medium cross-validation), but untested.

```53:68:frontend/lib/core/ui/components/app_signal.dart
  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  void _syncPulseController() {
    final shouldPulse = widget.thinking && widget.variant == AppSignalVariant.ai;
    if (shouldPulse && _pulseController == null) {
      _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
      _pulseAnimation = CurvedAnimation(parent: _pulseController!, curve: AppMotionEasing.linear);
    } else if (!shouldPulse && _pulseController != null) {
      _pulseController!.dispose();
      _pulseController = null;
      _pulseAnimation = null;
    }
  }
```

---

## High Priority Issues

| ID | Title | Status | Evidence |
|----|-------|--------|----------|
| H-01 | `AppBadge` ~5% of D7 spec | **STILL OPEN** | Single neutral pill; no variant/tone/size/dot API |
| H-02 | Notification count reimplements badge inline | **STILL OPEN** | `app_top_bar.dart` custom `Container` vs `AppBadge` |
| H-03 | `AppIconButton` missing variants/states/motion | **STILL OPEN** | Ghost-only; no loading/danger/ai; no press scale |
| H-04 | Split tooltip implementations | **STILL OPEN** | `AppIconButton` → raw `Tooltip`; sidebar → `AppTooltip` |
| H-05 | `AppAvatar` incomplete (image, sizes, hash, semantics) | **STILL OPEN** | Initials-only; raw `double size` |
| H-06 | `AppUserMenu` avatar trigger lacks accessible name | **STILL OPEN** | `InkWell` → `AppAvatar`; no `Semantics`/`Tooltip` on trigger |
| H-07 | `AppSignal` not marked decorative | **STILL OPEN** | No `ExcludeSemantics`; grep finds zero usages app-wide |
| H-08 | `widgets.dart` barrel unused | **STILL OPEN** | Zero `core/ui/widgets/widgets` imports in `frontend/lib` |
| H-09 | Stale Forui architecture docs / missing wrappers | **PARTIALLY FIXED** | `forui: ^0.22.3` in pubspec; zero `package:forui` imports; only `widgets.dart` under `core/ui/widgets/` |

### H-02 — Inline notification badge (duplicate styling)

**Status:** STILL OPEN

```96:118:frontend/lib/app/shell/navigation/app_top_bar.dart
                            if (notificationCount > 0)
                              PositionedDirectional(
                                end: 6,
                                top: 6,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: colors.statusDangerFg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    notificationCount > 9 ? '9+' : '$notificationCount',
                                    // ...
                                  ),
                                ),
                              ),
```

Sidebar nav count uses `AppBadge` (`app_sidebar.dart:294`); top bar does not — two badge implementations.

---

### H-04 — Split tooltip implementations

**Status:** STILL OPEN

```30:44:frontend/lib/core/ui/components/app_icon_button.dart
    return Tooltip(
      message: tooltip,
      child: IconButton(
        // ...
      ),
    );
```

```10:13:frontend/lib/core/ui/components/app_tooltip.dart
  Widget build(BuildContext context) {
    return Tooltip(message: message, child: child);
  }
```

`AppTheme` has no `tooltipTheme`; no shared wait duration or decoration.

---

### H-06 — User menu a11y

**Status:** STILL OPEN

```35:46:frontend/lib/app/shell/navigation/app_user_menu.dart
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          customBorder: const CircleBorder(),
          child: AppAvatar(name: user.name),
        );
      },
```

Screen readers get initials, not “Account menu for {name}”.

---

### H-09 — Forui docs vs reality

**Status:** PARTIALLY FIXED

- **Progress:** `forui` added to `pubspec.yaml` (line 50).
- **Still open:** No wrapper files (`AppButton`, `AppTextField`, etc.); no `package:forui` imports in `frontend/lib/`; `docs/ui/forui-wrappers.md` still describes Phase 1 wrappers as shipped.
- **Risk:** Dependency bloat + misleading docs; contributors expect abstraction layer that does not exist.

---

## Medium Priority Issues

| ID | Title | Status | Evidence |
|----|-------|--------|----------|
| M-01 | `AppTooltip` zero-value passthrough | **STILL OPEN** | One-line `Tooltip` wrapper |
| M-02 | `AppSignal.active == false` still full opacity | **STILL OPEN** | Non-pulse branch returns `signal(1, ...)` |
| M-03 | Pulse runs when `active: false` + `thinking: true` | **STILL OPEN** | `shouldPulse` ignores `active` |
| M-04 | Avatar initials diverge from web (mononym) | **STILL OPEN** | `parts.first[0]` vs web 2-char rule |
| M-05 | Unsafe grapheme indexing on avatar | **STILL OPEN** | `[0]` on string parts |
| M-06 | `AppBadge` no empty-label guard | **STILL OPEN** | No assert / shrink |
| M-07 | `AppIconButton` icon size contract undefined | **STILL OPEN** | Sidebar `size: 16` vs top bar default 24 |
| M-08 | `AppSignal` no `RepaintBoundary` | **STILL OPEN** | Per-frame `AnimatedBuilder` |
| M-09 | Dual motion import paths | **STILL OPEN** | `theme/app_motion.dart` re-export shim |
| M-10 | Missing status surface tokens for badges | **STILL OPEN** | Only `statusSuccessFg`, `statusDangerFg` in semantic colors |
| M-11 | `dev_tabs.dart` sole non-shell `AppSignal` consumer | **STILL OPEN** | Production `AppTabs` absent |
| **M-12** | **`scheduleBadgeTone` untested** | **NEW** | Label tested; tone mapper not |
| **M-13** | **Orphaned `forui` dependency** | **NEW** | In pubspec; never imported |

### M-02 / M-03 — `AppSignal` active semantics

**Status:** STILL OPEN

```115:119:frontend/lib/core/ui/components/app_signal.dart
        final shadows = widget.active && !reducedMotion
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)]
            : const <BoxShadow>[];

        return signal(1, shadows, constraints);
```

Pulse branch (lines 95–112) also omits `active` from pulse gate — only shadows.

---

### M-10 — Status surface tokens

**Status:** STILL OPEN

```32:33:frontend/lib/core/ui/theme/app_semantic_colors.dart
    required this.statusSuccessFg,
    required this.statusDangerFg,
```

No `statusInfo*`, `statusWarning*`, or soft-variant surfaces needed for D7 badge tones.

---

### M-12 — `scheduleBadgeTone` untested (NEW)

**Status:** NEW

`appointment_queue_display_test.dart` tests `scheduleBadgeLabel` but not `scheduleBadgeTone`:

```14:17:frontend/test/unit/appointments/appointment_queue_display_test.dart
    test('scheduleBadgeLabel uses canonical status labels', () {
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.scheduled), 'Scheduled');
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.checkedIn), 'Checked in');
    });
```

Presentation contract in domain is partially tested; tone mapping can drift silently until queue UI ships.

---

### M-13 — Orphaned `forui` dependency (NEW)

**Status:** NEW

`forui: ^0.22.3` in `pubspec.yaml`; `grep package:forui frontend/lib` → zero matches. Extends H-09: dependency without implementation.

---

## Cross-Validation

### Shell usage (`app/shell/navigation/`)

| Component | File | Usage | Change since cycle 1 |
|-----------|------|-------|----------------------|
| `AppIconButton` | `app_top_bar.dart`, `app_sidebar.dart` | Notifications, theme, collapse | Unchanged |
| `AppBadge` | `app_sidebar.dart:294` | Nav item count | Unchanged |
| `AppSignal` | `app_sidebar.dart:270` | Active nav edge | Unchanged |
| `AppAvatar` | `app_user_menu.dart:45` | Menu trigger | Unchanged |
| `AppTooltip` | `app_sidebar.dart:309` | Collapsed nav labels | Unchanged |
| Inline badge | `app_top_bar.dart:96–118` | Notification overlay | Unchanged (H-02) |

All shell imports use `core/ui/components/*` directly — not `widgets.dart` barrel.

### Accessibility

| Check | Result |
|-------|--------|
| `AppSignal` decorative exclusion | **Fail** — no `ExcludeSemantics` |
| `AppUserMenu` trigger label | **Fail** — initials only (H-06) |
| `AppIconButton` semantics | Tooltip-only; no explicit `Semantics` |
| `tooltipTheme` in `AppTheme` | **Absent** |
| `AppAvatar` person semantics | **Fail** — `CircleAvatar` + initials only |

### `AppSignal` dispose lifecycle

**Verified correct in source, untested:** `dispose()` disposes controller; `didUpdateWidget` syncs on `thinking`/`variant` change. No regression vs first cycle — gap is test coverage (C-02), not implementation bug.

### Duplicate inline badge styling

**Confirmed:** Top bar notification pill vs sidebar `AppBadge` vs future appointments `AppBadgeTone` — three parallel paths for badge-like UI.

---

## Production Usage Map (grep verified)

| Symbol | Production consumers |
|--------|---------------------|
| `AppIconButton` | `app_top_bar.dart`, `app_sidebar.dart` |
| `AppSignal` | `app_sidebar.dart`, `dev_tabs.dart`, `signal_section.dart` |
| `AppBadge` | `app_sidebar.dart` only |
| `AppAvatar` | `app_user_menu.dart` only |
| `AppTooltip` | `app_sidebar.dart` only |
| `AppBadgeTone` | `appointment_queue_display.dart` (domain only) |
| `widgets.dart` barrel | **0** production imports |

---

## Consolidation Summary

**Zero first-cycle Critical/High/Medium findings are fully fixed.** One High (H-09) is partially addressed: `forui` is in `pubspec.yaml` but wrappers and imports are still missing.

**Blocking before appointments queue UI:**

1. **C-01 / C-03:** Add tone/variant API to `AppBadge`; move `AppBadgeTone` to core/presentation; map domain status → tone in presentation only.
2. **C-02 / C-04:** Add `test/widget/core/ui/` — minimum: `AppSignal` pulse/dispose, `AppAvatar` initials, `AppIconButton` semantics, badge tones once implemented.
3. **H-02:** Replace top-bar inline badge with shared primitive.
4. **H-06, H-07:** `Semantics` on user-menu trigger; `ExcludeSemantics` on `AppSignal`.

**New gaps this cycle:**

- **M-12:** Test `scheduleBadgeTone` for all `AppointmentStatus` values.
- **M-13:** Implement Forui wrappers or remove unused `forui` dependency and update docs.

**Risk posture:** Shell-critical widgets remain production dependencies with no CI guardrails. Domain has advanced (`AppBadgeTone`, `scheduleBadgeTone`) while the widget layer is unchanged — the presentation gap is **wider** than at first review.
