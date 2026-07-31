# Contract: AppNotchedCard Widget (010)

UI component contract for the shared design-system notched card. No network, RPC, or storage interfaces.

**Implementation**: `frontend/lib/core/ui/widgets/layouts/app_notched_card.dart`
**Baseline reference**: `AppCard` (`frontend/lib/core/ui/widgets/layouts/app_card.dart`)
**Visual authority**: `docs/ui/notch_card_design.md`, `docs/ui/assets/notch_card_reference.png`

---

## Constructor

```dart
const AppNotchedCard({
  required Widget body,
  Widget? title,
  Widget? description,
  List<Widget>? actions,
  Key? key,
});
```

| Parameter | Required | Behavior |
| --------- | -------- | -------- |
| `body` | Yes | Rendered below title/description with standard card body padding |
| `title` | No | Omitted → no header title region |
| `description` | No | Omitted → title flows directly to body (matches `AppCard`) |
| `actions` | No | `null` or `[]` → minimum notch width; no bottom action row |

**Not configurable** (implementation details): fillet radius, shelf depth, notch min/max logic constants, border width, internal notch padding values, clip path parameters.

---

## Layout contract

### Card chrome

- Fill: `semanticColors.card`
- Border: 1 logical px `semanticColors.border` following full outline including notch
- Corner radius `shapeTokens.lg` on: leading-top, leading-bottom, trailing-bottom
- Top-trailing (LTR): step-down cut-out per FR-004; open corner above exit fillet

### Header / body

- Title: top-leading, vertically aligned with main top edge region
- Description: between title and body when present; subtitle styling parity with `AppCard`
- Body: required; caller controls internal layout
- Trailing horizontal space reserved for notch width so title/description do not overlap cut-out (LTR: reserve trailing; RTL: mirrored)

### Actions

- Rendered **only** in top cut-out shelf, never in a bottom row
- `Row` with `spacing: SpacingTokens.sm` when multiple actions
- Group centered horizontally and vertically within shelf
- Caller widgets rendered without modification or re-theming
- Overflow clipped at card bounding rect when actions wider than available trailing space

### Sizing

- Width/height/intrinsic behavior matches `AppCard` for equivalent child content
- Cut-out is a visual recession; MUST NOT add external margin changing card footprint (FR-012)

### Directionality

- LTR: cut-out on physical top-right (trailing)
- RTL: cut-out on physical top-left (trailing in reading direction)
- Automatic via ambient `Directionality`; callers MUST NOT pass edge overrides

---

## Semantics contract

- The widget MUST NOT introduce semantics nodes for the action region
- The widget MUST NOT merge or exclude child action semantics
- Callers MUST provide labels on interactive actions (e.g. `AppIconButton`)

---

## Integration points

| Consumer | Usage |
| -------- | ----- |
| Feature screens | `import` via `package:ai_clinic/core/ui/widgets/widgets.dart` |
| Theme showcase | Demo section with title, description, body, 1–3 representative actions |
| Tests | Widget tests assert layout bounds and RTL mirroring |

**Out of scope**: replacing existing `AppCard` Usages in features; migration is a separate feature.

---

## Visual acceptance checklist

Use for manual QA and optional golden baselines:

1. Side-by-side with `AppCard`: three corners, border, background, title/description typography match
2. Entry and exit fillets curve **downward**; top-trailing corner open
3. Actions float in recess with padding on all sides
4. Narrow width: actions clip at card edge, not mid-notch
5. RTL: notch and actions mirror to leading top corner

---

## Error / failure modes

| Condition | Behavior |
| --------- | -------- |
| Network / backend unavailable | N/A — local widget |
| AI unavailable | N/A |
| Action callback throws | Feature-level handling; card unaffected |
| Unbounded width parent | Same constraint rules as `AppCard` / `FCard` |
