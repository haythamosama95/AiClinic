# 02 — Design Tokens

Every value the UI is allowed to use. Encodes the direction from `01-foundation.md`. Nothing in a
feature should use a color, size, radius, shadow, or duration that is not derived from a token
here.

---

## 1. Token architecture (three tiers)

We use the standard 2026 three-tier model. Follow it strictly — it is what makes light/dark
theming and any future rebrand a token swap instead of a rewrite.

1. **Primitive tokens** — raw values (`--color-teal-600: #0B7075`, `--space-4: 16px`). Never
   consumed directly by components. The palette laboratory.
2. **Semantic tokens** — intent, mapped to primitives (`--surface-action: var(--color-teal-600)`,
   `--text-primary`, `--border-default`). **This is the layer components consume.** Light and dark
   themes differ *only* here.
3. **Component tokens** — sparing, component-scoped overrides (`--button-primary-bg`,
   `--sidebar-width`). Used only when a component genuinely needs a hook beyond the semantic set.

**Rule:** components reference semantic (and occasionally component) tokens — never primitives.
Naming taxonomy: `category-role-variant` (e.g. `text-status-danger`, `surface-raised`).

Values below are the canonical source. A `tokens.json` (W3C DTCG-shaped) mirroring this document
should be generated during the reference build so both web and Flutter consume one source.

---

## 2. Color — primitives

Cool-slate neutrals so data is the loudest thing on screen; one teal for the deterministic
product, one violet for AI, and a tight semantic status set.

### Neutrals (cool slate)

| Token | Hex | Typical use |
|-------|-----|-------------|
| `neutral-0` | `#FFFFFF` | pure white surface |
| `neutral-25` | `#FAFBFC` | app canvas (light) |
| `neutral-50` | `#F4F6F9` | muted canvas / hover fill |
| `neutral-100` | `#ECEFF3` | subtle fill, table stripes |
| `neutral-150` | `#E2E7EE` | hairline borders |
| `neutral-200` | `#D5DCE5` | default borders |
| `neutral-300` | `#C0C9D4` | strong borders, disabled fill |
| `neutral-400` | `#9AA6B4` | placeholder, disabled text |
| `neutral-500` | `#75828F` | tertiary text, icons-muted |
| `neutral-600` | `#55606D` | secondary text |
| `neutral-700` | `#3C4652` | body text (dark-on-light alt) |
| `neutral-800` | `#28303A` | headings on light |
| `neutral-900` | `#1A2029` | primary ink |
| `neutral-950` | `#0E1116` | app canvas (dark) |

### Teal — "Vital" (deterministic primary)

| Token | Hex |
|-------|-----|
| `teal-50` | `#E6F7F7` |
| `teal-100` | `#C4ECEC` |
| `teal-200` | `#93DBDC` |
| `teal-300` | `#5BC4C6` |
| `teal-400` | `#2BA7AB` |
| `teal-500` | `#0E8A8F` |
| `teal-600` | `#0B7075` |
| `teal-700` | `#0A5B5F` |
| `teal-800` | `#0A494C` |
| `teal-900` | `#093B3E` |

### Violet — "Synapse" (AI layer)

| Token | Hex |
|-------|-----|
| `violet-50` | `#EEEBFE` |
| `violet-100` | `#DAD4FC` |
| `violet-200` | `#BBB0F9` |
| `violet-300` | `#9A8BF4` |
| `violet-400` | `#7D6BEE` |
| `violet-500` | `#6A54E6` |
| `violet-600` | `#573FD1` |
| `violet-700` | `#4632AB` |
| `violet-800` | `#382889` |
| `violet-900` | `#2C1F6B` |

### Status — Success / Warning / Danger / Info

| Token | Hex | | Token | Hex |
|-------|-----|--|-------|-----|
| `green-50` | `#E7F6ED` | | `amber-50` | `#FBF1DF` |
| `green-100` | `#C6E9D2` | | `amber-100` | `#F6E0B8` |
| `green-500` | `#1F9D57` | | `amber-500` | `#C77F0A` |
| `green-600` | `#167E45` | | `amber-600` | `#A5650A` |
| `green-700` | `#0F5E34` | | `amber-700` | `#855009` |
| `red-50` | `#FBECEC` | | `blue-50` | `#E8F0FE` |
| `red-100` | `#F6CFCF` | | `blue-100` | `#C7DBFB` |
| `red-500` | `#D64545` | | `blue-500` | `#2D7FF9` |
| `red-600` | `#BC3333` | | `blue-600` | `#1C63D6` |
| `red-700` | `#9A2828` | | `blue-700` | `#164FAB` |

