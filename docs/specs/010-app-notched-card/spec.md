# Feature Specification: App Notched Card

**Feature Branch**: `010-app-notched-card`

**Created**: 2026-06-26

**Status**: Draft

**Input**: User description: "Read docs/ui/notch_card_design.md and come up with a specification according to the best practices of Flutter"

**Update 2026-06-26**: Correct exit fillet geometry — exit fillet curves **downward** from shelf to trailing edge; top-trailing corner remains open (trailing edge does not start at main top elevation).

**Design reference**: Authoritative visual and geometric details live in [docs/ui/notch_card_design.md](../../docs/ui/notch_card_design.md) and the reference screenshot at [docs/ui/assets/notch_card_reference.png](../../docs/ui/assets/notch_card_reference.png). Only the **top-trailing step-down cut-out shape** and **caller-supplied actions floating in the cut-out** are taken from the reference image — not surrounding card content (titles, charts, metrics, etc.). Where this spec summarizes geometry, the design document and reference image prevail.

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

Clinic screens rely on a consistent card pattern for grouping related information (metrics, forms, lists, and actions). The existing standard card (`AppCard`) places optional actions in a row at the **bottom** of the card body. The notched card variant moves those actions into a dedicated **step-down cut-out** along the **top-trailing edge** (top-right in LTR) so controls float in the recessed area beside the header without consuming vertical space below the content.

This feature delivers a reusable **App Notched Card** for the application design system. Feature developers can supply a title, optional description, free-form body content, and caller-provided action widgets for the **top-corner cut-out only**; end users see a polished card where actions appear floating inside the top-trailing recess against the screen background visible through the cut-out — not at the card bottom. The component must behave like the standard card for sizing, padding, and responsiveness so screens can adopt it without layout regressions.

Scope is limited to the shared UI component and its showcase/documentation. Migrating existing screens from the standard card to the notched variant is out of scope unless explicitly requested in a follow-up feature.

## Clarifications

### Session 2026-06-26

- Q: Should App Notched Card include a separate optional description/subtitle between title and body (matching AppCard), or keep title + body only? → A: Match AppCard fully — `title`, optional `description`/`subtitle`, `body` (main content), and notch `actions`.
- Q: When `actions` contains multiple widgets, how should the card arrange them inside the notch? → A: Horizontal row with the same inter-action spacing as `AppCard` (`SpacingTokens.sm`).
- Q: When actions exceed available trailing width, what should happen? → A: The **top-trailing** cut-out (top-right in LTR) expands to the maximum available trailing horizontal space up to the card edge; any actions still wider are clipped at the card boundary. Actions are never placed at the card bottom — unlike `AppCard`, all actions live only in the top-corner cut-out.
- Q: Should `body` be required or optional? → A: **Required** — maps to `AppCard.child`; callers must always supply main content.
- Q: Should the card add accessibility grouping for the notch action region? → A: **No** — callers are fully responsible for action accessibility semantics; the card adds no wrapper semantics.
- Q: What is the correct notch cut-out geometry? → A: **Step-down recession** per reference image — main top edge, entry fillet curving down to a horizontal shelf, exit fillet curving down to the trailing vertical edge; actions float in the recess on a layer above the card. Replaces earlier three-arc S-curve description.
- Q: Which direction does the exit fillet curve? → A: **Downward** — from the notch shelf onto the trailing vertical edge. The trailing edge does **not** begin at the main top elevation; the top-trailing corner remains open so screen background is visible along the upper trailing side above the exit fillet. Both entry and exit fillets curve downward (entry: main top → shelf; exit: shelf → trailing edge).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Display a Notched Card with Title, Description, and Body (Priority: P1)

As a clinic staff member viewing a dashboard or detail screen, I see information presented in a card that matches the application's existing card styling, with a title at the top-leading area, an optional description beneath it, and main content below, so the interface feels consistent and scannable.

**Why this priority**: The baseline card experience must work before actions or cut-out geometry add complexity. Without title/description/body layout parity with the standard card, the component cannot ship.

**Independent Test**: Render a notched card with title, optional description, and body (no actions). Verify visual parity with the standard card on the three non-notched corners, background, border, elevation, padding, and typography; confirm the cut-out area shows the minimum designed width without overlapping title, description, or body.

**Acceptance Scenarios**:

