# AiClinic — Flutter Conversion Roadmap

**Purpose:** a dependency-ordered plan for faithfully reproducing the approved AiClinic web
design system + application in Flutter. This document is the single source of truth that drives all
subsequent implementation batches handed to an implementation agent (Composer).

- **Web reference (source of truth):** `web-reference/src/**` (React + Vite + Tailwind v4).
- **Design intent:** `docs/ui/design-system/**` (docs describe intent; **code is ground truth**).
- **Target:** `frontend/` — Clean Architecture Flutter app. Domain/data/application layers +
  Riverpod feature providers/notifiers/models are **intact**. Only presentation widgets, theme, and
  `core/ui` component library were deleted (see `git show b01fb20`).
- **Foundation contract:** a parallel agent is building `frontend/lib/core/ui/` foundation
  (tokens, semantic `ThemeExtension`s, motion, `AppSignalLine`, fonts). This plan assumes it
  **EXISTS** and layers components on top of it. See §1.4 for the exact contract we depend on.

---

## 1. Executive summary & principles

### 1.1 Approach

We are **not** translating HTML/CSS to Flutter. We reproduce the *design* — the visual system,
interaction model, motion, and information architecture — using **idiomatic Flutter**. The web
reference tells us exactly what each component looks like, which variants/states exist, and how it
behaves; we re-express that with Flutter widgets, `LayoutBuilder`/slivers, `Overlay`, implicit and
explicit animations, and the foundation tokens.

### 1.2 Core principles

1. **Reuse the foundation.** Never hardcode a color, size, radius, duration, or shadow. Everything
   resolves from `context.colors`, `context.typography`, `AppSpacing`, `AppRadii`, `AppDurations`,
   `AppEasings`, `AppShadows`, `AppBreakpoints`, `AppMotion`. Primitives (`AppColorPrimitives`) are
   never used directly by components.
2. **App-owned abstractions.** Every reusable element is an `App*` widget under
   `lib/core/ui/widgets/<group>/`. Third-party packages (`forui`, `syncfusion`, `flutter_quill`,
   charts) are always **wrapped** behind an App component so they can be swapped without touching
   feature code. Feature widgets import only `App*` components — never `forui`/`syncfusion`/etc.
   directly.
3. **RTL/LTR, light/dark, reduced-motion are first-class**, not retrofits. Use `EdgeInsetsDirectional`,
   `AlignmentDirectional`, `Directionality`, logical `start/end`, and `Directionality.of(context)`
   for mirroring. Directional icons (chevrons, arrows, back/forward, breadcrumb separators, send)
   mirror; non-directional glyphs (search, calendar, user) do not. Every animation resolves through
   `AppMotion` reduced-motion handling. Arabic uses IBM Plex Sans Arabic with ≥1.7 line-height and
   Western digits.
4. **Desktop-first responsive.** Design at `xl` (≥1280). Adapt down via breakpoints (§ responsive):
   sidebar expanded → icon rail (`lg`) → overlay drawer (`md`); tables → horizontal scroll → stacked
   row-cards (`sm`/`xs`); master-detail → list+drawer; dialogs/drawers → full-screen sheets on `xs`.
   Prefer container-driven (`LayoutBuilder`) responsiveness over hard pixel checks.
5. **Bind to existing state.** The surviving Riverpod providers/notifiers/models (§6) define the
   data contracts the UI must consume. Widgets are thin: watch providers, render, dispatch intents.
   No business logic in presentation.
6. **Spend color only on meaning; prefer whitespace + type hierarchy over borders/fills.** One
   primary action per view region. AI is always violet-marked, contained, and human-gated.
7. **Every data surface handles the required trio:** loading (shape-matched skeletons via
   `skeletonizer`), empty (`AppEmptyState`), error (`AppErrorState`) — plus filtered-empty and
   no-access.

### 1.3 Naming & placement conventions

- Widgets live under `lib/core/ui/widgets/<group>/app_<name>.dart`; class `App<Name>`.
- Groups: `actions/`, `inputs/`, `display/`, `feedback/`, `navigation/`, `layout/`, `overlays/`,
  `data/`, `ai/`, `calendar/`, `chart/`, `timeline/`, `money/`, `code/`.
- Barrel export `lib/core/ui/widgets/widgets.dart` (re-exported by `lib/core/ui/ui.dart`).
- Enums mirror web variants (e.g. `AppButtonVariant { primary, secondary, ghost, danger, ai, link }`).

### 1.4 Foundation contract this plan depends on (assumed EXISTS)

| Foundation piece | What components consume |
|---|---|
| `AppColors` (ThemeExtension) via `context.colors` | surface/text/icon/border/action/actionAi/status/signal semantic colors, light+dark |
| `AppTypography` via `context.typography` | `displayLg…mono`, Arabic-aware styles |
| `AppSpacing` (s0..s24, 4px) | all gaps/padding |
| `AppRadii` (none/sm4/md6/lg8/xl12/xxl16/full + `BorderRadius` getters) | corners |
| `AppDurations` (instant80..deliberate480), `AppEasings` (Cubic) | animation timing |
| `AppShadows` (elevation1/2/3, light+dark) | card/overlay elevation |
| `AppBreakpoints` (sm640..xxl1536) | responsive |
| `AppZIndex`, `AppSignal`, `AppDensity` (compact/standard/comfortable → topbar & nav heights) | overlays, density |
| `AppMotion` + reduced-motion resolution; `AppFade`, `AppFadeScale`, `AppSlideUp`, `AppSlideInline` (RTL-aware), `AppCollapse`, stagger helper | all motion |
| `AppSignalLine` | nav indicator, tab underline, AI thinking pulse |
| Fonts | Inter (sans), Geist (display), Geist Mono (mono), IBM Plex Sans Arabic |

> **Note on web tokens → foundation.** The web maps show which semantic token each component uses
> (e.g. `bg-action-primary`, `text-status-danger-fg`, `--focus-ring`, `--focus-ring-ai`,
> `surface-selected`, `border-subtle`). Each App component must select the equivalent
> `context.colors.*` field. Web CSS vars like `--duration-instant`, `--signal-glow`, `motion-nav`,
> `motion-fade-scale`, `motion-command`, `motion-modal`, `motion-drawer` map to `AppDurations` /
> `AppMotion` presets.

---

## 2. Complete component inventory

Legend for **Strategy**: **(a)** Flutter SDK widget · **(b)** existing pubspec package wrapped ·
**(c)** `forui` component wrapped · **(d)** new custom App widget. Where a NEW pub dependency is
required it is flagged **[NEW DEP]** (consolidated in §9).

Universal interactive state set (per `04`): default, hover, focus-visible, pressed, disabled,
loading, error/invalid, selected, readonly — all in light+dark, LTR+RTL. `hover` maps to Flutter
`MouseRegion`/`WidgetStateController`; `focus-visible` maps to `Focus`/`FocusableActionDetector`
with a token focus ring (`--focus-ring` → `context.colors.borderFocus`; AI uses `--focus-ring-ai`).

### 2.A Actions → `lib/core/ui/widgets/actions/`

| Web source | Flutter App name | Target path | Variants / sizes / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `actions/Button.tsx` + `button-variants.ts` | `AppButton` | `actions/app_button.dart` | variants: primary/secondary/ghost/danger/ai/link; sizes sm(28)/md(36)/lg(44); leading+trailing icon slots; states incl. **loading** (spinner replaces leading icon, width locked, `aria-busy`), error ring, disabled | press scale 0.98 (`AppDurations.instant80`), reduced-motion disables scale | icon slots use logical start/end; min hit ≥32; ≥44 on touch layouts | **(d)** custom on `Semantics`+`InkWell`/`FocusableActionDetector`. Justify: exact variant/size/state matrix + luminous focus rings not offered cleanly by `forui`/`ElevatedButton`. |
| `actions/IconButton.tsx` | `AppIconButton` | `actions/app_icon_button.dart` | variants ghost/secondary/danger/ai; sizes sm 28²/md 32²/lg 40²; **requires** semantic label + tooltip | press scale, hover fill | non-directional icons not mirrored | **(d)** custom (shares base with `AppButton`). |
| `actions/SplitButton.tsx` | `AppSplitButton` | `actions/app_split_button.dart` | primary segment + chevron segment → `AppMenu`; variant/size follow button; disabled/loading | chevron opens fade-scale menu | chevron mirrors; rounded start/end logical | **(d)** custom composing `AppButton` + `AppMenu`. |
| `actions/SegmentedControl.tsx` | `AppSegmentedControl` | `actions/app_segmented_control.dart` | 2–5 options; sizes sm/md; selected uses `surface-selected`+`text-primary`; roving arrow-key nav; disabled option | color transition | arrow Left/Right honor direction; logical borders | **(d)** custom (`role=radiogroup` semantics, `FocusTraversalGroup`). |