---

## 3. Color — semantic tokens (light + dark)

Components use these. Dark values are the only thing that changes between themes.

### Surfaces & background

| Semantic token | Light | Dark | Use |
|----------------|-------|------|-----|
| `surface-canvas` | `neutral-25` | `neutral-950` | app background |
| `surface-default` | `neutral-0` | `#161B22` | cards, panels |
| `surface-raised` | `neutral-0` | `#1C232C` | popovers, dropdowns, modals |
| `surface-sunken` | `neutral-50` | `#0B0E13` | wells, code blocks, insets |
| `surface-muted` | `neutral-100` | `#222A34` | hover fills, table stripes |
| `surface-hover` | `neutral-50` | `#20272F` | row/control hover |
| `surface-selected` | `teal-50` | `#0E2B2C` | selected row/item |
| `surface-backdrop` | `rgba(16,21,28,.45)` | `rgba(3,6,10,.60)` | modal scrim |
| `surface-ai` | `violet-50` | `#1B1638` | AI panels/message ground |

### Text & icon

| Semantic token | Light | Dark |
|----------------|-------|------|
| `text-primary` | `neutral-900` | `#E6EBF2` |
| `text-secondary` | `neutral-600` | `#A9B4C0` |
| `text-tertiary` | `neutral-500` | `#7C8896` |
| `text-placeholder` | `neutral-400` | `#5C6773` |
| `text-disabled` | `neutral-400` | `#4E5866` |
| `text-inverse` | `neutral-0` | `neutral-900` |
| `text-link` | `teal-700` | `teal-300` |
| `text-ai` | `violet-700` | `violet-300` |
| `icon-default` | `neutral-600` | `#A9B4C0` |
| `icon-muted` | `neutral-400` | `#6B7684` |

### Borders & dividers

| Semantic token | Light | Dark |
|----------------|-------|------|
| `border-subtle` | `neutral-150` | `#232B35` |
| `border-default` | `neutral-200` | `#2C3542` |
| `border-strong` | `neutral-300` | `#3A4553` |
| `border-focus` | `teal-500` | `teal-400` |
| `border-ai` | `violet-400` | `violet-400` |

### Action (interactive) — deterministic = teal

| Semantic token | Light | Dark |
|----------------|-------|------|
| `action-primary` | `teal-600` | `teal-500` |
| `action-primary-hover` | `teal-700` | `teal-400` |
| `action-primary-active` | `teal-800` | `teal-300` |
| `action-primary-fg` | `neutral-0` | `neutral-950` |
| `action-secondary` | `surface-default` | `surface-raised` |
| `action-secondary-fg` | `text-primary` | `text-primary` |
| `action-subtle-hover` | `neutral-50` | `#20272F` |
| `action-disabled-bg` | `neutral-100` | `#20272F` |
| `focus-ring` | `teal-500 @ 45%` | `teal-400 @ 55%` |

### AI action — violet

| Semantic token | Light | Dark |
|----------------|-------|------|
| `action-ai` | `violet-600` | `violet-500` |
| `action-ai-hover` | `violet-700` | `violet-400` |
| `action-ai-fg` | `neutral-0` | `neutral-950` |
| `focus-ring-ai` | `violet-500 @ 45%` | `violet-400 @ 55%` |

### Status (foreground / background / border trios)

Each status has a `-fg` (text/icon on quiet ground), `-surface` (tint background), and `-border`.
Solid variants for badges use the `-500/600` primitive with `text-inverse`.

| Status | `-fg` (light / dark) | `-surface` (light / dark) | `-border` (light / dark) |
|--------|----------------------|---------------------------|--------------------------|
| success | `green-700` / `#5FD495` | `green-50` / `#0E2A1B` | `green-100` / `#1C4230` |
| warning | `amber-700` / `#E9B45A` | `amber-50` / `#2E2109` | `amber-100` / `#4A3712` |
| danger | `red-700` / `#F08A8A` | `red-50` / `#2E1414` | `red-100` / `#4A2323` |
| info | `blue-700` / `#7FB0FB` | `blue-50` / `#0F1F3A` | `blue-100` / `#1E355C` |