1. **Given** a notched card with a title and body, **When** it is displayed on a typical clinic screen width, **Then** the title appears near the top-leading corner, vertically aligned with the main top edge / cut-out region, using the same typography as the standard card title.
2. **Given** a notched card with an optional description supplied, **When** rendered, **Then** the description appears between the title and body using the same typography and styling as the standard card subtitle (`AppCard.description`).
3. **Given** a notched card with body content of arbitrary height, **When** rendered, **Then** the body appears below the title (and description when present) with the same internal padding and width behavior as the standard card main content area.
4. **Given** a notched card compared side-by-side with a standard card (same title, description, and body), **When** viewed on LTR layout, **Then** the three non-notched corners, border weight, background, shadow/elevation, and overall card dimensions match except for the top-trailing step-down cut-out.
5. **Given** no actions supplied, **When** the card renders, **Then** the cut-out retains a minimum width that preserves the intended visual design and does not collapse or disappear.

---

### User Story 2 - Float Caller-Supplied Actions in the Cut-Out (Priority: P1)

As a clinic staff member, I see action controls (dropdowns, icon buttons, menus) floating inside a step-down cut-out along the **top-trailing edge** of the card (top-right in LTR), against the screen background visible through the recess, so I can act on the card's context from the header area without looking to the bottom of the card.

**Why this priority**: The cut-out and floating actions layer are the distinguishing value of this component; they must work together on day one.

**Independent Test**: Render a notched card with one or more caller-supplied action widgets (e.g., a filter dropdown and an overflow icon button). Verify actions float centered within the cut-out shelf, the cut-out width grows to fit them with fixed internal padding, and title, description, and body never overlap the cut-out or actions.

**Acceptance Scenarios**:

1. **Given** a single action widget supplied by the caller, **When** the card renders, **Then** the action floats inside the top-trailing cut-out recess, centered within the shelf area (horizontally and vertically), and is not modified or re-styled by the card.
2. **Given** multiple action widgets supplied in order, **When** the card renders, **Then** all actions appear in a horizontal row inside the cut-out with the same inter-action spacing as `AppCard` (`SpacingTokens.sm`), centered as a group within the shelf; the cut-out width expands to accommodate their combined intrinsic width, inter-action gaps, and fixed horizontal padding.
3. **Given** actions whose combined width (including gaps and padding) exceeds the available trailing horizontal space, **When** the card is laid out in a constrained container, **Then** the top-trailing cut-out expands only up to the maximum trailing width available within the card edge; title, description, and body reserve space and never draw under the cut-out; any portion of the action row still exceeding that width is clipped at the card boundary (no bottom action row, no scroll inside the cut-out).
4. **Given** actions supplied, **When** inspecting the cut-out, **Then** internal padding ensures actions never touch the cut-out border line and appear to float against the background visible through the recess.
5. **Given** a notched card rendered in LTR, **When** inspecting the top-trailing outline, **Then** the exit fillet curves downward from the shelf to the trailing edge, the trailing edge begins below the main top elevation, and the open top-trailing corner shows screen background above the exit fillet.

---

### User Story 3 - RTL Layout (Priority: P2)

As a clinic staff member using the application in a right-to-left locale, I see the cut-out and floating actions on the top-leading edge (mirrored from LTR), so the card layout respects reading direction without manual per-screen adjustments.

**Why this priority**: The application supports international clinics; trailing-edge semantics must flip automatically for layout correctness.

**Independent Test**: Wrap a notched card with actions in an RTL directionality context. Verify the cut-out moves to the top-leading corner, title remains on the leading side, and the card mirrors naturally.

**Acceptance Scenarios**:

1. **Given** an RTL layout direction, **When** a notched card with actions renders, **Then** the cut-out appears on the top-leading corner (trailing edge in RTL) and actions remain centered within the shelf.
2. **Given** an RTL layout, **When** compared to an LTR rendering of the same card, **Then** horizontal layout mirrors appropriately while vertical spacing and non-notched corner radii remain consistent with the standard card.

---

### User Story 4 - Adopt the Component in Feature Screens (Priority: P3)

As a feature developer building clinic UI, I can add a notched card to a screen by supplying required `body`, optional `title` and `description`, and optional cut-out `actions`, without configuring cut-out geometry or card chrome, so integration stays simple and consistent with other design-system widgets.

**Why this priority**: Developer ergonomics ensure long-term maintainability and prevent one-off cut-out implementations across features.

**Independent Test**: Add the component to the theme showcase (or equivalent design-system demo) with representative title, description, body, and actions. Confirm the public surface exposes only title, description, body, and actions.

**Acceptance Scenarios**:

1. **Given** a developer integrating the component, **When** they consult the public API, **Then** `body` is required and `title`, `description`, and `actions` are optional; cut-out dimensions, fillet radius, shelf depth, border styling, and internal padding are not exposed.
2. **Given** actions passed as opaque widgets, **When** integrated, **Then** the card does not re-theme or restyle those widgets; it may arrange multiple actions in a horizontal row with standard design-system spacing and position the group within the cut-out; callers remain responsible for per-action accessibility labels and semantics.

