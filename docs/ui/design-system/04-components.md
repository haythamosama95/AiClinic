# 04 — Component Inventory

The reusable building blocks of AiClinic. Every reusable element is owned by the application (an
`App*` abstraction in Flutter, a shared component in the web reference) — never re-implemented per
feature. Each entry lists **purpose · variants · sizes · states · behavior/a11y**. All colors,
sizes, radii, and motion come from `02`/`03`.

**Universal state set** (every interactive component supports these): `default`, `hover`,
`focus-visible`, `active/pressed`, `disabled`, `loading` (where applicable), `error/invalid`
(where applicable), `selected` (where applicable), and `readonly` (where applicable). Every
component has light and dark renderings and works in LTR and RTL.

---

## A. Actions

### A1. Button
- **Purpose:** trigger an action.
- **Variants:** `primary` (teal, filled) · `secondary` (surface + `border-default`) · `ghost`
  (transparent, hover fill) · `danger` (red filled, for destructive) · `ai` (violet filled, AI
  actions only) · `link` (text-only, `text-link`).
- **Sizes:** `sm` (28px h) · `md` (36px h, default) · `lg` (44px h). Icon-inline supported at all
  sizes; leading/trailing icon slots.
- **States:** universal set + `loading` (spinner replaces leading icon, label stays, width locked,
  control disabled).
- **Behavior/a11y:** min touch/click target 28px (sm) but hit area ≥32px; label is a verb (`08`);
  `aria-busy` when loading; keyboard `Enter`/`Space`; press scales to 0.98 (`03`). Only one
  `primary` per view region.

### A2. Icon Button
- **Purpose:** compact action where a labeled button is too heavy (toolbars, table row actions).
- **Variants:** `ghost` (default) · `secondary` · `danger` · `ai`.
- **Sizes:** `sm` 28² · `md` 32² · `lg` 40².
- **a11y:** **must** have `aria-label` and a tooltip; never the sole affordance for a rare critical
  action without a labeled path elsewhere.

### A3. Split Button / Button with menu
- **Purpose:** a primary action plus related secondary actions.
- **Anatomy:** primary segment + chevron segment opening a `Menu`.
- **Behavior:** chevron opens `motion-fade-scale` menu; primary segment runs default action.

### A4. Button Group / Segmented Control
- **Purpose:** mutually exclusive choice among 2–5 short options (e.g. list/board view, day/week).
- **Anatomy:** grouped buttons sharing borders; selected uses `surface-selected` + `text-primary`,
  others ghost.
- **a11y:** `role="radiogroup"`, arrow-key navigation.

---

## B. Inputs & Forms

### B0. Form Field (wrapper)
- **Purpose:** the standard label/control/help/error scaffold every field uses.
- **Anatomy:** label (`text-body-strong`) · optional required mark · optional hint icon+tooltip ·
  control · helper text (`text-caption`, `text-tertiary`) · error text (`text-caption`,
  status-danger `-fg`, with 16px alert icon).
- **Behavior:** error replaces helper; `aria-describedby` links help/error; `aria-invalid` on
  error; label `for`/`id` association; required communicated in text, not color alone.

### B1. Text Input
- **Variants:** default · with leading/trailing icon · with prefix/suffix affix (e.g. `EGP`, `%`)
  · with inline action (clear ✕).
- **Sizes:** `sm` 32 · `md` 36 (default) · `lg` 44.
- **States:** universal + `invalid`, `readonly`, `with-value`, `placeholder`.
- **Behavior:** `radius-md`, `border-default` → `border-focus` + ring on focus; placeholder is an
  example, not the label.

### B2. Textarea — auto-grow option; min rows; character counter variant.

### B3. Search Input
- **Purpose:** filter/search within a page or list.
- **Anatomy:** leading search icon, clear ✕ when filled, optional inline result count, `⌘F`/`/`
  hint.
- **Behavior:** debounced (≈300ms to match backend), loading spinner in trailing slot while
  querying; `Esc` clears.

### B4. Password Input — masked with reveal toggle; caps-lock hint; no strength meter (out of
scope), but supports `invalid`.

### B5. Number / Stepper — tabular figures; optional +/− steppers; min/max/step; used for quantity
(defaults to 1 for invoice items).

### B6. Money Input (`AppMoneyField`)
- **Purpose:** enter currency amounts (prices, overrides, promotions, payments).
- **Anatomy:** currency affix (`EGP` leading in LTR / trailing appropriately in RTL), tabular
  figures, 2-decimal scale, thousands grouping on blur.
