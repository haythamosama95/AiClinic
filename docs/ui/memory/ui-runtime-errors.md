# UI Runtime Error Memory

Brief notes from fixing design-system showcase crashes (2026-07-07). Read this before adding or porting form and display components.

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

## 14. `padding.isNonNegative` (`AppAvatarGroup`)

**Symptom:** Red screen in Components → Avatar showcase at the avatar-group demo. Assertion in `shifted_box.dart`: `'padding.isNonNegative': is not true`. Error-causing widget is `AppAvatarGroup` in `avatar_showcase_section.dart`.

**Cause:** Overlapping avatars used `Padding` with negative `EdgeInsetsDirectional.start` (`-overlap`) to pull each avatar under the previous one. Flutter's `Padding` / `RenderPadding` requires all inset values to be non-negative.

**Fix:** Lay out overlapping avatars in a `Stack` with `PositionedDirectional` and a computed `step` (`dimension - overlap`). Size the group with an explicit `SizedBox` width instead of negative margins:

```dart
final step = dimension - overlap;
SizedBox(
  width: dimension + (count - 1) * step,
  height: dimension,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      for (var i = 0; i < visible.length; i++)
        PositionedDirectional(start: i * step, child: avatar),
    ],
  ),
)
```

**Affected files (fixed):** `app_avatar.dart`.

---

## 15. `RenderFlex` unbounded width + `Expanded` (`AppCalendar` time grid)

**Symptom:** Red screen in Components → Calendar (week/day view). `RenderFlex children have non-zero flex but incoming width constraints are unbounded` on `Row` in `app_calendar.dart` `_TimeGridView`. Cascading `RenderBox was not laid out` through `IntrinsicHeight`, `SingleChildScrollView`, and the design-system page.

**Cause:** `_TimeGridView` wraps day columns in a horizontal `SingleChildScrollView` whose child used `ConstrainedBox(minWidth: …)` only. That sets a **minimum** width but leaves **max width infinite**. `Expanded` children inside the inner `Row` need a bounded max width.

**Fix:** Give the scroll child a **tight** width with `SizedBox(width: minWidth)` instead of `ConstrainedBox` with only `minWidth`:

```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: SizedBox(
    width: minWidth,
    child: Column(/* Row + Expanded day columns */),
  ),
)
```

**Affected files (fixed):** `app_calendar.dart`.

---

## 16. `ScrollController` required (`AppScrollArea` / `Scrollbar.thumbVisibility`)

**Symptom:** Scheduler assertion when loading Components → Scroll area: `A ScrollController is required when Scrollbar.thumbVisibility is true`.

**Cause:** `AppScrollArea` used `Scrollbar(thumbVisibility: true)` without an explicit controller. With `thumbVisibility: true`, Flutter cannot fall back to `PrimaryScrollController` (not present in the design-system scroll context).

**Fix:** Convert `AppScrollArea` to a `StatefulWidget`, create a `ScrollController` in `initState`, pass it to both `Scrollbar` and `SingleChildScrollView`, and `dispose` it:

```dart
Scrollbar(
  controller: _scrollController,
  thumbVisibility: true,
  child: SingleChildScrollView(controller: _scrollController, child: child),
)
```

**Affected files (fixed):** `app_scroll_area.dart`.

---

## 17. `TypeError` on `List.reduce(math.max)` (`AppChart` / `_normalizeData`)

**Symptom:** Red screen during paint on Components → Chart (line chart): `type '(num, num) => num' is not a subtype of type '(int, int) => int' of 'combine'`. Stack points at `_normalizeData` in `app_chart.dart`.

**Cause:** Showcase data is literal `List<int>` (e.g. `[12, 18, 15, 22, 19]`). At runtime `List<int>.reduce` requires `(int, int) => int`, but `dart:math` `max` / `min` are `(num, num) => num`. The mismatch surfaces during `_LineChartPainter.paint`, not at compile time.

**Fix:** Compute min/max with a loop and `.toDouble()` instead of `reduce(math.max)` / `reduce(math.min)`:

```dart
var max = data.first.toDouble();
var min = data.first.toDouble();
for (var i = 1; i < data.length; i++) {
  final v = data[i].toDouble();
  if (v > max) max = v;
  if (v < min) min = v;
}
```

Matches the pattern already used in `_BarChartPainter`.

**Affected files (fixed):** `app_chart.dart`.

---

## 18. `InkWell` hover invisible on decorated card (`AppCard` interactive)

**Symptom:** Card showcase `variant="interactive"` (and `AppPatientCard` etc.) shows no hover background or click cursor; the card looks identical to the flat variant.

