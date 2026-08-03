# AiClinic Design System Specification

**Status:** Foundational specification (source of truth for all UI work)
**Type:** Foundation Feature — not a user-facing feature, but the visual and interaction
foundation every future feature inherits.
**Owner discipline:** Treat this suite the way the constitution treats architecture. When a
feature's UI conflicts with these documents, this suite wins unless it is deliberately amended.

---

## 1. Why this exists

AiClinic is an AI-first operating system for small-to-mid multi-branch clinics: desktop-first
on Windows, dense and keyboard-driven for receptionists and clinicians, trusted with money and
medical records, and deployed on modest hardware (8 GB RAM, no GPU). Every screen — patients,
appointments, the encounter workspace, billing, the service catalog, shifts, settings, and the
AI command surface — must feel like one instrument, not a patchwork.

This suite defines that single instrument once, so that:

- Every feature starts from a decided visual language instead of re-deciding it.
- The web reference build and the Flutter build produce the same experience.
- Quality compounds: a strong foundation makes every later feature cheaper and more consistent;
  weaknesses here propagate everywhere, so this is the highest-budget design work in the project.

This is a **specification**, not an implementation. It describes intent, tokens, components,
and behavior precisely enough that the reference build requires no visual guesswork.

---

## 2. Where this sits in the build pipeline

```text
Product Overview + Constitution
        │
        ▼
Design System Specification  ← YOU ARE HERE (docs/ui/design-system/)
        │
        ▼
Web Feature Design (skill)   → build the React reference, starting with the Showcase (09)
        │
        ▼
Frontend Design (skill)      → refine hierarchy, composition, motion within this language
        │
        ▼
Design Knowledge Manager     → promote what shipped back into docs/ui/principles/
        │
        ▼
Web → Flutter (skill)        → faithful Flutter reproduction + Flutter UI kit
        │
        ▼
Feature implementation       → every feature composes the established kit
```

The **Design System Showcase** (see `09-showcase.md`) is the first thing to build with the Web
Feature Design skill. It is the living catalog — like Storybook / shadcn docs / the Material
gallery — where every component, variant, state, and motion is demonstrated. It is the artifact
that gets reviewed and approved before any real feature UI is built.

---

## 3. Document map

| # | File | What it decides |
|---|------|-----------------|
| — | `README.md` | This index, pipeline, and how to use the suite |
| 01 | `01-foundation.md` | Product-grounded brand, aesthetic direction (decided, with rationale), design principles, anti-patterns |
| 02 | `02-tokens.md` | Design tokens: color (light + dark), typography, spacing, radius, elevation, borders, z-index — three-tier architecture |
| 03 | `03-motion.md` | Durations, easing, motion patterns, micro-interactions, the performance/`reduced-motion` budget |
| 04 | `04-components.md` | The full component inventory: anatomy, variants, states, behavior |
| 05 | `05-patterns.md` | App shell, page templates, navigation, forms, tables, data density, loading/empty/error, permission-aware UI, AI mode, the Command Bar |
| 06 | `06-responsive.md` | Desktop-first breakpoints, adaptation rules, and RTL/mirroring |
| 07 | `07-accessibility.md` | Accessibility standards and internationalization (English + Arabic) |
| 08 | `08-voice-and-content.md` | Microcopy voice, terminology, and content patterns |
| 09 | `09-showcase.md` | The Design System Showcase deliverable — what to build first and its acceptance bar |

Read `01` and `02` before anything else; they are the load-bearing decisions the rest depend on.

---

## 4. How to use this when building a feature

1. **Start from tokens and components.** Never introduce a new color, type size, spacing value,
   radius, shadow, or motion curve that is not in `02`/`03`. If you need one, that is a change to
   the system (see §5), not a local decision.
2. **Reuse before you build.** If a component in `04` covers the need, compose it. Create a new
   reusable component only when nothing fits — and then it belongs to the shared kit, documented
   in the Showcase, not to the feature.
3. **Compose with patterns.** Use the page templates, states, and navigation rules in `05` so
   every feature feels like the same product.
4. **Honor the floor.** Keyboard operability, visible focus, contrast, `reduced-motion`, RTL, and
   the loading/empty/error trio are requirements, not enhancements.

---

## 5. Changing the system

These documents are amendable, but changes are deliberate:

- **Token or component change** (new semantic token, new variant): update the relevant doc, add
  it to the Showcase, and note the rationale. Prefer extending semantics over adding primitives.
- **Aesthetic-direction change** (palette, type pairing, signature): treat as a major amendment —
  it touches every feature. Record what changed and why in `01`.
- **Keep the tiers clean.** Features consume semantic tokens; they never reach for raw primitive
  values. This is what makes theming (light/dark) and future rebrands a token swap rather than a
  rewrite.

Consistency is the product feature here. When in doubt, choose the option that makes AiClinic
feel more like one calm, precise instrument.
