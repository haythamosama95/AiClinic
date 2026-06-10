# Authenticated shell UI tests

Widget and unit tests for the authenticated application shell (`AuthenticatedShell`, left nav, header, content panel, and navigation config).

**Run:** `flutter test test/widget/shell/ test/unit/shell/`

**Source files:**

| File                                                            | Scope                                                       |
| --------------------------------------------------------------- | ----------------------------------------------------------- |
| `frontend/test/unit/shell/shell_nav_config_test.dart`           | Route bindings, labels, defaults, location resolution       |
| `frontend/test/widget/shell/shell_nav_badge_test.dart`          | Badge pill rendering and tone colors                        |
| `frontend/test/widget/shell/shell_nav_item_row_test.dart`       | Row layout, selection, hover pill, collapse fade, badge dot |
| `frontend/test/widget/shell/shell_nav_tree_connector_test.dart` | Tree connector sizing and custom paint                      |
| `frontend/test/widget/shell/shell_nav_group_test.dart`          | Group expand/collapse, chevron rotation, collapsed popover  |
| `frontend/test/widget/shell/shell_nav_test.dart`                | Sidebar layout, collapse width animation, footer, metrics   |
| `frontend/test/widget/shell/shell_header_test.dart`             | Page title, search, profile, icon buttons                   |
| `frontend/test/widget/shell/shell_header_profile_test.dart`     | Avatar initials edge cases                                  |
| `frontend/test/widget/shell/shell_content_panel_test.dart`      | Floating card decoration and child slot                     |
| `frontend/test/widget/shell/authenticated_shell_test.dart`      | Full shell layout, nav selection, routing, URL sync         |
| `frontend/test/widget/shell/shell_test_support.dart`            | Shared pump helpers and finders                             |

---

## ShellNavConfig (unit)

| Test Name                                                             | Scenario                                   | Pass Criteria                                                                                               | Fail Criteria                     |
| --------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `routeFor returns path for wired items`                               | Lookup each id in `_routesByItemId`        | `dashboard` → `/home`, appointment children → calendar/book/queue paths, `theme-showcase` → foundation demo | Wrong path or null for wired item |
| `routeFor returns null for unknown id`                                | Lookup `unknown-item`                      | Returns `null`                                                                                              | Throws or returns a path          |
| `itemIdForLocation resolves exact paths`                              | Pass each wired route path                 | Returns matching item id                                                                                    | Wrong id or null                  |
| `itemIdForLocation returns null for unrelated path`                   | Pass `/settings`                           | Returns `null`                                                                                              | False positive match              |
| `labelFor resolves top-level single`                                  | `dashboard`                                | Returns `Dashboard`                                                                                         | Null or wrong label               |
| `labelFor resolves group child`                                       | `appointments-queue`                       | Returns `Queue`                                                                                             | Null or wrong label               |
| `labelFor resolves theme showcase footer`                             | `theme-showcase`                           | Returns `Theme showcase`                                                                                    | Null or wrong label               |
| `labelFor returns null for unknown id`                                | `missing`                                  | Returns `null`                                                                                              | Wrong label                       |
| `groupIdFor returns appointments for child items`                     | Each appointments child id                 | Returns `appointments`                                                                                      | Null or wrong group               |
| `groupIdFor returns null for top-level single`                        | `dashboard`                                | Returns `null`                                                                                              | Non-null group                    |
| `defaultSelectedId returns first entry id`                            | Config has Dashboard first                 | Returns `dashboard`                                                                                         | Wrong default                     |
| `defaultExpandedGroupIds is empty when default is top-level`          | Default is `dashboard`                     | Empty set                                                                                                   | Contains group ids                |
| `defaultExpandedGroupIds contains parent when default is group child` | Hypothetical config with group child first | Contains that group id                                                                                      | Missing parent group              |

---

## ShellNavModels