---

### Edge Cases

- What happens when `actions` is null or an empty list? The card renders with the minimum cut-out width; title, description, and body layout remain correct.
- What happens when the title is very long? Title text follows the same wrapping/overflow behavior as the standard card; reserved cut-out width prevents overlap with the cut-out region.
- What happens when `description` is null or omitted? The layout collapses to title directly above body, matching standard card behavior when no subtitle is provided.
- What happens when body content is a zero-size widget (e.g., `SizedBox.shrink()`)? The card still satisfies the required `body` parameter and collapses to title (+ description when present) with minimum body area consistent with standard card empty-child behavior.
- What happens on very narrow viewports? Card respects parent width constraints; the top-trailing cut-out caps at available trailing width; title, description, and body must not draw under the cut-out; excess action width clips at the card edge.
- What happens when action widgets have heterogeneous sizes? Actions are laid out in a horizontal row with standard spacing; vertical centering within the cut-out uses the row's collective layout bounds relative to the shelf area.
- What happens when action widgets lack accessibility labels? The card does not add semantic grouping or fallback labels; feature screens must supply accessible action widgets (e.g., `AppIconButton` with labels), consistent with `AppCard` action responsibility.
- What happens when AI or backend services are unavailable? Not applicable — this is a presentational component with no service dependency; cards render identically offline and online.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a reusable **App Notched Card** component in the shared UI layer that feature screens can import like other design-system cards.
- **FR-002**: The notched card MUST match the standard application card for background color, border, elevation/shadow, internal padding, margins, width/height behavior, intrinsic sizing, and responsiveness on all corners except the top-trailing edge (LTR), which is replaced by a custom step-down cut-out.
- **FR-003**: The cut-out border MUST follow the clipped card outline continuously with no visible gaps, overlaps, or radius mismatches between clip and border.
- **FR-004**: The cut-out geometry MUST be a **step-down recession** along the top-trailing edge (LTR), traced as: (1) main top horizontal edge from the leading corner until the cut-out begins, (2) entry fillet — smooth concave curve downward to the notch shelf, (3) horizontal notch shelf at fixed depth below the main top edge, (4) exit fillet — smooth concave curve **downward** from the notch shelf to the trailing vertical edge, (5) trailing vertical edge continuing downward from the exit fillet to the bottom-trailing corner. The top-trailing corner MUST remain open (no card material at the main top elevation on the trailing side); screen background is visible through the recess above the shelf and along the upper trailing side. The reference screenshot at `docs/ui/assets/notch_card_reference.png` is authoritative for visual shape.
- **FR-005**: Both fillet transitions (entry and exit) MUST share one fixed corner radius; shelf depth MUST be a fixed internal constant. Callers MUST NOT configure fillet radius, shelf depth, or raw cut-out dimensions.
- **FR-006**: Cut-out width MUST equal the intrinsic width of supplied actions, inter-action gaps (`SpacingTokens.sm` between each pair when multiple actions are present), plus fixed internal horizontal padding, subject to a defined minimum width when no actions are supplied and a maximum of the available trailing horizontal space within the card (top-trailing corner in LTR).
- **FR-007**: The component MUST accept zero or more action widgets supplied by the caller. All actions MUST render exclusively inside the top-trailing cut-out — never in a bottom action row. Actions MUST float on a layer above the card (conceptually a Stack) and appear centered within the shelf area. Multiple actions MUST be laid out in a horizontal row with the same inter-action spacing as `AppCard`. Individual action widgets MUST NOT be re-themed or restyled.
- **FR-008**: The component MUST require a `body` widget (maps to `AppCard.child`). It MUST expose an optional title region (top-leading, vertically aligned with the main top edge / cut-out region), an optional description region (between title and body, matching standard card subtitle styling), and the required body region (below description or title, caller-controlled layout) using the same title and description typography as the standard card.
- **FR-009**: Title, description, body, and actions MUST NOT overlap; the layout MUST automatically reserve horizontal space for the cut-out on the trailing edge (LTR).
- **FR-010**: In RTL layout direction, the cut-out MUST move to the top-leading edge (trailing semantics) with the remainder of the layout mirroring naturally.
- **FR-011**: The public API MUST expose `body` (required), `title` (optional), `description` (optional), and `actions` (optional); cut-out geometry, padding constants, and border styling MUST remain internal implementation details.
- **FR-012**: The component MUST NOT alter overall card sizing behavior relative to the standard card — the cut-out is a visual recession in the card outline, not an additional margin that changes card footprint rules.
- **FR-013**: The same continuous outline path MUST be used for clipping card content and drawing the border wherever practical, so clip and stroke stay visually aligned.
- **FR-014**: The component MUST scale proportionally across screen sizes while preserving cut-out fillet and shelf-depth proportions defined by the fixed internal constants.
- **FR-015**: When the intrinsic cut-out width required by actions exceeds available trailing space, the component MUST cap cut-out width at that available space and clip overflowing action content at the card boundary without displacing title, description, or body layout.
- **FR-016**: The component MUST NOT add accessibility semantics (grouping, toolbar roles, or fallback labels) for cut-out actions; callers MUST supply fully accessible action widgets, matching `AppCard` caller responsibility for action semantics.