- **Behavior:** rejects negative where invalid; aligns value to the field's inline-end; parses
  paste; never used for display-only amounts (see D-Money display).

### B7. Phone Input — country context (Egypt default `+20`), formats as typed, validates shape not
carrier; Latin digits.

### B8. Select (native-style dropdown) — single choice from a short known list; chevron; menu via
`motion-fade-scale`; keyboard type-ahead.

### B9. Combobox / Autocomplete (`AppAutocompleteField`)
- **Purpose:** the core "pick from a catalog" control — patients, services, diagnoses, doctors,
  staff. This is a **signature interaction pattern** reused across features.
- **Anatomy:** text input + async results popover (avatar/label/meta rows), keyboard navigation,
  empty/no-match state, loading state, optional "create new" affordance where permitted.
- **Behavior:** debounced async search; highlights match; `Enter` selects highlighted; selection
  shows as filled value or chip; supports disabled/ineligible items with a reason (e.g. inactive
  service). Backend-first results.

### B10. Multi-select / Token input
- **Purpose:** choose several (e.g. branch assignment "selected branches", tags).
- **Anatomy:** selected values as removable chips inside the field + combobox popover; "All
  branches" convenience option.

### B11. Checkbox — single + indeterminate; used in table row selection headers.

### B12. Radio Group — vertical/horizontal; one selection; arrow-key nav.

### B13. Switch / Toggle — immediate boolean state (e.g. branch service Active/Inactive); label
always present; knob slides `duration-fast`; announces state.

### B14. Date Picker — calendar popover; keyboard entry + calendar; min/max; house date format;
supports promotion start/end. RTL calendar mirrors.

### B15. Time Picker — appointment/shift times; 12/24h per locale; step granularity.

### B16. Date Range Picker — dual-month popover for promotions/report ranges; inclusive-range
messaging; presets (Today, This week, This month).

### B17. File Upload / Dropzone
- **Purpose:** patient attachments (PDF/scans/lab reports).
- **Anatomy:** drop area + browse button, accepted-types hint, per-file rows with progress,
  success/error per file, remove.
- **States:** idle · drag-over (`surface-selected` + `border-focus`) · uploading · success · error.

### B18. Slider — rare (e.g. coverage %); tabular value label; keyboard arrows.

---

## C. Navigation

### C1. Sidebar / Nav Rail (`AppSidebar`)
- **Purpose:** primary app navigation.
- **Variants:** `expanded` (label + icon, ~248px) · `collapsed` (icon rail, ~56px, labels via
  tooltip). Sections grouped with `text-overline` headers.
- **Anatomy:** org/branch header at top, nav items (icon + label + optional count badge), the
  **Signal** active indicator on the inline-start edge, footer (settings, user).
- **Behavior:** active item uses `surface-selected` + `text-primary` + Signal; `motion-nav` moves
  the indicator; collapse persists; keyboard navigable; RTL puts it on the right.

### C2. Top Bar / App Bar (`AppTopBar`)
- **Anatomy:** three-zone layout — page context (breadcrumb/title, inline-start), centered
  **Command Bar** trigger (`⌘K`), inline-end cluster (branch switcher, notifications with compact
  count dot, theme toggle icon button, user menu).
- **Behavior:** sticky (`z-sticky`); `shell-topbar-height`; flat `surface-default` + `border-subtle`
  (no elevation or frost on chrome); command trigger is a fixed-width sunken field centered in the
  bar; condenses at narrow widths (branch switcher hides below `md`).

### C3. Breadcrumb — hierarchical location; last item is current (not a link); truncates middle on
overflow; separator mirrors in RTL.

### C4. Tabs
- **Variants:** `underline` (Signal underline, default) · `segmented` (in-panel) · `vertical`.
- **Behavior:** `motion-tab` slides the underline; arrow-key nav; `aria-selected`; lazy content
  allowed but preserve state.

### C5. Menu / Context Menu (`AppMenu`)
- **Purpose:** action lists (row actions "⋯", right-click, split-button menus).
- **Anatomy:** items (icon + label + optional shortcut hint + optional trailing check), separators,
  section labels, destructive items (`danger` `-fg`), disabled items with reason tooltip.
- **Behavior:** `motion-fade-scale`; full keyboard; `Esc` closes; focus returns to trigger.