| Test Name                                    | Scenario                                    | Pass Criteria             | Fail Criteria       |
| -------------------------------------------- | ------------------------------------------- | ------------------------- | ------------------- |
| `ShellNavSingle holds optional badge fields` | Construct with `badgeCount` and `badgeTone` | Fields accessible         | Fields missing      |
| `ShellNavGroup holds children list`          | Construct with child singles                | `children` length matches | Children not stored |

---

## ShellTokens

| Test Name                                       | Scenario                                                   | Pass Criteria                                                                                                                                      | Fail Criteria                                 |
| ----------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `navCollapsedWidth matches icon layout formula` | Compare constants                                          | `iconInsetFromNavEdge + itemIconSize + itemHorizontalPadding` equals `navCollapsedWidth` (28+20+12=60… verify against 64 if design intent differs) | Documented formula inconsistent with constant |
| `animation durations are positive`              | Read `hoverDuration`, `expandDuration`, `collapseDuration` | All > 0 ms                                                                                                                                         | Zero or negative duration                     |

---

## ShellNavBadge

| Test Name                                    | Scenario                    | Pass Criteria                                   | Fail Criteria        |
| -------------------------------------------- | --------------------------- | ----------------------------------------------- | -------------------- |
| `renders count text for positive count`      | `count: 8`, `tone: success` | Text `8` visible                                | Badge missing        |
| `renders nothing when count is zero`         | `count: 0`                  | `SizedBox.shrink` / no badge text               | Zero shown           |
| `renders nothing when count is negative`     | `count: -1`                 | No badge rendered                               | Negative count shown |
| `warning tone uses warning background token` | `tone: warning`             | Background `ShellTokens.badgeWarningBackground` | Wrong color          |
| `success tone uses success background token` | `tone: success`             | Background `ShellTokens.badgeSuccessBackground` | Wrong color          |
| `neutral tone uses semantic muted`           | `tone: neutral`             | Background matches `colors.muted`               | Wrong color          |
| `enforces minimum width constraint`          | Single-digit count          | `BoxConstraints(minWidth: 22)` on container     | Badge too narrow     |

---

## ShellNavItemRow

| Test Name                                                         | Scenario                                      | Pass Criteria                                                                                                | Fail Criteria                             |
| ----------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------- |
| `renders icon and label`                                          | Default row props                             | Icon and label text visible                                                                                  | Missing label or icon                     |
| `row height matches ShellTokens.itemHeight`                       | Pump row                                      | `SizedBox` height 40                                                                                         | Wrong height                              |
| `tap invokes onTap`                                               | Tap row                                       | Callback fired once                                                                                          | No callback                               |
| `selected state uses foreground icon color and semibold label`    | `isSelected: true`                            | Icon `colors.foreground`; label `FontWeight.w600`                                                            | Muted styling when selected               |
| `unselected state uses mutedForeground icon color`                | `isSelected: false`                           | Icon `colors.mutedForeground`                                                                                | Foreground when unselected                |
| `hover shows highlight pill via AnimatedOpacity`                  | Enter `MouseRegion`                           | `AnimatedOpacity` opacity moves toward 1; `DecoratedBox` pill with `colors.card` and `ShadowTokens.shadowSm` | No pill or instant jump with no animation |
| `hover pill fades out on exit`                                    | Enter then exit mouse                         | Mid-exit opacity between 0 and 1; settles at 0                                                               | Pill stays visible                        |
| `hover duration matches ShellTokens.hoverDuration`                | Enter hover, pump 180ms                       | Opacity at or near 1                                                                                         | Wrong duration constant                   |
| `renders ShellNavBadge when badgeCount and badgeTone set`         | `badgeCount: 3`, `badgeTone: warning`         | Badge with `3` visible beside label                                                                          | Badge missing                             |
| `renders trailing widget`                                         | Custom chevron trailing                       | Trailing icon visible                                                                                        | Trailing missing                          |
| `label ellipsizes with maxLines 1`                                | Long label string                             | `Text` has `maxLines: 1`, `overflow: ellipsis`                                                               | Wraps or clips badly                      |
| `label opacity fades with nav collapse progress`                  | Wrap in `ShellNavMetrics(collapseT: 0.5)`     | Label `Opacity` ≈ 0.5                                                                                        | Full opacity at mid-collapse              |
| `label hidden when collapseT is 1`                                | `ShellNavMetrics(collapseT: 1)`               | No label `Text` in expanded label region                                                                     | Label still fully visible                 |
| `badge dot appears on icon when collapsed past halfway`           | `badgeCount: 5`, `collapseT: 0.6`             | 7×7 primary dot on icon                                                                                      | Full badge pill or no indicator           |
| `badge dot hidden when expanded`                                  | `collapseT: 0`                                | No positioned dot on icon                                                                                    | Dot shown when expanded                   |
| `enablePointerEvents false skips MouseRegion and GestureDetector` | `enablePointerEvents: false`                  | No `GestureDetector` ancestor of row content                                                                 | Row captures taps                         |
| `hovered prop drives pill when pointer events disabled`           | `hovered: true`, `enablePointerEvents: false` | Highlight pill visible without internal hover                                                                | Pill only from internal MouseRegion       |

