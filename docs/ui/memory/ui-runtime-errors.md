# UI Runtime Error Memory

Brief notes from fixing design-system showcase crashes (2026-07-07). Consult this file only when explicitly instructed — not on every UI task.

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

## 23. `No Material widget found` (`AppBreadcrumb` / `InkWell`)

**Symptom:** Red screen in Dev → Components → Navigation → Breadcrumb (and TopBar with breadcrumb `pageContext`). Ancestor chain shows `InkWell` → `MouseRegion` → `_BreadcrumbSegment` → `AppBreadcrumb` → `ShowcaseDemo` / `DecoratedBox`, with no `Material` in between.

**Cause:** Link segments use `InkWell` for tap targets, but `ShowcaseDemo` is only a `DecoratedBox` — not a `Scaffold` or `Material` surface. `InkWell` requires a `Material` ancestor for ink splashes even when hover color is driven separately via `MouseRegion`.

**Fix:** Wrap each link `InkWell` in a transparent `Material` shell (same pattern as `AppBranchSwitcher`, `AppUserMenu`):

```dart
Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: item.onTap,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: label,
  ),
)
```

**Affected files (fixed):** `app_breadcrumb.dart`.

---

## 24. `RenderFlex` overflow (`AppTopBar` toolbar `Row`)

**Symptom:** Yellow/black overflow stripe on the right side of the top bar showcase (or live shell) — "overflowed by N pixels on the right" at `app_top_bar.dart` toolbar `Row`.

**Cause:** The toolbar `Row` (`mainAxisSize: min`) sits inside an `Expanded` + `Align(centerEnd)`. Its intrinsic width (branch switcher + icon buttons + user menu) can exceed the flex slot when the center search field and left `pageContext` consume most of the bar width. `Align` does not clip; the `Row` paints past its max width.

**Fix:** Wrap the toolbar `Row` in a horizontal `SingleChildScrollView` with `reverse: true` so actions stay end-aligned and can scroll when space is tight:

```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  reverse: true,
  clipBehavior: Clip.hardEdge,
  child: Row(mainAxisSize: MainAxisSize.min, children: [...]),
)
```

**Affected files (fixed):** `app_top_bar.dart`.

---

## 25. Vertical tabs hover flashes two colors (`AppTabs` vertical)

**Symptom:** In Dev → Components → Navigation → Tabs → Vertical, hovering a tab flickers between two background colors instead of a smooth hover.

**Cause:** Vertical tab buttons used `MouseRegion` + `setState` to drive an `AnimatedContainer` background (`surfaceHover` vs `surfaceSelected`). Rebuilding on hover can fight the pointer hit target, and animating the decoration while also toggling text color produces a visible two-tone flash. Selected tabs could also pick up `InkWell`-style hover if layered incorrectly.

**Fix:** Match `AppSidebar` nav items — `Material` + `InkWell(hoverColor:)` for background hover (disabled when selected), `MouseRegion` only for text color (`textPrimary` on hover), and `appInputFocusRingColor` for focus. Do not animate vertical tab backgrounds with `AnimatedContainer`.

```dart
Material(
  color: selected ? colors.surfaceSelected : Colors.transparent,
  child: InkWell(
    hoverColor: selected ? Colors.transparent : colors.surfaceHover,
    child: ...,
  ),
)
```

**Affected files (fixed):** `app_tabs.dart`.

---

## 26. Context menu opens far from click target (`AppContextMenu`)

**Symptom:** In Dev → Components → Navigation → Context menu, right-clicking the dashed target opens the menu offset from the cursor — often by the width of the app sidebar or shell chrome.

**Cause:** `_openAt` stored `localToGlobal` screen coordinates and placed the overlay `CompositedTransformTarget` with `Positioned(left:, top:)` using those globals directly. `Overlay` `Stack` children use coordinates relative to the overlay origin, not the screen, so any shell offset (sidebar, padding) shifts the menu away from the click.

**Fix:** Anchor with `event.position` / `LongPressStartDetails.globalPosition`, then convert to overlay-local space before `Positioned`:

```dart
final overlayBox = Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
final anchor = overlayBox!.globalToLocal(globalPosition);
Positioned(left: anchor.dx, top: anchor.dy, child: menu);
```

Drop the redundant `CompositedTransformTarget` / `CompositedTransformFollower` pair for cursor-anchored menus. Wrap the `Positioned` child in `IntrinsicWidth` so `_AppMenuList`'s `Column(crossAxisAlignment: stretch)` receives bounded width — bare `Positioned` in an overlay `Stack` passes infinite max width.

**Affected files (fixed):** `app_menu.dart`.

---

## 27. Feedback overlay buttons do nothing (`AppDialog` / `AppToast` / `AppToastHost`)

**Symptom:** In Dev → Components → Feedback, buttons in Toast, Dialog, and Drawer/Sheet showcases appear inert; the debug console floods with `setState() or markNeedsBuild() called during build`, `AnimationController.forward() called with no default duration`, `explicitChildNodes must be set to true if scopes route is true`, and (for toast) no toast ever appears.

**Cause:** Three separate lifecycle / overlay issues in the Phase 2 feedback port:

