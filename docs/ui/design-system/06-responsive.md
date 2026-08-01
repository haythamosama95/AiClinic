# 06 — Responsive & Direction

AiClinic is **desktop-first** (Windows, clinic LAN) and must adapt gracefully to narrower windows
and secondary platforms — without becoming a different product. It must also be equally correct in
**LTR (English)** and **RTL (Arabic)**.

---

## 1. Philosophy

- Design at the **`xl` (≥1280px)** target first. This is where receptionists and clinicians work.
- **Adapt, don't redesign.** Smaller widths reflow and consolidate the *same* information
  architecture; they don't introduce a separate mobile app.
- **Never mobile-first** (constitution / product overview). Mobile is a supported secondary
  experience, not the design driver.
- Prioritize keyboard efficiency and information density at desktop sizes; prioritize touch targets
  and single-column flow at small sizes.

---

## 2. Breakpoints & behavior

| Range | Label | Shell & layout behavior |
|-------|-------|-------------------------|
| ≥1536 | `2xl` | Full shell; content capped for readability; master-detail side-by-side; wide tables full-width |
| 1280–1535 | `xl` (**primary**) | Full shell; expanded sidebar; master-detail; multi-pane workspace |
| 1024–1279 | `lg` | Sidebar collapses to icon rail by default; master-detail may become list→drawer; workspace panes reduce |
| 768–1023 | `md` | Sidebar becomes an overlay drawer (hamburger); single primary column; detail as drawer/modal; tables scroll horizontally or switch to stacked rows |
| 640–767 | `sm` | Single column; Top Bar condenses; filters collapse into a filter sheet; card lists replace wide tables |
| <640 | `xs` | Full single-column; bottom or overlay navigation; essential actions only; dialogs go full-screen |

Use logical, content-driven breakpoints (let components reflow when cramped) rather than
pixel-pedantry. Prefer container/`LayoutBuilder`-style responsiveness where a component's own width
should decide its layout.

---

## 3. Component adaptation rules

- **Sidebar:** expanded → icon rail (`lg`) → overlay drawer (`md` and below).
- **Tables:** wide tables → horizontal scroll with a sticky first column → **stacked "row cards"**
  (label:value pairs) on `sm`/`xs`. Keep numeric alignment and tabular figures.
- **Master–Detail:** side-by-side (`xl`/`lg`) → list with detail in a drawer/modal (`md` and
  below).
- **Toolbars/filters:** inline → wrap → collapse into a "Filters" sheet with a count badge.
- **Dialogs/Drawers:** centered/side → full-screen sheets on `xs`.
- **Metric rows:** N-across grid → 2-across → 1-across.
- **Command Bar:** always available; full-width sheet on small screens.
- **Calendar/Workspace:** multi-pane → tabbed/segmented views on smaller screens.

Touch targets: ≥28px at desktop density; **≥44px** on touch-sized layouts (`md` and below).

---

## 4. Direction (RTL / LTR)

Arabic is a first-class language for the target market. RTL is not an afterthought.

### Layout
- Set direction at the root (`dir="rtl"` / `TextDirection.rtl`), not per element.
- **Use logical properties everywhere** — `margin-inline-start/end`, `padding-inline`, `inset-inline`,
  `text-align: start/end`, `border-inline` — so layout mirrors automatically. Never hardcode
  left/right for layout.
- The whole shell mirrors: sidebar moves to the right, breadcrumbs and back-affordances reverse,
  drawers slide from the opposite edge, the Signal indicator sits on the inline-start edge (which
  is the right in RTL).

### Icons & motion
- **Mirror directional icons** (chevrons, arrows, back/forward, breadcrumb separators, send). **Do
  not mirror** non-directional icons (search, user, calendar, most glyphs) or logos.
- Directional motion (`motion-slide-inline`, drawers, tab underline) follows the reading direction
  automatically via logical properties.

### Typography & numbers
- Apply the Arabic font family (`IBM Plex Sans Arabic`) on `:lang(ar)`/`[dir="rtl"]`; **do not**
  rely on Latin→Arabic font fallback (rhythm mismatch).
- Arabic body `line-height` ≥ 1.7 (more than Latin); **never** apply negative/large letter-spacing
  to Arabic (it breaks glyph joins).
- Use **Western Arabic digits (0–9)** across all surfaces (dashboard convention); keep them
  tabular.
- **Bidi safety:** wrap Latin runs inside Arabic text (product names, codes, versions, IDs) with
  proper isolation so they don't visually reorder. Currency and dates format per locale but keep
  numeric alignment.

### Testing
- Every screen is reviewed in both directions and both themes. A layout is not "done" until it is
  correct in RTL.