---

## ShellNavSingleItem

| Test Name                                      | Scenario             | Pass Criteria                   | Fail Criteria           |
| ---------------------------------------------- | -------------------- | ------------------------------- | ----------------------- |
| `delegates label and icon from ShellNavSingle` | Item with label/icon | Row shows item label and icon   | Wrong text/icon         |
| `tap calls onSelected with item id`            | Tap item             | `onSelected` receives item `id` | Wrong id or no callback |
| `forwards badge fields to row`                 | Item with badge      | `ShellNavBadge` visible         | Badge not forwarded     |
| `reflects isSelected prop`                     | `isSelected: true`   | Row selected styling            | Unselected appearance   |

---

## ShellNavTreeConnector

| Test Name                                 | Scenario         | Pass Criteria                                             | Fail Criteria     |
| ----------------------------------------- | ---------------- | --------------------------------------------------------- | ----------------- |
| `renders nothing when childCount is zero` | `childCount: 0`  | `SizedBox.shrink`                                         | Connector painted |
| `sizes to childCount times item height`   | `childCount: 3`  | Height `3 * ShellTokens.itemHeight`, width 28             | Wrong dimensions  |
| `uses CustomPaint for tree lines`         | `childCount: 2`  | `CustomPaint` with `_ShellNavTreeConnectorPainter`        | No custom paint   |
| `line color uses border at 65% alpha`     | Pump connector   | Painter `lineColor` matches `colors.border` at 0.65 alpha | Wrong color       |
| `shouldRepaint when childCount changes`   | Compare painters | `shouldRepaint` true when count differs                   | Stale paint       |

---

## ShellNavGroupWidget

