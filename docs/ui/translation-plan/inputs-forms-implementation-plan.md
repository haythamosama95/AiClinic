# Implementation Plan — Dev → Components → Inputs & Forms (Flutter Port)

Spec target: port the **Inputs & forms** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page.

## 0. Ambiguities & Design Decisions (resolve before coding)

1. **forui vs native Material.** `docs/ui/forui-wrappers.md` describes a forui-based abstraction (`AppTextField`, `core/ui/widgets/buttons/…`, `AppSelect`, etc.), but **none of it exists** in `lib/` — `forui` is imported nowhere. The only shipped, "ready" component group (Actions) uses **native Material** widgets (`MenuAnchor`/`MenuItemButton`, `CircularProgressIndicator`) under `lib/core/ui/components/app_*.dart`, exported via `lib/core/ui/widgets/widgets.dart`.
   **Decision: follow the shipping Actions convention (native Material). Do not introduce forui.** Treat `forui-wrappers.md` as superseded.

2. **Core file layout.** Existing App widgets are **flat** (`core/ui/components/app_button.dart` … `app_tooltip.dart`).
   **Decision: keep flat** — create `app_<name>.dart` per widget, plus one shared `app_input_styles.dart`. Showcase sections use a `<group>/` subfolder (mirrors the existing `components/actions/` and the web's `inputs/`) → `components/inputs/<name>_showcase_section.dart`.

3. **Popover technology.** Web uses a Radix+motion `Popover` for Select/Combobox/MultiSelect/DatePicker/TimePicker/DateRangePicker. Existing `AppSplitButton` uses Material `MenuAnchor`. `MenuAnchor` only renders `MenuItemButton`s, which is too restrictive for free-form content (listboxes, calendars).
   **Decision: introduce a thin `AppPopover` wrapper** (`app_popover.dart`) built on Material `Overlay`/`OverlayEntry` (positioned via `LayerLink` + `CompositedTransformFollower`), sized to match trigger width, with fade-scale motion via `app_motion.dart`. This is the one new architectural piece; justified because 5 widgets share it and the existing `MenuAnchor` cannot host arbitrary content.

4. **Calendar grid.** `pubspec.yaml` has `syncfusion_flutter_calendar`, but that is heavyweight for a showcase month grid.
   **Decision: build a small in-house `AppMonthGrid`** (used by DatePicker and DateRangePicker), matching the web's localized month grid. Keep it private to the inputs group (file `app_month_grid.dart`) to avoid premature promotion.

5. **`AppKbd`.** SearchInput's shortcut hint needs a kbd glyph (the web `kbd` component is also its own display-group section later).
   **Decision: create a small `AppKbd` primitive** now (it will be reused by the future Display group). Keep it minimal.

6. **i18n / RTL.** Showcase samples bilingual EN/AR copy via `devPreviewProvider`. Widgets must stay direction-agnostic via `Directionality.of(context)`. Money/Phone force `Directionality.ltr` for the numeric field (matches web). Date pickers consume `devPreviewProvider` locale for `Intl.NumberFormat`/`DateFormat` and AR weekday glyphs. `package:intl` is already a dependency.

7. **Controlled/uncontrolled.** Mirror web's `value`/`defaultValue` + `onValueChange` pattern as Flutter `controller`/`onChanged` (idiomatic), with internal fallback state when no controller is supplied — exactly like the actions `AppButton` (internal `_hovered`/`_pressed`).

8. **Error/invalid** lives on the control (visual border) **and** the wrapping `AppFormField` (text). Match web: control exposes `invalid: bool`; `AppFormField` exposes `error: String?`.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppTooltip` | `core/ui/components/app_tooltip.dart` | FormField hint tooltip |
| `AppAvatar` | `core/ui/components/app_avatar.dart` | Combobox/MultiSelect item avatars |
| `AppPressable` | `core/ui/components/app_pressable.dart` | press/hover state on custom triggers |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion` | `core/ui/theme/*` | every widget |
| `MenuAnchor` pattern (from `AppSplitButton`) | reference only | informs `AppPopover` design |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | locale/direction in showcases |
| Showcase primitives: `ShowcaseSection`, `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection` | `components/showcase_primitives.dart` | every showcase section |
| Section wiring: `component_registry.dart`, `component_section_builders.dart`, `components_content.dart` | `components/` | one-line registration per widget |
| `file_picker` | pubspec | FileDropzone |

## 2. New shared abstractions to introduce first (Phase 1 kickoff)

| File (`lib/core/ui/components/`) | Export name | Analog | Purpose |
|---|---|---|---|
| `app_input_styles.dart` | `AppInputSize` enum (`sm/md/lg`), `appInputBorder(...)`, `appInputDecoration(...)`, metrics | web `input-styles.ts` | shared sizing + invalid/disabled/readOnly border/focus-ring. Sizes: sm=32, md=36, lg=44 height (match existing button metrics in `app_button.dart`). |
| `app_form_field.dart` | `AppFormField` (+ optional `fieldControlProps` helper) | web `FormField` | label + required `*` + `AppTooltip` hint + helper/error text slot wrapping a child control. `error`?→ red `<p role=alert>`-equivalent; else `helper`?. |
| `app_kbd.dart` | `AppKbd` | web `kbd` | small bordered monospace glyph (e.g. `/`). |
| `app_popover.dart` (Phase 2) | `AppPopover` | web `Popover` | `Overlay`-based, trigger-width-aligned, fade-scale. Used by Select/Combobox/MultiSelect/pickers. |
| `app_chip.dart` (Phase 2) | `AppChip` | web `components/chip/Chip` | plain/selectable/removable chip; MultiSelect tokens. |
| `app_month_grid.dart` (Phase 3, group-private) | `AppMonthGrid` | web `MonthGrid` (internal) | month layout with localized weekday headers, today/selected/in-range styling. |

**Barrel update:** append every new `app_*.dart` to `lib/core/ui/widgets/widgets.dart`.

## 3. Phasing

> Rationale: **Phase 1** = text-entry + the `AppFormField`/`app_input_styles` foundation everything else leans on (no overlays). **Phase 2** = choice + popover selections, introducing `AppPopover`/`AppChip`. **Phase 3** = date/time (reuse Phase-2 popover + new month grid), file drop, slider. Each phase is independently shippable.

### Phase 1 — Text entry foundations
Widgets: **FormField, TextInput, Textarea, SearchInput, PasswordInput, NumberInput, MoneyField, PhoneInput**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Form field | `AppFormField` | CREATE `components/app_form_field.dart`; MOD `widgets.dart` | `AppTooltip`, `AppTypography`, `AppSpacing`, `app_colors` | NEW wrapper | none (foundation) |
| Text input | `AppTextInput` (+ expose `AppInputSize`) | CREATE `components/app_text_input.dart`; CREATE `components/app_input_styles.dart`; MOD `widgets.dart` | `app_input_styles`, `AppPressable`,theme | NEW wrapper | `app_input_styles` |
| Textarea | `AppTextarea` | CREATE `components/app_textarea.dart`; MOD `widgets.dart` | `app_input_styles`, `AppFormField` (in showcase) | NEW wrapper | `app_input_styles` |
| Search input | `AppSearchInput` | CREATE `components/app_search_input.dart`; CREATE `components/app_kbd.dart`; MOD `widgets.dart` | `app_input_styles`, `AppKbd`, timer-debounce | NEW wrapper | `app_input_styles`, `AppKbd` |
| Password input | `AppPasswordInput` | CREATE `components/app_password_input.dart` | `app_input_styles`, `AppFormField` (in showcase) | NEW wrapper | `app_input_styles` |
| Number / stepper | `AppNumberInput` | CREATE `components/app_number_input.dart` | `app_input_styles`, `AppPressable` (steppers), `AppButton` styling hints | NEW wrapper | `app_input_styles` |
| Money field | `AppMoneyField` | CREATE `components/app_money_field.dart` | `app_input_styles`, `Intl.NumberFormat` (currency EGP, 2 decimals, grouping-on-blur), `Directionality.ltr` for field | NEW wrapper (extends affix pattern from TextInput) | `app_input_styles`; **TextInput** (shared affix logic — factor an internal `_AppAffixInput` mixin/helpers) |
| Phone input | `AppPhoneInput` | CREATE `components/app_phone_input.dart` | `app_input_styles`, digit-strip + 3-3-4 grouping formatting, `Directionality.ltr`, country-code affix | NEW wrapper | `app_input_styles` |

Showcase sections (Phase 1), under `features/design_system/presentation/components/inputs/`:
`form_field_showcase_section.dart`, `text_input_showcase_section.dart`, `textarea_showcase_section.dart`, `search_input_showcase_section.dart`, `password_input_showcase_section.dart`, `number_input_showcase_section.dart`, `money_field_showcase_section.dart`, `phone_input_showcase_section.dart`.

### Phase 2 — Choice controls + popup selections
Widgets: **Checkbox, RadioGroup, Switch, Select, Combobox, MultiSelect**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Checkbox | `AppCheckbox` (bool + tri-state `indeterminate`) | CREATE `components/app_checkbox.dart` | theme, `AppPressable`, custom 20px box + Check/Minus indicator | NEW | none |
| Radio group | `AppRadioGroup` + `AppRadioOption` | CREATE `components/app_radio_group.dart` | theme, custom 20px circle dot | NEW (group) | none |
| Switch | `AppSwitch` | CREATE `components/app_switch.dart` | theme, animated thumb (h-24 w-44, RTL translate mirror) | NEW | none |
| Select | `AppSelect` + `AppSelectOption` (`{value,label,disabled,disabledReason}`) | CREATE `components/app_select.dart`; CREATE `components/app_popover.dart`; MOD `widgets.dart` | `AppPopover`, chevron trigger (rotate on open), Check icon on selected, type-ahead, Arrow/Enter/Esc nav | NEW | **AppPopover** (create here) |
| Combobox / autocomplete | `AppCombobox` + `AppComboboxItem` (`{id,label,meta?,avatar?,initials?,disabled?,disabledReason?}`) | CREATE `components/app_combobox.dart` | `AppPopover`, `AppAvatar`, `Spinner`-equivalent (`CircularProgressIndicator`), match `<mark>` highlight, debounce async `onSearch`, "Create" row optional | NEW | **AppPopover**, `AppAvatar`, **AppComboboxItem model** (shared with MultiSelect) |
| Multi-select / token | `AppMultiSelect` (reuses `AppComboboxItem`) | CREATE `components/app_multi_select.dart`; CREATE `components/app_chip.dart`; MOD `widgets.dart` | `AppPopover`, `AppChip` (removable), trigger = chip-wrap + inline combobox field, "All branches" option, "No more options" empty | NEW | **AppPopover**, **AppChip**, **AppComboboxItem** (from Combobox) |

Showcase sections (Phase 2): `choice_controls_showcase_section.dart` (Checkbox+RadioGroup+Switch, three exported `*Showcase` classes per web), `select_showcase_section.dart`, `combobox_showcase_section.dart`, `multi_select_showcase_section.dart`.

### Phase 3 — Date/time, file, slider
Widgets: **DatePicker, TimePicker, DateRangePicker, FileDropzone, Slider**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Date picker | `AppDatePicker` | CREATE `components/app_date_picker.dart`; CREATE `components/app_month_grid.dart` (group-private); MOD `widgets.dart` (export picker; keep grid internal or export) | `AppPopover`, `AppMonthGrid`, `Intl.DateFormat`, typed-input parse (d/m/y, d.m.y, d-m-y), min/max disables cells, prev/next icons mirror in RTL, AR weekday glyphs `ح ن ث ر خ ج س` | NEW | **AppPopover** (P2), **AppMonthGrid** (create here) |
| Time picker | `AppTimePicker` | CREATE `components/app_time_picker.dart` | `AppPopover`, generated slots at `stepMinutes=15`, 12h for `ar` else 24h, scrollable listbox, Clock trigger icon | NEW | **AppPopover** (P2) |
| Date range picker | `AppDateRangePicker` + `AppDateRange {start,end}` | CREATE `components/app_date_range_picker.dart` | `AppPopover`, **same `AppMonthGrid`** (dual side-by-side), preset buttons (Today/This week/This month), start-then-end selection w/ auto-order, in-range fill, aria-live caption ("Inclusive range…"/"Select end date") | NEW | **AppPopover**, **AppMonthGrid** (from DatePicker) |
| File dropzone | `AppFileDropzone` + `AppFileItem {id,name,size,status,progress?,error?}` | CREATE `components/app_file_dropzone.dart` | `file_picker`, drag-over highlight, progress bar (`LinearProgressIndicator`), per-file remove, status icons (`CircularProgressIndicator`/Check/Alert), `onUpload` async simulate, `maxSizeMb` reject | NEW | `file_picker` (pubspec) |
| Slider | `AppSlider` | CREATE `components/app_slider.dart` | Material `Slider` restyled (h-1.5 track, 20px thumb, invalid danger border), `<output>` value label (`showValue`, `formatValue`), single-thumb (array value uses `[0]`) | NEW (thin restyle over Material Slider — matches "native Material" decision) | none |

Showcase sections (Phase 3): `date_time_showcase_section.dart` (DatePicker+TimePicker+DateRangePicker, three exported `*Showcase` per web), `file_dropzone_showcase_section.dart`, `slider_showcase_section.dart`.

## 4. Instantiation in the Dev page (mirrors web reference)

> **Binding source of truth:** the per-demo arrangement, props, labels, copy, and variant matrices in each Flutter showcase section **must mirror exactly** how the corresponding showcase in `web-reference/src/showcase/components/inputs/<Name>Showcase.tsx` instantiates the web widget. Composer 2.5 should open the referenced `.tsx` for each widget and reproduce, demo-for-demo:
> - the number, order, and titles of `ShowcaseDemo` cells;
> - the exact props passed to the control (sizes, variants, `defaultValue`s, placeholders, icons, affixes, disabled/readOnly/invalid flags, etc.);
> - any `ShowcaseVariantMatrix` rows below the `ShowcaseDemoGrid`;
> - the bilingual EN/AR copy where the web demo uses labels/placeholders/helpers (AR translations follow the existing showcase convention, e.g. `button_showcase_section.dart`'s `_copyEn` / `_copyAr` pattern).
>
> The Flutter `ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix` primitives are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the control widget name and prop syntax change (e.g. `defaultValue="x"` → `initialValue: 'x'`/controller, `invalid` stays `invalid`, `showClear` stays `showClear`).

For every widget, the showcase section wraps demos in the existing primitives so the Dev page renders them identically to `web-reference`:

```
ShowcaseSection(id, title, description, componentName, child:
  ShowcaseDemoGrid(columns: 2, children: [
    ShowcaseDemo(label, propsHint, child: <App widget with sample props>),
    ...
  ])
)
```

Concretely per widget (variant matrices to reproduce; copy EN/AR strings matching `web-reference`):

- **Form field** — 2 demos: default helper, error+required+hint (TextInput inside).
- **Text input** — Sizes (sm/md/lg), Variants (leadingIcon Mail, prefix "EGP", suffix "%" + trailingIcon Percent), States (default, showClear, disabled, readOnly, invalid).
- **Textarea** — notes w/ FormField; autoGrow + showCounter + maxLength=200.
- **Search input** — async simulate (loading→resultCount); states default/disabled/invalid; "/" kbd hint.
- **Password input** — FormField "At least 8 characters"; invalid demo with default "short"; reveal toggle + caps-lock hint.
- **Number / stepper** — FormField "Quantity" defaultValue=1, min=1, max=99.
- **Money field** — FormField "Default price" required default 350; invalid default -10; EGP affix.
- **Phone input** — FormField "Mobile number"; +20 fixed; formats as typed.
- **Select** — FormField "Branch"; options incl. one disabled w/ `disabledReason`.
- **Combobox** — async search demo (mock 600ms over catalog w/ meta+initials+1 disabled), static list w/ ineligible item, empty-results state.
- **Multi-select** — FormField "Selected branches"; controlled value over 3 branches; chips removable; "All branches" affordance.
- **Checkbox** — defaultChecked, indeterminate, disabled.
- **Radio group** — vertical (cash/card/insurance) + horizontal (day/week/month).
- **Switch** — on (defaultChecked) + disabled.
- **Date picker** — FormField; calendar popover; min/max; RTL mirror.
- **Time picker** — FormField; 15-min slots; 12h (AR) / 24h (EN).
- **Date range picker** — FormField; presets; dual-month; inclusive-range caption.
- **File dropzone** — FormField "Patient attachments" helper "PDF, JPG, or PNG…"; controlled files; per-file progress; remove.
- **Slider** — FormField "Insurance coverage"; defaultValue 75; `%` value label.

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished `id`, change `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (keep order; ids already present, see lines 114–132).
2. `component_section_builders.dart` — add an entry per ready id in `componentSectionBuilders`:
   `'form-field': () => const FormFieldShowcaseSection(),` etc. (reuse the exact `'id'` strings from `component_registry.dart`.)
3. Import the new section files at the top of `component_section_builders.dart` (group imports under an `// Inputs & forms` comment, mirroring the existing Actions block).
4. Append new `app_*.dart` core files to the `widgets.dart` barrel export list (under a `// Inputs` sub-comment).
5. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- The `forui`-based wrappers described in `docs/ui/forui-wrappers.md` are not built or reconciled here.
- Display-group kbd/chip/tooltip/calendar sections beyond what inputs need — `AppKbd`/`AppChip` are created now but their own showcase sections belong to the Display milestone.
- Syncfusion calendar integration — not used for the showcase month grids.
- No new architectural patterns beyond the justified `AppPopover` overlay helper.

## 7. Source reference — web widget inventory

The 18 widgets in `web-reference/src/showcase/components/inputs/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `form-field` | Form field | `FormFieldShowcase.tsx` | `FormField` |
| `text-input` | Text input | `TextInputShowcase.tsx` | `TextInput` |
| `textarea` | Textarea | `TextareaShowcase.tsx` | `Textarea` |
| `search-input` | Search input | `SearchInputShowcase.tsx` | `SearchInput` |
| `password-input` | Password input | `PasswordInputShowcase.tsx` | `PasswordInput` |
| `number-input` | Number / stepper | `NumberInputShowcase.tsx` | `NumberInput` |
| `money-field` | Money field | `MoneyFieldShowcase.tsx` | `MoneyField` |
| `phone-input` | Phone input | `PhoneInputShowcase.tsx` | `PhoneInput` |
| `select` | Select | `SelectShowcase.tsx` | `Select` |
| `combobox` | Combobox / autocomplete | `ComboboxShowcase.tsx` | `Combobox` |
| `multi-select` | Multi-select / token | `MultiSelectShowcase.tsx` | `MultiSelect` |
| `checkbox` | Checkbox | `ChoiceControlsShowcase.tsx` | `Checkbox` |
| `radio-group` | Radio group | `ChoiceControlsShowcase.tsx` | `RadioGroup` |
| `switch` | Switch | `ChoiceControlsShowcase.tsx` | `Switch` |
| `date-picker` | Date picker | `DateTimeShowcase.tsx` | `DatePicker` |
| `time-picker` | Time picker | `DateTimeShowcase.tsx` | `TimePicker` |
| `date-range-picker` | Date range picker | `DateTimeShowcase.tsx` | `DateRangePicker` |
| `file-dropzone` | File dropzone | `FileDropzoneShowcase.tsx` | `FileDropzone` |
| `slider` | Slider | `SliderShowcase.tsx` | `Slider` |

Shared web building blocks (port equivalents listed in §2):
- `input-base/input-styles.ts` — `InputSize = 'sm'|'md'|'lg'`, `inputFieldClasses`, `inputWrapperClasses`, `inputAffixClasses`, `bareInputClasses`.
- `form-field/FormField.tsx` — label/required-mark/hint-tooltip/helper/error scaffold + `fieldControlProps`.
- `popover/Popover.tsx` — Radix+motion fade-scale popover (trigger-width aligned).
- `spinner/Spinner.tsx` — lucide Loader2 spinner.
- `chip/Chip.tsx` — plain/selectable/removable chip (used by MultiSelect tokens).
- `kbd/KbdKey` — keyboard glyph (used by SearchInput shortcut hint).

Cross-cutting web notes (inform the Flutter port):
- Single `InputSize` system shared by every input.
- Every input supports `invalid` (danger border + danger focus ring), `disabled`, and most support `readOnly` (sunken bg). Error text lives in `FormField`, not the control.
- `FormField` is the canonical label/helper/error wrapper; controls accept `id` + `aria-*` to wire up.
- Select/Combobox/MultiSelect/DatePicker/TimePicker/DateRangePicker all share the Radix popover (width matches trigger).
- i18n/RTL: MoneyField and PhoneInput force `dir="ltr"` for the numeric field; DatePicker/DateRangePicker/TimePicker use `useDirection()` (`ar`→`ar-EG`, AR weekday glyphs, 12h vs 24h, icon mirroring).
- Controlled/uncontrolled supported via `value`/`defaultValue` + `onValueChange` (or `onCheckedChange` for choice controls).
- Dependencies outside `ui/`: `Chip`, `KbdKey`, `Tooltip`, `useDirection`, `cn`, `motionPresets`, Radix primitives (Checkbox/RadioGroup/Switch/Slider/Popover), lucide-react icons.