# 07 — Accessibility & Internationalization

Accessibility is a requirement, not an enhancement. AiClinic is used all day, by non-technical
staff, in two languages, on varied hardware. The target is **WCAG 2.2 AA** across both themes and
both directions.

---

## 1. Color & contrast

- **Body/UI text:** ≥ **4.5:1** against its background. Large text (≥18.66px/24px bold or ≥24px):
  ≥ **3:1**.
- **Non-text UI** (borders of inputs, icons that carry meaning, focus rings, control boundaries):
  ≥ **3:1**.
- Verify in **both light and dark** themes. Semantic tokens in `02` are chosen to meet these; any
  new pairing must be checked.
- **Never encode meaning in color alone** (P8). Status always pairs with text and/or an icon/shape;
  charts use labels/patterns as well as hue; required fields say "required".
- Disabled elements are exempt from contrast minimums but must still be understandable.

---

## 2. Keyboard

- **Everything operable by keyboard.** Every workflow (book, invoice, document, configure) is
  completable without a mouse (P5).
- **Focus is always visible** — the 2px focus ring (`02`) is never removed; violet variant on AI
  surfaces.
- **Logical focus order** follows reading order (and mirrors in RTL).
- **Focus management:** modals/drawers trap focus and restore it to the trigger on close; menus and
  the Command Bar are fully arrow-key navigable; `Esc` closes the topmost overlay.
- **No keyboard traps.** Skip-to-content link at the top of the shell.
- **Shortcuts** (`⌘K`, `/`, go-to, `Esc`) are discoverable and never the *only* way to do
  something; they don't clobber assistive-tech or browser shortcuts.

---

## 3. Screen readers & semantics

- Use **native/semantic roles** first; add ARIA only to fill gaps.
- Every control has an accessible name (visible label preferred; `aria-label` for icon-only
  controls, always paired with a tooltip).
- **Live regions:** toasts and async results use `role="status"`/`aria-live="polite"`; errors use
  `assertive` where appropriate.
- **Forms:** labels programmatically associated; `aria-describedby` for help/error;
  `aria-invalid` on error; group related fields with `fieldset`/`legend` or `role="group"`.
- **Tables:** proper header associations, sortable columns announce sort state, selection state
  announced.
- **State:** `aria-expanded`, `aria-selected`, `aria-current` (nav), `aria-busy` (loading),
  `aria-pressed` (toggles) reflect real state.
- **Images/icons:** decorative ones are hidden from AT; meaningful ones have text alternatives.

---

## 4. Motion & sensory

- Respect `prefers-reduced-motion` (and low-power) per `03`: no essential info conveyed by motion;
  animations become fade/instant; loops (Signal pulse, shimmer) stop.
- No content flashes more than 3×/second.
- Autoplaying/looping motion (AI thinking) is subtle, pauses on response, and is disable-able.

---

## 5. Targets, zoom & text

- **Target size:** ≥ 24×24px effective (WCAG 2.2); touch layouts ≥ 44px.
- **Reflow:** usable at 200% zoom without loss of content/function; text remains legible.
- **No text in images** for essential content.
- Respect user font-size/OS settings where the platform allows.

---

## 6. AI-specific accessibility

- Proposed Action Cards (`F4`) are fully keyboard-operable; Approve/Edit/Dismiss are real buttons
  with clear names.
- Streaming AI text is announced politely (not per-token spam); a "response complete" cue is
  available.
- The AI-vs-human distinction is conveyed by **label and text**, not violet color alone (P7 + §1).

---

## 7. Internationalization (English + Arabic)

- **Direction:** full LTR/RTL support per `06` (logical properties, mirrored layout and directional
  icons).
- **No concatenated strings:** all copy is translatable as whole phrases with placeholders;
  pluralization and gender handled by the i18n layer, not string-gluing.
- **No hardcoded text** in components; everything comes from the localization catalog.
- **Locale-aware formatting** for dates, times, numbers, and currency; consistent house formats
  (`08`); Western digits by default.
- **Layout tolerance:** components accommodate text expansion/contraction between languages (Arabic
  and English differ in length and density) without clipping or breaking.
- **Bidi correctness:** isolate embedded Latin/numeric runs within Arabic text.

---

## 8. Definition of done (a11y gate)

A component/screen is not complete until:

- [ ] Fully keyboard operable with visible focus and correct order (LTR + RTL).
- [ ] Contrast passes AA in light and dark.
- [ ] Meaning never conveyed by color alone.
- [ ] Screen-reader labels, roles, and state are correct.
- [ ] Reduced-motion path verified.
- [ ] Localized (EN + AR), mirrored correctly, no clipped/overflowing text.
- [ ] Target sizes and 200% zoom reflow verified.