| Test Name                                                             | Scenario                            | Pass Criteria                                                      | Fail Criteria                 |
| --------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------ | ----------------------------- |
| `renders group header with label and icon`                            | Collapsed group `isExpanded: false` | Group label visible in header row                                  | Header missing                |
| `header tap calls onToggle with group id`                             | Tap group header                    | `onToggle('appointments')`                                         | Wrong id or no callback       |
| `group header selected when child selected and group collapsed`       | Child selected, `isExpanded: false` | Header `isSelected: true`                                          | Header unselected             |
| `group header not selected when expanded even if child selected`      | Child selected, `isExpanded: true`  | Header `isSelected: false`                                         | Header stays selected         |
| `expanded shows all child ShellNavSingleItem rows`                    | `isExpanded: true`                  | Each child label visible                                           | Children hidden               |
| `collapsed clips child rows with zero heightFactor`                   | `isExpanded: false`                 | `Align` `heightFactor` is 0 (children clipped, may remain in tree) | Children fully visible        |
| `expand animates heightFactor from 0 to 1`                            | Toggle `isExpanded` false → true    | Mid-animation `Align` `heightFactor` between 0 and 1; settles at 1 | Instant show or stuck partial |
| `collapse animates heightFactor from 1 to 0`                          | Toggle true → false                 | Mid-animation heightFactor between 0 and 1; children clipped       | Instant hide                  |
| `expand duration matches ShellTokens.expandDuration`                  | Expand group                        | Animation completes at 250ms                                       | Wrong timing                  |
| `chevron rotates 180° when expanded`                                  | `isExpanded: true`                  | `RotationTransition` turns ≈ 0.5 (180°)                            | Chevron unchanged             |
| `chevron at 0 turns when collapsed`                                   | `isExpanded: false`                 | Turns ≈ 0                                                          | Rotated while collapsed       |
| `renders ShellNavTreeConnector for children`                          | Expanded group with 3 children      | `ShellNavTreeConnector(childCount: 3)`                             | Connector missing             |
| `didUpdateWidget syncs controller when isExpanded changes externally` | Flip `isExpanded` without tap       | Animation runs forward/reverse                                     | Stuck state                   |
| `init sets controller to 1 when starting expanded`                    | `isExpanded: true` on first frame   | Children fully visible immediately                                 | Collapsed flash               |

### Collapsed sidebar group header (`_CollapsedNavGroupHeader`)

| Test Name                                         | Scenario                              | Pass Criteria                                       | Fail Criteria               |
| ------------------------------------------------- | ------------------------------------- | --------------------------------------------------- | --------------------------- |
| `shows icon-only header when nav collapsed`       | `ShellNavMetrics(collapseT: 1)`       | Group icon row without expand chevron               | Full label row with chevron |
| `hover on header shows highlight pill`            | Mouse enter on collapsed group header | Row `hovered: true` styling                         | No hover feedback           |
| `tap opens AppPopoverMenu with child items`       | Tap collapsed group icon              | Popover lists Calendar, Book appointment, Queue     | Menu missing or wrong items |
| `popover item tap calls onSelected with child id` | Open menu; tap Calendar               | `onSelected('appointments-calendar')`               | Wrong id                    |
| `popover child items show icons`                  | Open menu                             | Each `AppPopoverMenuItem` has icon                  | Text-only menu              |
| `header uses enablePointerEvents false on row`    | Inspect collapsed header row          | `ShellNavItemRow` with `enablePointerEvents: false` | Row steals popover gestures |

---

## ShellNavMetrics

| Test Name                                       | Scenario                      | Pass Criteria              | Fail Criteria     |
| ----------------------------------------------- | ----------------------------- | -------------------------- | ----------------- |
| `maybeOf returns metrics when ancestor present` | Child under `ShellNavMetrics` | `collapseT` value readable | Null              |
| `maybeOf returns null without ancestor`         | Pump isolated widget          | Null                       | False ancestor    |
| `updateShouldNotify when collapseT changes`     | Rebuild with new `collapseT`  | Dependents rebuild         | Stale `collapseT` |

---

## ShellNav

