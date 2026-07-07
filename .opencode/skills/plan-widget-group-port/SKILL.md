---
name: plan-widget-group-port
description: Use when the user asks to plan the port of a web-reference Dev component group (e.g. "Display", "Navigation", "Feedback & overlays", "AI", "Layout & utility") from the React/TS web-reference into the Flutter frontend. Produces a Markdown implementation plan under docs/ui/translation-plan/ for Composer 2.5. Use ONLY for the AiClinic design-system widget-port workflow; do not use for general Flutter work or for the already-shipped Actions and Inputs & forms groups.
---

# Plan widget group port (web-reference → Flutter)

Produce a detailed, pragmatic Markdown implementation plan (no Flutter code) for porting one
**Dev → Components** showcase group from `web-reference/` into the Flutter `frontend/` App
abstraction layer. The plan is executed later by Composer 2.5.

## Execution mode

**MANDATORY build mode.** This skill's final step is to write a Markdown document to
`docs/ui/translation-plan/<group-slug>-implementation-plan.md`. That is impossible in plan mode.

- Your very first assistant message after loading this skill MUST be the "Resolved: group = … ,
phases = N. Starting research…" line, and you then proceed directly into research + writing the
file in a **single pass** with no intermediate approval gate.
- You MUST call the `write` tool on the plan file before declaring the task done. Posting the
plan in chat alone is a failure of this skill.
- If the session is actually read-only (plan mode) — e.g. you cannot open `write` and get a
"cannot modify files" / permission-denied signal — stop and utter ONE sentence asking the user
to switch to build mode, then stop entirely (do not perform the research until they switch).
Do not dump the plan into chat as a substitute.
- Do NOT internally reason "I'm in plan mode, so I'll just present it." There is no "presenting
plan in chat" variant of this skill. The plan file either gets written, or you stop.
- This rule overrides any plan-mode/system-reminder you may have inherited from the caller.
Re-read the skill's front matter and this section each time before starting.

## Inputs

The user names the target group in their message. Substitute it for the placeholders below:

- `<GROUP_NAME>`    — human title as shown in the web nav (e.g. "Data display", "Navigation").
- `<group-folder>`  — the showcase folder name (e.g. `display`, `navigation`, `feedback`, `ai`,
  `layout`). If unsure, map from `ShowcaseGroupId` in `web-reference/src/showcase/registry.ts`.
- `<group-slug>`    — kebab output filename stem (e.g. `display`, `navigation`,
  `feedback-overlays`, `ai`, `layout-utility`).
- `<GroupFallback>` — skip `Actions` (shipped) and `Inputs & forms` (already planned at
  `docs/ui/translation-plan/inputs-forms-implementation-plan.md`).

If the user does not name a group, ask once via the question tool which group to plan.

## Research steps (perform before writing)

Do these efficiently — read only what each step names; parallelize where possible.

1. Read `web-reference/src/showcase/components/<group-folder>/index.ts` → enumerate every widget
   section `id` + `title` + `status` in the target group.
2. For each showcase file in that folder, read it AND its underlying UI component(s):
   - usually under `web-reference/src/components/ui/<component-dir>/`
   - sometimes under `web-reference/src/components/<dir>/` when the component lives outside `ui/`
     (e.g. `chip`, `kbd`, `tooltip`)
   Capture: exported names, props, variants, sizes, states, sub-components, dependencies.
3. Read `web-reference/src/showcase/registry.ts` and `web-reference/src/pages/ComponentsPage.tsx`
   for group metadata (title, description, ordering, status counts).
4. Inspect the shipping Flutter App abstraction layer to mirror its conventions:
   - `frontend/lib/core/ui/components/app_*.dart` — naming, flat layout, native Material widgets
     (NOT forui despite pubspec — forui is imported nowhere).
   - `frontend/lib/core/ui/widgets/widgets.dart` — barrel export list.
   - `frontend/lib/core/ui/theme/*` — `context.appColors` (`AppSemanticColors`), `AppSpacing`,
     `AppRadius`, `AppTypography`, `AppMotion`.
   - `frontend/lib/features/design_system/presentation/components/component_registry.dart` —
     the placeholder entries to flip to `ready`.
   - `.../component_section_builders.dart` — the per-id builder map to extend.
   - `.../components_content.dart` and `.../showcase_primitives.dart` (`ShowcaseSection`,
     `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection`).
   - `.../components/actions/*_showcase_section.dart` — the canonical port pattern (especially
     `button_showcase_section.dart` for the bilingual `_copyEn`/`_copyAr` convention).
   - `frontend/lib/features/design_system/presentation/providers/dev_preview_provider.dart`
     (bilingual EN/AR + RTL preview).
   - `frontend/pubspec.yaml` for available deps (forui declared but unused; native Material is
     the convention; `file_picker`, `intl`, `google_fonts`, etc. available).
