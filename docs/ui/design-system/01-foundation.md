# 01 — Foundation

The brand, the aesthetic direction, and the principles that govern every visual decision in
AiClinic. This document decides the direction; `02-tokens.md` encodes it in values. Read this
first.

---

## 1. The product, in one paragraph

AiClinic is an AI-first clinic operating system for small-to-mid multi-branch clinics in Egypt
and the wider MENA region. Staff — receptionists, doctors, administrators, lab and owner roles —
run the whole clinic day through it: registering patients, booking and queuing appointments,
documenting visits, issuing invoices, managing the service catalog and shifts. It is
**desktop-first on Windows**, used for long shifts on modest hardware, and it carries money and
medical records, so it must feel **trustworthy and precise**. An AI layer sits beside every
workflow as an *interaction accelerator* — it drafts structured actions that a human always
approves; it never acts on its own. The product's identity is not "a chatbot for clinics." It is
**a calm, fast operating console where clinic work becomes structured, and AI is one assistive
surface within it.**

## 2. Who it is for

- **Primary users are not technical.** They value speed, clarity, and an interface that never
  makes them feel stupid. Density is welcome; clutter is not.
- **They work fast and repetitively.** The receptionist books, checks in, and invoices dozens of
  times a day. Keyboard efficiency and muscle memory matter more than delight-for-its-own-sake.
- **They work long hours.** Low eye strain and a first-class dark theme are functional
  requirements, not preferences.
- **They read Arabic and English.** The interface must be equally correct in RTL and LTR.
- **Their hardware is modest.** 8 GB RAM, no GPU. The aesthetic must be beautiful *and* cheap to
  render.

## 3. The single job of the interface

**Let clinic staff move through operational work quickly and confidently, with the AI available
but never in the way.** Every visual choice is judged against that job. If a treatment looks
premium but slows the receptionist down or muddies a number, it loses.

---

## 4. Aesthetic direction — decided

We commit to one direction rather than shipping a menu of themes. The direction is:

### "Calm Clinical Precision" — an instrument, not a dashboard

The reference feeling is a **well-designed medical instrument panel** crossed with the
keyboard-first precision of Linear / Raycast and the restraint of Stripe and Vercel. Surfaces are
quiet and cool; type is confident and legible; color is spent almost entirely on **one signal**.
The product should feel engineered, honest, and unhurried — the way a good vitals monitor is
readable at a glance and never shouts.

Three moves define it:

1. **Quiet cool-neutral canvas.** Backgrounds and surfaces are low-chroma, faintly blue-slate
   neutrals — clean and clinical without being sterile-white or harsh-black. This lets data and
   status be the loudest things on screen.

2. **A single "vital" accent for the deterministic product, a distinct accent for AI.** The
   standard, human-driven product uses one confident **teal** ("Vital Teal") for primary actions,
   selection, and focus. The **AI surfaces use a separate violet** ("Synapse Violet"). This split
   is not decoration — it *encodes the product's core philosophy*: the deterministic, human-gated
   system and the assistive AI layer are different things, and the interface should make that
   legible at a glance. Teal means "the system will do exactly this." Violet means "the AI is
   proposing; a human decides."

3. **The Signal — the signature element.** A single thin, luminous line, reminiscent of a vitals
   baseline, is the one memorable motif. It is the active-navigation indicator, the focus accent
   on the Command Bar, and the "thinking" affordance on AI surfaces (a quiet pulse along the
   line). It is teal in standard mode and violet in AI mode. It appears in exactly the places
   that carry the most meaning — where you are, what has focus, and where the AI is working —
   and nowhere else.

### The hero: the Command Bar

The most characteristic moment in the product is the **Command Bar** (a `⌘K` / `Ctrl+K` surface):
a single field that is at once global search, navigation, quick actions, and the entry point to AI
mode. It is where "keyboard-first" and "AI-first" meet, so it is the hero of the Showcase and the
first thing a new user should discover. Opening it is the product introducing itself.

### Why this direction (and not the obvious ones)

Grounding the direction in the subject and the constraints, and deliberately avoiding the current
AI-generated defaults:

- **Not warm cream + serif + terracotta.** That editorial look fights a dense, numeric, operational
  tool and reads as a magazine, not an instrument.
- **Not near-black + a single acid/neon accent.** Too aggressive and consumer-hype for software
  trusted with patients and money, and fatiguing across a long shift.
