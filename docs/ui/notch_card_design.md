# App Notched Card Specification

Design a reusable Flutter widget named **AppNotchedCard**. The widget should visually match the existing AppCard used throughout the project while introducing a custom step-down cut-out in the top-trailing corner (top-right in LTR) that can host one or more floating action widgets.

The implementation should prioritize simplicity, maintainability, rendering performance, and consistency with the existing UI components.

**Visual reference**: The authoritative notch shape and action placement are defined by the reference screenshot stored at `docs/ui/assets/notch_card_reference.png` (top-trailing step-down cut-out with caller-supplied actions floating in the recessed area). Only the cut-out geometry and floating actions in that image apply — not surrounding card content such as titles, charts, or metrics.

---

# Overall Structure

The widget consists of two conceptual layers:

1. **Background Card**
  - Responsible for rendering the card shape, border, background, elevation, and clipping.
  - Contains a custom step-down cut-out along the top-trailing edge.
2. **Actions Layer**
  - One or more widgets supplied by the caller.
  - Positioned above the card using a `Stack`.
  - Although implemented as floating widgets, they must visually sit inside the cut-out recess against the screen background visible through the notch.

The overall hierarchy should resemble:

```text
Stack
 ├── Notched Card
 └── Positioned Actions (floating in cut-out)
```

---

# Card Shape

The widget should be identical to the existing AppCard except for the top-trailing corner.

Requirements:

- The top-trailing corner is replaced by a custom step-down cut-out.
- The remaining three corners must match AppCard exactly.
- Background color, border, elevation, shadows, padding, and styling must remain consistent with AppCard.
- The border must precisely follow the clipped shape, including the cut-out.
- There must be no visible gaps, overlaps, or mismatched radii between clipping and border rendering.

---

# Notch Geometry

The cut-out exists only along the top-trailing edge (top-right in LTR).

The notch is a **step-down recession** — a recessed horizontal shelf lower than the main top edge, with smooth rounded transitions at both ends. The page background is visible through the cut-out; actions float in this open area.

The clipped outline path, traced from the leading top corner toward the trailing edge, consists of:

1. **Main top edge** — horizontal segment at the card's normal top elevation from the leading corner until the cut-out begins.
2. **Entry fillet** — a smooth concave rounded curve that transitions downward from the main top edge to the notch shelf.
3. **Notch shelf** — a horizontal segment at a fixed depth below the main top edge; its length expands or contracts based on supplied actions (plus internal padding).
4. **Exit fillet** — a smooth concave rounded curve that transitions **downward** from the notch shelf to meet the trailing vertical edge.
5. **Trailing edge** — the card's normal vertical edge continues downward from the exit fillet to the bottom-trailing corner. The trailing edge does **not** start at the main top elevation; the top-trailing corner remains open so page background is visible along the upper trailing side above the exit fillet.

Both fillets curve downward (entry: main top → shelf; exit: shelf → trailing edge).

Both fillet transitions (entry and exit) MUST share one fixed corner radius. That radius and the notch shelf depth are internal implementation constants and are **not configurable** by callers.

If any written description conflicts with the reference screenshot, **the reference screenshot prevails** for cut-out shape and action placement.

---

# Notch Dimensions

Requirements:

- **Width**: Computed from the intrinsic width of supplied actions, inter-action gaps, and fixed horizontal padding; subject to a defined minimum width when no actions are supplied and a maximum of available trailing horizontal space within the card.
- **Depth**: Fixed internal constant (vertical drop from main top edge to notch shelf); not configurable by callers.
- The horizontal shelf segment automatically expands or contracts based on the supplied actions.
- When no actions are supplied, the cut-out retains a minimum width that preserves the intended visual design.
- Internal padding must ensure that actions never touch the cut-out border.

---

# Actions

The widget accepts one or more action widgets.

Requirements:

- Actions are inserted exactly as supplied by the caller.
- The widget must not modify, wrap, or style the actions.
- Actions float in the cut-out recess on a layer above the card (Stack).
- Actions are laid out in a horizontal row and centered as a group within the cut-out (horizontally and vertically within the shelf area).
- The cut-out width adapts to fit the supplied actions.
- Any number of actions should be supported, provided sufficient horizontal space exists.

---

# Card Content

The card contains content regions matching AppCard.

## Title

- Positioned near the top-leading corner.
- Vertically aligned with the main top edge / notch region.
- Uses the same typography and styling as AppCard.

## Description (optional)

- Positioned between title and body when supplied.
- Uses the same typography and styling as AppCard subtitle.

## Body

- Positioned below the title (and description when present).
- Supplied entirely by the caller.
- Required parameter; the widget imposes no restrictions on the body's layout.

---

# Layout Behavior

The widget should behave identically to AppCard with respect to:

- Width constraints.
- Height behavior.
- Internal padding.
- Margins.
- Intrinsic sizing.
- Responsiveness.

The cut-out must not alter the overall sizing behavior of the card.

The title, description, and body must never overlap the cut-out or the floating action widgets. The widget shall reserve sufficient horizontal space for the cut-out automatically.

---

# Clipping

The clipping implementation should:

- Produce a smooth continuous path.
- Avoid unnecessary path operations.
- Reuse the same path for clipping and border rendering whenever practical.
- Minimize anti-aliasing artifacts.

---

# Public API

The widget should expose only the following configurable properties:

- `title` (optional)
- `description` (optional)
- `body` (required)
- `actions` (optional)

The following are implementation details and must not be externally configurable:

- Cut-out geometry.
- Fillet radius.
- Notch shelf depth.
- Internal notch padding.
- Border styling.

---

# RTL Support

If the application is running in a right-to-left layout:

- The cut-out should automatically move to the trailing edge.
- In RTL layouts this places the cut-out along the top-leading corner.
- The remainder of the layout should mirror naturally.

---

# Implementation Requirements

1. Prioritize simplicity over excessive abstraction.
2. Avoid unnecessary widget nesting.
3. Minimize layout and repaint work.
4. Keep the implementation easy to understand and maintain.
5. Follow the existing architecture and conventions used by AppCard.
6. The cut-out should scale naturally across different screen sizes while preserving its proportions.
7. The same geometric path should be used for clipping and border rendering whenever possible to ensure perfect visual alignment.