5. If the group needs cross-widget shared infrastructure that does not yet exist (e.g. popover,
   chip, kbd, calendar grid, dialog, drawer, toast) AND earlier planned groups have not already
   introduced it, identify it and propose minimal in-house wrappers under
   `frontend/lib/core/ui/components/app_*.dart` — only when existing primitives cannot host the
   content. Avoid introducing new architectural patterns unless justified; reuse `MenuAnchor`,
   `Overlay`/`OverlayEntry`, `showDialog`, etc. as appropriate.
6. Read `docs/ui/memory/ui-runtime-errors.md` end-to-end. It captures the red-screen crashes hit
   while porting the Inputs & forms group (Material-ancestor missing, `MediaQuery`/inherited
   widget read in `initState`, `intl` locale not initialized, duplicate `FocusNode` on `Focus` +
   `TextField`, etc.). Identify which widgets in THIS group risk the same regressions (any that
   embed a Material primitive in a custom shell, open an `OverlayEntry`/popover, format dates with
   a non-default locale, or attach a `Focus`/`FocusNode`). The plan must call these out so Composer
   2.5 does not repeat them.

## Plan contents (the Markdown document must include)

1. **Ambiguities & design decisions** — list BEFORE implementation steps. Cover: forui vs native
   Material (always: native Material, `forui-wrappers.md` is superseded), file layout (flat
   `app_<name>.dart` + `<group>/` showcase subfolder), any new shared abstraction justification,
   i18n/RTL handling, controlled/uncontrolled pattern, error/invalid placement. **Open this
   section with a ⚠️ callout** directing Composer 2.5 to read `docs/ui/memory/ui-runtime-errors.md`
   first, then enumerate the group-specific regressions to avoid (e.g. overlay widgets must not
   read `MediaQuery` in `initState`; locale-specific `DateFormat` requires
   `ensureIntlDateFormattingInitialized()` at app startup; `FocusNode` must not be shared between
   an ancestor `Focus` and a descendant `TextField`; Material primitives inside custom
   `DecoratedBox`/`AnimatedContainer` shells need a `Material` ancestor). Reference the memory's
   "Checklist for new input components" by item number.
2. **Existing App assets to reuse** — table of path → used by, citing concrete `lib/...` paths.
3. **New shared abstractions to introduce** — table of file → export name → web analog → purpose,
   with the phase that introduces each.
4. **Three implementation phases** — each a logical, independently-shippable cluster. For every
   widget specify: Flutter widget(s) to create (App-prefixed, native Material, flat under
   `core/ui/components/`); files to create/modify under `frontend/`; existing App widgets/themes/
   utilities to reuse (cite paths); whether a NEW wrapper is required or an existing one should be
   extended; implementation dependencies on other widgets in the same or earlier phase.
5. **Dev-page instantiation spec per widget** — must mirror `web-reference` demo-for-demo: number,
   order, and titles of `ShowcaseDemo` cells; exact props (sizes, variants, `defaultValue`s,
   placeholders, icons, affixes, disabled/readOnly/invalid flags); any `ShowcaseVariantMatrix`
   rows; bilingual EN/AR copy following the existing `_copyEn`/`_copyAr` convention. State
   explicitly that the corresponding `web-reference/src/showcase/components/<group-folder>/<Name>Showcase.tsx`
   is the binding source of truth to reproduce, and that the Flutter showcase primitives
   (`ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix`) are 1:1 in shape
   with the web ones, so only the control name and prop syntax change.
6. **Wiring steps** — after each phase: flip `status` placeholder→ready in `component_registry.dart`
   (reuse exact `id` strings); add a `componentSectionBuilders` entry per ready id in
   `component_section_builders.dart` grouped under a `// <Group>` comment; import the new section
   files; append new `app_*.dart` files to `widgets.dart` barrel under a sub-comment; run
   `flutter analyze` on changed files; do not commit unless asked.
7. **Out-of-scope / defer** — call out things deliberately left for later milestones.
8. **Web widget inventory table** — `id → title → showcase file → underlying UI component` for
   every widget in the group, plus a short note on shared web building blocks
   (`input-base/input-styles.ts`, `popover/Popover.tsx`, `spinner/Spinner.tsx`, `chip/Chip.tsx`,
   `kbd`, `tooltip`, `useDirection`, `cn`, `motionPresets`, Radix primitives, lucide-react) that
   have Flutter equivalents proposed in §3.

## Hard constraints

- **Do not generate any Flutter code.** Output only the Markdown plan.
- Follow the existing architecture, coding style, naming conventions, file organization, and
  design patterns of the shipped App widgets (Actions group is the reference; Inputs & forms plan
  is the second reference at `docs/ui/translation-plan/inputs-forms-implementation-plan.md`).
- Every widget must sit behind the App abstraction layer so feature code imports `App*` widgets
  only — never Material/internal libs directly beyond `core/ui`.
- Keep the plan pragmatic and concise; do not over-analyze.
- Save the document to `docs/ui/translation-plan/<group-slug>-implementation-plan.md`.

## Reference document

The Inputs & forms plan at `docs/ui/translation-plan/inputs-forms-implementation-plan.md` is the
canonical example of the expected structure, depth, and tone. Read it once before writing to match
its format (sections 0–7 plus a web inventory).