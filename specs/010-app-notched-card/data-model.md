# Data Model: App Notched Card (010)

This feature is **presentational only**. There are no database tables, RPCs, caches, or persistent entities. The "data model" documents the widget's logical structure, layout inputs, and internal geometry state used during build.

## Public surface: `AppNotchedCard`

| Field | Type | Required | Notes |
| ----- | ---- | -------- | ----- |
| `body` | `Widget` | Yes | Main card content; maps to `AppCard.child` (FR-008) |
| `title` | `Widget?` | No | Top-leading header; same role as `AppCard.title` |
| `description` | `Widget?` | No | Between title and body; maps to `AppCard.description` / forui subtitle |
| `actions` | `List<Widget>?` | No | Caller-supplied controls rendered only in top cut-out shelf (FR-007) |

**Validation rules (compile-time / build-time)**:

- `body` MUST be provided (non-nullable constructor parameter).
- `actions` MAY be `null` or empty — card renders minimum notch width (edge case in spec).
- Callers MUST supply accessible semantics on action widgets; the card MUST NOT add semantics (FR-016).

**Relationships**:

- `AppNotchedCard` is a **sibling** of `AppCard`; no inheritance or shared mutable state.
- Action widgets MAY invoke feature logic (navigation, RPC calls) via their own callbacks; the card does not participate.

## Internal entity: `NotchGeometry`

Ephemeral values computed per layout pass (not stored across frames except as local variables / `State` fields).

| Field | Type | Derivation |
| ----- | ---- | ---------- |
| `cardSize` | `Size` | From parent constraints |
| `cornerRadius` | `double` | `context.shapeTokens.lg` (three standard corners) |
| `filletRadius` | `double` | Fixed constant `_kNotchFilletRadius` (FR-005) |
| `shelfDepth` | `double` | Fixed constant `_kNotchShelfDepth` (FR-005) |
| `notchWidth` | `double` | `clamp(minWidth, actionsIntrinsicWidth + padding, trailingAvailable)` (FR-006, FR-015) |
| `minNotchWidth` | `double` | Fixed constant when no actions (FR-006) |
| `horizontalPadding` | `double` | Fixed constant around action row |
| `shelfRect` | `Rect` | Horizontal segment at `shelfDepth` below main top; length = `notchWidth` on trailing side (LTR) |
| `outlinePath` | `Path` | Closed path for clip + border (FR-004, FR-013) |
| `isRtl` | `bool` | `Directionality.of(context)` (FR-010) |

## Internal entity: `CutOutRegion`

Logical region described in the feature spec; not a separate Dart class unless implementation clarity benefits.

| Attribute | Description |
| --------- | ----------- |
| Edge | Top-trailing in LTR; top-leading (trailing semantics) in RTL |
| Profile | Step-down: main top → entry fillet ↓ → shelf → exit fillet ↓ → trailing edge |
| Background | Screen/page background visible through recess and open top-trailing corner |
| Action layout | Horizontal row, `SpacingTokens.sm` between items, group centered in shelf |

## Internal entity: `ActionSlot`

| Attribute | Description |
| --------- | ----------- |
| Widgets | Ordered list from `actions` parameter |
| Layout | `Row(spacing: SpacingTokens.sm)` inside `PositionedDirectional` on shelf |
| Theming | Opaque — no wrapper, no theme override (FR-007) |
| Overflow | `ClipRect` at card bounds when width exceeds `notchWidth` cap (FR-015) |

## State transitions

Not applicable — stateless widget. Parent rebuilds when `title`, `description`, `body`, or `actions` change.

## Theme dependencies (read-only)

| Token | Usage |
| ----- | ----- |
| `semanticColors.card` | Fill |
| `semanticColors.border` | Outline stroke |
| `shapeTokens.lg` | Leading top, leading bottom, trailing bottom corner radii |
| `SpacingTokens.sm` | Inter-action gap (parity with `AppCard`) |
| `SpacingTokens.*` | Internal padding aligned with `FCard` / `AppCard` during implementation |

No writes to theme or persistent configuration.