### C6. Pagination — page controls + range summary ("1–50 of 2,000") with tabular figures;
page-size select; supports large catalogs; keyboard operable.

### C7. Stepper / Wizard — multi-step flows (e.g. first-run org/branch setup, new-branch service
setup); numbered steps (numbers here are legitimate — order carries meaning), current/complete/
upcoming states, back/next, per-step validation.

### C8. Command Bar (`AppCommandBar`) — **the hero**
- **Purpose:** unified search + navigation + quick actions + AI entry, opened via `⌘K`/`Ctrl+K`.
- **Anatomy:** centered overlay panel (`elevation-3`, `radius-xl`), single input with the Signal
  focus accent, grouped results (Navigate / Patients / Actions / "Ask AI…"), keyboard-only
  operable, per-item shortcut hints, recent/suggested when empty.
- **Behavior:** `motion-command`; fuzzy search; arrow keys + `Enter`; typing a natural-language
  query and choosing "Ask AI…" transitions to AI mode (accent → violet). `Esc` closes; focus
  restores. Backdrop uses restrained frost (disabled on reduced-transparency).

### C9. Branch Switcher — current branch with dropdown of accessible branches; search when many;
shows org context; changing branch re-scopes data (with clear feedback).

### C10. User Menu — avatar → menu (profile, theme toggle, language EN/AR, sign out, app version).
  Theme is also available as a top-bar icon button (`C2`) for quick access.

---

## D. Data Display

### D1. Table / Data Grid (`AppTable`)
- **Purpose:** the workhorse for patients, invoices, appointments, services, staff, shifts.
- **Anatomy:** sticky header, sortable columns (sort caret), optional row selection (checkbox),
  cell alignment (text = start, numbers/money = inline-end, status = start), row hover, row
  actions ("⋯" / inline icon buttons), sticky first column option, footer summary row (totals).
- **Density:** `compact` (36px rows) · `default` (40px) · `comfortable` (48px). Zebra optional via
  `surface-muted`.
- **States:** loading (skeleton rows) · empty (empty state) · error · filtered-empty ("no matches")
  · selection-active (bulk action bar appears).
- **Behavior:** keyboard row/cell navigation, `Enter` opens row; sort/filter update instantly (no
  stagger); pagination or virtualized scroll for large sets; column config where useful. Never
  animate numeric cells on load.

### D2. Card (`AppCard`)
- **Purpose:** grouped surface.
- **Variants:** `flat` (border, `elevation-0`) · `raised` (`elevation-1`) · `interactive`
  (hover/focus, whole-card clickable) · `ai` (`surface-ai` + `border-ai`, AI content only).
- **Anatomy:** optional header (title + actions), body, optional footer; padding `space-4`–
  `space-6`.

### D3. Metric / Stat Card
- **Purpose:** KPI display (revenue, appointments today, outstanding).
- **Anatomy:** label (`text-overline`/`text-caption`), value (`text-display`/`text-h1`, tabular),
  optional delta (▲/▼ with success/danger `-fg`), optional sparkline, optional context caption.
- **Rule:** the big-number-with-delta pattern is used where it is genuinely the best answer, not by
  default (see `01` P1).

### D4. Entity Cards (composed from `AppCard` + primitives)
- **Patient Card:** avatar/initials, name, key IDs/phone, tags (insurance, flags), quick actions.
- **Appointment Card:** time, patient, doctor, status pill, branch; used in queue/calendar.
- **Invoice Card / Row:** number (mono), patient, amount (money), status pill, date.
- **Service Card / Row:** name, default price, global status, branch availability summary.
  These are documented as compositions, not new primitives.

### D5. List (`AppList`) — vertical items (icon/avatar + primary + secondary + trailing); dividers
or spacing; selectable; used where a table is too heavy.

### D6. Description List / Key-Value — read-only detail display (patient summary, invoice meta);
label (`text-tertiary`) + value (`text-primary`, tabular for data); two-column on wide, stacked on
narrow.

### D7. Badge / Status Pill (`AppBadge`)
- **Purpose:** status and counts.
- **Variants:** `solid` · `soft` (tinted `-surface` + `-fg`, default) · `outline` · `dot` (leading
  status dot + label). Colors from the status set + neutral + teal + violet(AI).
- **Sizes:** `sm` · `md`. Always paired with text/meaning; a lone status dot has an accessible
  label.

### D8. Chip / Tag — compact descriptors; `removable` (✕) variant for filters/multi-select;
`selectable` variant (filter chips); neutral by default.