**Domain status mapping** (use consistently across the app):
- Paid / Active / Confirmed / Completed / Present → **success**
- Pending / Partially paid / Scheduled / Draft → **warning** (or neutral for Draft)
- Overdue / Cancelled / Inactive / No-show / Error → **danger**
- Informational / In progress / New → **info**

---

## 4. Typography

### Font families

| Role | Family (with fallbacks) | Notes |
|------|-------------------------|-------|
| `font-sans` (UI/body) | `"Inter", system-ui, sans-serif` | default everywhere; enable `font-feature-settings: "cv05","ss01"` for a cleaner grotesque; `tabular-nums` on data |
| `font-display` (headings, big numbers) | `"Geist", "Inter", sans-serif` | confident, technical; weights 500–700 |
| `font-mono` (IDs, code, shortcuts, raw AI output) | `"Geist Mono", "JetBrains Mono", monospace` | technical/data contexts only |
| `font-arabic` | `"IBM Plex Sans Arabic", sans-serif` | applied on `:lang(ar)` / `[dir="rtl"]`; see `06`/`07` |

Do **not** fall back Latin→Arabic in one family list (produces vertical-rhythm mismatch). Set the
Arabic family explicitly per language. Ship weights 300/400/500/700 for Arabic.

### Type scale

Base body is **14px** (dense desktop). All values `size / line-height`.

| Token | Size / Line | Weight | Family | Use |
|-------|-------------|--------|--------|-----|
| `text-display-lg` | 32 / 40 | 600 | display | hero numbers, marketing-scale |
| `text-display` | 28 / 36 | 600 | display | page hero, large metrics |
| `text-h1` | 24 / 32 | 600 | display | page title |
| `text-h2` | 20 / 28 | 600 | display | section title |
| `text-h3` | 18 / 26 | 600 | display/sans | subsection, card title |
| `text-title` | 16 / 24 | 600 | sans | dialog title, list header |
| `text-body-lg` | 15 / 24 | 400 | sans | emphasis body |
| `text-body` | 14 / 22 | 400 | sans | **default** |
| `text-body-strong` | 14 / 22 | 500 | sans | labels, emphasized cells |
| `text-body-sm` | 13 / 20 | 400 | sans | dense tables, secondary |
| `text-caption` | 12 / 16 | 400 | sans | metadata, helper text |
| `text-overline` | 11 / 16 | 600 | sans | section eyebrows, `+0.06em`, uppercase |
| `text-mono` | 13 / 20 | 400 | mono | IDs, amounts-as-code, shortcuts |

**Weights:** `400` regular · `500` medium · `600` semibold · `700` bold. Avoid `<400` and `>700`.
**Tracking:** default `0`; `-0.01em` for `text-display*`/`text-h1`; `+0.06em` only on `text-overline`.
Never apply negative tracking to Arabic.
**Numerals:** `font-variant-numeric: tabular-nums` on all tables, money, counts, times, and metrics.
Use **Western Arabic digits (0–9)** by default across all surfaces (dashboard convention).

---

## 5. Spacing

4px base unit. Use logical properties (`margin-inline`, `padding-block`) so RTL mirrors for free.

| Token | px | Token | px |
|-------|----|-------|----|
| `space-0` | 0 | `space-5` | 20 |
| `space-px` | 1 | `space-6` | 24 |
| `space-0.5` | 2 | `space-8` | 32 |
| `space-1` | 4 | `space-10` | 40 |
| `space-2` | 8 | `space-12` | 48 |
| `space-3` | 12 | `space-16` | 64 |
| `space-4` | 16 | `space-20` | 80 |
| | | `space-24` | 96 |

**Density guidance:** control inner padding `space-2`–`space-3`; card padding `space-4`–`space-6`;
page gutters `space-6`–`space-8`; section gaps `space-8`–`space-12`. Dense table rows target
36–40px height; comfortable rows 44–48px (see `05`).

---

## 6. Radius