### 2.B Inputs & Forms → `lib/core/ui/widgets/inputs/`

Shared: `input-base/input-styles.ts` defines `InputSize sm(32)/md(36)/lg(44)`, wrapper/bare/field
class helpers, `border-default`→`border-focus`+ring on focus, invalid ring. Reproduce as
`AppFieldSize` + shared `_AppInputDecoration` builder consumed by all fields.

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `ui/form-field/FormField.tsx` | `AppFormField` | `inputs/app_form_field.dart` | label(bodyStrong)+required mark+hint icon/tooltip+control slot+helper(caption)+error(caption+danger+16px alert icon, replaces helper); links `describedby`/`invalid` | error fade-in | label above; RTL text-align start | **(d)** custom scaffold wrapping any control. |
| `ui/text-input/TextInput.tsx` | `AppTextField` | `inputs/app_text_field.dart` | leading/trailing icon, prefix/suffix affix (EGP/%), inline clear ✕; sizes; invalid/readonly/with-value/placeholder | focus ring color transition | affix + icons logical start/end | **(a)** `TextField` + custom decoration; **(c)** optional `forui` FTextField wrapped. Pick **(a)** for exact affix/clear control. |
| `ui/textarea/Textarea.tsx` | `AppTextArea` | `inputs/app_text_area.dart` | autoGrow, minRows, `maxLength`+counter variant, invalid | grow animates height (`AppCollapse`-style) | — | **(a)** `TextField(maxLines:null)` + counter. |
| `ui/search-input/SearchInput.tsx` | `AppSearchField` | `inputs/app_search_field.dart` | leading search icon, clear ✕ when filled, inline result count, `⌘F`/`/` hint, trailing loading spinner, debounce ~300ms, Esc clears | spinner fade | icon non-mirrored; hint chip logical end | **(d)** custom on `AppTextField` + debounce timer. |
| `ui/password-input/PasswordInput.tsx` | `AppPasswordField` | `inputs/app_password_field.dart` | masked + reveal toggle, caps-lock hint, invalid | reveal icon crossfade | toggle logical end | **(a)** `TextField(obscureText)` + toggle. |
| `ui/number-input/NumberInput.tsx` | `AppNumberField` | `inputs/app_number_field.dart` | tabular figures, optional +/− steppers, min/max/step, default 1 for invoice qty | stepper press | steppers logical end | **(a)** `TextField` + `inputFormatters` + steppers. |
| `ui/money-field/MoneyField.tsx` | `AppMoneyField` | `inputs/app_money_field.dart` | currency affix (EGP leading LTR / trailing RTL), tabular, 2-decimal, thousands grouping on blur, rejects invalid negatives, parses paste | — | affix flips per direction; value aligns inline-end | **(a)** `TextField` + `decimal` package + formatter. Never for display. |
| `ui/phone-input/PhoneInput.tsx` | `AppPhoneField` | `inputs/app_phone_field.dart` | country context (Egypt `+20`), formats as typed, validates shape, Latin digits | — | country code logical start | **(d)** custom on `AppTextField` + formatter (no lib; shape-only). |
| `ui/select/Select.tsx` | `AppSelect` | `inputs/app_select.dart` | single choice, chevron, type-ahead, invalid/disabled/readonly | menu fade-scale (`AppFadeScale`) | chevron mirrors | **(d)** custom trigger + `Overlay` menu (shares `AppPopover`/`AppMenu`). |
| `ui/combobox/Combobox.tsx` | `AppAutocomplete` | `inputs/app_autocomplete.dart` | **signature pattern**: text + async results popover (avatar/label/meta rows), debounced 300ms, match highlight, Enter selects highlighted, empty/no-match, loading, disabled items w/ reason, optional "create new" | popover fade-scale; results stagger optional | popover width = trigger; rows start-aligned | **(d)** custom on `AppPopover` + `RawAutocomplete`-style controller. Binds to feature search notifiers. |
| `ui/multi-select/MultiSelect.tsx` | `AppMultiSelect` | `inputs/app_multi_select.dart` | selected values as removable chips in field + combobox popover; "All branches" convenience | chip add/remove fade | chips wrap; logical | **(d)** custom on `AppAutocomplete` + `AppChip`. |
| `ui/checkbox/Checkbox.tsx` | `AppCheckbox` | `inputs/app_checkbox.dart` | checked/unchecked/**indeterminate** (used in table header), disabled, invalid | check draw / scale | — | **(c)** `forui` FCheckbox wrapped, or **(a)** `Checkbox`. Pick **(a)** for indeterminate control. |
| `ui/radio-group/RadioGroup.tsx` | `AppRadioGroup` | `inputs/app_radio_group.dart` | vertical/horizontal, arrow-key nav, disabled | selection dot scale | orientation honors direction | **(a)** custom on `Radio` + `FocusTraversalGroup`. |
| `ui/switch/Switch.tsx` | `AppSwitch` | `inputs/app_switch.dart` | boolean, always-labeled, invalid; knob slides `duration-fast` | knob slide (`AppDurations`) | knob slides toward end | **(c)** `forui` FSwitch wrapped or **(a)** `Switch`. |
| `ui/date-picker/DatePicker.tsx` | `AppDatePicker` | `inputs/app_date_picker.dart` | calendar popover + keyboard entry, min/max, house `dd/mm/yyyy` format, locale-aware (ar-EG), RTL calendar mirrors + mirrored nav chevrons | popover fade-scale | month grid mirrors; prev/next swap in RTL | **(d)** custom calendar grid in `AppPopover` (not `showDatePicker`, to match visuals + RTL + tokens). |
| `ui/time-picker/TimePicker.tsx` | `AppTimePicker` | `inputs/app_time_picker.dart` | 12/24h per locale, step granularity | popover | — | **(d)** custom on `AppPopover`. |
| `ui/date-range-picker/DateRangePicker.tsx` | `AppDateRangePicker` | `inputs/app_date_range_picker.dart` | dual-month popover, inclusive-range messaging, presets (Today/This week/This month) | popover | dual month order mirrors | **(d)** custom (extends date picker). |
| `ui/file-dropzone/FileDropzone.tsx` | `AppFileDropzone` | `inputs/app_file_dropzone.dart` | drop area + browse; accepted-types hint; per-file rows w/ progress; success/error/remove; states idle/drag-over/uploading/success/error | drag-over highlight; row add slide | — | **(b)** wrap `file_picker` for browse + `DropTarget`/drag; custom rows. |
| `ui/slider/Slider.tsx` | `AppSlider` | `inputs/app_slider.dart` | rare (coverage %), tabular value label, keyboard arrows, min/max/step | thumb drag | track fills from start | **(c)** `forui` FSlider or **(a)** `Slider` wrapped. |
| `ui/spinner/Spinner.tsx` | `AppSpinner` | `inputs/app_spinner.dart` | sizes sm/md | continuous rotate (respects reduced-motion → static/È subtle) | — | **(a)** `CircularProgressIndicator` styled, or custom painter. |

### 2.C Navigation → `lib/core/ui/widgets/navigation/`

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `navigation/AppSidebar.tsx` | `AppSidebar` | `navigation/app_sidebar.dart` | expanded (~248) / collapsed icon rail (~56, labels via tooltip); nav groups w/ overline headers; count badges; footer items; active = `surface-selected`+`text-primary`+**Signal** on inline-start edge; roving arrow-key nav | width transition `duration-base`; Signal moves via shared-element (`motion-nav`) — use `AppSignalLine` + an animated indicator position | moves to right in RTL; Signal on inline-start (= right); collapse chevron mirrors | **(d)** custom. Signal uses `AppSignalLine`. |
| `navigation/AppTopBar.tsx` | `AppTopBar` | `navigation/app_top_bar.dart` | 3-zone: page context (breadcrumb/title) start / centered Command trigger (`⌘K`, fixed-width sunken field) / end cluster (branch switcher hidden <md, notifications w/ count dot, theme toggle, user menu); sticky, flat `surface-default`+`border-subtle`, height per density | none on chrome | mirrors; command centered | **(d)** custom. Registers command trigger focus node in command controller. |
| `navigation/Breadcrumb.tsx` | `AppBreadcrumb` | `navigation/app_breadcrumb.dart` | hierarchical; last = current (non-link); truncates middle on overflow; separator mirrors | — | separator (chevron) mirrors | **(d)** custom `Wrap`/`Row`. |
| `navigation/Tabs.tsx` | `AppTabs` | `navigation/app_tabs.dart` | underline (Signal underline, default) / segmented (delegates to `AppSegmentedControl`) / vertical; arrow-key nav; lazy but state-preserving | underline slides (`motion-tab`) via `AppSignalLine` + animated position | underline slide + arrow keys honor direction | **(d)** custom (not Material `TabBar`, to get Signal underline + variants). |
| `navigation/Menu.tsx` (+ `ContextMenu`) | `AppMenu` | `navigation/app_menu.dart` | items (icon+label+shortcut hint+trailing check), separators, section labels, destructive (`danger-fg`), disabled w/ reason tooltip; context (long-press/right-click) | fade-scale (`motion-fade-scale`); Esc closes; focus returns to trigger | placement mirrors | **(d)** custom on `Overlay`/`CompositedTransformFollower`. |
| `ui/DropdownMenu.tsx` | `AppDropdownMenu` | `navigation/app_dropdown_menu.dart` | trigger+content+item+separator primitives used by `AppSplitButton`, `AppUserMenu` | fade-scale | align start/end logical | **(d)** custom (internal building block of `AppMenu`). |
| `navigation/Pagination.tsx` | `AppPagination` | `navigation/app_pagination.dart` | page controls + range summary ("1–50 of 2,000", tabular) + page-size select; keyboard | — | prev/next mirror; digits Western | **(d)** custom composing `AppSelect`+`AppIconButton`. |
| `navigation/Stepper.tsx` | `AppStepper` | `navigation/app_stepper.dart` | horizontal/vertical; step states complete/current/upcoming (numbered — order carries meaning); connectors; back/next w/ per-step disabled | connector fill; indicator state color | connector direction; back/next mirror | **(d)** custom. |
| `navigation/CommandBar.tsx` + `providers/CommandBarProvider.tsx` | `AppCommandBar` | `navigation/app_command_bar.dart` | **the hero**: centered overlay (`elevation-3`, `radius-xl`), single input w/ Signal focus accent, grouped results (Navigate/Patients/Actions/Ask AI…), per-item shortcut Kbd hints, recent/suggested when empty, arrow+Enter, fuzzy filter, `⌘K`/`Ctrl+K` global open, Esc closes + restores focus, "Ask AI…" transitions accent teal→violet + AI thinking Signal; restrained backdrop frost (off under reduced-transparency) | `motion-command` (scale+fade); Signal thinking pulse | full-width sheet on small; mirrors | **(d)** custom via `Overlay` + `Shortcuts`/`Actions` for `⌘K`; `AppSignalLine`. |
| `navigation/BranchSwitcher.tsx` | `AppBranchSwitcher` | `navigation/app_branch_switcher.dart` | current branch + dropdown of accessible branches; search when many; shows org context; change re-scopes data | menu fade-scale | — | **(d)** custom on `AppMenu` + search. Binds to `branchSelectionNotifier`. |
| `navigation/UserMenu.tsx` | `AppUserMenu` | `navigation/app_user_menu.dart` | avatar → menu (profile, theme toggle, language EN/AR, sign out, app version) | fade-scale | — | **(d)** custom on `AppAvatar`+`AppDropdownMenu`. |
| `navigation/AiModeToggle.tsx` + `providers/AiModeProvider.tsx` | `AppAiModeToggle` | `navigation/app_ai_mode_toggle.dart` | Standard↔AI switch; accent cross-fades teal↔violet; labeled; persists per session | accent crossfade (`AppFade`/color tween) | — | **(d)** custom bound to `aiModeProvider`. |

### 2.D Data Display → `lib/core/ui/widgets/data/` (+ `display/`, `calendar/`, `chart/`, `timeline/`, `money/`, `code/`)

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `table/DataTable.tsx` | `AppTable<T>` | `data/app_table.dart` | sticky header; sortable columns (sort caret: none/asc/desc); optional row selection (header + row checkbox, indeterminate); align start(text)/end(num+tabular)/center; row hover; row actions (inline icon / "⋯"); optional sticky first column; zebra; footer summary; density compact(36)/default(40)/comfortable(48) from `AppDensity`; states loading (skeleton rows), empty, error, filtered-empty, selection-active → Bulk Action Bar; keyboard row nav, Enter opens; **never animate numeric cells** | row hover color only; no load animation on numbers | RTL: start/end alignment flips; sticky first col = inline-start; caret mirrors | **(d)** custom on `Table`/`CustomScrollView`+slivers. Justify: exact sort/selection/sticky/density + `skeletonizer` loading; virtualization via sliver list for large sets. On `sm`/`xs` switch to stacked row-cards. |
| `card/Card.tsx` | `AppCard` | `layout/app_card.dart` | flat (border, elev0) / raised (elev1) / interactive (hover+focus, whole clickable) / ai (`surface-ai`+`border-ai`); optional header (title+actions), body, footer; padding sm/md/lg (space-4..6) | interactive hover elevation/tint | header actions logical end | **(d)** custom on `Material`/`DecoratedBox` + `AppShadows`. |
| `card/MetricCard.tsx` | `AppMetricCard` | `data/app_metric_card.dart` | label(overline/caption), value(display/h1 tabular), optional delta (▲/▼ success/danger), optional sparkline (`AppChart` sparkline), optional caption | none on value load | delta arrow mirrors? no (semantic up/down) | **(d)** custom composing `AppCard`. |
| `card/EntityCards.tsx` | `PatientCard`, `AppointmentCard`, `InvoiceCard`, `ServiceCard` | `data/entity_cards.dart` | documented **compositions** of `AppCard`+`AppAvatar`+`AppBadge`+`AppMoney`+quick actions (per `04 D4`) | — | — | **(d)** compositions (not new primitives). |
| `list/List.tsx` | `AppList` / `AppListItem` | `data/app_list.dart` | item leading(icon/avatar)+primary+secondary+trailing; selectable; divided or spaced | selection tint | leading logical start | **(a)** custom on `ListView`/`Column` + `ListTile`-like. |
| `description-list/DescriptionList.tsx` | `AppDescriptionList` | `data/app_description_list.dart` | label(tertiary)+value(primary, tabular for data); 1 or 2 columns; 2-col wide → stacked narrow | — | label/value order logical | **(d)** custom responsive grid. |
| `badge/Badge.tsx` | `AppBadge` | `display/app_badge.dart` | variants solid/soft(default)/outline/dot; colors neutral/success/warning/danger/info/teal/violet(ai); sizes sm/md; dot needs accessible label | — | dot logical start | **(d)** custom. |
| `chip/Chip.tsx` | `AppChip` | `display/app_chip.dart` | removable (✕) for filters/multi-select; selectable (filter toggle); neutral default | removal fade | ✕ logical end | **(d)** custom. |
| `avatar/Avatar.tsx` | `AppAvatar` | `display/app_avatar.dart` | image or initials fallback; sizes xs20→xl48; status dot online/offline/busy/away; deterministic initials color (neutral-safe subset) | — | status dot logical end | **(d)** custom on `CircleAvatar`/`ClipOval`. |
| `avatar/AvatarGroup.tsx` | `AppAvatarGroup` | `display/app_avatar_group.dart` | overlap + "+N"; max; size | — | overlap direction logical | **(d)** custom `Stack`. |
| `tooltip/Tooltip.tsx` + `TooltipProvider` | `AppTooltip` | `overlays/app_tooltip.dart` | brief text on hover/focus; in after ~400ms (`duration-fast`); side top/right/bottom/left; align; optional arrow; role=tooltip | fade in | RTL-aware placement (left/right swap) | **(d)** custom on `Overlay` (not Material `Tooltip`, for token styling + RTL side + focus trigger). |
| `timeline/Timeline.tsx` | `AppTimeline` | `timeline/app_timeline.dart` | chronological node+connector+timestamp(tabular)+content; grouping by day (Today/Yesterday/…) | — | node logical start; connector direction | **(d)** custom. |
| `calendar/Calendar.tsx` | `AppCalendar` | `calendar/app_calendar.dart` | views day/week/month(+agenda); time-grid w/ events, all-day row, now-indicator (**Signal line**), conflict styling (overlap warning), event popover, click/drag create where permitted, keyboard nav, doctor/branch filters | now-line Signal; view switch | RTL mirrors week order; header nav mirrors | **(b)** wrap `syncfusion_flutter_calendar` behind `AppCalendar`; style to tokens; overlay Signal now-indicator; provide day/week/month + agenda. Justify: syncfusion already in pubspec, robust time-grid + RTL. |
| `chart/Chart.tsx` | `AppChart` | `chart/app_chart.dart` | types line/area/bar/stacked-bar/donut/sparkline; categorical palette (teal+neutrals+status hues, documented); tabular axis labels; few gridlines; hover/focus tooltips; **data-table fallback + aria** | calm draw; no jitter | axis label direction; digits Western | **(b)+[NEW DEP]** wrap `fl_chart` behind `AppChart`; expose the 6 chart types + a lightweight custom `CustomPainter` sparkline. Provide accessible summary/table alongside. |
| `money/MoneyDisplay.tsx` | `AppMoney` | `money/app_money.dart` | read-only currency; tabular, 2 decimals, house grouping, symbol/position per locale; emphasis weight for totals; negative/refund via status color | — | symbol position per locale; digits Western; Latin isolation in Arabic | **(d)** custom on `intl` `NumberFormat` + `decimal`. |
| `progress/Progress.tsx` | `AppProgress` | `display/app_progress.dart` | bar (determinate) / circular (small/indeterminate) / steps (segmented); tabular percent label | fill/rotate (reduced-motion → static) | fills from start | **(a)** `LinearProgressIndicator`/custom painter wrapped. |
| `skeleton/Skeleton.tsx` | `AppSkeleton` | `feedback/app_skeleton.dart` | variants text/circular/rectangular; width/height; calm shimmer; static under reduced motion | shimmer via `skeletonizer` (respects reduced-motion) | — | **(b)** wrap `skeletonizer`. |
| `divider/Divider.tsx` | `AppDivider` | `display/app_divider.dart` | horizontal/vertical hairline (`border-subtle`); optional centered label | — | — | **(a)** custom on `Divider`/`Container`. |
| `kbd/Kbd.tsx` | `AppKbd` | `display/app_kbd.dart` | mono small `surface-sunken` chip for keys; `keys` convenience | — | — | **(d)** custom (Geist Mono). |
| `code-block/CodeBlock.tsx` | `AppCodeBlock` | `code/app_code_block.dart` | IDs/raw/AI output; `surface-sunken`; copy button; optional language label | copy feedback | LTR force for code even in RTL | **(d)** custom (Geist Mono) + `Clipboard`. |

### 2.E Feedback & Overlays → `lib/core/ui/widgets/feedback/` + `overlays/`

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `toast/Toast.tsx` + `ToastProvider` | `AppToast` + `AppToastScope`/controller | `overlays/app_toast.dart` | variants success/danger/info/neutral; optional action (Undo/View); stack max 3; auto-dismiss (success ~4s, danger ~8s/persist); pause on hover; dismissible; role status/alert | `motion-slide-up`; stack layout animation | corner respects RTL (inline-end) | **(d)** custom `Overlay` entry + Riverpod controller (replaces React context). |
| `alert/Alert.tsx` | `AppAlert` | `feedback/app_alert.dart` | info/success/warning/danger/ai; icon+title+body+optional actions+optional dismiss; used for degraded/offline/permission/validation-summary | dismiss collapse | icon logical start | **(d)** custom. |
| `dialog/Dialog.tsx` | `AppDialog` | `overlays/app_dialog.dart` | sizes sm/md/lg/full; header(title+close)+scrollable body+footer(actions, primary inline-end); sticky header/footer; focus trap; Esc closes (guard when dirty); backdrop frost (reduced-transparency safe); returns focus; scroll lock | `motion-modal` scale+fade | actions logical end; full-screen on `xs` | **(d)** custom `showGeneralDialog` wrapper + `FocusScope`. |
| `dialog/Dialog.tsx` (`ConfirmationDialog`) | `AppConfirmationDialog` | `overlays/app_confirmation_dialog.dart` | destructive/financial; title states effect; consequence-first body; danger/primary + cancel; optional typed-confirmation | modal | — | **(d)** custom on `AppDialog`. |
| `drawer/Drawer.tsx` | `AppDrawer` | `overlays/app_drawer.dart` | side inline-end(default)/inline-start/bottom; sizes sm/md/lg; modal or non-modal; focus mgmt; header/body/footer | `motion-drawer` (RTL-aware slide); bottom slides up | slides from opposite edge in RTL; bottom sheet on narrow | **(d)** custom `showGeneralDialog`/`Overlay` + `AppSlideInline`. |
| `ui/popover/Popover.tsx` | `AppPopover` | `overlays/app_popover.dart` | anchored transient surface (quick edit/filters/event details); optional arrow; dismiss on outside/Esc; used by Select/Combobox/DatePicker/Menu | `motion-fade-scale` | placement mirrors | **(d)** custom on `Overlay`+`CompositedTransformTarget/Follower`. Core building block. |
| `loading-overlay/LoadingOverlay.tsx` | `AppLoadingOverlay` | `feedback/app_loading_overlay.dart` | scoped (over card/panel) or global (route); dimmed surface + spinner/skeleton; prefer optimistic UI | fade in dim | — | **(d)** custom `Stack` overlay. |
| `empty-state/EmptyState.tsx` | `AppEmptyState` | `feedback/app_empty_state.dart` | variants first-run/no-results/no-access/error; icon/illustration+title+one-line+primary action(or shortcut hint)+optional secondary | fade in | centered | **(d)** custom. |
| `error-state/ErrorState.tsx` | `AppErrorState` | `feedback/app_error_state.dart` | icon+plain cause+retry; never raw stack; distinct from empty | fade in | — | **(d)** custom. |

### 2.F AI Components (violet, human-gated) → `lib/core/ui/widgets/ai/`

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `ai/AiPanel.tsx` | `AppAiPanel` | `ai/app_ai_panel.dart` | message history, input+send(Enter), Signal thinking indicator, suggested prompts when empty, scope indicator (branch/context), stop/regenerate; streaming via `motion-fade` (no typewriter jitter) | Signal thinking pulse; message fade-in | input send icon mirrors; bubbles side per role | **(d)** custom composing `AppAiMessageBubble`+`AppSignalLine`. |
| `ai/AiMessageBubble.tsx` | `AppAiMessageBubble` | `ai/app_ai_message_bubble.dart` | user (neutral, inline-end) / assistant (`surface-ai`, inline-start); markdown-capable; optional timestamp; copy action | fade-in | sides swap in RTL | **(d)+[NEW DEP]** custom + markdown renderer (`flutter_markdown`/`markdown_widget`) wrapped for assistant content. |
| `ai/AiSuggestion.tsx` | `AppAiSuggestion` | `ai/app_ai_suggestion.dart` | subtle violet inline suggestion attached to field/section; opt-in; dismissible; leads to approval | fade/collapse | — | **(d)** custom. |
| `ai/ProposedActionCard.tsx` | `AppAiProposedAction` | `ai/app_ai_proposed_action.dart` | **critical**: violet card "Proposed by AI"; human-readable summary; structured fields (editable where safe); Approve/Edit/Dismiss; states proposed/editing/submitting/approved/rejected/failed(w/ validation error) | state transitions fade; editing ring | — | **(d)** custom on `AppCard(variant: ai)`. Approve dispatches the normal validated backend path. |
| `ai/ThinkingIndicator.tsx` | `AppAiThinkingIndicator` | `ai/app_ai_thinking_indicator.dart` | the Signal pulse; only steady-state animation; stops on response; static label under reduced motion | Signal pulse | — | **(d)** custom on `AppSignalLine(variant: ai, thinking: true)`. |

### 2.G Layout & Utility → `lib/core/ui/widgets/layout/`

| Web source | Flutter App name | Target path | Variants / states | Motion | RTL / responsive | Strategy |
|---|---|---|---|---|---|---|
| `layout/AppShell.tsx` | `AppShell` | `layout/app_shell.dart` | composition: sidebar + top bar + content region (independent scroll, max content width, tables full-width) + overlay layers (command/modal/drawer/popover/toast by z-index) | — | full mirror | **(d)** custom (see §4). |
| `layout/PageHeader.tsx` | `AppPageHeader` | `layout/app_page_header.dart` | title(h1)+description+breadcrumb+primary action(s)+optional tabs; consistent top rhythm | — | actions logical end | **(d)** custom. |
| `layout/SectionHeader.tsx` | `AppSectionHeader` | `layout/app_section_header.dart` | overline/h3+description+section actions | — | — | **(d)** custom. |
| `layout/Toolbar.tsx` | `AppToolbar` | `layout/app_toolbar.dart` | start/center/end slots; sticky; wraps gracefully; standard strip above tables/lists; collapses to Filters sheet on small | — | slots logical; wrap | **(d)** custom on `Wrap`/`Row`. |
| `layout/BulkActionBar.tsx` | `AppBulkActionBar` | `layout/app_bulk_action_bar.dart` | appears on selection; count + actions + clear; `surface-raised`+elev2 | slide/fade in | — | **(d)** custom. |
| `scroll-area/ScrollArea.tsx` | `AppScrollArea` | `layout/app_scroll_area.dart` | styled thin calm scrollbars; keyboard scrollable; edge-fade hints; maxHeight | fade edges | — | **(a)** `Scrollbar`+`ShaderMask` edge fade. |
| `resizable/ResizablePanels.tsx` | `AppResizablePanels` | `layout/app_resizable_panels.dart` | master-detail + encounter workspace; draggable divider w/ keyboard (arrow ±); min/max %; nestable; persists | divider hover color | drag math mirrors in RTL (see web `dir==='rtl'` handling) | **(d)** custom `LayoutBuilder`+`GestureDetector`+`Focus`. (Optional pkg `multi_split_view` — recommend custom to control keyboard + RTL + tokens.) |

### 2.H Primitive / foundation-owned

| Web source | Flutter | Notes |
|---|---|---|
| `primitives/Signal.tsx` | `AppSignalLine` (**foundation**) | variants standard/ai; orientation h/v; size default/hero; `thinking` pulse; `active` glow. Already provided by foundation — components consume it. |

**Component count:** ~**80 App components** (Actions 4 · Inputs 20 · Navigation 12 · Data/Display 23
incl. 4 entity-card compositions · Feedback/Overlays 9 · AI 5 · Layout 7) built on top of the
foundation `AppSignalLine` primitive, plus **7 provider migrations** (§3).

---

## 3. Providers → Flutter state

Web React contexts map to Riverpod. Several already have Flutter homes (foundation / existing app
providers); the rest become new `Notifier`s under `lib/core/ui/state/` (UI-only) — feature state
stays in the existing feature providers.

| Web provider | Responsibility | Flutter equivalent | Exists? |
|---|---|---|---|
| `ThemeProvider` (light/dark, persisted, system default) | theme mode | existing `lib/app/providers/theme_provider.dart` (re-add) + `MaterialApp.themeMode`; persisted via `shared_preferences` | Partially (file exists; wire to `AppColors`/`AppTypography` ThemeExtensions) |
| `DensityProvider` (compact/default/comfortable, persisted) | density → topbar/nav/table heights | new `densityProvider` (`Notifier<AppDensity>`) in `core/ui/state/`; drives `AppDensity` | Enum `AppDensity` in foundation; **provider new** |
| `DirectionProvider` (ltr/rtl + locale en/ar, persisted; sets drawer offset & motion inline-start) | direction + locale | new `localeDirectionProvider`; drives `MaterialApp.locale` + `Directionality`; `AppSlideInline` reads direction from context | **new** (foundation motion is RTL-aware) |
| `AiModeProvider` (standard↔AI, session) | AI accent teal↔violet | new `aiModeProvider` (`Notifier<bool>`) | **new** |
| `CommandBarProvider` (open state, ⌘K global, trigger focus) | command bar open/focus | new `commandBarProvider` + a global `Shortcuts`/`Actions` for `⌘K`/`Ctrl+K`; trigger focus node registration | **new** |
| `ToastProvider` (queue, max 3, auto-dismiss, pause) | transient toasts | new `toastControllerProvider` + `Overlay` host in `AppShell` | **new** |
| `TooltipProvider` (delay coordination) | tooltip open delay/singleton | `AppTooltip` self-manages via `Overlay` + timer; a light `tooltipControllerProvider` optional | **new (light)** |

Feature-facing existing providers the UI binds to (theme/branch/auth/connectivity already present):
`authSessionProvider`, `startupSessionProvider`, `branchSelectionNotifier`, `connectivityProvider`,
`repository_providers`, `session_context_loader`, plus all feature notifiers in §6.

---

## 4. App shell & navigation

The persistent authenticated frame (per `05 §1`). Rebuild inside the existing
`lib/app/shell/authenticated_shell.dart` (currently a passthrough `ShellDevShellWrapper(child)`),
wrapping the `ShellRoute` child from `lib/app/router.dart`.

**`AppShell` layout (xl):**
```
┌───────────────────────────────────────────────┐
│ AppTopBar: [breadcrumb] [⌘K search] [branch▾ ◔ ☾ @]│  ← sticky, flat, height per density
├──────────┬────────────────────────────────────┤
│ AppSidebar│  content region (feature route)     │  ← independent scroll, max width, tables full
│  ▎active  │                                     │
│  groups   │                                     │
│  [footer] │                                     │
└──────────┴────────────────────────────────────┘
   overlays: AppCommandBar · AppDialog · AppDrawer · AppPopover · AppToast (z-index ordered)
```

Responsive behavior (`06`): sidebar expanded (`xl`) → icon rail (`lg`) → overlay drawer + hamburger
(`md` and below); top bar condenses (branch switcher hides <`md`); content single-column on small.

Pieces & data sources:
- **`AppSidebar`** — nav model. Web uses `navigation/nav-model.ts` (`NavGroup[]`, `NavItem`, count
  badges, footer items, org/branch header). In Flutter, rebuild an equivalent
  `lib/app/shell/config/shell_nav_config.dart` (deleted; recreate) producing groups keyed to
  `AppRoutes`, gated by `permissionServiceProvider` (hide vs disable per RBAC `05 §7`). Active item
  derives from `GoRouterState` location. Signal active indicator uses `AppSignalLine` with an
  animated indicator position (`motion-nav`).
- **`AppTopBar`** — breadcrumb/title (page context), centered command trigger (registers focus node
  in `commandBarProvider`), branch switcher (`branchSelectionNotifier`), notifications count dot,
  theme toggle (`themeProvider`), `AppUserMenu` (`authSessionProvider` for user + sign out).
- **`AppCommandBar`** — mounted once at shell level; global `⌘K` via `Shortcuts`/`Actions`; items
  aggregate navigate targets + patient search (`AppAutocomplete` against patient search notifier) +
  actions + "Ask AI…" (flips `aiModeProvider`).
- **Density** — `densityProvider` drives topbar/nav/table heights via `AppDensity`.
- Existing router (`lib/app/router.dart`) + `AppRoutes` (`lib/app/app_routes.dart`) stay; feature
  routes currently render `uiPendingPlaceholder(...)` and will be swapped to real pages per §6.

---

## 5. Patterns → Flutter page templates

Each pattern (`web-reference/src/showcase/patterns/**`) becomes a reusable Flutter page
scaffold/composition. Build these as composition helpers/mixins (not one-offs) so feature pages
assemble them (per `05 §11`).

| Pattern (web) | `05` template | Flutter composition |
|---|---|---|
| `DashboardPattern.tsx` | Dashboard/Analytics | `AppPageHeader` → metric row (`AppMetricCard` grid, N→2→1 across via `LayoutBuilder`) → charts grid (`AppChart`) → detail `AppTable`s. |
| `ListIndexPattern.tsx` | List/Index | `AppPageHeader` → `AppToolbar` (`AppSearchField` + filter `AppChip`s + primary `AppButton`) → `AppTable` (loading/empty/error/filtered-empty) → `AppPagination`. Selection → `AppBulkActionBar`. |
| `RecordDetailPattern.tsx` | Record Detail | `AppPageHeader` (title + status `AppBadge` + actions + `AppTabs`) → sections: `AppDescriptionList`, related `AppTable`, `AppTimeline`. |
| `EditorFormPattern.tsx` | Editor/Form | page header or `AppDialog`/`AppDrawer` → grouped `AppSectionHeader` + `AppFormField` sections (single-column default; 2-col paired on wide) → sticky footer actions; validate on blur+submit; backend rule → field/summary `AppAlert`; stale-edit conflict messaging. |
| `MasterDetailPattern.tsx` | Master–Detail | `AppResizablePanels` (list inline-start + detail inline-end) on `xl`/`lg`; list → detail in `AppDrawer`/route on `md` and below. |
| `WorkspacePattern.tsx` | Workspace | Nested `AppResizablePanels`: patient context (`PatientCard`+vitals) · primary SOAP/plan (`AppTextArea` sections + save/sign) · dockable `AppAiPanel`. Multi-pane → tabbed/segmented on smaller. |
| `CalendarQueuePattern.tsx` | Board/Queue + Calendar | `AppToolbar` (filters, `AppSegmentedControl` view) → `AppCalendar` (day/week/month) or queue columns of entity cards with status. |
| `WizardPattern.tsx` | Wizard | `AppStepper` (numbered) + per-step `AppFormField` sections + back/next w/ per-step validation. |
| `AiFlowPattern.tsx` | AI interaction (`05 §10`) | `AppAiModeToggle`/command entry → `AppAiPanel` converse (stream) → `AppAiProposedAction` (summary + editable safe fields) → human Approve/Edit/Dismiss → normal record + `AppToast`; failure → same error mapping as forms. |
| `StateGalleryPattern.tsx` | Content states (`05 §6`) | canonical loading (`AppSkeleton`), empty (`AppEmptyState` first-run/no-results/no-access), error (`AppErrorState`), degraded/offline (`AppAlert`) treatments reused everywhere. |

---

## 6. Feature pages → pattern + components

Real routes from `lib/app/router.dart` + `lib/app/app_routes.dart`; deleted page/widget files
(the prior UI, from `git show b01fb20 --stat`) enumerate everything to rebuild. Each page **binds to
the surviving provider(s)** listed and composes the noted pattern.

### 6.1 Auth & Setup (V1-1, setup)
- **Login** (`/login`) — Empty/Auth pattern; centered `AppCard`/modal. Binds `authNotifier`.
  Deleted: `auth/.../login_page.dart`, `login_modal.dart`.
- **Bootstrap / first-run setup** (`/bootstrap`, setup guidance) — Wizard pattern (`AppStepper`):
  organization → branch → staff → complete. Binds `setupNotifier`, `provisioningNotifier`,
  `staffAssignableBranchesProvider`, `clinicSetupProviders`. Deleted: `setup/.../setup_modal.dart`,
  `setup_*_step.dart`, `setup_step_indicator.dart`, `staff_form_fields.dart`, `branch_form_fields.dart`,
  `organization_form_fields.dart`, etc.
- **Staff create / password reset** (`/staff/create`, `/staff/reset-password`) — Editor/Form (dialog).

### 6.2 Dashboard / Home
- **Home / Dashboard** (`/home`) — Dashboard pattern. Deleted: `dashboard/.../dashboard_page.dart`.

### 6.3 Patients (V1-3)
- **Patients list** (`/patients`) — List/Index. Binds `patientListNotifier`, `patientListFilters`.
  Deleted: `patients_page.dart`, `patients_table.dart`, `patients_toolbar.dart`,
  `patients_filter_sidebar.dart`, `patients_sort_popover.dart`, `patients_empty_state.dart`,
  `patients_table_skeleton.dart`.
- **Register patient** (`/patients/new`), **Edit** (`/patients/:id/edit`) — Editor/Form (modal).
  Deleted: `create_patient_modal.dart`, `duplicate_candidates_dialog.dart`.
- **Patient detail** (`/patients/:id`) — Record Detail (tabs Overview/Visits/Billing) +
  `AppTimeline`, documents, notes, health tracking. Binds `patientDetailProvider`,
  `patientDetailHistoryProvider`. Deleted: `patient_detail_page.dart`,
  `patient_detail_timeline_section.dart`, `patient_detail_documents_card.dart`,
  `patient_detail_notes_card.dart`, `patient_billing_section.dart`, `patient_gender_avatar.dart`,
  `patient_container_transform_transition.dart`.

### 6.4 Appointments (V1-4)
- **Appointments hub / list** (`/appointments`), **Queue** (`/appointments/queue`) — Board/Queue.
  Binds `appointmentQueueProvider`, `appointmentQueueShiftProvider`. Deleted:
  `appointment_queue_page.dart`, `queue/*` (schedule/session/waiting columns, stats banner,
  row status button, shift doctor picker).
- **Calendar** (`/appointments/calendar`) — Calendar pattern (`AppCalendar`/syncfusion). Binds
  `appointmentCalendarProvider`. Deleted: `appointment_calendar_page.dart`,
  `appointment_calendar_*` (header bar, filter popover, data source, color legend, skeleton).
- **Book** (`/appointments/book`) — Editor/Form (sheet). Deleted: `appointment_booking_sheet.dart`.
- **Doctor schedule** (`/appointments/schedule/:doctorId`) — Calendar/list.
- **Appointment detail** (`/appointments/:id`) — Record Detail + status journey/timeline. Binds
  `appointmentDetailProvider`. Deleted: `appointment_detail_page.dart`,
  `appointment_detail_status_actions.dart`, `appointment_status_timeline_widget.dart`,
  `appointment_reschedule_confirm_dialog.dart`, `appointment_cancel_dialog.dart`,
  `visit_create_dialog.dart`.

### 6.5 Visits / Encounter Workspace (V1-5)
- **Visit documentation** (`/visits/:id/document`) — Workspace pattern (multi-pane, SOAP,
  dockable AI). Binds `visitDocumentationNotifier`, `encounterStepProvider`,
  `workspaceModeProvider`, `expertModeScrollProvider`, `patientSafetyProvider`. Deleted:
  `visit_documentation_page.dart`, `encounter_workspace_shell.dart`, `clinical_note_editor.dart`
  (→ `flutter_quill` behind an App rich-text component), `encounter_phase_*`, `encounter_review.dart`,
  `treatment_plan_*`, `investigation_*`, `catalog_autocomplete_field.dart` (→ `AppAutocomplete`),
  `visit_attachment_list.dart` (→ `AppFileDropzone` + `pdfx`/`open_filex`).
- **Visit detail** (`/visits/:id/detail`) — Record Detail. Binds `visitDetailProvider`. Deleted:
  `visit_detail_page.dart`, `visit_detail_actions.dart`, `visit_patient_info_card.dart`,
  `visit_shared_widgets.dart`.

### 6.6 Billing (V1-6)
- **Invoices list** (`/billing/invoices`) — List/Index. Binds `invoiceListNotifier`,
  `invoiceListFilters`. Deleted: `invoice_list_page.dart`.
- **Invoice detail** (`/billing/invoices/:id`) — Record Detail (totals, payments, receipt print via
  `pdf`+`printing`). Binds `invoiceDetailProvider`, `paymentNotifier`. Deleted: `invoice_detail_page.dart`,
  `invoice_totals_panel.dart`, `payment_form.dart`, `refund_form.dart`, `receipt_print_preview.dart`,
  `void_invoice_dialog.dart`, `invoice_status_badge.dart`.
- **Invoice editor** (`/billing/invoices/:id/edit`) — Editor/Form. Binds `invoiceEditorNotifier`.
  Deleted: `invoice_editor_page.dart`, `invoice_items_editor.dart`, `invoice_discount_panel.dart`,
  `line_discount_field.dart`, `discount_scope_guard.dart` (RBAC disable-with-reason).
- **Insurance providers** (`/billing/insurance-providers`) — List/Index. Binds
  `insuranceProvidersNotifier`. Deleted: `insurance_providers_page.dart`, `insurance_panel.dart`.
- **Billing settings** (`/settings/billing`) — Settings. Binds `billingSettingsNotifier`. Deleted:
  `billing_settings_page.dart`.

### 6.7 Service Catalog (V1-8, 015)
- **Service list** (`/settings/services`) — List/Index. Binds `serviceCatalogListNotifier`,
  `serviceListFilters`. Deleted: `service_catalog_list_page.dart`.
- **Service editor** (`/settings/services/new`, `/:id/edit`) — Editor/Form + branch-config matrix +
  promotion editor. Binds `serviceEditorNotifier`, `serviceFormDraftSnapshot`,
  `serviceSelectorNotifier`. Deleted: `service_editor_page.dart`, `service_form.dart`,
  `branch_configuration_matrix.dart`, `copy_configuration_dialog.dart` (cross-branch confirm `E4`),
  `promotion_editor.dart`, `new_branch_service_setup.dart`, `create_service_modal.dart`,
  `invoice_service_selector.dart`.

### 6.8 Shifts (V1-7)
- **Shifts calendar** (`/shifts/calendar`), **New** (`/shifts/new`), **Detail** (`/shifts/:id`) —
  Calendar pattern + Editor/Form. (Providers under `appointments` shift providers /
  `appointmentQueueShiftProvider`; note: no `shifts/presentation/providers` dir exists — verify
  during Batch.)

### 6.9 Settings & Admin (V1-2)
- **Settings hub** (`/settings`), **Idle timeout** (`/settings/idle-timeout`) — Settings tabs.
  Deleted: `settings_page.dart`, `settings_tab_bar.dart`, `settings_cards_grid.dart`,
  `idle_timeout_settings_card.dart`, `settings_section_card.dart`.
- **Organization** (`/settings/organization`), **Branches** (`/settings/branches`, `/new`,
  `/:id/edit`) — Settings + Editor/Form. Binds `clinicSetupProviders`. Deleted:
  `organization_settings_section.dart`, `branch_settings_section.dart`,
  `branch_working_hours_sheet.dart`, `create_branch_modal.dart`.
- **Staff** (`/settings/staff`, `/new`, `/:id`, `/:id/reset-password`) — List/Index + detail sheet.
  Binds `staffListNotifier`. Deleted: `staff_list_page.dart`, `staff_list_toolbar.dart`,
  `staff_list_filter_popover.dart`, `staff_member_card.dart`, `staff_detail_sheet.dart`,
  `create_staff_modal.dart`.
- **Permissions** (`/settings/permissions`) — matrix. Binds `rolePermissionsNotifier`. Deleted:
  `role_permissions_page.dart`, `role_permissions_matrix.dart`.

> RBAC everywhere (`05 §7`): hide unusable nav/sections; disable-with-reason tooltip for present but
> unpermitted actions; read-only rendering; backend remains authority. Multi-branch context
> (`05 §8`) surfaced via `AppBranchSwitcher` + labels/empty states.

---

## 7. Dependency-ordered phase plan (the deliverable)

Batches are cohesive, independently testable, and ordered so each depends only on prior batches.
**Phase 0 (Foundation)** is being delivered by the parallel agent and is a hard prerequisite for
everything. Size = rough effort (S ≈ ½ day, M ≈ 1 day, L ≈ 2–3 days).

### Phase 0 — Foundation (DONE / in parallel) — prerequisite
Tokens, semantic `ThemeExtension`s (`AppColors`, `AppTypography`), motion (`AppMotion` + wrappers),
`AppSignalLine`, fonts, density enum. **All batches below depend on this.**

### Phase 1 — Atomic components (no cross-component deps)
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B1 Actions** | `AppButton`, `AppIconButton`, `AppSpinner`, `AppSegmentedControl` | P0 | M |
| **B2 Display atoms** | `AppBadge`, `AppChip`, `AppAvatar`, `AppAvatarGroup`, `AppDivider`, `AppKbd`, `AppProgress`, `AppSkeleton`(skeletonizer) | P0 | M |
| **B3 Money & code** | `AppMoney`, `AppCodeBlock` | P0 | S |
| **B4 Input core** | `AppFieldSize`/shared decoration, `AppFormField`, `AppTextField`, `AppTextArea`, `AppPasswordField`, `AppNumberField`, `AppMoneyField`, `AppPhoneField`, `AppSearchField` | P0 | L |
| **B5 Choice inputs** | `AppCheckbox`, `AppRadioGroup`, `AppSwitch`, `AppSlider` | P0 | M |

### Phase 2 — Overlay primitives (unblock composite inputs & menus)
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B6 Popover/Overlay core** | `AppPopover` (Overlay + CompositedTransform), `AppTooltip`, `TooltipProvider` shim | P0, B1 | M |
| **B7 Menus** | `AppDropdownMenu`, `AppMenu` (+ context menu), `AppSplitButton` | B1, B6 | M |
| **B8 Popover inputs** | `AppSelect`, `AppAutocomplete` (signature), `AppMultiSelect`, `AppDatePicker`, `AppTimePicker`, `AppDateRangePicker` | B4, B6 | L |
| **B9 File input** | `AppFileDropzone` (file_picker) | B4 | M |

### Phase 3 — Composite display & content-state components
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B10 Cards** | `AppCard`, `AppMetricCard`, EntityCards (Patient/Appointment/Invoice/Service) | B1, B2, B3 | M |
| **B11 Lists & KV** | `AppList`/`AppListItem`, `AppDescriptionList`, `AppTimeline` | B2 | M |
| **B12 Content states** | `AppEmptyState`, `AppErrorState`, `AppLoadingOverlay`, `AppAlert` | B1, B2 | M |
| **B13 DataTable** | `AppTable<T>` (sort/select/sticky/density/zebra/footer + loading/empty/error + stacked-rows responsive) | B1, B2, B5, B12 | L |

### Phase 4 — Feedback & overlay surfaces
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B14 Toast** | `AppToast` + `toastControllerProvider` + shell overlay host | B1, P0 | M |
| **B15 Dialog/Drawer** | `AppDialog`, `AppConfirmationDialog`, `AppDrawer` (focus trap, scroll lock, RTL slide, xs full-screen) | B1, B6 | L |

### Phase 5 — Data-viz, calendar, rich text, resizable
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B16 Chart** | `AppChart` (fl_chart wrap: line/area/bar/stacked/donut/sparkline + a11y table) **[NEW DEP fl_chart]** | B2 | L |
| **B17 Calendar** | `AppCalendar` (syncfusion wrap: day/week/month/agenda, now-Signal, conflicts, RTL) | B1, B6 | L |
| **B18 Resizable & scroll** | `AppResizablePanels`, `AppScrollArea` | P0 | M |
| **B19 Rich text** | App rich-text editor wrapping `flutter_quill` (SOAP/clinical notes) | B4 | L |

### Phase 6 — UI state providers, navigation & shell
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B20 UI state providers** | `densityProvider`, `localeDirectionProvider`, `aiModeProvider`, `commandBarProvider`; wire `themeProvider` to ThemeExtensions | P0 | M |
| **B21 Nav atoms** | `AppBreadcrumb`, `AppTabs` (Signal underline), `AppStepper`, `AppPagination` | B1, B2, B6 | M |
| **B22 Shell chrome** | `AppSidebar` (Signal active, groups, collapse, RTL), `AppTopBar`, `AppBranchSwitcher`, `AppUserMenu`, `AppAiModeToggle`, recreate `shell_nav_config.dart` | B7, B20, B21 | L |
| **B23 Command Bar** | `AppCommandBar` (⌘K global, groups, Ask-AI transition, Signal) | B6, B20, B8 | L |
| **B24 App Shell** | `AppShell` assembling sidebar+topbar+content+overlay layers; mount in `authenticated_shell.dart`; responsive (rail/drawer) | B22, B23, B14, B15 | L |

### Phase 7 — Layout/pattern scaffolds & AI
| Batch | Components / files | Depends on | Size |
|---|---|---|---|
| **B25 Layout utility** | `AppPageHeader`, `AppSectionHeader`, `AppToolbar`, `AppBulkActionBar` | B1, B21 | M |
| **B26 AI components** | `AppAiThinkingIndicator`, `AppAiMessageBubble` (+markdown **[NEW DEP]**), `AppAiSuggestion`, `AppAiProposedAction`, `AppAiPanel` | B10, B12, B19? | M |
| **B27 Pattern scaffolds** | Dashboard, ListIndex, RecordDetail, EditorForm, MasterDetail, Workspace, CalendarQueue, Wizard, AiFlow, StateGallery composition helpers | B10–B26 | L |

### Phase 8 — Feature pages (grouped by feature; each depends on B27 + its provider)
Order by dependency/risk: Auth/Setup → Dashboard → Patients → Appointments → Visits → Billing →
Service Catalog → Shifts → Settings. Each batch swaps that feature's `uiPendingPlaceholder` routes
for real pages.

| Batch | Feature (routes) | Composes | Binds | Size |
|---|---|---|---|---|
| **B28** | Auth + Setup (`/login`, `/bootstrap`, setup, staff create/reset) | Empty/Auth, Wizard, Editor/Form | `authNotifier`, `setupNotifier`, `provisioningNotifier`, `clinicSetupProviders` | L |
| **B29** | Dashboard (`/home`) | Dashboard | dashboard/metric providers | M |
| **B30** | Patients (`/patients`, `/new`, `/:id`, `/:id/edit`) | ListIndex, EditorForm, RecordDetail | `patientListNotifier`, `patientDetailProvider`, `patientDetailHistoryProvider` | L |
| **B31** | Appointments (hub/queue/calendar/book/detail/schedule) | Board/Queue, Calendar, EditorForm, RecordDetail | `appointmentQueue/Calendar/Detail` providers | L |
| **B32** | Visits/Encounter (`/visits/:id/document`, `/detail`) | Workspace, RecordDetail | `visitDocumentationNotifier`, `encounterStepProvider`, `workspaceModeProvider`, `visitDetailProvider` | L |
| **B33** | Billing (invoices list/detail/editor, insurance, billing settings) | ListIndex, RecordDetail, EditorForm | `invoiceList/Detail/Editor`, `paymentNotifier`, `insuranceProvidersNotifier`, `billingSettingsNotifier` | L |
| **B34** | Service Catalog (list, editor, branch matrix, promotions) | ListIndex, EditorForm | `serviceCatalogListNotifier`, `serviceEditorNotifier`, `serviceSelectorNotifier` | L |
| **B35** | Shifts (calendar/new/detail) | Calendar, EditorForm | shift providers (verify) | M |
| **B36** | Settings & Admin (hub, org, branches, staff, permissions, idle timeout) | Settings, ListIndex, EditorForm | `staffListNotifier`, `rolePermissionsNotifier`, `clinicSetupProviders` | L |

**Totals:** Phase 0 (foundation, external) + **36 implementation batches (B1–B36)**.

---

## 8. Risks & fidelity notes

- **Command Bar (hero).** Hardest chrome piece: global `⌘K`/`Ctrl+K` (use app-level
  `Shortcuts`/`Actions` or a `HardwareKeyboard` handler — beware conflicts with text fields),
  fuzzy grouped results, keyboard-only operation, focus restore to trigger, Signal focus accent,
  teal→violet AI transition, and restrained backdrop frost (`BackdropFilter`) that must **disable
  under reduced-transparency/low-power**. Web renders via portal; Flutter uses `Overlay`.
- **DataTable.** Sorting/selection (indeterminate header)/sticky header + sticky first column +
  density + footer totals + zebra + loading skeleton + virtualization for thousands of rows. Flutter
  has no drop-in; build on `Table`/`CustomScrollView` slivers with pinned header. The `sm`/`xs`
  fallback to stacked "row-cards" (label:value) is a distinct layout — plan both from the start.
- **Calendar.** Wrap `syncfusion_flutter_calendar`; theming to tokens, injecting a Signal
  now-indicator, conflict styling, and **RTL week mirroring** need care. Syncfusion RTL support and
  custom appointment builders must be validated early.
- **Rich text editor (clinical notes).** `flutter_quill` is pinned to a **git override** (upstream
  RTL/empty-line paint crash, `#2487`). Wrap it behind an App component; confirm the override builds;
  toolbar/format set must match the deleted `clinical_note_editor.dart` intent. RTL + empty-line
  editing is the known fragile path.
- **Resizable panels.** No native equivalent; custom drag + keyboard (arrow ±) + min/max + **RTL
  drag math** (web flips `clientX` when `dir==='rtl'`) + persistence. Nested panels (workspace) add
  complexity.
- **AI streaming / thinking motion.** Stream responses via `motion-fade` (no typewriter jitter);
  Signal pulse is the only steady-state animation and must **stop on response** and go static under
  reduced motion. Never scroll the user away from a pending `AppAiProposedAction`.
- **RTL mirroring.** Whole-shell mirror (sidebar → right, Signal on inline-start = right, drawers
  slide from opposite edge, breadcrumb/chevron/send icons mirror; search/calendar/user do not).
  Use logical insets/alignment everywhere; audit each component in RTL before "done".
- **Tabular figures.** Money/dates/counts/IDs must use tabular figures (Inter/Geist Mono
  `fontFeatures: [FontFeature.tabularFigures()]`) and **Western digits** even in Arabic; wrap Latin
  runs in Arabic text with bidi isolation (`Unicode.LRI`/`Directionality`).
- **PDF / printing.** Receipt/print preview uses `pdf` + `printing` + `pdfx` (viewer) + `open_filex`.
  Desktop (Windows/LAN) printing paths and Arabic glyph shaping in generated PDFs need validation.
- **Reduced-motion & low hardware.** Every animation resolves via `AppMotion`; skeleton shimmer,
  Signal glow/pulse, press-scale, backdrop frost all degrade. Keep lists virtualized.
- **Global keyboard shortcuts** (`⌘K`, `/` page search, `g`-then-key, `Esc` closes topmost overlay)
  must not steal focus from text inputs — scope with `Shortcuts`/`FocusScope` carefully.
- **Density coupling.** `AppDensity` drives topbar/nav/table row heights; changing it must reflow
  without layout jank.

---

## 9. New dependencies to add (not already in pubspec)

Already present (reuse, wrap): `forui`, `syncfusion_flutter_calendar`, `syncfusion_flutter_core`,
`skeletonizer`, `file_picker`, `flutter_quill` (+git override), `open_filex`, `pdf`, `printing`,
`pdfx`, `google_fonts`, `go_router`, `flutter_riverpod`, `intl`, `decimal`, `timezone`.

**Recommended NEW packages:**

| Package | Reason | Used by |
|---|---|---|
| **`fl_chart`** | Charting library for `AppChart` (line/area/bar/stacked/donut). No chart lib currently in pubspec; the web renders custom SVG. `fl_chart` is the lightest, free, well-maintained option. (Alt: `syncfusion_flutter_charts` — heavier, separate pkg, but consistent with the syncfusion calendar already used. Prefer `fl_chart` unless a single-vendor stack is desired.) | B16 `AppChart` |
| **`flutter_markdown`** *(or `markdown_widget`)* | `AppAiMessageBubble` assistant content is markdown-capable. `flutter_markdown` is simplest; `markdown_widget` is a more actively-maintained alternative with better selection/RTL. Pick one. | B26 AI bubbles |

**Optional / evaluate (not required):**

| Package | Reason |
|---|---|
| `desktop_drop` | Nicer file drag-and-drop for `AppFileDropzone` on desktop (in addition to `file_picker` browse). Custom `DropTarget` otherwise. |
| `multi_split_view` | Could back `AppResizablePanels`, but custom is recommended for keyboard + RTL + token control. |

**Fonts note:** `google_fonts` provides Inter and IBM Plex Sans Arabic dynamically. **Geist / Geist
Mono** may not be available via `google_fonts`; if not, bundle them as local font assets in
`pubspec.yaml` (foundation owns this). Flag for the foundation agent — no code change here.

---

## 10. Definition of done (per component / page, from `04 H` + `07`)
- Light + dark via semantic tokens only (no primitives, no hardcoded values).
- Full universal state set where applicable (hover/focus-visible/pressed/disabled/loading/error/selected/readonly).
- Keyboard operable, visible focus ring, sensible tab order.
- Correct in RTL (logical insets/alignment, mirrored directional icons only).
- Contrast meets `07`; motion from `03`/`AppMotion`, degrades under reduced motion.
- Loading / empty / error handled where the surface can be in those states.
- Copy follows `08` (verbs, sentence case, consistent terms); Western digits, tabular where numeric.
- Binds to the correct surviving provider; no business logic in presentation.