### D9. Avatar — image or initials fallback; sizes `xs` 20 → `xl` 48; `AvatarGroup` (overlap +
"+N"); optional status dot; deterministic initials color from a neutral-safe subset.

### D10. Tooltip — brief supplementary text on hover/focus; `duration-fast` in after ~400ms; never
holds essential-only info; `role="tooltip"`; RTL-aware placement.

### D11. Timeline — chronological events (patient history, visit/audit trail); node + connector +
timestamp (tabular) + content; supports grouping by day.

### D12. Calendar (`AppCalendar`)
- **Purpose:** appointments and shifts.
- **Views:** day · week · month (+ optional agenda/list). Time-grid with events, all-day row,
  now-indicator (a Signal line), conflict styling (overlap not allowed → visual warning).
- **Behavior:** click/drag to create where permitted, keyboard navigation, event popover, RTL
  mirrors the week; doctor/branch filters.

### D13. Chart primitives (`AppChart`)
- **Purpose:** analytics (revenue, busiest hours, doctor performance).
- **Types:** line, area, bar, stacked bar, donut/pie (sparingly), sparkline.
- **Rules:** categorical palette derived from teal + neutrals + status hues (documented, not
  ad-hoc); tabular axis labels; accessible (data table fallback, aria); calm, few gridlines;
  tooltips on hover/focus. Wrap the charting library behind `AppChart`.

### D14. Money Display (`AppMoney`) — read-only currency rendering; tabular figures, 2 decimals,
house grouping, currency symbol/position per locale; emphasis weight for totals; negative/refund
styling via status color, not just a minus.

### D15. Progress — `bar` (determinate) · `circular` (small/indeterminate) · `steps` (segmented).
Tabular percent label.

### D16. Skeleton — shape-matched placeholders for known layouts; calm shimmer (`03`); static under
reduced motion.

### D17. Divider — hairline (`border-subtle`); horizontal/vertical; optional centered label.

### D18. Kbd / Shortcut Hint — mono, small, `surface-sunken` chip for keys (`⌘`, `K`, `Enter`);
used in menus, tooltips, Command Bar, empty states to teach shortcuts.

### D19. Code / Mono block — for IDs and raw/technical/AI output; `surface-sunken`; copy button.

---

## E. Feedback & Overlays

### E1. Toast / Snackbar (`AppToast`)
- **Purpose:** transient confirmation or failure after an action.
- **Variants:** `success` · `danger` · `info` · `neutral`; optional action (Undo, View).
- **Behavior:** `motion-slide-up`, stack (max ~3), auto-dismiss (success ~4s; errors persist or
  longer), pause on hover, dismissible; `role="status"`/`alert`; corner respects RTL. Copy follows
  action verbs (Publish → "Published", `08`).

### E2. Inline Alert / Banner (`AppAlert`)
- **Purpose:** persistent contextual message within a page/form/section.
- **Variants:** `info` · `success` · `warning` · `danger` · `ai`.
- **Anatomy:** status icon + title + body + optional actions + optional dismiss. Used for
  subscription-degraded notice, offline notice, permission notes, validation summaries.

### E3. Dialog / Modal (`AppDialog`)
- **Purpose:** focused task or decision requiring attention (create/edit forms, details).
- **Sizes:** `sm` · `md` · `lg` · `full` (rare). `radius-xl`, `elevation-3`.
- **Anatomy:** header (title + close) · scrollable body · footer (actions, primary at
  inline-end). Sticky header/footer for long bodies.
- **Behavior:** `motion-modal`; focus trap; `Esc` closes (unless dirty→confirm); backdrop
  (frost, reduced-transparency-safe); returns focus to trigger; scroll lock.

### E4. Confirmation Dialog (destructive/financial)
- **Purpose:** guard irreversible or money-affecting actions (archive patient, delete service,
  replace branch config, void).
- **Anatomy:** clear title stating the effect, consequence body, `danger` primary + `cancel`;
  optional typed-confirmation for high-stakes; consequence-first copy (`08`, P8).

### E5. Drawer / Sheet (`AppDrawer`)
- **Purpose:** side panel for detail/edit without leaving context (patient detail, invoice editor,
  filters).
- **Variants:** inline-end (default), inline-start, bottom (narrow screens). Sizes sm/md/lg.
- **Behavior:** `motion-drawer` (RTL-aware), optional non-modal (dismiss on outside interaction) or
  modal with scrim; focus management like dialog.