| Token | px | Use |
|-------|----|-----|
| `radius-none` | 0 | full-bleed dividers only |
| `radius-sm` | 4 | chips, tags, small badges, checkboxes |
| `radius-md` | 6 | **controls** (buttons, inputs, selects) |
| `radius-lg` | 8 | cards, popovers, menus |
| `radius-xl` | 12 | modals, large panels, AI message bubbles |
| `radius-2xl` | 16 | feature/marketing surfaces (rare) |
| `radius-full` | 9999 | avatars, pills, toggle knobs, status dots |

Never zero-radius the whole UI (harsh, off-brand) and never pill-everything. Controls = `md`,
containers = `lg`.

---

## 7. Elevation (shadows)

Kept intentionally cheap for low-end hardware (P10). Elevation is border + a soft shadow, not glow.
In dark theme, elevation is carried mostly by a lighter `surface-*` plus a subtler shadow.

| Token | Light value | Use |
|-------|-------------|-----|
| `elevation-0` | none (rely on `border-subtle`) | flat cards, table |
| `elevation-1` | `0 1px 2px rgba(16,21,28,.06), 0 1px 1px rgba(16,21,28,.04)` | resting cards, sticky header |
| `elevation-2` | `0 4px 12px rgba(16,21,28,.10)` | dropdowns, popovers, tooltips |
| `elevation-3` | `0 12px 32px rgba(16,21,28,.16)` | modals, Command Bar |

Dark theme: reduce alpha ~40% and lean on surface contrast (`elevation-2` →
`0 4px 14px rgba(0,0,0,.45)`).

**Frost (restrained):** only transient full-screen overlays (Command Bar backdrop, modal scrim)
may use `backdrop-blur: 8px` behind `surface-backdrop`. Never on always-on chrome. Disable blur
under `prefers-reduced-transparency` / low-power (see `03`).

---

## 8. Borders & focus

| Token | Value |
|-------|-------|
| `border-width-hairline` | 1px |
| `border-width-emphasis` | 1.5px |
| `border-width-heavy` | 2px |
| `focus-ring-width` | 2px |
| `focus-ring-offset` | 2px |
| `focus-ring-style` | `2px solid focus-ring` + `2px` offset (violet variant on AI surfaces) |

Focus is **always** visible via the ring (never removed). Inputs additionally show
`border-focus`. See `07`.

---

## 9. The Signal (signature) tokens

The one memorable motif from `01`. It is a thin luminous line/indicator.

| Token | Value | Use |
|-------|-------|-----|
| `signal-thickness` | 2px (3px on hero) | thickness of the line |
| `signal-color` | `action-primary` (teal) | standard mode |
| `signal-color-ai` | `action-ai` (violet) | AI mode |
| `signal-glow` | `0 0 0 transparent` → soft `0 0 8px color @ 35%` on active | subtle, optional; drop on reduced-motion/low-power |
| `signal-radius` | `radius-full` | rounded line caps |

Appears **only** as: the active nav indicator (inline-start edge), the Command Bar focus accent,
and the AI "thinking" pulse. Nowhere else.

---

## 10. Z-index

| Token | Value |
|-------|-------|
| `z-base` | 0 |
| `z-dropdown` | 1000 |
| `z-sticky` | 1100 |
| `z-backdrop` | 1200 |
| `z-modal` | 1300 |
| `z-popover` | 1400 |
| `z-toast` | 1500 |
| `z-tooltip` | 1600 |
| `z-command` | 1700 |

---

## 11. Iconography

- **Library:** Lucide (matches the web stack; consistent 1.5px stroke, geometric, calm).
- **Sizes:** `icon-sm` 16 · `icon-md` 20 (default, aligns with 14px text) · `icon-lg` 24 ·
  `icon-xl` 32 (empty states / feature).
- **Stroke:** 1.5px at all sizes; do not mix stroke weights.
- **Color:** `icon-default` / `icon-muted`; status icons take the status `-fg`; AI icons take
  `text-ai`.
- **Alignment:** optically center with text; never let an icon be the only affordance for a
  critical action without a label or tooltip.

---

## 12. Breakpoints (summary — full rules in `06`)

Desktop-first. Primary design target is `xl` (≥1280). Below that we adapt, not redesign.

| Token | Min width | Context |
|-------|-----------|---------|
| `bp-sm` | 640 | large phone |
| `bp-md` | 768 | tablet portrait |
| `bp-lg` | 1024 | tablet landscape / small laptop |
| `bp-xl` | 1280 | **primary desktop target** |
| `bp-2xl` | 1536 | large desktop |
