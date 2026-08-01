# 08 — Voice & Content

Words are design material, not decoration. In an operational tool trusted with money and medical
records, copy is what makes the interface understandable and therefore usable. Bring the same
intentionality to text that you bring to spacing and color.

---

## 1. Voice

AiClinic sounds **clear, calm, and competent** — like a capable colleague who respects the user's
time. Plain over clever. Specific over vague. Never cute, never alarmist, never apologetic filler.

- **Confident, not chatty.** Say what a thing does; don't sell it.
- **Human, not robotic.** Natural phrasing, but no jokes in financial/medical contexts.
- **Respectful of expertise.** Users are professionals; don't over-explain the obvious.
- **Bilingual by design.** Everything reads naturally in both English and Arabic — write for
  translation (whole phrases, no glued fragments), not literal word-swaps.

---

## 2. Writing from the user's side of the screen

- Name things by what people **control and recognize**, not by how the system is built. "Branch
  price", not "override record". "Sign in", not "authenticate".
- Describe actions in plain terms: what happens when I click this?
- Prefer the domain vocabulary clinic staff already use (patient, visit, invoice, shift, service).

---

## 3. Mechanics

- **Sentence case** for everything: buttons, titles, labels, menus. (Not Title Case, not ALL CAPS
  — except the deliberate `text-overline` eyebrow.)
- **Active voice, verb-first** actions: "Save changes", "Add service", "Book appointment" — not
  "Submit", not "OK" for a specific action.
- **One name per concept, everywhere.** The button that says "Publish" produces a toast that says
  "Published". Don't call the same thing "archive" in one place and "deactivate" in another.
- **Be brief.** Cut filler ("please", "in order to", "successfully"). Every word earns its place.
- **Numbers, dates, money** follow the house formats (§6) and use tabular figures.
- **Sentence-level punctuation:** helper text and messages are sentences; labels and buttons are
  not (no trailing period on a label/button).

---

## 4. Element-by-element

- **Buttons:** the exact action. "Add service", "Approve", "Copy configuration", "Void invoice".
  Never "Yes/No" for consequential actions — restate the verb ("Delete service" / "Cancel").
- **Labels:** the noun the field captures. "Default price", "Promotion start date". Mark required
  fields in text, not color alone.
- **Placeholders:** an example or format, never a substitute for the label. "e.g. Consultation".
- **Helper text:** the constraint or consequence. "Used when a branch has no price override."
- **Tooltips:** one line of supplementary help or the reason a disabled control is disabled.
- **Empty states:** an invitation to act — what this is + the first action. "No services yet. Add
  your first service to start billing."
- **Confirmations:** state the consequence, then the verb. Title: "Delete this service?" Body:
  "It will no longer be selectable on new invoices. Past invoices are unchanged." Buttons: "Delete
  service" / "Cancel".

---

## 5. Errors, empties, and edge states

Treat failure and emptiness as moments for **direction**, not mood.

- **Errors explain and offer a way forward**, in the interface's voice — no apologies, never vague.
  Say what happened and what to do: "This price is higher than the branch price. Lower the
  promotion to continue." Map backend codes to plain language:
  - `DUPLICATE_NAME` → "A service with this name already exists in your organization."
  - `PROMO_EXCEEDS_PRICE` → "The promotion must be less than or equal to the effective price."
  - `STALE_SERVICE` / `STALE_SERVICE_BRANCH` → "This was changed by someone else. Reload to see the
    latest version before saving."
  - permission denied → "You don't have permission to do this."
  - offline/unreachable → "Can't reach the server. Your changes weren't saved."
- **Never** show raw errors, stack traces, or internal codes to the user.
- **Empty is an invitation**, not a dead end (see §4).
- **Degraded modes** (offline, subscription-limited, AI unavailable) are stated calmly and factually
  with what still works (`05` §9).

---

## 6. House formats & terminology

- **Currency:** amounts with 2 decimals, thousands grouping, and the currency indicator (Egypt
  default EGP); tabular figures; never invent per-screen formats. Use `AppMoney` for display.
- **Dates/times:** one locale-aware format per context (e.g. `04 Jul 2026`, `1:17 PM`); relative
  time ("2 min ago") only where freshness matters, with an absolute value on hover.
- **Digits:** Western Arabic digits (0–9) across all surfaces.
- **Terminology (canonical):** patient, staff, branch, organization, appointment, visit, invoice,
  invoice item, service, promotion, shift, role, permission. Use these consistently; don't
  introduce synonyms.
- **Status words** map to the semantic set (`02`): Active/Inactive, Paid/Partially paid/Unpaid,
  Overdue, Scheduled/Completed/Cancelled/No-show, Draft. Same word for the same state everywhere.

---

## 7. AI copy

- **Label AI clearly.** AI surfaces and proposals are marked as AI ("Proposed by AI", "AI
  suggestion") in text — not by color alone (P7, `07`).
- **Frame proposals as proposals.** "AI suggests booking…", and the action button is the plain verb
  ("Approve", "Edit", "Dismiss"). Never phrase an AI suggestion as a completed fact.
- **Be honest about limits.** When AI is unavailable: "AI is unavailable right now. You can do this
  manually." Never pretend the AI did something a human hasn't approved.
- **Summaries are neutral and reviewable**, and every actionable AI output leads to a human
  approval step.