| Test Name                                                              | Scenario                             | Pass Criteria                                                  | Fail Criteria                                |
| ---------------------------------------------------------------------- | ------------------------------------ | -------------------------------------------------------------- | -------------------------------------------- |
| `renders all ShellNavConfig.entries`                                   | Default pump                         | Dashboard, Appointments group visible                          | Entry missing                                |
| `renders theme showcase footer above collapse control`                 | Inspect column                       | `Theme showcase` below main list, above Collapse               | Wrong order                                  |
| `highlights selected top-level item`                                   | `selectedItemId: dashboard`          | Dashboard row selected                                         | Wrong selection                              |
| `highlights selected child in group`                                   | `selectedItemId: appointments-queue` | Queue child selected                                           | Wrong row                                    |
| `respects expandedGroupIds for group state`                            | `expandedGroupIds: {'appointments'}` | Appointments children visible                                  | Group collapsed                              |
| `item tap calls onItemSelected`                                        | Tap Dashboard                        | `onItemSelected('dashboard')`                                  | No callback                                  |
| `collapse control shows Collapse label and chevron_left when expanded` | Initial state                        | Text `Collapse`, `Icons.chevron_left`                          | Wrong label/icon                             |
| `collapse control shows chevron_right when collapsed`                  | After collapse animation             | `Icons.chevron_right`; label text hidden when `collapseT` is 1 | Wrong icon or label visible at full collapse |
| `collapse toggle animates sidebar width 260 → 64`                      | Tap Collapse; pump mid-animation     | `SizedBox` width between 64 and 260                            | Instant jump or wrong endpoints              |
| `collapse animation duration matches ShellTokens.collapseDuration`     | Full collapse                        | Completes at 250ms                                             | Wrong timing                                 |
| `collapse clips content with ClipRect and OverflowBox`                 | During collapse                      | Full 260px nav content left-aligned inside shrinking clip      | Content reflows incorrectly                  |
| `provides ShellNavMetrics to descendants`                              | During collapse                      | Descendants read changing `collapseT` 0→1                      | Metrics missing                              |
| `list scrolls when entries overflow`                                   | Short viewport height                | `ListView` scrollable                                          | Overflow error                               |
| `aligns nav below header offset`                                       | Layout                               | Top `SizedBox` height `ShellTokens.headerHeight`               | Nav underlaps header                         |

---

## ShellHeader

| Test Name                                        | Scenario                 | Pass Criteria                                                                                             | Fail Criteria                       |
| ------------------------------------------------ | ------------------------ | --------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `fixed height matches ShellTokens.headerHeight`  | Pump header              | `SizedBox` height 64                                                                                      | Wrong height                        |
| `renders page title when provided`               | `pageTitle: 'Dashboard'` | Title text visible, `titleLarge` style, `colors.foreground`                                               | Title missing                       |
| `omits title and spacer when pageTitle is null`  | `pageTitle: null`        | No title `Text`; search still centered                                                                    | Empty title gap                     |
| `title ellipsizes on overflow`                   | Very long `pageTitle`    | `maxLines: 1`, `overflow: ellipsis`                                                                       | Wraps                               |
| `renders centered search field with max width`   | Default pump             | `AppTextInput` hint `Search patients, appointments, visits…`; `maxWidth: 480`; search prefix icon size 18 | Missing search or wrong constraints |
| `search uses AppFieldSize.sm`                    | Inspect input            | `size: AppFieldSize.sm`                                                                                   | Wrong size                          |
| `renders ShellHeaderProfile`                     | Default pump             | Name `Alex Morgan`, role `Clinic Administrator`                                                           | Profile missing                     |
| `renders notifications icon button with tooltip` | Default pump             | `Icons.notifications_outlined`, tooltip `Notifications`                                                   | Missing control                     |
| `renders settings icon button with tooltip`      | Default pump             | `Icons.settings_outlined`, tooltip `Settings`                                                             | Missing control                     |
| `action spacing uses headerActionsGap and sm`    | Layout                   | Gap 16 between profile and notifications; 8 before settings                                               | Wrong spacing                       |
| `horizontal padding uses contentPanelInset`      | Layout                   | Padding horizontal 16                                                                                     | Wrong inset                         |

---

## ShellHeaderIconButton