### Key Entities

- **App Notched Card**: A presentational UI container with required body, optional title, optional description, optional top cut-out actions, and a top-trailing step-down cut-out (LTR). No persistent data; actions are ephemeral UI supplied per screen.
- **Cut-out region**: The step-down recession along the top trailing edge — a horizontal shelf below the main top edge bounded by entry and exit fillets (both curving downward) — that sizes to fit actions plus padding. Screen background is visible through the recess above the shelf and along the open top-trailing corner above the exit fillet; the trailing vertical edge begins below the exit fillet, not at the main top elevation.
- **Action slot**: One or more caller-supplied widgets floating in the cut-out on a layer above the card; when multiple, arranged in a horizontal row with `AppCard`-equivalent spacing, without per-widget re-theming.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Supports dense clinic dashboards and detail panels where quick actions (filters, overflow menus, status toggles) should sit beside the card title without extra vertical space — typical for small-to-mid multi-branch clinics on desktop and tablet workflows. Hospital-grade customizable layout engines and per-tenant card chrome are out of scope.
- **Layer Placement**: Entirely **Flutter presentation layer** (`core/ui` design system). No Supabase, PostgreSQL, RPC, RLS, or AI service involvement. Action widgets may invoke feature logic that touches backend services, but this component does not.
- **Data Integrity & Security**: The card does not store or transmit data. Callers must not place sensitive patient information inside action widgets beyond what the screen already exposes. No new permissions, audit events, or tenant scoping rules are introduced by this component.
- **Failure Handling**: Purely local rendering; no network or AI dependency. If action callbacks fail (e.g., backend error from a button press), existing feature-level error handling applies — the card itself does not add failure modes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a design-system side-by-side comparison, 100% of reviewed non-notched visual attributes (corner radii on three corners, border, background, elevation, title and description typography) match the standard card on reference breakpoints (mobile, tablet, desktop widths used by the app).
- **SC-002**: With 1–3 typical action controls (e.g., filter dropdown, icon button) at typical card widths, actions are fully visible floating inside the top-trailing cut-out with padding on all sides in 100% of golden/visual regression cases; at constrained widths where clipping applies per FR-015, clipping occurs only at the card boundary and not by the cut-out border geometry itself.
- **SC-003**: Title, description, and body text never intersect the cut-out or action bounds in automated layout tests across LTR and RTL at minimum, typical, and maximum card widths.
- **SC-004**: Feature developers can integrate the component with only `title`, `description`, `body`, and `actions` parameters — integration examples require no cut-out-related configuration (verified in showcase/demo screen).
- **SC-005**: RTL mirror behavior passes manual or automated directionality tests without per-screen `Directionality` workarounds.
- **SC-006**: On a representative screen, interacting with surrounding content does not cause visible flicker or layout shift in the notched card beyond what the standard card exhibits under the same conditions.
- **SC-007**: Cut-out shape in visual regression matches the reference screenshot (`docs/ui/assets/notch_card_reference.png`) for step-down profile, downward-oriented entry and exit fillets, open top-trailing corner, fillet smoothness, and floating action placement within the recess.

## Assumptions

- The existing **App Card** (`AppCard`) remains the baseline for styling, padding tokens, title typography, and description/subtitle styling; the notched variant is a sibling component, not a breaking change to `AppCard`.
- Fixed fillet radius, shelf depth, and internal padding are chosen by implementers to match the reference screenshot and theme density; they are constants, not theme tokens exposed to callers.
- `body` is **required** (maps to `AppCard.child`); `title`, `description`, and `actions` are optional, matching `AppCard` optionality patterns except actions relocate to the top-trailing cut-out and float on a layer above the card.
- Visual verification uses golden tests and/or the theme showcase page pattern already established in the project, with the reference screenshot as the cut-out shape baseline.
- Screen migration from `AppCard` to the notched variant is deferred; this feature ships the component and showcase only.
- Accessibility: the card MUST NOT wrap cut-out actions in additional semantic groups or supply fallback labels; action widgets MUST retain semantics supplied by callers (e.g., labeled `AppIconButton`). The card MUST provide sufficient contrast for the cut-out border against the card background per existing theme contrast rules.