### E6. Popover — anchored transient surface for lightweight forms/info (quick edit, filters, event
details); `motion-fade-scale`; arrow optional; dismiss on outside click/`Esc`.

### E7. Loading Overlay — scoped (over a card/panel) or global (route change); dimmed surface +
spinner/skeleton; never blocks the whole app for LAN-fast work (prefer optimistic UI, `03`).

### E8. Empty State (`AppEmptyState`)
- **Purpose:** zero-data, no-results, no-access, first-run.
- **Anatomy:** restrained on-brand illustration or icon, title, one-line explanation, primary
  action (or shortcut hint), optional secondary. Variants: `first-run` (invitation to act),
  `no-results` (adjust filters), `no-access` (permission), `error` (retry).

### E9. Error State — for failed loads/sections: icon, plain-language cause, retry action; never a
raw stack trace to the user; distinct from empty.

---

## F. AI Components (violet, human-gated)

All AI components are visually distinct (violet accent, `surface-ai`, labeled) and every actionable
output routes through explicit human approval (P7, constitution).

### F1. AI Mode Toggle — switches Standard ↔ AI context; accent cross-fades teal↔violet
(`03`); clearly labeled; persists per session.

### F2. AI Command / Chat Surface (`AppAiPanel`)
- **Purpose:** natural-language interaction (as a panel/drawer or Command Bar continuation).
- **Anatomy:** message history, input with send + `Enter`, the Signal "thinking" indicator,
  suggested prompts when empty, scope indicator (which branch/context the AI sees).
- **Behavior:** streaming responses via `motion-fade` (no typewriter jitter); stop/regenerate;
  never scrolls the user away from a pending approval.

### F3. AI Message Bubble — `user` (neutral, inline-end) · `assistant` (`surface-ai`, inline-start);
markdown-capable; timestamps optional; copy action; RTL-aware sides.

### F4. Proposed Action Card (`AppAiProposedAction`) — **critical**
- **Purpose:** render a structured action the AI proposes (book appointment, create invoice,
  assign shift) for human approval.
- **Anatomy:** violet-accented card labeled "Proposed by AI", a human-readable summary of exactly
  what will happen, the structured fields (editable where safe), and **explicit
  Approve / Edit / Dismiss** controls. Approve runs the normal, validated backend path — the AI
  never executes.
- **States:** proposed · editing · submitting · approved (becomes a normal record + toast) ·
  rejected · failed (validation error surfaced clearly).

### F5. AI Suggestion (inline) — subtle violet-marked suggestion attached to a field/section (e.g.
"AI can draft this SOAP note"); opt-in; dismissible; leads into an approval step.

### F6. AI Thinking Indicator — the Signal pulse (`03`); only animation in steady state; stops on
response; static label under reduced motion.

---

## G. Layout & Utility

### G1. Page Header — page title (`text-h1`), optional description, breadcrumb, primary action(s),
optional tabs; consistent top-of-page rhythm.

### G2. Section Header — `text-overline`/`text-h3` + optional description + section actions;
structures long pages.

### G3. Toolbar / Filter Bar — search + filter chips + view controls + bulk actions; sticky; wraps
gracefully; the standard control strip above tables/lists.

### G4. Bulk Action Bar — appears when table rows are selected; count + relevant actions + clear;
uses `surface-raised` + `elevation-2`.

### G5. Scroll Area — styled overflow container with thin, calm scrollbars; keyboard scrollable;
shadow/edge fade hints for more content.

### G6. Resizable / Split Panels — for master-detail (list + detail) and the encounter workspace;
draggable divider with keyboard support; min/max sizes; persists.

### G7. App Shell — the composition of Sidebar + Top Bar + content region + overlay layers; defined
as a pattern in `05`.

---

## H. Component checklist (every component must satisfy)

- [ ] Light and dark renderings via semantic tokens only (no primitives, no hardcoded values).
- [ ] Full universal state set where applicable.
- [ ] Keyboard operable with visible `focus-visible` ring; sensible tab order.
- [ ] Correct in RTL (logical properties, mirrored icons where directional).
- [ ] Contrast meets `07` targets in both themes.
- [ ] Motion from `03`; degrades under reduced motion.
- [ ] Loading / empty / error handled where the component can be in those states.
- [ ] Copy follows `08` (verbs, sentence case, consistent terms).
- [ ] Demonstrated in the Showcase (`09`) with every variant and state.