**Cause:** Two issues: (1) an opaque `DecoratedBox` child of `InkWell` covers ink/hover paint on the `Material` layer; (2) `InkWell` is **disabled** when `onTap` is null, so showcase demos without a handler never enter hover state. Even with `Ink(decoration)`, null `onTap` blocks hover.

**Fix:** Drive hover with `MouseRegion` + `AnimatedContainer` background swap (same pattern as `AppChip`), not `InkWell` hover ink:

```dart
MouseRegion(
  onEnter: (_) => setState(() => _hovered = true),
  onExit: (_) => setState(() => _hovered = false),
  cursor: SystemMouseCursors.click,
  child: AnimatedContainer(
    decoration: BoxDecoration(
      color: _hovered ? colors.surfaceHover : colors.surfaceDefault,
      ...
    ),
    child: content,
  ),
)
```

Works without `onTap` and matches web `hover:bg-surface-hover transition-colors`.

**Affected files (fixed):** `app_card.dart`.

---

## 19. Timeline dots clipped / layout cascade (`AppTimeline`)

**Symptom:** Timeline event dots are not visible in the design-system showcase (or any screen using `AppTimeline`). After the rail refactor, the components page can collapse into a layout mess: `A Stack requires bounded constraints from its parent` at `app_timeline.dart`, followed by dozens of `RenderBox was not laid out` errors up through `components_content.dart`.

**Cause:** (1) Dots were absolutely positioned with a **negative** `start` offset inside a padded `DecoratedBox` border shell — ancestor paint bounds clip negative overflow even when the local `Stack` sets `clipBehavior: Clip.none`. (2) The rail fix used `PositionedDirectional(top: 0, bottom: 0)` inside a width-only `SizedBox` within a `Column`. The `Stack` received unbounded height (`0.0<=h<=Infinity`), which violates Flutter's layout rules and cascades layout failures through the entire components page.

**Fix:** Per-item `Row` rail with positive offsets, wrapped in `IntrinsicHeight` so the rail `Stack` gets a finite height from the text column:

```dart
IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: AppSpacing.space6 + _dotOverhang,
        child: Stack(
          children: [
            PositionedDirectional(
              start: _dotOverhang,
              top: 0,
              bottom: 0,
              width: _borderWidth,
              child: ColoredBox(color: colors.borderSubtle),
            ),
            PositionedDirectional(
              start: 0,
              top: _dotTop,
              child: _TimelineDot(colors: colors),
            ),
          ],
        ),
      ),
      Expanded(child: /* event text */),
    ],
  ),
)
```

**Affected files (fixed):** `app_timeline.dart`.

---

## 20. Data table header/body misalignment (`AppDataTable`)

**Symptom:** In the Table / Data grid showcase, the header row does not span the full table width, column cells sit under the wrong headers, and text sizes look inconsistent per column (e.g. balance amounts larger than name/phone).

**Cause:** `AppDataTable` rendered the header and body as **two separate** `Table` widgets, each inside its own horizontal `SingleChildScrollView`. `IntrinsicColumnWidth` was computed independently per table, so column widths diverged. The header table also shrank to content width instead of filling the container (`w-full` on web). `AppMoneyDisplay` hard-coded `AppTypography.body`, overriding the table cell's `bodySm` `DefaultTextStyle`.

**Fix:** Merge header and data/loading rows into **one** `Table` inside a single horizontal `SingleChildScrollView`. Wrap with `LayoutBuilder` + `ConstrainedBox(minWidth: constraints.maxWidth)` so the grid spans the full width. Use `FlexColumnWidth(1)` for columns without an explicit width. Make `AppMoneyDisplay` inherit `DefaultTextStyle.of(context).style` so table cells control typography. Wrap the footer slot in `DefaultTextStyle(bodySm)` so `WidgetSpan` children (e.g. `AppMoneyDisplay`) match row text size. Span header labels across the full column width (`SizedBox(width: double.infinity)` + `textAlign` / full-width sort `TextButton`) so headers align with their column's `TableAlign`.

```dart
LayoutBuilder(
  builder: (context, constraints) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: Table(
          columnWidths: { /* FlexColumnWidth(1) for fluid cols */ },
          children: [headerRow, ...dataRows],
        ),
      ),
    );
  },
)
```

**Affected files (fixed):** `app_data_table.dart`, `app_money_display.dart`.

---

## 21. Badge / status pill stretches to full available width (`AppBadge`)

**Symptom:** Badge and status pills span the entire width of their parent (showcase demo card, `Wrap` line, table cell) instead of hugging their label/dot content.

**Cause:** `SizedBox(height: …)` without an explicit width expands to `constraints.maxWidth` when the parent passes a bounded max width (e.g. `Wrap`, `Align`, grid cell). A `Flexible` label inside the inner `Row` also invited flex expansion in tight layouts.

