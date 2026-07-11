---
description: Plan the Flutter port of one web-reference Dev component group (no code) — outputs a Markdown spec under docs/ui/translation-plan/ for Composer 2.5.
agent: plan
---

# Plan widget group port

You are producing an implementation plan (NOT implementing). Load and strictly follow the
`plan-widget-group-port` skill's instructions, then execute that workflow for the group the user
passed as the argument below.

## Arguments

`$ARGUMENTS` is whatever the user typed after the command. Because opencode's `$1`/`$2` are
naive whitespace-split tokens (no NLP), treat `$ARGUMENTS` as a **free-form natural-language
request** and parse it yourself rather than trusting positional token splits.

Extract two values from `$ARGUMENTS`:

1. **`group`** (required) — the target web-reference component group. Accept any of:
   - human nav title, with or without surrounding filler words like `section`, `group`, `the`,
     `port`, `plan`, casing variants, and ampersand or `and` forms. Examples that should ALL
     resolve to the `display` folder:
     `Data Display`, `Data display section`, `the data-display group`, `Display`, `display`,
     `port the display section`, `plan the Data Display component group`.
   - showcase folder name directly (e.g. `display`, `navigation`, `feedback`, `ai`, `layout`).
   - any group id from `web-reference/src/showcase/registry.ts` (`ShowcaseGroupId`).
   When the user's wording is ambiguous or matches multiple groups, normalize against the
   `ShowcaseGroupId` enum (`actions, inputs, display, navigation, feedback, ai, layout`) and the
   human titles in `web-reference/src/pages/ComponentsPage.tsx`. If still ambiguous, ask the user
   once via the question tool which of the remaining (not-yet-shipped, not-already-planned) groups
   to plan: Display, Navigation, Feedback & overlays, AI, or Layout & utility. Never plan
   `Actions` (shipped) or `Inputs & forms` (already planned at
   `docs/ui/translation-plan/inputs-forms-implementation-plan.md`) without explicit user override.

2. **`phases`** (optional, default `3`) — the number of implementation phases to divide the work
   into. Accept any of these phrasings as specifying N phases:
   - a trailing bare integer, e.g. `/plan-widget-group display 4`
   - `into N phases`, `dissect ... into N phases`, `split ... into N phases`,
     `divide ... into N phases`, `N phases`, `in N phases`, `with N phases`
   - `N-phase`, `N phase`, e.g. `5-phase`
   - just the integer `N` anywhere in `$ARGUMENTS` when the user clearly meant phase count
     (heuristic: integer between 1 and 6 inclusive AND the word `phase`/`phases` appears, OR the
     integer is the last token in the string).
   Constraint: 1 ≤ N ≤ 6. If parsed value is outside this range, or no phase count is recoverable,
   fall back to `3` and **note the fallback** in the plan's "Ambiguities & design decisions"
   section (e.g. "User requested 9 phases; clamped to 6 because each phase must remain a
   meaningful logical cluster.").

After parsing, in your first assistant message, briefly echo what you resolved (one line) so the
user can correct you before you do all the research, e.g.:
`Resolved: group = Display (folder 'display'), phases = 5. Starting research…`
Do NOT re-ask if the parse is confident — just proceed; the user can interrupt if wrong.

Substitute the resolved `group` into the skill's `<GROUP_NAME>`, `<group-folder>`, and
`<group-slug>` placeholders, and override the skill's default 3-phase count with the resolved
`phases` everywhere the skill mentions "3 implementation phases" / "three phases" / phase tables.

## Examples (all valid invocations)

Terse positional (still works):
- `/plan-widget-group display` → 3 phases (default).
- `/plan-widget-group navigation 4` → 4 phases.
- `/plan-widget-group "Feedback & overlays" 2` → 2 phases.
- `/plan-widget-group ai` → 3 phases (default).

Free-form prose (this is the recommended form, and is what the user most often types):
- `/plan-widget-group Data Display section and dissect it into 5 phases` → display, 5 phases.
- `/plan-widget-group plan the Navigation group, 4 phases` → navigation, 4 phases.
- `/plan-widget-group port the feedback group into 2 phases` → feedback, 2 phases.
- `/plan-widget-group AI section, dissect into 6 phases` → ai, 6 phases.
- `/plan-widget-group layout utility group, split into 3 phases` → layout, 3 phases.
- `/plan-widget-group Display` → display, 3 phases (default).

## Execution

1. Invoke the `plan-widget-group-port` skill to load its full workflow.
2. Perform the skill's research steps (parallelize reads where possible).
3. Divide the widgets into the **`$2` (or default 3) implementation phases** specified by the
   argument — each phase a logical, independently-shippable cluster. If `$2` differs from 3,
   still preserve the same per-widget table schema the skill defines; just split across that many
   phase tables instead of three.
4. Write the Markdown plan to `docs/ui/translation-plan/<group-slug>-implementation-plan.md`
   matching the structure/depth of the canonical inputs-forms plan (sections 0–7 + a web widget
   inventory table; per-widget Dev-page instantiation must mirror the web reference demo-for-demo).

## Hard constraints

- Do not generate any Flutter code. Output only the Markdown plan file.
- Do not modify `frontend/` source. Only write the plan doc.
- Do not commit unless the user explicitly asks.
- Follow the existing App abstraction conventions (native Material; forui-wrappers.md is
  superseded). See the skill for full detail.

Reference example: `docs/ui/translation-plan/inputs-forms-implementation-plan.md`.