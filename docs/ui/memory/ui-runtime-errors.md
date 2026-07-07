# Inputs & Forms — Runtime Error Memory

Brief notes from fixing design-system input showcase crashes (2026-07-07). Read this before adding or porting form components.

## 1. `No Material widget found` (TextField / Slider)

**Symptom:** Red screen in Components showcase; ancestor chain shows `AnimatedContainer` / `DecoratedBox` / `ShowcaseDemo`, not `Material`.

**Cause:** New input widgets use custom `BoxDecoration` shells (web-style) but embed Material primitives (`TextField`, `Slider`) directly. Those widgets require a `Material` ancestor for ink, focus, and text selection—even when the visible border comes from a parent `AnimatedContainer`.

**Fix:** Wrap the Material primitive in a transparent Material shell:

```dart
appWrapMaterialInput(TextField(...))  // helper in app_input_styles.dart
```

Apply at the **innermost** shell that owns the primitive:

- Bare inputs: wrap the `TextField` before placing it in `AnimatedContainer`.
- Affix wrappers (`AppAffixInputWrapper`, `_ComboboxInputShell`): wrap `widget.child` inside `Expanded`.
- Do **not** assume `MaterialApp` or `ShowcaseDemo` provides Material.

**Affected files (fixed):** `app_text_input.dart`, `app_textarea.dart`, `app_password_input.dart`, `app_number_input.dart`, `app_combobox.dart`, `app_date_picker.dart`, `app_multi_select.dart`. (`app_slider.dart` uses a custom slider — see entry #9.)

---

## 2. `MediaQuery` / inherited widget read in `initState` (`AppPopover`)

**Symptom:** `dependOnInheritedWidgetOfExactType<MediaQuery>() was called before _AppPopoverState.initState() completed` when opening combobox, select, multi-select, date/time pickers.

**Cause:** `AppPopover.initState` called `AppMotion.transitionFor(context: context, ...)`, which reads `MediaQuery.disableAnimationsOf(context)`. Inherited widgets are unavailable during `initState`.

**Fix:** Initialize `AnimationController` with a context-free duration:

```dart
_controller = AnimationController(
  vsync: this,
  duration: AppMotion.resolveDuration(AppMotionPreset.fadeScale),
);
```

Use `AppMotion.transitionFor` only in `build` or overlay builders where `context` is valid. Respect reduced motion there, not in `initState`.

---

## 3. `Locale data has not been initialized` (`DateFormat`)

**Symptom:** Crash on `AppDateRangePicker` / `AppDatePicker` when formatting with explicit locales (`en-GB`, `ar-EG`).

**Cause:** `DateFormat.MMMd(locale)` and similar patterns need `initializeDateFormatting` from `intl/date_symbol_data_local.dart` before first use. Default `DateFormat.yMMMd()` without a locale works; locale-specific patterns do not.

**Fix:**

1. Call `ensureIntlDateFormattingInitialized()` at app startup (`main.dart`), before `runApp`.
2. Utility lives in `frontend/lib/core/utils/intl_date_formatting.dart`.
3. When adding new date locales, register them in that helper.

---

## 4. `Tried to make a child into a parent of itself` (duplicate `FocusNode` on `Focus` + `TextField`)

**Symptom:** Red screen when opening the Combobox showcase (or any screen using `AppCombobox`). Assertion in `focus_manager.dart` line 1045: `'child != this'`. Error-causing widget points at `TextField` in `app_combobox.dart`. Secondary layout/hit-test errors on unrelated widgets (e.g. `AppSlider`) may follow from a corrupted focus tree.

**Cause:** The same `FocusNode` was passed to both an ancestor `Focus` widget and a descendant `TextField`. Flutter attaches a focus node to exactly one `Focus` widget; `TextField` creates its own `Focus` internally when given `focusNode`, so sharing one node on parent and child triggers a circular reparent during `_FocusState.didChangeDependencies`. An ancestor `Focus(onKeyEvent: …)` wrapper around a `TextField` is enough to trigger this when both use the same node—even if keyboard handling was the only reason for the wrapper.

**Fix:** Keep `focusNode` only on the `TextField`. Handle arrow/enter/escape on that node directly; do **not** wrap the field in another `Focus` that shares the node.

```dart
@override
void initState() {
  super.initState();
  _focusNode
    ..addListener(_handleFocusChange)
    ..onKeyEvent = _handleKeyEvent;
}

@override
void dispose() {
  _focusNode
    ..removeListener(_handleFocusChange)
    ..onKeyEvent = null
    ..dispose();
  super.dispose();
}

// build: TextField(focusNode: _focusNode, …) with no ancestor Focus wrapper
```

If an ancestor `Focus` is required for other reasons, omit `focusNode` on it (`Focus(onKeyEvent: …)` only). Prefer `FocusNode.onKeyEvent` on the field node instead (see `app_combobox.dart`).

**Affected files (fixed):** `app_combobox.dart`.

---

## 5. Text not vertically centered in input shells (`AppTextInput`)

**Symptom:** Typed text and placeholder sit against the top edge of sm/md/lg text inputs in the Components showcase (Form field, Text input).

**Cause:** Bare `TextField` uses `isCollapsed: true` and zero `contentPadding` inside a fixed-height `AnimatedContainer`. Without vertical alignment, the field hugs the top of the shell.

**Fix:** Center the field in the shell:

```dart
appCenterInputField(TextField(...))  // Align(centerStart) + appWrapMaterialInput
```

Use in `AppTextInput` and `AppAffixInputWrapper` (shared affix shell).

**Affected files (fixed):** `app_input_styles.dart`, `app_text_input.dart`.

---

## 6. Duplicate textarea character counter (`AppTextarea`)

**Symptom:** Auto-grow + counter demo shows two stacked `n/200` counters.

**Cause:** `TextField` with `maxLength` renders its own counter; `AppTextarea` also paints a custom counter when `showCounter` is true.

**Fix:** Suppress the built-in counter when showing the custom one:

```dart
decoration: appBareInputDecoration(...).copyWith(
  counterText: widget.showCounter ? '' : null,
  ...
)
```

**Affected files (fixed):** `app_textarea.dart`.

---

## 7. Form-field hint tooltip opens below icon (`AppFormField`)

**Symptom:** Help tooltip on the "Consultation" form-field error demo appears below the `?` icon instead of above.

**Cause:** Flutter `Tooltip` defaults to `preferBelow: true`; web `Tooltip` defaults to `side="top"`.

**Fix:** Pass `preferBelow: false` on `AppTooltip` in `AppFormField`. `AppTooltip` exposes optional `preferBelow` so other call sites (e.g. sidebar) keep their placement.

**Affected files (fixed):** `app_tooltip.dart`, `app_form_field.dart`.

---

## 8. `BoxConstraints forces an infinite height` (`DevSectionLayout` Row)

**Symptom:** Red screen on Design System page at startup (large breakpoint). Assertion in `box.dart`: `BoxConstraints forces an infinite height` on `RenderConstrainedBox`; error-causing widget is `Row` in `dev_section_layout.dart`. Cascading `RenderBox was not laid out` errors up through `design_system_page.dart` and `app_shell.dart`.

**Cause:** `DevSectionLayout` uses a horizontal `Row` with `crossAxisAlignment: CrossAxisAlignment.stretch`. The page lives inside `AppShell` → `SingleChildScrollView` → `Column`, which passes **unbounded max height** to children. `stretch` turns that into a **tight** infinite height on the cross axis, which is invalid for `SizedBox(width: 208, child: DevSectionStickyNav(...))`.

**Fix:** Use top alignment in the scroll context and fall back to viewport height for sticky clamping:

```dart
return Row(
  crossAxisAlignment: CrossAxisAlignment.start, // not stretch
  children: [
    SizedBox(width: 208, child: DevSectionStickyNav(child: nav)),
    ...
  ],
);

// In DevSectionStickyNav sticky math:
final containerHeight = constraints.maxHeight.isFinite
    ? constraints.maxHeight
    : viewportHeight;
```

**Affected files (fixed):** `dev_section_layout.dart`.

---

## 9. `RenderBox.size accessed beyond the scope of resize` (`AppSlider` / Material `Slider`)

**Symptom:** Red screen on Design System → Components → Slider (or at startup when all input sections load). Assertion in `box.dart` (`sizeAccessAllowed`); error-causing widget is `Slider` in `app_slider.dart`. Stack includes `_RenderLayoutSurrogateProxyBox` / `_RenderTheater.performLayout`, `RenderLeaderLayer` with a dangling `LayerLink`, and `_RenderDeferredLayoutBox` never laid out. Follow-on scheduler/gesture errors (`!childSemantics.renderObject._needsLayout`, cannot hit test).

**Cause:** Material `Slider` **always** wraps its child in `OverlayPortal` + `CompositedTransformTarget` for the drag value indicator — even when `showValueIndicator: ShowValueIndicator.never`. Inside `SingleChildScrollView` → `Column` (design-system page), deferred overlay layout reads `theater.size` while the theater is still laying out. Bounding height or disabling the value indicator does **not** remove the portal; the assert still fires.

**Fix:** Do **not** use Material `Slider`. Implement a custom track + thumb with `LayoutBuilder`, `GestureDetector`, and `Focus` (keyboard arrows). `AppSlider` already renders its own value label above the track, so the Material overlay is redundant anyway.

```dart
// Custom slider — no OverlayPortal, safe inside scroll views.
LayoutBuilder(
  builder: (context, constraints) {
    final thumbCenterX = _thumbRadius + fraction * (constraints.maxWidth - _thumbRadius * 2);
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _updateFromLocalDx(d.localPosition.dx, constraints.maxWidth),
      child: Stack(/* inactive track, active range, thumb */),
    );
  },
)
```

**Affected files (fixed):** `app_slider.dart`.

---

## 10. `setState() or markNeedsBuild() called during build` (`AppPopover` / `AppSelect`)

**Symptom:** Animation library assertion when opening `AppSelect` (or combobox, multi-select, date/time pickers). Stack shows `_AppPopoverState._open` → `AnimationController.forward` from `didUpdateWidget`, while the parent (`AppSelect`) is still building. Follow-on `RenderFollowerLayer` / `Tooltip` paint-transform errors may appear from a half-initialized overlay.

**Cause:** Controlled `AppPopover` (`open:` prop) called `_open()` / `_close()` synchronously inside `didUpdateWidget`. That runs during the parent's build and starts the fade-scale `AnimationController`, which notifies `AnimatedBuilder` listeners and triggers `markNeedsBuild` mid-build. `initState` already deferred open with `addPostFrameCallback`; `didUpdateWidget` did not.

**Fix:** Schedule controlled open/close after the current frame, and bail if `open` changed again before the callback runs:

```dart
@override
void didUpdateWidget(covariant AppPopover oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.open != oldWidget.open && widget.open != null) {
    final nextOpen = widget.open!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.open != nextOpen) return;
      if (nextOpen) {
        _open(notify: false);
      } else {
        _close(notify: false);
      }
    });
  }
}
```

**Affected files (fixed):** `app_popover.dart` (fixes all controlled popover consumers: `app_select.dart`, `app_combobox.dart`, `app_multi_select.dart`, date/time pickers).

---

## 11. `RenderFollowerLayer` paint transform (`Tooltip` in `AppPopover` / `AppSelect`)

**Symptom:** Rendering assertion when opening `AppSelect` with a disabled option that has `disabledReason`. Error points at `Tooltip` in `app_select.dart`; message: `The paint transform cannot be reliably computed because of RenderFollowerLayer(s)`.

**Cause:** `AppPopover` positions its menu with `CompositedTransformFollower` inside an `OverlayEntry`. Material `Tooltip` (and `MenuAnchor`, etc.) also host overlay children via `OverlayPortal`. Nesting those inside a `RenderFollowerLayer` subtree is unsupported in Flutter 3.38+ — follower paint transforms are established after layout, so overlay descendants cannot compute a reliable transform.

**Fix:** Do **not** wrap popover list items in `Tooltip`. Show disabled reasons inline (match `AppCombobox`); keep the reason on `Semantics.label` for screen readers:

```dart
// Inline caption under the option label — no Tooltip inside AppPopover child.
if (opt.disabled && opt.disabledReason != null)
  Text(
    opt.disabledReason!,
    style: AppTypography.caption(context).copyWith(color: warningColor),
  ),
```

**Affected files (fixed):** `app_select.dart`.

---

## 12. Stale popover content while typing (`AppPopover` / `AppCombobox`)

**Symptom:** Combobox empty state ("No matches for …") does not appear while typing; it only shows after blur and refocus. Same stale overlay can affect loading text and filtered results for any `AppPopover` consumer.

**Cause:** `AppPopover` inserts an `OverlayEntry` once on open (`_showOverlay` returns early when `_overlayEntry != null`). Parent rebuilds (e.g. `AppCombobox` after debounced search) update `widget.child`, but the overlay entry is not marked for rebuild, so it keeps the snapshot from first open.

**Fix:** In `didUpdateWidget`, when still open and `open` did not just toggle, schedule `_overlayEntry?.markNeedsBuild()` after the frame (same constraint as entry #10 — must not run during parent build):

```dart
} else if (_isOpen) {
  _scheduleOverlayRefresh();
}

void _scheduleOverlayRefresh() {
  if (_overlayRefreshScheduled) return;
  _overlayRefreshScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _overlayRefreshScheduled = false;
    if (!mounted || !_isOpen) return;
    _overlayEntry?.markNeedsBuild();
  });
}
```

**Affected files (fixed):** `app_popover.dart` (all controlled popover consumers: combobox, select, multi-select, date/time pickers).

---

## 13. `'attached': is not true` (`CompositedTransformFollower` / `AppPopover`)

**Symptom:** Repeated foundation/scheduler assertions (`rendering/object.dart` line ~3675, `'attached': is not true`) when opening, closing, or interacting with date/time pickers (and other `AppPopover` consumers). No single widget stack; errors cascade from layout/paint scheduling.

**Cause:** Deferred overlay refresh (`_scheduleOverlayRefresh`, entry #12) can call `markNeedsBuild` while the popover is closing or the trigger `CompositedTransformTarget` is temporarily detached. `CompositedTransformFollower` then calls `getTransformTo` on a detached leader. `_measureTriggerWidth` could also read `RenderBox.size` on a detached box (`hasSize` does not imply `attached`).

**Fix:** Guard all overlay/transform touch points in `app_popover.dart`:

1. Skip overlay refresh while `_isClosing` or when `!entry.mounted || !_overlayLinkActive`.
2. Cancel pending refresh when `_close` starts.
3. In overlay builder, return `SizedBox.shrink()` when `!_overlayLinkActive` (before building `CompositedTransformFollower`).
4. In `_measureTriggerWidth`, require `box.attached && box.hasSize` before reading `size`.

```dart
bool get _overlayLinkActive {
  final leader = _layerLink.leader;
  return leader != null && leader.attached;
}

// overlay builder
if (!_overlayLinkActive) return const SizedBox.shrink();

// measure trigger
if (box != null && box.attached && box.hasSize) {
  _triggerWidth = box.size.width;
}
```

**Affected files (fixed):** `app_popover.dart`.

---

## Checklist for new input components

1. Does it use `TextField`, `Slider`, `InkWell`, or `DropdownButton`? → Add `appWrapMaterialInput`.
2. Does it use `AppPopover` or read `MediaQuery` / theme in `initState`? → Defer to `didChangeDependencies` or use static motion tokens. For controlled `open:` changes, defer `_open` / `_close` in `didUpdateWidget` with `addPostFrameCallback` (see entry #10). While open, schedule `_overlayEntry?.markNeedsBuild()` via `_scheduleOverlayRefresh()` on child updates so overlay content stays in sync (see entry #12) — never call `markNeedsBuild` synchronously from `didUpdateWidget`, and skip refresh while closing or when the layer link is detached (see entry #13). Do **not** put `Tooltip` / `MenuAnchor` inside `AppPopover` child content — use inline text instead (see entry #11).
3. Does it format dates with a non-default locale? → Ensure locale is initialized in `ensureIntlDateFormattingInitialized`.
4. Does a `Focus` wrapper share `focusNode` with an inner `TextField`? → Keep `focusNode` on the `TextField` only; assign `FocusNode.onKeyEvent` on that node instead of wrapping with `Focus` (see `app_combobox.dart`, `app_number_input.dart`).
5. Single-line field in a fixed-height shell? → Wrap with `appCenterInputField` so typed text is vertically centered (bare `TextField` + `isCollapsed` aligns to top).
6. Custom character counter on `TextField` with `maxLength`? → Set `counterText: ''` in `InputDecoration` to hide Flutter's built-in counter.
7. Form-field hint tooltip? → Pass `preferBelow: false` on `AppTooltip` to match web `side="top"`.
8. Row/Column inside `SingleChildScrollView`? → Do not use `CrossAxisAlignment.stretch` on a `Row` when the parent gives unbounded height; use `start` and derive sticky/viewport height from `MediaQuery` when `constraints.maxHeight` is infinite.
9. Material `Slider` inside a scroll view? → **Do not use Material `Slider`**; its `OverlayPortal` cannot be disabled. Build a custom track/thumb slider instead (see `app_slider.dart`).

---