**Fix:** Match `AppChip` — wrap the pill in `UnconstrainedBox(constrainedAxis: Axis.vertical)` so horizontal sizing is intrinsic. Replace height-only `SizedBox` + `Center` with `ConstrainedBox(minHeight: …)` and a `Row(mainAxisSize: MainAxisSize.min)` label (no `Flexible`).

```dart
UnconstrainedBox(
  constrainedAxis: Axis.vertical,
  alignment: AlignmentDirectional.centerStart,
  clipBehavior: Clip.none,
  child: DecoratedBox(
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.height),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        child: Row(mainAxisSize: MainAxisSize.min, children: [/* dot + label */]),
      ),
    ),
  ),
)
```

**Affected files (fixed):** `app_badge.dart`.

---

## 22. Money display yellow underlines and oversized text (`AppMoneyDisplay`)

**Symptom:** In Dev → Components → Data display, any widget showing currency (`AppMoneyDisplay` in the money showcase, table balance column, list trailing amounts, entity cards) renders with debug yellow underlines and an enormous font size.

**Cause:** `AppMoneyDisplay` copied the ambient `DefaultTextStyle.of(context).style` wholesale (added for table cell sizing in entry #20). That inherited unpredictable `fontFamily`/metrics from ancestors and, inside a `WidgetSpan` footer `Text.rich`, produced inline layout with wrong text scale. Missing-glyph debug underlines appeared when the inherited font could not render tabular digits or the `−` prefix.

**Fix:** Resolve typography from `AppTypography.body(context)` and only adopt parent `DefaultTextStyle` **size/weight/height** when they differ from theme `bodyMedium` **and** the parent font size is not larger than body (guards against unrelated heading/display ancestors). Set `Text.rich(style: base)` so metrics stay consistent. Replace the data-table footer `WidgetSpan` + `Text.rich` with a `Row` of label text + `AppMoneyDisplay`. Wrap entity-card prices with explicit `DefaultTextStyle` (`bodyStrong` on invoices, `bodySm` on services) to match the web `className` tokens.

```dart
static TextStyle _baseTextStyle(BuildContext context) {
  final body = AppTypography.body(context);
  final parent = DefaultTextStyle.of(context).style;
  final themeBody = Theme.of(context).textTheme.bodyMedium!;
  final bodyFontSize = body.fontSize ?? themeBody.fontSize!;
  if (parent.fontSize != null && parent.fontSize! > bodyFontSize) return body;
  // ... adopt compact parent overrides (table bodySm, bodyStrong wrappers)
}
```

**Affected files (fixed):** `app_money_display.dart`, `data_table_showcase_section.dart`, `app_card.dart`.

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

## Checklist for new display components

1. Overlapping items (avatar groups, chips)? → Use `Stack` + `PositionedDirectional` with a positive `step`; never negative `Padding` or `margin`.
2. Timeline / rail indicators? → Use a fixed-width rail `SizedBox` with positive line + dot offsets; wrap the item `Row` in `IntrinsicHeight` + `CrossAxisAlignment.stretch` when the rail `Stack` uses `top`/`bottom` positioning (see entry #19).
3. `Expanded` / `Flexible` inside a `Row`? → Parent must have bounded width (tight `SizedBox` or finite `maxWidth`), especially inside horizontal `SingleChildScrollView` (see entry #15).
4. `Scrollbar(thumbVisibility: true)`? → Provide an explicit `ScrollController` shared with the scroll view (see entry #16).
5. `List.reduce(math.max)` / `math.min` on `List<num>` that may be `List<int>` at runtime? → Loop with `.toDouble()` instead (see entry #17).
6. Custom surface needs hover without guaranteed `onTap`? → Use `MouseRegion` + `AnimatedContainer` background swap, not `InkWell` (see entry #18).
7. `AppDataTable` header/body alignment? → Use a **single** `Table` for header + rows inside one horizontal scroll; never split into two `Table`s with independent `IntrinsicColumnWidth` (see entry #20). Stretch with `LayoutBuilder` + `ConstrainedBox(minWidth: constraints.maxWidth)` and `FlexColumnWidth(1)` for fluid columns.
8. Pill / chip / badge that should hug content? → Wrap in `UnconstrainedBox(constrainedAxis: Axis.vertical)`; never use height-only `SizedBox` inside a width-bounded parent (see entry #21).
9. `AppMoneyDisplay` typography? → Anchor on `AppTypography.body` for font family/metrics; only adopt parent `DefaultTextStyle` size/weight when it intentionally differs from theme `bodyMedium` **and** parent font size is ≤ body (never inherit heading/display sizes). Do not put it inside a `WidgetSpan` — use a `Row` or explicit `DefaultTextStyle` wrapper instead (see entry #22).

---