1. **Controlled `AppDialog`** called `showDialog` synchronously from `didUpdateWidget` when `open:` flipped to `true`, mutating the navigator overlay mid-build (same class of bug as entry #10 for `AppPopover`).
2. **`AppToastHost`** was mounted in `MaterialApp.builder`, which wraps the navigator **child** — the host context is an **ancestor** of `Overlay`, so `Overlay.maybeOf(context)` in `didChangeDependencies` always returned `null` and no toast overlay entry was ever inserted. `appToast` updated the controller but nothing rendered.
3. **`_ToastView`** and **`_AppDialogShell`** called `AnimationController.forward()` in `initState` before duration was configured (or before `didChangeDependencies` ran). **`_AppDialogPanel`** used `Semantics(scopesRoute: true)` without `explicitChildNodes: true`.

**Fix:**

1. Defer controlled dialog presentation in `didUpdateWidget` with `addPostFrameCallback` (mirror entry #10). Cache `NavigatorState` when presenting; use it in `dispose` instead of `Navigator.of(context)` on a deactivated element.
2. Lazily bind the toast overlay from the **caller** route context on first `appToast` call:

```dart
void appToast(BuildContext context, AppToastInput input) {
  final controller = _AppToastHostScope.maybeOf(context);
  controller?.ensureOverlay(context); // Overlay.of(context, rootOverlay: true)
  controller?.show(input);
}
```

3. Initialize motion controllers with static `AppMotion.resolveDuration(preset)` in `initState`; call `forward()` from `didChangeDependencies` after applying reduced-motion duration. Add `explicitChildNodes: true` when `scopesRoute: true` on dialog panels.

**Affected files (fixed):** `app_dialog.dart`, `app_toast.dart`.

---

## Checklist for new input components

1. Does it use `TextField`, `Slider`, `InkWell`, or `DropdownButton`? → Add `appWrapMaterialInput`.
2. Does it use `AppPopover` or read `MediaQuery` / theme in `initState`? → Defer to `didChangeDependencies` or use static motion tokens. For controlled `open:` changes, defer `_open` / `_close` in `didUpdateWidget` with `addPostFrameCallback` (see entry #10). While open, schedule `_overlayEntry?.markNeedsBuild()` via `_scheduleOverlayRefresh()` on child updates so overlay content stays in sync (see entry #12) — never call `markNeedsBuild` synchronously from `didUpdateWidget`, and skip refresh while closing or when the layer link is detached (see entry #13). In `dispose`, remove the overlay entry only — do not reset `AnimationController.value` (see entry #39). Do **not** put `Tooltip` / `MenuAnchor` inside `AppPopover` child content — use inline text instead (see entry #11).
3. Does it format dates with a non-default locale? → Ensure locale is initialized in `ensureIntlDateFormattingInitialized`.
4. Does a `Focus` wrapper share `focusNode` with an inner `TextField`? → Keep `focusNode` on the `TextField` only; assign `FocusNode.onKeyEvent` on that node instead of wrapping with `Focus` (see `app_combobox.dart`, `app_number_input.dart`).
5. Single-line field in a fixed-height shell? → Wrap with `appCenterInputField` so typed text is vertically centered (bare `TextField` + `isCollapsed` aligns to top).
6. Custom character counter on `TextField` with `maxLength`? → Set `counterText: ''` in `InputDecoration` to hide Flutter's built-in counter.
7. Form-field hint tooltip? → Pass `preferBelow: false` on `AppTooltip` to match web `side="top"`.
8. Row/Column inside `SingleChildScrollView`? → Do not use `CrossAxisAlignment.stretch` on a `Row` when the parent gives unbounded height; use `start` and derive sticky/viewport height from `MediaQuery` when `constraints.maxHeight` is infinite.
9. Material `Slider` inside a scroll view? → **Do not use Material `Slider`**; its `OverlayPortal` cannot be disabled. Build a custom track/thumb slider instead (see `app_slider.dart`).
10. Token/multi-select with chips + inline query `TextField` in `Wrap`? → Hide the query field when every option is selected and the user is not searching; use a fixed ~72px width when visible so `Wrap` does not leave a blank second row (see entry #38).
11. `AppRichTextEditor` / Quill with list toolbar buttons? → Override `lists`, `leading`, and `indent` in `customStyles` with the same `appBareInputTextStyle` as `paragraph`; wrap the editor in `DefaultTextStyle` (see entry #46).

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

## Checklist for new navigation components

1. `InkWell` outside `Scaffold` / overlay (e.g. inside `ShowcaseDemo`)? → Wrap in `Material(color: Colors.transparent)` — `MaterialApp` alone does not provide Material to arbitrary descendants (see entry #23).
2. Fixed-width toolbar/actions `Row` inside `Expanded`? → Use horizontal `SingleChildScrollView(reverse: true)` so the row can scroll instead of overflowing (see entry #24).
3. Vertical tab / nav list item hover? → `Material` + `InkWell(hoverColor:)` for background; `MouseRegion` only for label color — never `AnimatedContainer` + `setState` background swap (see entry #25).
4. Cursor-anchored overlay (`AppContextMenu`)? → Use `event.position` and `overlayBox.globalToLocal` for `Positioned` in `OverlayEntry`; screen globals are wrong (see entry #26). Wrap the menu in `IntrinsicWidth` so stretch `Column` children get bounded width.

## Checklist for new feedback / overlay components

1. Controlled `open:` modal (`AppDialog`, `AppDrawer`, `AppPopover`)? → Defer `showDialog` / `showGeneralDialog` / overlay mutations to `addPostFrameCallback` in `didUpdateWidget` — never call them synchronously during build (see entries #10, #27).
2. App-global overlay host in `MaterialApp.builder`? → The builder wraps the navigator child, so the host context cannot see `Overlay`. Bind the overlay lazily from a **route** `BuildContext` on first show (see entry #27).
3. `Semantics(scopesRoute: true)` on modal panels? → Also set `explicitChildNodes: true`.
4. `AnimationController.forward()` in overlay enter animations? → Set a default duration in `initState`; defer `forward()` to `didChangeDependencies` when duration depends on reduced motion (see entries #2, #27).
5. `AppDialog` with header + scroll body + footer? → Use `Flexible` for the `SingleChildScrollView` when `LayoutBuilder` reports finite `maxHeight`; do not subtract a fixed `chromeEstimate` from body height (see entry #40).
6. Tappable rows inside dialog body (`ListTile`, `InkWell`)? → Use `AppList` + `AppListItem` (or wrap in `Material`) — `AppDialog` `DecoratedBox` is not a `Material` ancestor (see entry #41).

---

## 28. `RenderFlex` overflow (`PlaceholderPage` shell `Column`)

**Symptom:** Yellow/black overflow stripe on shell placeholder routes (e.g. Home after sign-out or hot restart) — "overflowed by N pixels on the bottom" at `placeholder_page.dart` root `Column`. Error constraints show a tight height (~viewport minus top bar and shell padding, e.g. `h=150`).

**Cause:** `PlaceholderPage` is a tall intrinsic `Column` (header, card, skeleton rows). When the shell content slot passes a **bounded** max height — `AppShell` `fillViewport` path (`Align` inside `Expanded` without `SingleChildScrollView`) or a short viewport during route refresh — the column is forced into that height and its children overflow.

**Fix:** Use `mainAxisSize: MainAxisSize.min` on page columns and wrap in `SingleChildScrollView` only when `LayoutBuilder` reports `constraints.hasBoundedHeight`. When the shell already scrolls (unbounded max height), return the column directly to avoid nested primary scroll views.

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.hasBoundedHeight) {
      return SingleChildScrollView(child: body);
    }
    return body;
  },
);
```

**Affected files (fixed):** `placeholder_page.dart`.

## Checklist for new shell / placeholder pages

1. Tall `Column` body in `AppShell`? → Set `mainAxisSize: MainAxisSize.min` and, when `LayoutBuilder` reports `constraints.hasBoundedHeight`, wrap in `SingleChildScrollView` so `fillViewport` shells and short viewports can scroll (see entry #28). Viewport-filling pages (e.g. design system with internal `Expanded`) stay on the `fillViewport` shell path — including while the page is the **outgoing** transition child (see entry #30).

---

## 29. Provider write in `dispose` (`AppTopBar` / `CommandBarController`)

**Symptom:** Console exception when auth redirects unmount the shell (e.g. login → home, hot restart, sign-out). Either "Bad state: Using `ref` when a widget is about to or has been unmounted is unsafe" or "Tried to modify a provider while the widget tree was building" at `_AppTopBarState.dispose` → `CommandBarController.registerTrigger`.

**Cause:** `dispose()` cleared the command-bar trigger by writing provider state. Riverpod forbids both `ref` after deactivation and **any** provider mutation during widget lifecycle finalization (`dispose` runs while `finalizeTree` is in progress).

**Fix:** Cache the notifier in `initState` (never `ref.read` in `dispose`). Defer the unregister with `Future(() => …)` and only clear when the disposing widget still owns the trigger — avoids wiping a newly mounted `AppTopBar` during login → home transitions:

```dart
// command_bar_controller.dart
void unregisterTriggerIfCurrent(GlobalKey key) {
  if (state.triggerKey == key) {
    state = state.copyWith(clearTriggerKey: true);
  }
}

// app_top_bar.dart
@override
void dispose() {
  final triggerKey = _triggerKey;
  final controller = _commandBarController;
  Future(() => controller.unregisterTriggerIfCurrent(triggerKey));
  super.dispose();
}
```

**Affected files (fixed):** `app_top_bar.dart`, `command_bar_controller.dart`.

---

## 30. `RenderFlex` unbounded height + `Expanded` (`DesignSystemPage` / shell transition)

**Symptom:** Red screen when opening or leaving the Design System page (`/foundation-demo`), especially during shell page transitions. `RenderFlex children have non-zero flex but incoming height constraints are unbounded` on `Column` in `design_system_page.dart`. Cascading `does not meet its constraints` through `shell_page_transition.dart`, `app_shell.dart`, and scheduler semantics assertions.

**Cause:** `DesignSystemPage` uses `Expanded` for `DevSectionLayout`. `AppShell` sets `fillViewport: true` only when the **router location** is the design-system route. After `ShellPageTransition` was added, navigating **away** from Design System updates `matchedLocation` to e.g. `/home` (`fillViewport: false`) while the **outgoing** `DesignSystemPage` is still animating. The shell wraps that outgoing page in `SingleChildScrollView`, which passes unbounded max height to the page `Column` + `Expanded`.

**Fix:** Keep viewport-fill framing for the **displayed** page key during transitions, not only the destination route:

```dart
// app_shell.dart — builder receives activePageKey from ShellPageTransition
final effectiveFillViewport =
    fillViewport ||
    ShellNavConfig.isDesignSystemLocation(activePageKey.toString());
```

Also guard `DesignSystemPage` with `LayoutBuilder`: use `Expanded` only when `constraints.hasBoundedHeight`; otherwise give `DevSectionLayout` an explicit viewport-based `SizedBox` height so `Expanded` is never used in a scroll context.

**Affected files (fixed):** `shell_page_transition.dart`, `app_shell.dart`, `design_system_page.dart`.

---

## 31. `Tried to modify a provider while the widget tree was building` (`ThemeTransitionHost`)

**Symptom:** Crash on app start (or when `MaterialApp.builder` mounts). Stack shows repeated `Element.inflateWidget` / `ComponentElement.mount` frames. Riverpod error: modifying a provider during `initState` or `dispose`.

**Cause:** `ThemeTransitionHost` registered its transition runner by assigning `themeTransitionControllerProvider.notifier.state` in `initState` and clearing it with `ref.read` in `dispose`. Notifier writes during widget lifecycle are forbidden; `ref` is also unsafe in `dispose` after unmount.

**Fix:** Use a mutable registry object from a plain `Provider` (field assignment does not notify listeners). Cache the registry in `initState`; clear the runner in `dispose` via the cached field, not `ref`:

```dart
late final ThemeTransitionRegistry _registry;

@override
void initState() {
  super.initState();
  _registry = ref.read(themeTransitionRegistryProvider);
  _registry.runner = _runTransition;
}

@override
void dispose() {
  if (identical(_registry.runner, _runTransition)) {
    _registry.runner = null;
  }
  super.dispose();
}
```

Give `ThemeTransitionHost` a stable `ValueKey` in `MaterialApp.builder` so shell rebuilds do not recreate the host unnecessarily.

**Affected files (fixed):** `theme_transition_controller.dart`, `theme_transition_host.dart`, `app.dart`.

## Checklist for new shell / Riverpod lifecycle

1. Provider cleanup in `dispose()`? → Save the notifier/controller in a field during `initState`; never call `ref.read` / `ref.watch` in `dispose`; defer writes with `Future(() => …)` and guard by identity when another widget may have re-registered (see entry #29).
2. Registering callbacks/runners at mount? → Do not assign `Notifier.state` in `initState`; use a mutable registry from a plain `Provider` instead (see entry #31).
3. Page uses `Expanded` / viewport-fill layout? → Ensure `AppShell` `fillViewport` (or `effectiveFillViewport` during transitions) stays true while that page is **visible**, not only after navigation completes (see entry #30).

---

## 31. `RenderFlex` overflow (`LoginPage` modal + dev panel)

**Symptom:** Yellow/black overflow stripe on app start in debug — "overflowed by 36 pixels on the bottom" at `login_page.dart` root `Column` (line ~176). Constraints show a tight SafeArea height (e.g. `h=688`) with a large login panel (~648px) plus the debug `AuthDevWidgets.panel` (~76px) beneath it.

**Cause:** The centered `Column` stacks `_LoginPanel` (capped at `min(screenHeight * 0.9, 680)`) and the debug-only dev-login shortcuts. On short viewports or when SafeArea/padding reduce available height, the combined intrinsic height exceeds the bounded `Column` parent. The panel height math does not reserve space for the dev footer.

**Fix:** Wrap the centered column in `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: constraints.maxHeight)` so content stays vertically centered when it fits and scrolls when the login panel plus dev panel exceed the viewport:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
        ),
      ),
    );
  },
)
```

**Affected files (fixed):** `login_page.dart`.

---

## 32. Provider write in `dispose` (`LoginPage` / `AuthNotifier`)

**Symptom:** Console exception after successful login redirect — "Bad state: Using `ref` when a widget is about to or has been unmounted is unsafe" at `_LoginPageState.dispose` when clearing sign-in UI state.

**Cause:** `dispose()` called `ref.read(authSessionProvider)` and/or `ref.read(authNotifierProvider.notifier).resetSignInForm()`. Same Riverpod lifecycle rule as entry #29: `ref` is invalid after deactivation, and provider writes during `finalizeTree` are unsafe.

**Fix:** Cache `AuthNotifier` in `initState` (never `ref.read` in `dispose`). Track `isAuthenticated` with `ref.listenManual(authSessionProvider, …)` into a field. Defer `resetSignInForm()` with `Future(() => …)` only when the cached flag is still false:

```dart
late final AuthNotifier _authNotifier;
ProviderSubscription<AuthSessionState>? _authSessionSub;
var _isAuthenticated = false;

@override
void initState() {
  super.initState();
  _authNotifier = ref.read(authNotifierProvider.notifier);
  _isAuthenticated = ref.read(authSessionProvider).isAuthenticated;
  _authSessionSub = ref.listenManual(
    authSessionProvider,
    (_, next) => _isAuthenticated = next.isAuthenticated,
  );
}

@override
void dispose() {
  _authSessionSub?.close();
  if (!_isAuthenticated) {
    final notifier = _authNotifier;
    Future(() => notifier.resetSignInForm());
  }
  // … dispose controllers
}
```

**Affected files (fixed):** `login_page.dart`.

---

## 33. `RenderFlex` overflow + duplicate `GlobalKey` (`SetupScreen` / `SetupStepPanel`)

**Symptom:** On Settings → Setup, yellow/black overflow stripe ("overflowed by N pixels on the bottom") at `setup_screen.dart` root `Column`. Console repeats `Multiple widgets used the same GlobalKey` when switching setup steps or after auth session refresh.

**Cause:** (1) The setup page stacks a header, optional completion banner, and the tall `SetupWizard` in a `Column`. When the settings content slot passes a bounded max height (large breakpoint `Row` + `Expanded`, or viewport-fill shell framing), the column is forced into that height and overflows. (2) `SetupStepPanel` used a custom `AnimatedSwitcher.layoutBuilder` that kept **both** the outgoing and incoming step subtrees mounted during the slide transition. Each step contains `AppSelect` / `AppCombobox` → `AppPopover` widgets that own `GlobalKey`s for overlay anchoring; mounting two steps at once attaches the same key objects twice.

**Fix:** Scroll the setup page body when height is bounded (same pattern as entry #28). Only mount the active step in the switcher — do not stack `previousChildren` when children contain overlay/popover primitives:

```dart
// setup_screen.dart
return LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.hasBoundedHeight) {
      return SingleChildScrollView(child: body);
    }
    return body;
  },
);

// setup_step_panel.dart
layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
```

**Affected files (fixed):** `setup_screen.dart`, `setup_step_panel.dart`.

---

## 34. `AppProgress` bar fill invisible / stuck (`FractionallySizedBox`)

**Symptom:** Determinate progress bars (e.g. clinic setup wizard header) appear as a static muted track; the fill never grows when `value` or wizard step changes even though the `%` label updates.

**Cause:** `_buildBar` used `FractionallySizedBox` with only `widthFactor`. When `heightFactor` is omitted, the child keeps loose height constraints; `ColoredBox` has no intrinsic height, so the fill renders at **0px tall** (width is correct but invisible).

**Fix:** Always set `heightFactor: 1` (and `alignment: AlignmentDirectional.centerStart`) on bar-track `FractionallySizedBox` children so the fill spans the track height:

```dart
FractionallySizedBox(
  widthFactor: fraction,
  heightFactor: 1,
  alignment: AlignmentDirectional.centerStart,
  child: ColoredBox(color: colors.actionPrimary),
)
```

Apply the same pattern to the reduced-motion indeterminate bar segment.

**Affected files (fixed):** `app_progress.dart`.

---

## 35. Password field loses focus on every keystroke (`AppPasswordInput`)

**Symptom:** In settings clinic setup (staff step), typing into the password field drops focus after each character; other text fields in the same form behave normally.

**Cause:** `AppPasswordInput.didUpdateWidget` reassigned `_controller.text` whenever `initialValue` changed from the parent. Staff setup syncs password to Riverpod on every `onChanged`, so each keystroke triggered a rebuild and a controller write. Unlike `AppTextInput`, there was no guard to skip sync while the user is editing. Reassigning `TextEditingController.text` resets selection and drops focus.

**Fix:** Match `AppTextInput` — only apply `initialValue` when the owned controller is still empty:

```dart
if (_ownsController &&
    widget.initialValue != oldWidget.initialValue &&
    widget.initialValue != null &&
    _controller.text.isEmpty) {
  _controller.text = widget.initialValue!;
}
```

Also add `ValueKey(itemId)` on `EntityList` cards so list items keep stable element identity across draft rebuilds.

**Affected files (fixed):** `app_password_input.dart`, `entity_list.dart`.

## 36. Settings nav rail tab never highlights except General (`SettingsNavRail`)

**Symptom:** On the settings page, clicking Setup (or any tab other than General) switches the content panel, but the left nav rail keeps General highlighted.

**Cause:** `SettingsPage` read `GoRouterState.matchedLocation` to resolve the active tab. Inside a `ShellRoute` builder, `matchedLocation` is the **leaf segment only** (e.g. `setup`), not the full path `/settings/setup`. `AppRoutes.settingsScreenFromPath` expects a full path with `settings` as the first segment, so a bare segment falls through to the default `'general'`.

**Fix:** Resolve the active tab from `GoRouterState.uri.path` instead:

```dart
final location = GoRouterState.of(context).uri.path;
final activeScreen = AppRoutes.settingsScreenFromPath(location);
```

**Affected files (fixed):** `settings_page.dart`.

## 37. Settings nav item flashes black on click (`SettingsNavRail`)

**Symptom:** Tapping a settings nav rail item briefly shows a black background before the selected teal state appears.

**Cause:** `InkWell` uses the theme default splash/highlight overlay (dark Material ink). The web reference uses plain buttons with `hover:bg-surface-hover` and no ripple.

**Fix:** Replace `InkWell` with `GestureDetector` and drive hover/selected backgrounds from `Material.color` via the existing `MouseRegion` hover state (same pattern as horizontal `AppTabs`).

**Affected files (fixed):** `settings_nav_rail.dart`.

---

## 38. Extra blank row in multi-select after all options selected (`AppMultiSelect`)

**Symptom:** In Staff setup (and other `AppMultiSelect` usages), after selecting every available branch the field shows selected chips plus an empty second line of vertical space inside the bordered input.

**Cause:** Chips and the query `TextField` live in a `Wrap`. The `TextField` always stayed in the tree with `ConstrainedBox(minWidth: 64)` even when `_filtered` was empty (all options already selected). `Wrap` placed the empty field on a new run, leaving a full input-height blank row.

**Fix:** Hide the inline query field when there is nothing left to pick and the user is not searching (`value` non-empty, `_filtered` empty, controller empty, not focused). Match the web `min-w-[8ch]` token width when the field is shown so it stays on the chip row:

```dart
bool get _showQueryField =>
    widget.value.isEmpty ||
    _filtered.isNotEmpty ||
    _controller.text.isNotEmpty ||
    _focused;

// In Wrap children:
if (_showQueryField) SizedBox(width: 72, child: field),
```

Tapping the shell still opens the popover (`No more options`) without forcing focus onto a hidden field.

**Affected files (fixed):** `app_multi_select.dart`.

---

## 39. `setState() or markNeedsBuild() called when widget tree was locked` (`AppPopover` dispose)

**Symptom:** Animation library assertion on sign-out or route teardown when an open `AppPopover` (combobox, select, multi-select, date picker, etc.) is unmounted. Stack: `_AppPopoverState.dispose` → `_removeOverlay` → `AnimationController.value=` → `AnimatedBuilder._handleChange`.

**Cause:** `dispose` called `_removeOverlay(immediate: true)`, which set `_controller.value = 0` to skip the close animation. That notifies the overlay's `AnimatedBuilder` listeners while Flutter is finalizing the element tree (`BuildOwner.lockState` during unmount). Same class of lifecycle violation as entry #10, but during teardown instead of build.

**Fix:** In `dispose`, remove the `OverlayEntry` directly and dispose the controller without resetting its value:

```dart
@override
void dispose() {
  final entry = _overlayEntry;
  _overlayEntry = null;
  entry?.remove();
  _controller.dispose();
  super.dispose();
}
```

Do not call `_controller.value =` or `forward`/`reverse` from `dispose`.

**Affected files (fixed):** `app_popover.dart`.

## Checklist for new settings / wizard pages

1. Tall `Column` in settings content (`Expanded` slot or bounded shell)? → `mainAxisSize: MainAxisSize.min` plus `LayoutBuilder` + conditional `SingleChildScrollView` when `constraints.hasBoundedHeight` (see entries #28, #33).
2. `AnimatedSwitcher` between steps/screens with `AppSelect`, `AppCombobox`, `AppPopover`, or other `GlobalKey` owners? → Do **not** keep `previousChildren` in a stacked `layoutBuilder`; mount only `currentChild` (see entry #33). Settings tab switches already use `ShellPageTransition`, which shows one page at a time.
3. `FractionallySizedBox` fill inside a fixed-height track? → Set `heightFactor: 1` so `ColoredBox` children are not 0px tall (see entry #34).
4. `AppPopover` on screens torn down during sign-out or route replace? → In `dispose`, remove the `OverlayEntry` only; do **not** reset `AnimationController.value` (notifies `AnimatedBuilder` while the tree is locked — see entry #39).

---

## 40. `RenderFlex` overflow (`AppDialog` panel `Column`)

**Symptom:** Yellow/black overflow stripe at the bottom of a large dialog with header, scroll body, and footer (e.g. Add Patient on the patients page) — "overflowed by N pixels on the bottom" at `_AppDialogPanel` `Column` in `app_dialog.dart`.

**Cause:** Body `maxHeight` was computed as `layoutConstraints.maxHeight - chromeEstimate` with a fixed `chromeEstimate` of 140px when `showHeader` is true. That ignored the footer (~68px) and did not match the real header height (~82px). Header + body cap + footer exceeded the dialog `maxHeight` (e.g. 82 + 654 + 68 = 804 vs 794 → 10px overflow).

**Fix:** Drop the fixed chrome subtraction. When `LayoutBuilder` reports finite `maxHeight`, wrap the scroll body in `Flexible` so the `Column` allocates remaining space after header and footer lay out at intrinsic height:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (showHeader) header,
    if (layoutConstraints.maxHeight.isFinite)
      Flexible(child: SingleChildScrollView(child: child))
    else
      SingleChildScrollView(child: child),
    if (footer != null) footer,
  ],
)
```

**Affected files (fixed):** `app_dialog.dart`.

---

## 41. `ListTile` ink invisible inside `AppDialog` (`DecoratedBox`)

**Symptom:** Console floods with framework assertions when patient search results appear in the appointment booking dialog: "ListTile background color or ink splashes may be invisible." Widget key `patient_picker_result_0`; ancestor chain shows `ListTile` inside `AppDialog` → `DecoratedBox` with `surfaceDefault` background.

**Cause:** `ListTile` paints its splash/hover on the nearest `Material` ancestor. `AppDialog` panel shells use `DecoratedBox` + `BoxDecoration(color: …)` without an intermediate `Material`, so ink effects are hidden and Flutter asserts in debug.

**Fix:** Do **not** use raw `ListTile` inside `AppDialog` (or any decorated shell). Use design-system list primitives that already wrap interactive rows in `Material` + `InkWell`:

```dart
SingleChildScrollView(
  child: AppList(
    children: [
      for (var i = 0; i < results.length; i++)
        AppListItem(
          primary: Text(results[i].fullName),
          secondary: Text(results[i].phone ?? results[i].branchName),
          onTap: () => onSelect(results[i]),
        ),
    ],
  ),
)
```

If `ListTile` is unavoidable, wrap each tile in `Material(color: Colors.transparent, child: ListTile(…))`.

**Affected files (fixed):** `appointment_booking_sheet.dart`.

---

## 44. `RenderFlex` overflow (`AppointmentCalendarTile` medium strip `Row`)

**Symptom:** Yellow/black overflow stripe on appointment calendar tiles in day/month/schedule views — "overflowed by N pixels on the right" at `_buildMediumStrip` `Row` in `appointment_calendar_tile.dart` (~line 234). Constraints show a tight tile width (~149px) with time range, patient name, and status chip all competing horizontally.

**Cause:** Layout breakpoints (`_showFullStrip`, `_showMediumStrip`, status chip at `bounds.width >= 160`) used the raw Syncfusion `bounds.width`, but the encounter strip content area is smaller after the accent bar (~3px) and horizontal padding (~16px). At `bounds.width` ~168 the status chip rendered even though only ~149px remained for the `Row`. Fixed children (`_TimeBlock` ~101px + `_StatusChip` ~79px + spacers) exceeded that width before the `Expanded` patient section received any space.

**Fix:** Derive `_contentWidth` (bounds minus chrome) and use it for strip mode thresholds and status visibility. Only show the medium-strip status chip when `_contentWidth >= 196`. Wrap the time block in `Flexible` in the medium strip and ellipsize its label so it can shrink when space is still tight:

```dart
double get _contentWidth {
  final accentWidth = _isTightHeight ? 2.0 : 3.0;
  final horizontalPadding = _isTightHeight ? AppSpacing.space1 * 2 : AppSpacing.space2 * 2;
  return (bounds.width - accentWidth - horizontalPadding).clamp(0.0, double.infinity);
}

bool get _showStatusInMediumStrip =>
    _contentWidth >= AppointmentCalendarTile._horizontalMediumWithStatusWidth;

// medium strip Row
Flexible(flex: 2, child: _TimeBlock(..., compact: true)),
Expanded(flex: 3, child: _LabeledStripSection(...)),
if (_showStatusInMediumStrip) _StatusChip(..., compact: true),
```

**Affected files (fixed):** `appointment_calendar_tile.dart`.

---

## 43. `NoSuchMethodError`: `firstOrNull` on `WhereIterable` (`AppointmentDetailPage`)

**Symptom:** Red screen opening an appointment detail page. `Class 'WhereIterable<BranchListItem>' has no instance getter 'firstOrNull'` in `_resolveBranchName` at `appointment_detail_page.dart`.

**Cause:** `_resolveBranchName` accepted an untyped `AsyncValue branchesAsync`. The `data:` callback parameter was inferred as `dynamic`, so `.where(...).firstOrNull` used dynamic dispatch. `firstOrNull` is an `Iterable` extension method, not an instance getter — it is not resolved at runtime on `dynamic`.

**Fix:** Type the async value so the extension applies at compile time:

```dart
String? _resolveBranchName(String branchId, AsyncValue<List<BranchListItem>> branchesAsync) {
  return branchesAsync.maybeWhen(
    data: (branches) => branches.where((branch) => branch.id == branchId).firstOrNull?.name,
    orElse: () => null,
  );
}
```

**Affected files (fixed):** `appointment_detail_page.dart`.

**Checklist:** When calling `firstOrNull` / `lastOrNull` / other extension methods on Riverpod `AsyncValue` data, ensure the `AsyncValue<T>` generic is explicit — never pass bare `AsyncValue`.

---

## 42. `setState() or markNeedsBuild() called during build` (`AppointmentCalendarPage` / `SfCalendar`)

**Symptom:** Foundation/widgets assertion when opening the appointments calendar (or when mode/focus date changes). Stack shows `_AppointmentCalendarPageState._syncCalendarView` → `CalendarController.view=` → `_SfCalendarState._calendarValueChangedListener` → `_OpacityWidgetState._update`, while `AppointmentCalendarPage` is still building.

**Cause:** `build` called `_syncCalendarView(state)` synchronously to push Riverpod mode/focus into `CalendarController`. Assigning `view` or `displayDate` notifies Syncfusion's internal listeners, which reset fade animations and call `setState` mid-build — same lifecycle rule as entries #10 and #27.

**Fix:** Defer controller sync to after the frame (mirror `_scheduleDataSourceSync`). Coalesce multiple schedules per frame and read fresh provider state in the callback:

```dart
void _scheduleCalendarViewSync() {
  if (_calendarViewSyncScheduled) return;
  _calendarViewSyncScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _calendarViewSyncScheduled = false;
    if (!mounted) return;
    _syncCalendarView(ref.read(appointmentCalendarProvider));
  });
}
```

**Affected files (fixed):** `appointment_calendar_page.dart`.

---

## 41. `ListTile` ink invisible inside `AppDialog` (`DecoratedBox`)

**Symptom:** Console floods with framework assertions when patient search results appear in the appointment booking dialog: "ListTile background color or ink splashes may be invisible." Widget key `patient_picker_result_0`; ancestor chain shows `ListTile` inside `AppDialog` → `DecoratedBox` with `surfaceDefault` background.

**Cause:** `ListTile` paints its splash/hover on the nearest `Material` ancestor. `AppDialog` panel shells use `DecoratedBox` + `BoxDecoration(color: …)` without an intermediate `Material`, so ink effects are hidden and Flutter asserts in debug.

**Fix:** Do **not** use raw `ListTile` inside `AppDialog` (or any decorated shell). Use design-system list primitives that already wrap interactive rows in `Material` + `InkWell`:

```dart
SingleChildScrollView(
  child: AppList(
    children: [
      for (var i = 0; i < results.length; i++)
        AppListItem(
          primary: Text(results[i].fullName),
          secondary: Text(results[i].phone ?? results[i].branchName),
          onTap: () => onSelect(results[i]),
        ),
    ],
  ),
)
```

If `ListTile` is unavoidable, wrap each tile in `Material(color: Colors.transparent, child: ListTile(…))`.

**Affected files (fixed):** `appointment_booking_sheet.dart`.

---

## 44. `RenderFlex` overflow (`AppointmentCalendarTile` medium strip `Row`)

**Symptom:** Yellow/black overflow stripe on appointment calendar tiles in day/month/schedule views — "overflowed by N pixels on the right" at `_buildMediumStrip` `Row` in `appointment_calendar_tile.dart` (~line 234). Constraints show a tight tile width (~149px) with time range, patient name, and status chip all competing horizontally.

**Cause:** Layout breakpoints (`_showFullStrip`, `_showMediumStrip`, status chip at `bounds.width >= 160`) used the raw Syncfusion `bounds.width`, but the encounter strip content area is smaller after the accent bar (~3px) and horizontal padding (~16px). At `bounds.width` ~168 the status chip rendered even though only ~149px remained for the `Row`. Fixed children (`_TimeBlock` ~101px + `_StatusChip` ~79px + spacers) exceeded that width before the `Expanded` patient section received any space.

**Fix:** Derive `_contentWidth` (bounds minus chrome) and use it for strip mode thresholds and status visibility. Only show the medium-strip status chip when `_contentWidth >= 196`. Wrap the time block in `Flexible` in the medium strip and ellipsize its label so it can shrink when space is still tight:

```dart
double get _contentWidth {
  final accentWidth = _isTightHeight ? 2.0 : 3.0;
  final horizontalPadding = _isTightHeight ? AppSpacing.space1 * 2 : AppSpacing.space2 * 2;
  return (bounds.width - accentWidth - horizontalPadding).clamp(0.0, double.infinity);
}

bool get _showStatusInMediumStrip =>
    _contentWidth >= AppointmentCalendarTile._horizontalMediumWithStatusWidth;

// medium strip Row
Flexible(flex: 2, child: _TimeBlock(..., compact: true)),
Expanded(flex: 3, child: _LabeledStripSection(...)),
if (_showStatusInMediumStrip) _StatusChip(..., compact: true),
```

**Affected files (fixed):** `appointment_calendar_tile.dart`.


---

## 45. `StateError` — `ref` in `dispose` (`VisitIntakeSection`)

**Symptom:** Console throws `Bad state: Using "ref" when a widget is about to or has been unmounted is unsafe` when navigating away from a visit intake screen. Stack points to `_VisitIntakeSectionState._unregisterFlushCallbacks` called from `dispose`.

**Cause:** `dispose()` called `ref.read(visitDocumentationProvider(...).notifier)` to unregister clinical-note flush callbacks. Riverpod forbids `ref` after the widget is deactivated because it relies on `BuildContext`.

**Fix:** Cache the notifier when registering flush callbacks; use that field in `dispose` instead of `ref.read`:

```dart
VisitDocumentationNotifier? _documentationNotifier;

void _registerFlushCallbacks(VisitDocumentationNotifier notifier) {
  _documentationNotifier = notifier;
  notifier.registerClinicalNoteFlush(_complaintFlush);
  // ...
}

void _unregisterFlushCallbacks() {
  _documentationNotifier
    ?..unregisterClinicalNoteFlush(_complaintFlush)
    ..unregisterClinicalNoteFlush(_historyFlush);
  _documentationNotifier = null;
}
```

**Affected files (fixed):** `visit_intake_section.dart`.

---

## 46. List text red with yellow underlines (`AppRichTextEditor` bullets / numbered lists)

**Symptom:** Toggling bullet or numbered list in `AppRichTextEditor` changes line text to red with yellow debug underlines; normal paragraph text looks correct.

**Cause:** `_editorStyles` only overrode `paragraph` and `placeHolder`. Quill switches list lines to `DefaultStyles.lists` and bullet/number markers to `DefaultStyles.leading`, which still came from `DefaultStyles.getInstance(context)` (`DefaultTextStyle` + hard-coded 16px metrics). That inherited the wrong font/color for list blocks and list markers — missing-glyph debug underlines on the bullet/number `Text` widgets.

**Fix:** Merge app input typography into all list-related block styles and wrap the editor in `DefaultTextStyle`:

```dart
lists: DefaultListBlockStyle(bodyStyle, ...),
leading: DefaultTextBlockStyle(bodyStyle, ...),
indent: DefaultTextBlockStyle(bodyStyle, ...),
link: bodyStyle.copyWith(color: colors.textLink, decoration: TextDecoration.underline),
// ...
DefaultTextStyle(style: bodyStyle, child: editorPane),
```

**Affected files (fixed):** `app_rich_text_editor.dart`.

---

## 47. `RenderFlex` unbounded height + `Expanded` (`VisitSubmittedPage`)

**Symptom:** Red screen after completing a visit and navigating to `/visits/:visitId/submitted`. `RenderFlex children have non-zero flex but incoming height constraints are unbounded` on `Column` in `visit_submitted_page.dart` `_VisitSubmittedContentView`. Cascading `RenderBox was not laid out` through `ClinicSetupWelcomeScope` and `authenticated_shell.dart`.

**Cause:** All visit-submitted state views used a root `Column` with `Expanded` to vertically center confirmation content. `AppShell` wraps non-`fillViewport` routes in `SingleChildScrollView`, which passes unbounded max height — `Expanded` is invalid in that context (same class as entries #28, #30).

**Fix:** Extract `_VisitSubmittedPageLayout` with `LayoutBuilder`: when `constraints.hasBoundedHeight`, use `Expanded` + `Center` for viewport fill; when unbounded, use `mainAxisSize: MainAxisSize.min` with no `Expanded`. For the content view, add a nested `LayoutBuilder` so `SingleChildScrollView` wraps the confirmation card only in the bounded path (avoid nested primary scroll views when the shell already scrolls).

```dart
class _VisitSubmittedPageLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(mainAxisSize: MainAxisSize.min, children: [header, body]);
        }
        return Column(children: [header, Expanded(child: Center(child: body))]);
      },
    );
  }
}
```

**Affected files (fixed):** `visit_submitted_page.dart`.

---

## 48. `_ResourceViewRenderObject` infinite / NaN size (`SfCalendar` doctor timeline)

**Symptom:** Red screen when opening or switching to the appointments calendar **Doctors** view (`CalendarView.timelineDay`). Rendering assertion: `_ResourceViewRenderObject object was given an infinite size during layout` with `Size(120.0, NaN)` at `SfCalendar` in `appointment_calendar_page.dart`. Cascading `RenderBox was not laid out`, null-check, and semantics assertions follow.

**Cause:** Two issues combined:

1. **Stale resource collection:** `AppointmentCalendarDataSource.updateItems` called `notifyListeners(CalendarDataSourceAction.reset, …)` after updating both `appointments` and `resources`. Syncfusion's `reset` handler refreshes appointments only — it does **not** update the calendar state's internal `_resourceCollection`. After switching from week/day to doctors view, `dataSource.resources` was populated (so `isResourceEnabled` was true) while `_resourceCollection` stayed `[]`. `panelHeight = resourceItemHeight * 0` became `NaN` via Syncfusion's `visibleResourceCount: -1` math (`timelineViewHeight / 0` then `Infinity * 0`).

2. **Defensive layout:** `visibleResourceCount: -1` lets Syncfusion divide viewport height by resource count; when count is stale-zero this produces `NaN` panel height inside the resource `ListView` (unbounded height → uses `panelHeight`).

**Fix:**

1. After `reset`, also notify resource changes so `_resourceCollection` syncs:

```dart
notifyListeners(CalendarDataSourceAction.reset, appointments ?? const []);
final resourceList = resources;
if (resourceList != null && resourceList.isNotEmpty) {
  notifyListeners(CalendarDataSourceAction.resetResource, resourceList);
}
```

2. In doctors mode, set a positive `visibleResourceCount` from viewport height instead of `-1`:

```dart
final timelineVisibleResourceCount = state.mode == AppointmentCalendarMode.doctors
    ? (calendarBodyHeight / _timelineResourceRowHeight).floor().clamp(1, 20)
    : -1;
```

**Affected files (fixed):** `appointment_calendar_data_source.dart`, `appointment_calendar_page.dart`.

## Checklist for Syncfusion `SfCalendar` / timeline resources

1. Updating `CalendarDataSource.resources`? → Notify with `CalendarDataSourceAction.resetResource` (or `addResource` / `removeResource`) — `reset` alone does **not** refresh the calendar's internal `_resourceCollection` (see entry #48).
2. Doctor timeline (`CalendarView.timelineDay`)? → Prefer a positive `visibleResourceCount` derived from viewport height; avoid `-1` when resource rows use a fixed height (`timelineAppointmentHeight`).

---

## 49. `ArgumentError` invalid `clamp` min > max (`AppointmentCalendarPage`)

**Symptom:** Red screen when opening the appointments calendar from a patient profile (nested inside `SingleChildScrollView`). `Invalid argument(s): 240.0` at `appointment_calendar_page.dart` in `_buildCalendar` during `double.clamp`.

**Cause:** `calendarBodyHeight` used `(viewportHeight - toolbarHeight).clamp(240.0, viewportHeight)`. Dart's `clamp` throws when `min > max`. In a scrollable/unbounded layout the calendar viewport can be smaller than 240px, so `clamp(240.0, viewportHeight)` fails.

**Fix:** Compute available height first, then apply the 240px minimum only when there is enough space:

```dart
final availableHeight = (viewportHeight - appointmentCalendarToolbarHeight).clamp(0.0, viewportHeight);
final calendarBodyHeight = availableHeight < 240.0
    ? availableHeight
    : availableHeight.clamp(240.0, viewportHeight);
```

**Affected files (fixed):** `appointment_calendar_page.dart`.