| Test Name                            | Scenario        | Pass Criteria                          | Fail Criteria    |
| ------------------------------------ | --------------- | -------------------------------------- | ---------------- |
| `renders icon at size 20`            | Any icon        | `Icon` size 20                         | Wrong size       |
| `button is 40×40 circle`             | Pump button     | `SizedBox` 40×40, `CircleBorder`       | Wrong shape/size |
| `shows tooltip on hover/long press`  | Pump            | `Tooltip` message matches prop         | Missing tooltip  |
| `default background is muted`        | No hover        | `Material` color `colors.muted`        | Wrong default    |
| `hover background becomes accent`    | Mouse enter     | `colors.accent`                        | No hover change  |
| `hover clears on exit`               | Enter then exit | Returns to `colors.muted`              | Stuck accent     |
| `ink well uses circle custom border` | Tap             | `InkWell` `customBorder: CircleBorder` | Square splash    |
| `onTap is wired (no-op for now)`     | Tap button      | No throw; ripple/splash                | Crashes          |

---

## ShellHeaderProfile

| Test Name                                  | Scenario                 | Pass Criteria                          | Fail Criteria      |
| ------------------------------------------ | ------------------------ | -------------------------------------- | ------------------ |
| `renders default name and role`            | Default constructor      | `Alex Morgan`, `Clinic Administrator`  | Wrong placeholders |
| `avatar size matches headerAvatarSize`     | Default pump             | `CircleAvatar` radius 20 (40/2)        | Wrong size         |
| `avatar shows initials from name`          | `name: 'Alex Morgan'`    | Text `AM`                              | Wrong initials     |
| `single-word name uses first character`    | `name: 'Admin'`          | `A`                                    | Multiple chars     |
| `empty name shows question mark`           | `name: ''` or whitespace | `?`                                    | Blank avatar       |
| `avatar has border using colors.border`    | Inspect decoration       | `Border.all(color: colors.border)`     | No border          |
| `name uses semibold bodyMedium foreground` | Style check              | `FontWeight.w600`, `colors.foreground` | Wrong style        |
| `role uses bodySmall mutedForeground`      | Style check              | `colors.mutedForeground`               | Wrong style        |
| `name and role ellipsize`                  | Very long strings        | `maxLines: 1`, ellipsis                | Wrap overflow      |

---

## ShellContentPanel

| Test Name                                    | Scenario                      | Pass Criteria                           | Fail Criteria             |
| -------------------------------------------- | ----------------------------- | --------------------------------------- | ------------------------- |
| `renders child inside panel`                 | Child `Text('Content')`       | Text visible                            | Child missing             |
| `uses semantic background by default`        | No `backgroundColor`          | `colors.background` fill                | Wrong fill                |
| `custom backgroundColor overrides default`   | `backgroundColor: Colors.red` | Red fill                                | Theme background used     |
| `applies xl border radius from shape tokens` | Pump panel                    | `BorderRadius.circular(shapeTokens.xl)` | Wrong radius              |
| `draws border with semantic border color`    | Pump panel                    | `Border.all(color: colors.border)`      | No border                 |
| `applies ShadowTokens.card shadow`           | Pump panel                    | `boxShadow: ShadowTokens.card`          | Flat panel                |
| `clips child to rounded rect`                | Overflowing child             | `ClipRRect` matches decoration radius   | Child bleeds past corners |

---

## ShellContentPlaceholder

| Test Name                | Scenario                 | Pass Criteria                       | Fail Criteria |
| ------------------------ | ------------------------ | ----------------------------------- | ------------- |
| `expands to fill parent` | Place inside bounded box | `SizedBox.expand` fills constraints | Zero size     |

---

## AuthenticatedShell (integration)

