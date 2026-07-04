# 09 — Design System Showcase (Deliverable Spec)

The Showcase is the **first thing built** with the Web Feature Design skill and the artifact that
gets reviewed and approved before any real feature UI. It is the living, browsable proof that the
design system in `01`–`08` is real, cohesive, and complete — the AiClinic equivalent of Storybook /
shadcn docs / the Material gallery.

This document specifies *what to build*. It is a "Foundation Feature", not a user-facing feature.

---

## 1. Goal

Produce a single, production-quality web application (the reference stack: React + TypeScript +
Vite + Tailwind + Radix + Lucide + Motion) that:

- Demonstrates **every** token, component, variant, state, and motion pattern from this suite.
- Proves the whole system in **both themes** (light/dark) and **both directions** (LTR/RTL).
- Serves as the canonical visual reference the Flutter build reproduces with no guesswork.
- Establishes the shared component library every future feature composes from.

Treat this as the **highest-budget design work in the project**: every later feature inherits this
foundation, so quality here compounds and weaknesses here propagate.

---

## 2. Global chrome of the Showcase

- **App shell** matching `05`: sidebar navigation of sections, top bar with a live **theme toggle
  (light/dark)**, **direction toggle (LTR/RTL)**, **language toggle (EN/AR)**, and a **density
  toggle** — all switching the entire Showcase live.
- A working **Command Bar (`⌘K`)** to jump between Showcase sections (dogfoods the hero).
- Every example shows its **token/component name** and, where useful, the props/variants that
  produced it. Copy-to-reference affordances are welcome.
- A persistent **"reduced motion"** switch (in addition to honoring the OS setting) to demo the
  reduced-motion path.

---

## 3. Required sections

Build one page/section per area. Each must show variants **and states** (default, hover, focus,
active, disabled, loading, error, selected, empty — as applicable), in both themes and directions.

### 3.1 Foundations
- **Colors:** primitive palettes and the full semantic mapping, rendered in light and dark with
  contrast values shown; the teal-vs-violet (deterministic vs AI) distinction called out.
- **Typography:** the full type scale in `font-sans`/`font-display`/`font-mono`, plus an Arabic
  specimen in `IBM Plex Sans Arabic` (with correct line-height); tabular-figure demo.
- **Spacing & layout:** the spacing scale, radius scale, breakpoints.
- **Elevation:** all elevation levels; the restrained frost example.
- **Iconography:** the Lucide set at each size; directional-mirroring demo.
- **The Signal:** the signature element in all three placements (nav, Command Bar focus, AI pulse),
  teal and violet.

### 3.2 Motion
- Interactive triggers for **every motion preset** (`03`): fade, fade-scale, slide, modal, drawer,
  command, collapse, tab, nav, row-enter, AI thinking/streaming.
- A duration/easing reference with replay buttons.
- Live reduced-motion comparison.

### 3.3 Components
One subsection per group in `04`, each with the full variant/state matrix:
- **Actions:** buttons (all variants/sizes/states incl. loading), icon buttons, split button,
  button group/segmented.
- **Inputs & Forms:** form field scaffold, text/textarea/search/password/number, **money field**,
  phone, select, **combobox/autocomplete** (async, empty, ineligible-with-reason), multi-select/
  token, checkbox/radio/switch, date/time/range pickers, file dropzone, slider — including
  validation/error states.
- **Navigation:** sidebar (expanded/collapsed/RTL), top bar, breadcrumb, tabs, menu/context menu,
  pagination, stepper, **Command Bar**, branch switcher, user menu.
- **Data display:** table/data grid (all densities, sort/select/empty/loading/error/bulk),
  cards (flat/raised/interactive/ai), metric card, entity cards (patient/appointment/invoice/
  service), list, description list, badge/status pill (full status set), chip/tag, avatar/group,
  tooltip, timeline, calendar (day/week/month), chart primitives, money display, progress,
  skeleton, divider, kbd, code block.
- **Feedback & overlays:** toast (all variants + undo), inline alert, dialog (all sizes),
  confirmation dialog (destructive/financial), drawer/sheet, popover, loading overlay, empty
  states (first-run/no-results/no-access/error).
- **AI:** mode toggle, AI panel/chat, message bubbles (user/assistant), **Proposed Action Card**
  (proposed→editing→submitting→approved/rejected/failed), inline AI suggestion, thinking indicator.
- **Layout & utility:** page/section headers, toolbar/filter bar, bulk action bar, scroll area,
  resizable panels, the app shell itself.

### 3.4 Patterns (composed demos)
Realistic, mocked compositions from `05` (mock data only — no backend, per Web Feature Design):
- **List/Index** (e.g. a services or patients list with toolbar, table, pagination, states).
- **Master–Detail** (list + detail drawer).
- **Editor/Form** (e.g. service editor with branch-config matrix + promotion editor + validation).
- **Record Detail** (tabs + description lists + related table + timeline).
- **Workspace** (multi-pane encounter-style layout with dockable AI panel).
- **Calendar / Queue** (appointment day/week with events + queue board).
- **Dashboard** (metric cards + charts + table).
- **Wizard** (multi-step setup).
- **The AI flow end-to-end:** ask → stream → Proposed Action Card → human Approve → success toast.
- **State gallery:** loading/empty/error/no-access/degraded for a representative surface.

### 3.5 Content & guidelines (rendered reference)
- Voice examples (`08`): good vs avoid for buttons, errors, empties, confirmations, AI copy.
- Accessibility notes (`07`) demonstrated: visible focus walkthrough, contrast, keyboard map,
  reduced motion.

---

## 4. Non-negotiable acceptance criteria

The Showcase is approved only when all hold:

- [ ] **Token-pure:** no color/size/radius/shadow/duration outside `02`/`03`; components consume
      semantic (not primitive) tokens; a generated `tokens.json` mirrors `02`.
- [ ] **Complete:** every component in `04` and every motion preset in `03` is demonstrated with its
      full applicable state set.
- [ ] **Dual theme:** everything is correct and contrast-passing in light **and** dark.
- [ ] **Dual direction & language:** everything is correct in LTR/EN **and** RTL/AR, with the
      Arabic font, mirrored layout, and mirrored directional icons.
- [ ] **Accessible:** meets the `07` "definition of done" — keyboard operable, visible focus, SR
      semantics, reduced-motion path, target sizes, 200% reflow.
- [ ] **Signature present:** the Command Bar hero and the Signal motif are implemented and feel as
      described in `01`.
- [ ] **AI boundary legible:** AI surfaces are visually and textually distinct and always gated by a
      human approval step.
- [ ] **Performant on modest hardware:** smooth with no heavy blur/continuous effects; frost and
      loops disabled under reduced-motion/low-power.
- [ ] **Reusable & owned:** every reusable element is a shared, documented component (no
      feature-local one-offs); ready to consume by real features and to translate to Flutter.
- [ ] **Premium & cohesive:** reads as one calm, precise instrument — not a template, not any of the
      AI-default looks called out in `01`.

---

## 5. After approval

Once reviewed and approved:

1. Run the **Design Knowledge Manager** skill to promote what shipped into `docs/ui/principles/`
   (design-system, components, patterns, motions, tokens, accessibility, responsive), keeping this
   spec suite and the living docs in sync.
2. Run **Web → Flutter** to build the Flutter UI kit that reproduces the Showcase faithfully.
3. Begin real feature UIs — each one composing the established kit and patterns, never re-deciding
   the foundation.
