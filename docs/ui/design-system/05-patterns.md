# 05 — Patterns

How components compose into consistent experiences. Features assemble these patterns rather than
inventing layouts, so the whole product feels like one instrument. Patterns use tokens (`02`),
motion (`03`), and components (`04`).

---

## 1. The App Shell

The persistent frame every authenticated screen lives in.

```text
┌───────────────────────────────────────────────────────────────┐
│  Top Bar:  [breadcrumb/title]        [⌘K]  [branch▾] [AI] [◔] [@]│
├──────────┬────────────────────────────────────────────────────┤
│          │                                                      │
│ Sidebar  │   Content region (page)                              │
│ (nav)    │   ┌───────────────────────────────────────────┐     │
│  ▎Home   │   │ Page header                                │     │
│   Patients│  │ Toolbar / filters                          │     │
│   Appts  │   │ Content: table / cards / detail / workspace│     │
│   Billing│   │                                            │     │
│   ...    │   └───────────────────────────────────────────┘     │
│  [settings]                                                     │
└──────────┴────────────────────────────────────────────────────┘
   ▎ = the Signal active indicator (teal)          overlays: modal/drawer/toast/command
```

- **Sidebar** (`C1`): primary navigation, collapsible to an icon rail; org/branch context at top;
  the Signal marks the active item. In RTL it moves to the right.
- **Top Bar** (`C2`): location + the Command Bar trigger (`⌘K`), branch switcher, AI mode toggle,
  notifications, user menu. Sticky.
- **Content region:** scrolls independently; max content width for readability on very wide
  screens, but tables/workspaces may go full-width.
- **Overlay layers:** Command Bar, modals, drawers, popovers, toasts — ordered by `z-index` (`02`).

---

## 2. Page templates

Pick one per screen; do not improvise page structure.

| Template | Use | Structure |
|----------|-----|-----------|
| **List / Index** | patients, invoices, services, staff, shifts | Page header → toolbar (search + filters + primary action) → `AppTable` (or card grid) → pagination |
| **Master–Detail** | patient list + patient detail, invoice list + editor | Split panels (`G6`): list (inline-start) + detail/drawer (inline-end) |
| **Record Detail** | a single patient / invoice / service | Page header (title + status + actions) → tabs → sections (description lists, related tables, timeline) |
| **Editor / Form** | create/edit service, invoice, appointment | Page header or dialog/drawer → grouped form sections → sticky footer actions |
| **Workspace** | the visit/encounter workspace | Resizable multi-pane: context (patient) + primary work (SOAP/plan) + supporting (orders/billing); AI panel dockable |
| **Board / Queue** | appointment queue, day board | Columns or time-grid of entity cards with status |
| **Calendar** | appointments, shifts | `AppCalendar` day/week/month + filters |
| **Dashboard / Analytics** | overview, reports | Metric cards row → charts grid → detail tables |
| **Wizard** | first-run setup, new-branch service setup | Stepper (`C7`) + per-step form + back/next |
| **Settings** | org/branch/staff/roles, preferences | Sidebar sub-nav or tabs + form sections |
| **Empty / Auth** | login, first-run, empty app | Centered single-column, minimal chrome |

Consistent vertical rhythm: page gutter `space-6`–`space-8`; header→toolbar `space-4`; section gaps
`space-8`–`space-12`.

---

## 3. Navigation model

- **Primary:** sidebar for top-level domains.
- **Secondary:** tabs within a record/section; sub-nav in settings.
- **Contextual:** row/card "⋯" menus, context menus.
- **Global/fast:** the Command Bar (`⌘K`) — search anything, jump anywhere, run actions, or ask AI.
- **Breadcrumbs** show hierarchy on deep pages.
- **Back/return:** editing in drawers/modals keeps users in context; full-page editors offer a
  clear cancel/back that guards unsaved changes.

Keyboard: `⌘K` command bar, `/` focus page search, `g` then a key for go-to (documented in Command
Bar), `Esc` closes the topmost overlay. All shortcuts are discoverable, never required.

---

## 4. Forms

- Use `Form Field` (`B0`) for every field; label above control (dense, scannable), helper below.
- **Grouping:** related fields in sections with `Section Header`; one primary action per form.
- **Layout:** single column by default (fastest to scan/complete); two columns only for short,
  paired fields on wide screens.
- **Validation:** validate on blur and on submit; show inline errors at the field + an optional
  summary alert for long forms; never rely on color alone; keep the offending field in view.
- **Server authority:** the frontend validates for usability, but the backend is the source of
  truth (constitution III). Surface backend rule violations (e.g. `PROMO_EXCEEDS_PRICE`,
  `DUPLICATE_NAME`, `STALE_*` concurrency) as clear field/summary errors mapped to plain language.
- **Optimistic concurrency:** on a stale-edit conflict, tell the user their copy is out of date and
  offer to reload — never silently overwrite.
- **Saving:** primary button shows `loading`; disable double-submit; confirm success with a toast;
  keep the form open on error with values intact.
