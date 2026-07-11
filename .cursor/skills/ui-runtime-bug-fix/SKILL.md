---
name: ui-runtime-bug-fix
description: >-
  Investigates and fixes Flutter UI runtime bugs from a user description, then
  records the issue, root cause, and fix in docs/ui/memory/ui-runtime-errors.md.
  Use only when the user explicitly reports a UI crash, red screen, widget
  error, layout exception, or design-system showcase bug, or asks to fix and
  document a runtime UI error. Do not use for general Flutter UI work.
---

# UI Runtime Bug Fix

## Purpose

Accept a UI bug description, reproduce and fix it in the Flutter codebase, then append durable knowledge to `docs/ui/memory/ui-runtime-errors.md` so future work avoids the same failure.

This skill **fixes code** and **updates memory**. It does not redesign features or refactor unrelated code.

---

## Input

A UI bug description. The user may provide:

- Error message or stack trace
- Steps to reproduce
- Affected screen or component name
- Screenshot or red-screen text

If details are missing, infer from the error text and search the codebase before asking the user.

---

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Read memory
- [ ] 2. Reproduce / locate
- [ ] 3. Diagnose root cause
- [ ] 4. Fix (minimal diff)
- [ ] 5. Verify
- [ ] 6. Document in ui-runtime-errors.md
```

### 1. Read memory

This skill is the explicit trigger to consult the memory file. Before changing code, read `docs/ui/memory/ui-runtime-errors.md`.

- If the bug matches an existing entry, apply the documented fix pattern first.
- If the entry exists but is incomplete, extend it instead of duplicating.
- If it is genuinely new, plan a new numbered entry.

### 2. Reproduce / locate

1. Parse the error: exception type, widget name, file, line.
2. Search the codebase for the failing widget, route, or showcase section.
3. Open the design-system showcase if the bug is in a component demo (`frontend/lib/features/design_system/`).
4. Run `dart analyze` on suspect files if no runtime trace is given.

Common Flutter UI failure classes in this project:

- Missing `Material` ancestor (`TextField`, `Slider`, `InkWell`, `DropdownButton`)
- Inherited widget reads in `initState` (`MediaQuery`, `Theme`, `AppMotion.transitionFor`)
- Uninitialized `intl` locale data (`DateFormat` with explicit locale)
- `RenderFlex` overflow, unbounded constraints, `setState` after dispose
- Popover/overlay lifecycle (`AppPopover`, combobox, select, date pickers)

### 3. Diagnose root cause

State the **why**, not just the symptom:

- Which widget threw?
- Which lifecycle or constraint rule was violated?
- Why did our design-system pattern trigger it (e.g. custom `BoxDecoration` shell without `Material`)?

Do not guess. Trace the ancestor chain and the call site that provoked the error.

### 4. Fix (minimal diff)

- Fix at the correct layer: shared component over one-off showcase patch.
- Prefer existing helpers (`appWrapMaterialInput`, `ensureIntlDateFormattingInitialized`, `AppMotion.resolveDuration`) over new abstractions.
- Match surrounding naming, imports, and file structure.
- Do not widen scope to unrelated components or docs.

### 5. Verify

1. Run `dart analyze` on every changed Dart file.
2. If the bug was in a showcase section, confirm the demo path compiles and the fix addresses the reported steps.
3. Fix analyzer issues introduced by the change.

Do not commit unless the user asks.

### 6. Document in ui-runtime-errors.md

Append or update an entry in `docs/ui/memory/ui-runtime-errors.md`.

**Entry format** (match existing style):

```markdown
## N. `ExceptionType` or short title (`WidgetName`)

**Symptom:** What the user sees — red screen text, when it triggers, which screen.

**Cause:** Why it happened — lifecycle rule, missing ancestor, uninitialized dependency, constraint logic.

**Fix:** What changed and where. Include a short code snippet when the pattern is reusable.

**Affected files (fixed):** `file_a.dart`, `file_b.dart` — omit if obvious from the fix section.
```

Rules for the memory file:

- Use the next sequential number for new issues.
- Keep the intro line at the top; only update it if the doc scope broadens.
- Add a `---` separator between entries.
- If the fix introduces a reusable guard (checklist item), add or extend the **Checklist for new …** section at the bottom.
- Never delete prior entries; refine or cross-reference instead.
- Write for the next agent: concrete, searchable, implementation-specific.

---

## Output

When finished, tell the user:

1. **Issue** — one sentence summary
2. **Cause** — why it happened
3. **Fix** — what files changed and the pattern applied
4. **Memory** — confirm the `ui-runtime-errors.md` entry number/title added or updated

---

## Rules

- Read `docs/ui/memory/ui-runtime-errors.md` before fixing; write to it after fixing.
- Minimal diff; no drive-by refactors.
- Fix shared components when the bug affects multiple inputs or showcases.
- Do not duplicate memory entries.
- Do not create commits or PRs unless requested.
- For web/React bugs, only use this skill when the user wants the Flutter side fixed and documented; otherwise stop and clarify.

---

## Success criteria

- The reported UI error no longer occurs for the described steps.
- Changed Dart files pass `dart analyze`.
- `docs/ui/memory/ui-runtime-errors.md` contains a clear Symptom / Cause / Fix entry.
- Future similar work can discover the fix by reading the memory file alone.