| Test Name                                             | Scenario                                                                            | Pass Criteria                                                     | Fail Criteria                         |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------- |
| `renders nav, header, and content panel`              | Pump with child                                                                     | `ShellNav`, `ShellHeader`, `ShellContentPanel`, child all present | Region missing                        |
| `outer background uses accent color`                  | Pump shell                                                                          | Root `ColoredBox` `colors.accent`                                 | Wrong chrome color                    |
| `content panel inset padding`                         | Layout                                                                              | LTRB inset 16, top `SpacingTokens.sm`, sides/bottom 16            | Wrong padding                         |
| `header title reflects default selected nav item`     | Initial route `/home`                                                               | Title `Dashboard`                                                 | Wrong or null title                   |
| `header title updates when route changes`             | Navigate to appointments calendar                                                   | Title `Calendar`                                                  | Stale title                           |
| `selecting nav item calls context.go with route`      | Tap Dashboard (from another item)                                                   | Location `/home`                                                  | No navigation                         |
| `selecting group child navigates to child route`      | Tap Queue                                                                           | Location appointments queue path                                  | Wrong route                           |
| `selecting child expands parent group (parent state)` | Parent adds group id on `onItemSelected` (see `AuthenticatedShell._onItemSelected`) | `expandedGroupIds` contains parent after child tap                | Group stays collapsed in parent state |
| `header title updates when route changes via nav`     | Expand Appointments; tap Calendar                                                   | Title `Calendar`; route content visible                           | Stale title                           |
| `toggling group does not navigate`                    | Tap Appointments header                                                             | `onGroupToggled` only; URL unchanged                              | Unwanted navigation                   |
| `URL drives selected item over local state`           | Deep-link to queue route                                                            | Queue highlighted without manual tap                              | Wrong selection                       |
| `unknown route falls back to local selectedItemId`    | Unmapped shell child route                                                          | Local selection still highlights                                  | No selection                          |
| `child renders inside ShellContentPanel`              | Placeholder child text                                                              | Text inside panel                                                 | Child outside panel                   |
| `nav and content share row layout`                    | Layout                                                                              | `Row` with nav + `Expanded` column                                | Wrong structure                       |

### AuthenticatedShell animations (via ShellNav)

| Test Name                                           | Scenario                                | Pass Criteria                                | Fail Criteria            |
| --------------------------------------------------- | --------------------------------------- | -------------------------------------------- | ------------------------ |
| `sidebar collapse does not break header title`      | Collapse nav                            | Header title still visible and correct       | Title clipped or cleared |
| `collapsing sidebar fades nav labels`               | Mid-collapse                            | Labels partially transparent per `collapseT` | Labels snap off          |
| `appointments popover works when sidebar collapsed` | Collapse nav; open Appointments popover | Child routes selectable                      | Menu broken              |
| `expanding sidebar restores labels and tree`        | Collapse then expand                    | Full labels and group tree visible           | Labels or tree missing   |

---

## Accessibility and interaction polish

| Test Name                             | Scenario               | Pass Criteria                                   | Fail Criteria     |
| ------------------------------------- | ---------------------- | ----------------------------------------------- | ----------------- |
| `nav rows use click cursor`           | Hover nav row          | `SystemMouseCursors.click`                      | Default cursor    |
| `header icon buttons expose tooltips` | Semantics              | Tooltip messages for Notifications and Settings | Missing semantics |
| `search field is keyboard focusable`  | Tab focus              | `AppTextInput` receives focus                   | Not focusable     |
| `selected nav item visually distinct` | Selected vs unselected | Foreground + semibold vs muted                  | Indistinguishable |

---

## Edge cases

| Test Name                                            | Scenario                   | Pass Criteria                                 | Fail Criteria                       |
| ---------------------------------------------------- | -------------------------- | --------------------------------------------- | ----------------------------------- |
| `rapid collapse toggle reverses mid-animation`       | Tap Collapse twice quickly | Width animates back toward 260 without error  | Controller assertion or stuck width |
| `rapid group toggle reverses expand animation`       | Double-tap group header    | heightFactor reverses smoothly                | Stuck half-open                     |
| `selecting same item twice still invokes callback`   | Double-tap Dashboard       | `onItemSelected` twice (or idempotent router) | Crash                               |
| `theme showcase footer navigates to foundation demo` | Tap Theme showcase         | Route `/foundation-demo`                      | No navigation                       |
| `queue badge shows count 8 with success tone`        | Appointments expanded      | Badge `8` with success background             | Wrong count/tone                    |
