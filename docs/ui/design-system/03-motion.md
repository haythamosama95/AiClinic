# 03 — Motion

Motion in AiClinic clarifies state and orients the user; it never performs. Because the product
runs on modest hardware (8 GB RAM, no GPU) and is used for long shifts, motion is restrained,
cheap to render, and fully respectful of `prefers-reduced-motion`.

Guiding rule: **animate to explain a change of state or position. If an animation is decorative,
delete it.** (Principle P3, P10.)

---

## 1. Duration tokens

| Token | ms | Use |
|-------|----|-----|
| `duration-instant` | 80 | state color change (hover/active) on small controls |
| `duration-fast` | 120 | button/checkbox/switch feedback, tooltip in |
| `duration-quick` | 160 | dropdown/menu/popover open, tab underline |
| `duration-base` | 220 | default transition, modal/panel, list item enter |
| `duration-slow` | 320 | large surfaces (drawer, sheet, route change) |
| `duration-deliberate` | 480 | rare orchestrated moments (first-run, empty→data reveal) |

Never exceed `duration-slow` for anything the user is waiting on to act. Perceived speed is a
feature.

---

## 2. Easing tokens

| Token | Curve | Use |
|-------|-------|-----|
| `ease-standard` | `cubic-bezier(0.2, 0, 0, 1)` | default; most enter/move transitions |
| `ease-out` | `cubic-bezier(0.16, 1, 0.3, 1)` | elements entering / expanding (decelerate) |
| `ease-in` | `cubic-bezier(0.4, 0, 1, 1)` | elements leaving / collapsing (accelerate) |
| `ease-in-out` | `cubic-bezier(0.65, 0, 0.35, 1)` | position changes, reordering |
| `ease-emphasized` | `cubic-bezier(0.2, 0, 0, 1)` w/ longer duration | hero moments (Command Bar) |
| `ease-linear` | `linear` | continuous loaders, progress, the Signal pulse |

Default pairing: **`duration-base` + `ease-standard`**. Entrances prefer `ease-out`; exits prefer
`ease-in` and are ~30% faster than their entrance.

---

## 3. Property budget (what we animate)

Animate only cheap, compositor-friendly properties:

- **Allowed:** `opacity`, `transform` (translate/scale), `background-color`, `border-color`,
  `color`, `box-shadow` (sparingly), `width/height` only for small controls or when using a
  measured/`grid-template-rows` technique.
- **Avoid:** animating layout of large lists, continuous `backdrop-filter`, large blur, `top/left`
  positional animation, shadow on scroll for big surfaces.
- Movement distances are small: **8–16px** translate for enters; scale from `0.98`→`1` (never big
  pops).

---

## 4. Motion patterns (presets)

These are named, reusable presets. Introducing a new reusable motion means adding it here.

| Preset | Behavior | Tokens |
|--------|----------|--------|
| `motion-fade` | opacity 0→1 | `duration-base` · `ease-standard` |
| `motion-fade-scale` | opacity 0→1 + scale 0.98→1 | `duration-quick` · `ease-out` — dropdowns, popovers, menus |
| `motion-slide-up` | translateY 8px→0 + fade | `duration-base` · `ease-out` — toasts, list item enter |
| `motion-slide-inline` | translate inline-start 12px→0 + fade | `duration-base` · `ease-out` — panel/detail enter (RTL-aware) |
| `motion-modal` | scrim fade + dialog scale 0.97→1 + translateY 8px→0 | `duration-base` · `ease-out`; exit `duration-fast` · `ease-in` |
| `motion-drawer` | translate off-inline-edge → 0 | `duration-slow` · `ease-standard` (RTL-aware) |
| `motion-command` | scrim frost-in + panel scale 0.96→1 + translateY 10px→0 | `duration-quick` · `ease-emphasized` — the hero |
| `motion-collapse` | height/`grid-rows` 0→auto + fade | `duration-quick` · `ease-standard` — accordions, tree |
| `motion-tab` | Signal underline slides between tabs | `duration-quick` · `ease-in-out` |
| `motion-nav` | Signal indicator moves along sidebar edge | `duration-quick` · `ease-in-out` |
| `motion-row-enter` | new row fade + slight slide-up, staggered ≤5 items @ 20ms | `duration-base` · `ease-out` |

**Stagger:** only for small groups (≤ ~6 items), 20–30ms step. Never stagger long lists or tables
being paginated/filtered — they update instantly.

---

## 5. Micro-interactions

- **Buttons:** background to hover color in `duration-instant`; on press, `transform: scale(0.98)`
  for `duration-fast`. No bounce.
- **Inputs:** border to `border-focus` + focus ring fade-in over `duration-fast`.
- **Checkbox/Radio/Switch:** check draws / knob slides over `duration-fast` · `ease-out`.
- **Rows/Cards (interactive):** `surface-hover` fill on hover in `duration-instant`; a hairline
  `border-focus` on keyboard focus.
- **Tooltips:** fade in after ~400ms hover delay (`duration-fast`); out immediately.
- **Copy/confirm affordances:** icon swap (e.g. copy→check) with a quick `motion-fade-scale`.
- **Number changes** (totals, counters): may cross-fade the value; **never** roll/animate digits on
  load-bearing financial figures — correctness reads instantly (P6/P8).

---

## 6. AI motion (the Signal, thinking, streaming)

AI is the one place with a signature ambient motion — kept subtle and always violet.

- **Thinking / working:** the Signal line performs a slow left-to-right (reading-direction)
  luminance sweep, `duration-deliberate`+ loop, `ease-linear`, low amplitude. This is the *only*
  looping animation allowed in steady state, and it stops the instant the AI responds.
- **Streaming text:** tokens appear by `motion-fade` per chunk; no per-character typewriter jitter.
- **Proposed action reveal:** AI-proposed action cards enter with `motion-slide-up`; the human
  approval controls are always visible immediately (never animate the approval affordance in
  late).
- **Mode transition (Standard ↔ AI):** accent color cross-fades teal↔violet over `duration-base`;
  no layout thrash.

---

## 7. Loading & progress

- **Skeletons** for content whose shape is known (tables, cards, detail panes): a calm shimmer,
  `duration-deliberate` loop, `ease-linear`, low contrast (`surface-muted`→`surface-hover`).
- **Spinners** only for indeterminate, button-scoped, or small waits; use a single house spinner.
- **Progress bars** for determinate work (uploads, imports); `ease-linear`.
- **Optimistic UI:** apply the change immediately, animate it in, and reconcile/toast on
  failure — do not block the user behind a spinner for LAN-fast mutations.
- **Latency thresholds:** <100ms feels instant (no loader); 100–500ms use inline/button spinner;
  >500ms use skeletons or a progress affordance.

---

## 8. Reduced motion & low power

This is a requirement, not a nice-to-have.

Under `prefers-reduced-motion: reduce` (and any low-power/low-transparency signal):

- Replace all movement/scale with **instant or fade-only** transitions capped at `duration-fast`.
- **Disable** the Signal pulse/sweep, skeleton shimmer loop (show a static placeholder), any
  parallax, and all `backdrop-filter` frost (fall back to a solid `surface-backdrop`).
- Keep state color changes (they aid comprehension, not motion sickness).
- Never hide functionality or content behind motion; motion is always additive.