- **Not the broadsheet look** (hairline rules, zero radius, newspaper columns). Zero-radius harshness
  and dense column rules undercut approachability for non-technical staff and hurt scannability of
  operational data.
- **Not glassmorphism as the primary language.** Heavy blur and translucency are expensive on
  8 GB / no-GPU hardware and reduce legibility. We allow a *restrained* frost only on transient
  overlays (see `02`/`03`); it is never the foundation.

Alternatives considered and set aside: a pure indigo "AI everywhere" palette (buries the important
human-vs-AI distinction and leans into the AI cliché); a warm, friendly "consumer health" look
(undermines the precision and trust the product needs). The teal/violet split with a cool-neutral
base is the choice that is specific to *this* product's philosophy rather than a generic
healthcare or generic-AI default.

> The full palette, type pairing, and the exact rendering of The Signal live in `02-tokens.md`.
> This document owns the *why*; that document owns the *values*.

---

## 5. Design principles

These are the rules of taste for the whole system. When a decision is unclear, resolve it toward
these.

### P1 — Data is the hero; chrome recedes.
The loudest things on any screen should be the patient's name, the amount, the status, the time.
Navigation, containers, and decoration stay quiet. Prefer whitespace and typographic hierarchy
over borders and fills to create structure.

### P2 — Spend color like it's expensive.
Color carries meaning: teal = primary/interactive/selected, violet = AI, and the semantic set
(success/warning/danger/info) = status. Neutral surfaces do the rest. A screen with color
everywhere is a screen where color means nothing.

### P3 — Calm over clever.
This is software people use for eight hours. Favor stillness, generous spacing, and predictable
placement over novelty. Motion clarifies; it never performs. If an effect is doing a party trick,
remove it.

### P4 — Density with air.
Desktop clinic work is information-dense by nature. Embrace dense tables and compact controls, but
give every dense region internal rhythm and breathing room so it reads as organized, not crammed.
Density is a layout discipline, not an excuse for clutter.

### P5 — Keyboard is a first-class citizen.
Every primary workflow is completable from the keyboard. Focus is always visible and always
follows a sensible order. Shortcuts are discoverable (via the Command Bar and tooltips) and
consistent across the app.

### P6 — Numbers are typographically first-class.
Money, quantities, counts, times, IDs, and dates use tabular figures so columns align and values
are comparable at a glance. Currency and dates follow one house format everywhere.

### P7 — Make the AI boundary visible.
Anything the AI proposes is visually distinct (violet, labeled, contained) and always sits behind
an explicit human approval step. The user must never be unsure whether they are looking at a fact
or a suggestion.

### P8 — Trust is a visual property.
Destructive and financial actions are clearly weighted and confirmed. Status is unambiguous.
Errors explain and offer a way forward. The interface should feel like it takes the user's data as
seriously as they do.

### P9 — Two directions, one quality.
English/LTR and Arabic/RTL are equal citizens. Layout mirrors correctly, type is set well in both
scripts, and neither feels like a translation of the other.

### P10 — Beautiful *and* cheap to render.
Elegance here comes from spacing, type, and restraint — things that cost nothing at runtime — not
from heavy blur, large shadows, or constant animation. The design must stay smooth on the minimum
hardware.

---

## 6. Anti-patterns (do not do these)

- Introducing a one-off color, font size, radius, shadow, or easing curve outside the tokens.
- Using the AI violet for non-AI things, or the product teal for AI things.
- Decorative gradients, glows, or drop shadows that carry no meaning.
- Full-width heavy borders or card-in-card-in-card nesting to create structure that spacing could
  create instead.
- Motion on load-bearing content (numbers, statuses) that delays comprehension.
- Emoji or playful illustration in operational/financial/medical contexts. Empty-state
  illustration is allowed, restrained, and on-brand.
- Center-aligned body text or numeric columns; text aligns to the reading direction, numbers align
  by their nature (see `05`).
- Any interaction that is mouse-only.

---

## 7. What "done well" looks like

A new staff member sits down, opens the app, and within a minute understands where they are, what
matters on the screen, and how to start their task. A receptionist runs their whole day without
reaching for the mouse. A doctor reads a patient history at a glance in a dim room without
squinting. An administrator trusts the numbers. And when the AI offers help, everyone can tell —
instantly — that it is a suggestion waiting for their yes. Nothing on screen feels accidental.