- **Money & quantities:** `AppMoneyField`/number with tabular figures; quantity defaults to 1.
- **Destructive/financial:** route through Confirmation Dialog (`E4`).

---

## 5. Tables & data density

- Default density `default` (40px rows); offer `compact` for power users on large lists.
- **Alignment:** text starts at the reading edge; numbers, money, and dates align to the
  inline-end with tabular figures; status pills start-aligned.
- **Sorting/filtering:** update instantly; keep scroll position; show active filters as removable
  chips in the toolbar; show result counts.
- **Selection:** header checkbox + row checkboxes → Bulk Action Bar (`G4`).
- **Row actions:** most-common action inline (icon button), the rest in a "⋯" menu.
- **Large sets:** pagination with range summary or virtualized scroll (catalogs up to thousands).
- **Totals:** footer summary row for financial tables.
- **Row → detail:** `Enter`/click opens the record (drawer or page per template).

---

## 6. Content states (the required trio + more)

Every data surface must handle **loading, empty, and error** — plus filtered-empty and no-access.

| State | Treatment |
|-------|-----------|
| **Loading** | skeletons matched to the final shape (tables/cards/detail); button/inline spinner for actions; no layout shift when data arrives |
| **Empty (first-run)** | `AppEmptyState` invitation: what this is + primary action (e.g. "Add your first service") |
| **Empty (no results)** | "No matches" + suggestion to adjust search/filters + clear-filters action |
| **Error** | `Error State`: plain cause + retry; never a raw error; preserve the rest of the page |
| **No access** | permission empty state explaining the missing permission, no dead-end |
| **Partial/degraded** | inline alert (e.g. subscription-degraded read-only, offline) — see §9 |

---

## 7. Permission-aware UI (RBAC)

Access is role-based (owner/administrator/doctor/receptionist/lab). The UI reflects permissions but
never *enforces* them (backend does, constitution IV).

- **Hide vs disable:** hide entire nav/sections the role can't use; **disable with a reason
  tooltip** for actions that exist but aren't permitted in context (e.g. discount without
  `billing.discount`, service management without `services.manage`).
- **Read-only rendering:** show data with edit affordances removed rather than empty screens.
- **Defense in depth:** even when the UI shows an action, the backend re-checks; surface a clean
  "You don't have permission" message if a call is denied.
- **Consistency:** the same permission gates the same affordance everywhere.

---

## 8. Multi-branch & tenant context

- The current **branch** is always visible (Top Bar switcher, `C9`); switching re-scopes data with
  clear feedback (brief loading + a confirmation of the new scope).
- Branch-scoped vs org-shared data is signposted (e.g. patients/staff are org-shared; invoices,
  schedules, numbering are branch-scoped — reflect this in labels and empty states).
- Cross-branch features (copy service configuration, new-branch setup) name source and target
  branches explicitly and confirm before replacing existing configuration (`E4`).
- Numbering (invoice/appointment) is per-branch; render with tabular figures and branch context.

---

## 9. Operational continuity (offline, degraded, low hardware)

The product must degrade gracefully, never hard-lock (constitution V).

- **Offline / connectivity loss:** show a persistent, calm inline alert; keep manual workflows
  working where possible; disable only what truly needs the network, with clear messaging; queue
  or block writes explicitly rather than failing silently.
- **Subscription-degraded:** worst case is **read-only with data preserved** — communicate it via a
  banner, keep everything viewable, never delete or hide data.
- **AI unavailable:** every workflow remains fully doable manually; AI affordances show a quiet
  "AI is unavailable" state and step aside (constitution V).
- **Low hardware:** honor reduced-motion/low-power (`03`); avoid heavy effects; keep lists
  virtualized and interactions responsive.

---

## 10. AI interaction pattern (Standard ↔ AI)

The product's defining flow. AI is an assistive surface, always human-gated (P7).

1. **Enter AI:** via the AI mode toggle or by asking a natural-language question in the Command
   Bar. Accent shifts teal→violet (`03`); the context/scope the AI can see is shown.
2. **Converse:** user asks; AI streams a response (`F2`/`F3`). AI may **read** limited context but
   proposes, never executes.
3. **Propose:** actionable intents render as **Proposed Action Cards** (`F4`) — a plain-language
   summary of exactly what will happen, with editable safe fields.
4. **Human approval:** the user Approves / Edits / Dismisses. Approve runs the **normal validated
   backend path** (same RPC a manual action would use) — the AI has no write access.
5. **Result:** on success the record appears as a normal record + a toast; on validation failure,
   the same clear error mapping as manual forms (§4).

Visual contract: AI content is always violet-marked and contained; a user can never confuse a
suggestion for a committed fact; the approval affordance is always present before anything happens.

---

## 11. Composition rules

- Reuse components (`04`) and these patterns before creating anything new.
- Any new reusable element joins the shared kit and the Showcase (`09`) — never lives inside one
  feature.
- Prefer whitespace and type hierarchy over borders/fills for structure (P1).
- One primary action per view; keep secondary/tertiary actions visually quieter.
- Spend color only on meaning (P2); keep chrome neutral.
