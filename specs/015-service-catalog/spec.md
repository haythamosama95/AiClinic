# Feature Specification: Service Catalog

**Feature Branch**: `015-service-catalog`

**Created**: 2026-07-02

**Status**: Draft

**Input**: User description: "Drive a specification for the service catalog feature from docs/service_catalog_feature.md. It shall follow Flutter best practices, clean architecture, clean code, modular design and good UI/UX design."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

Today, billing (`specs/007-billing`) captures charges as **free-text invoice item descriptions**: whoever issues an invoice types the service name and unit price by hand. This produces inconsistent naming, price drift between branches and staff, no controlled promotions, and no reliable way to report on "how many of service X did we sell". A multi-branch clinic needs a single, administrator-governed list of billable services with per-branch pricing and activation.

This feature introduces a **Service Catalog**: an administrator-curated, organization-scoped list of the services a clinic provides. Each service has a **default price** and a **global status** (active/inactive). Every service is **assigned** to one or more branches (or all branches). Each assigned branch may independently **activate/deactivate** the service, **override the price**, and configure a time-boxed **promotional price**. When staff issue an invoice, they **select** services from the catalog instead of typing them; the system resolves the correct **effective unit price** for the invoice's branch and date, and stores an **immutable snapshot** on the invoice item so historical invoices never change when the catalog later changes.

The primary beneficiaries are **owners/administrators** who standardize the service list, control pricing per branch, and run promotions; **receptionists/billing staff** who issue accurate invoices faster without guessing prices; and **patients** who receive consistent, correctly-priced receipts across branches. Reporting, analytics dashboards, service categories/taxonomies, cost/margin tracking, inventory/consumables, package/bundle pricing, tax rules, and AI-assisted pricing are explicitly **out of scope** for this feature.

This feature **modifies the invoice item contract** from `specs/007-billing`: the free-text `description` entry path is removed entirely and replaced by a required catalog selection, and each invoice item gains a `service_id` link plus price-snapshot fields. Previously issued invoices remain untouched.

## Clarifications

### Session 2026-07-02

- Q: Are services organization-scoped or global? → A: **Organization-scoped.** A service belongs to exactly one organization and is assigned to that organization's branches. Cross-organization visibility is never allowed. This reuses the existing branch-based multi-tenant isolation.
- Q: How does this reconcile with the existing free-text `invoice_items.description` from V1-6 (007-billing)? → A: **Catalog selection totally replaces the free-text description path.** The free-text service-name entry mechanism is removed entirely — it is not retained as an alternate authoring path. Each invoice item gains a required `service_id`; the item's `service_name` is a snapshot copied from the selected service (the former free-text `description` becomes this snapshot field). Historical invoice items created before this feature keep their stored values unchanged (immutable); no back-fill or migration of history occurs, but no new free-text item can ever be authored again.
- Q: Where does unit price come from now that staff can no longer type it? → A: **The server resolves it** from the catalog at add-to-invoice time using the priority promo → branch override → default, and stamps the resolved amount onto the invoice item as an immutable snapshot. Staff may still edit **quantity**; they may not free-type unit price (line-level discount, if permitted, remains the V1-6 mechanism for reducing a line — pricing overrides are an administrator/catalog concern, not a per-invoice typed value).
- Q: Can the same service appear twice on one invoice? → A: **No.** A service may appear at most once per invoice; selecting it again increases that line's quantity (default quantity 1).
- Q: How many concurrent promotions per service per branch? → A: **At most one active promotion window per service per branch at any time.** The branch configuration holds a single optional promotion (price + start date + end date). Overlapping/second promotions are not modeled in this feature.
- Q: When a service is deleted, what happens? → A: **Soft delete only.** A service that has never been used may be soft-deleted; a service referenced by any invoice is retained (soft-deleted, hidden from selectors) so historical invoices remain intact. Hard delete is never used.
- Q: Which roles may manage the catalog? → A: **`owner` and `administrator` only** via a new `services.manage` permission key. Any user who can create invoices (e.g., `receptionist` with `invoices.create`) may **read/select** active services for their branch; a separate `services.view` read key gates catalog browsing screens.
- Q: Is editing a service allowed to change past invoices? → A: **No.** Editing name, default price, assignments, branch configuration, or global status affects only future invoice pricing/selection. Previously issued invoice items keep their snapshots.
- Q: Which date drives promotion-window evaluation and the price snapshot when adding a service to an invoice? → A: **The current date at add-to-invoice time.** The server resolves the effective price using the date the line is added and **locks it into the item snapshot immediately**; it never re-resolves afterward (even if the invoice is issued on a later date or a promotion starts/ends in between). "Invoice date" for promotion evaluation therefore means the add-to-invoice date, not the eventual issue date.
- Q: When a service is assigned to "all branches", how are branches created later handled? → A: **No automatic propagation.** "All branches" expands to explicit per-branch configuration rows for the branches that exist at save time; branches created later are NOT auto-assigned. Instead, a **new-branch service setup step** prompts an administrator to populate the new branch's catalog configuration via one of: (a) select the services it needs from the catalog, (b) copy the entire configuration from an existing branch, or (c) copy from an existing branch and then modify. This reuses the copy-configuration capability (User Story 7).
- Q: What happens to an existing promotion if the default price or branch override is later lowered below the promotion price? → A: **The invariant `promotion_price ≤ effective branch price` is enforced on every price change.** A default-price or branch-override change that would leave any existing promotion priced above the new effective price MUST be rejected; the administrator must first adjust or clear the affected promotion. The invariant therefore always holds, preventing silent overcharging.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a Service and Assign Branches (Priority: P1)

As an owner or administrator with `services.manage`, I can create a service with a name, a default price, a global status, and a branch assignment (all branches or selected branches), so the clinic has a single governed list of billable services available in the right locations.

**Why this priority**: The catalog is the anchor for every other capability; nothing else (pricing, promotions, invoice selection) can exist without it.

**Independent Test**: Create a service "Consultation" with default price 200, assign it to two of three branches, save, and verify it appears as selectable at the two assigned branches and not at the third.

**Acceptance Scenarios**:

1. **Given** a user with `services.manage`, **When** they create a service with a valid name, non-negative default price, global status `active`, and assignment to "all branches", **Then** the service is created, assigned to every current branch of the organization, and becomes selectable at each branch (subject to branch activation).
2. **Given** a user with `services.manage`, **When** they create a service assigned to selected branches, **Then** the service is available only at the chosen branches and unavailable at unassigned branches.
3. **Given** a user without `services.manage`, **When** they attempt to create a service, **Then** the action is blocked at UI and server layers.
4. **Given** a user with `services.manage`, **When** they submit a service with an empty name or a negative default price, **Then** creation is rejected with a clear validation message and nothing is persisted.
5. **Given** a service name that already exists (case-insensitive) in the same organization among non-deleted services, **When** the user tries to create a duplicate, **Then** creation is rejected with a "service name already exists" message.
6. **Given** a user in organization A, **When** they create a service, **Then** the service is scoped to organization A and never visible to organization B.

---

### User Story 2 - Select a Catalog Service on an Invoice with Correct Pricing (Priority: P1)

As reception or billing staff issuing an invoice, I can select one or more services from the catalog (not type them) and have the system apply the correct effective unit price for the invoice's branch and date, storing an immutable snapshot, so invoices are consistent and historically stable.

**Why this priority**: This is the point where the catalog delivers user value; it replaces error-prone manual entry and is used on every invoice.

**Independent Test**: On a `draft` invoice at Branch B, open the service selector, add "Consultation", verify the unit price equals the resolved effective price for Branch B on the add-to-invoice date, verify a snapshot (service id, name, unit price) is stored, then later change the catalog price and confirm the issued invoice is unchanged.

**Acceptance Scenarios**:

1. **Given** a `draft` invoice at the user's branch and a service that is globally active, assigned to that branch, and branch-active, **When** the user selects the service, **Then** an invoice item is added with quantity 1, the server-resolved effective unit price, a snapshot of the service id and name, and a computed total.
2. **Given** the invoice editor, **When** the user attempts to add a line, **Then** only services satisfying **all** of (globally active) AND (assigned to the invoice branch) AND (branch-active) are offered; ineligible services are not selectable.
3. **Given** the invoice editor, **When** the user tries to type a free-text service name, **Then** the system does not allow it; every line must originate from a catalog selection.
4. **Given** a service already present on the invoice, **When** the user selects the same service again, **Then** the existing line's quantity increases by 1 rather than creating a duplicate line.
5. **Given** an invoice item added from the catalog, **When** the catalog service is later renamed, repriced, or deactivated, **Then** the already-added invoice item retains its stored snapshot (name and unit price) unchanged.
6. **Given** a branch whose only matching service is branch-inactive or globally inactive, **When** the user opens the selector, **Then** that service does not appear and cannot be added.
7. **Given** an invoice item, **When** the user changes quantity to a positive integer, **Then** the line total recomputes as quantity × snapshot unit price; the user cannot free-type the unit price.

---

### User Story 3 - Configure Branch Price Override and Activation (Priority: P2)

As an owner or administrator with `services.manage`, I can, per assigned branch, activate/deactivate a service and set an optional price override, so each branch can charge and offer services independently while falling back to the default price when no override is set.

**Why this priority**: Branch-level pricing and activation are core differentiators for multi-branch clinics, but they build on an existing service (US1).

**Independent Test**: For "Consultation" (default 200), set Branch B override to 150 and Branch C to inactive; verify Branch B invoices resolve 150, Branch A (no override) resolves 200, and Branch C cannot select it.

**Acceptance Scenarios**:

1. **Given** an assigned branch with no override, **When** an invoice is created there, **Then** the effective price is the service default price.
2. **Given** an administrator sets a non-negative branch price override, **When** an invoice is created at that branch (no active promo), **Then** the effective price is the override.
3. **Given** an administrator clears a branch override, **When** an invoice is created at that branch, **Then** the effective price reverts to the service default price.
4. **Given** an administrator deactivates the service for a specific branch, **When** staff at that branch open the service selector, **Then** the service is not selectable there, even though it remains active at other branches.
5. **Given** a globally inactive service, **When** any branch configuration marks it active, **Then** it is still not selectable at any branch (global inactive overrides branch-active).
6. **Given** a branch not assigned to the service, **When** an administrator attempts to configure a price override for that branch, **Then** the operation is rejected until the branch is assigned.
7. **Given** a user without `services.manage`, **When** they attempt to change branch activation or override, **Then** the action is blocked.

---

### User Story 4 - Configure Promotional Pricing per Branch (Priority: P2)

As an owner or administrator with `services.manage`, I can configure a time-boxed promotional price for a service at a branch (price, start date, end date), so the branch automatically charges the promotional price during the promotion window and reverts afterward.

**Why this priority**: Promotions are a common clinic sales mechanism, but they depend on branch configuration (US3) already existing.

**Independent Test**: Set Branch C promo 100 from 01-Jan to 31-Jan on top of override 120; verify invoices dated in January resolve 100, invoices on 31-Jan (inclusive) resolve 100, and invoices on 01-Feb resolve 120.

**Acceptance Scenarios**:

1. **Given** an administrator configures a promotion with a promotional price, start date, and end date where price ≤ effective branch price and start ≤ end, **When** an invoice is dated within the inclusive window, **Then** the effective price is the promotional price.
2. **Given** a configured promotion, **When** the add-to-invoice date is before the start date or after the end date, **Then** the promotion is ignored and the branch override (or default) price applies.
3. **Given** an administrator sets a promotional price greater than the effective branch price, **When** they save, **Then** the operation is rejected with a validation message.
4. **Given** an administrator provides a promotional price with only one of the two dates (missing start or end), **When** they save, **Then** the operation is rejected; a promotion requires both start and end dates.
5. **Given** an administrator sets a start date later than the end date, **When** they save, **Then** the operation is rejected.
6. **Given** a branch already has a promotion window configured, **When** the administrator saves a second promotion for the same service and branch, **Then** it replaces the single stored promotion (only one promotion per service per branch is retained).
6a. **Given** a branch with an active promotion at price P, **When** the administrator later lowers the branch override or the service default price below P, **Then** the change is rejected with a message to adjust or clear the promotion first, keeping `promotion_price ≤ effective price` always true.
7. **Given** a promotion window has expired relative to the current/invoice date, **When** an invoice is created, **Then** no manual step is required for reversion; pricing automatically falls back to override/default based on the date.

---

### User Story 5 - Edit a Service and Change Global Status (Priority: P2)

As an owner or administrator with `services.manage`, I can edit a service's name, default price, branch assignments, branch configuration, and global status, with changes affecting only future invoices, so the catalog stays current without altering historical records.

**Why this priority**: Ongoing maintenance and enable/disable are essential for a living catalog, but secondary to creation and pricing resolution.

**Independent Test**: Rename "Consultation" to "General Consultation", raise default price to 220, mark globally inactive, and verify new invoices cannot select it while previously issued invoices are unchanged and still show the old snapshot.

**Acceptance Scenarios**:

1. **Given** a service with existing invoices, **When** an administrator edits the name or default price, **Then** future invoices reflect the change while previously issued invoice items keep their snapshots unchanged.
2. **Given** an administrator marks a service globally `inactive`, **When** staff at any branch open the service selector, **Then** the service is not selectable at any branch regardless of branch configuration.
3. **Given** an administrator reactivates a globally inactive service, **When** staff open the selector at an assigned, branch-active branch, **Then** the service becomes selectable again.
4. **Given** an administrator removes a branch from the assignment, **When** staff at that branch open the selector, **Then** the service is no longer selectable there; its historical invoice items remain intact.
5. **Given** an administrator renames a service to a name that collides (case-insensitive) with another non-deleted service in the organization, **When** they save, **Then** the edit is rejected with a duplicate-name message.
6. **Given** a service referenced by at least one invoice, **When** an administrator attempts to permanently delete it, **Then** the system performs a soft delete (hide from selectors, retain history) rather than a hard delete.

---

### User Story 6 - Browse, Search, and Filter the Catalog (Priority: P2)

As an owner, administrator (`services.view`/`services.manage`), I can browse the service catalog and search/filter by name, global status, and branch, so I can quickly find and manage services in a growing list.

**Why this priority**: A management surface is needed once more than a handful of services exist; depends on services existing.

**Independent Test**: Create several services with mixed statuses and branch assignments, search by a name fragment, filter by status `inactive`, filter by a specific branch, and verify correct, paginated results.

**Acceptance Scenarios**:

1. **Given** services exist in the organization, **When** the user opens the catalog list, **Then** it shows each service's name, default price, global status, and an at-a-glance branch/pricing summary, with pagination.
2. **Given** the user searches by a name fragment, **When** results render, **Then** only matching non-deleted services in the organization are shown.
3. **Given** the user filters by global status `inactive`, **When** results render, **Then** only inactive services are shown.
4. **Given** the user filters by a specific branch, **When** results render, **Then** only services assigned to that branch are shown, with that branch's effective price/status summarized.
5. **Given** a user without `services.view` and without `services.manage`, **When** they attempt to open the catalog management screen, **Then** access is blocked (invoice-issuing users can still select services in the invoice editor via read access).

---

### User Story 7 - Copy Branch Configuration Between Branches (Priority: P3)

As an owner or administrator with `services.manage`, I can copy service configuration (assignments, activation status, price overrides, promotional pricing) from a source branch to a target branch, choosing to replace the target's existing configuration or merge only missing entries, so I can roll out a branch's setup quickly.

**Why this priority**: A convenience/scale accelerator that meaningfully reduces setup effort but is not required for the catalog to function.

**Independent Test**: Configure Branch A fully, copy to empty Branch D with "merge missing only" and verify D matches A; then change one value in D, copy again with "replace" after confirming, and verify D fully matches A again.

**Acceptance Scenarios**:

1. **Given** a source and target branch and a user with `services.manage`, **When** they copy with mode "merge missing only", **Then** target entries that do not yet exist are created from the source (assignment, activation, override, promotion) and existing target entries are left untouched.
2. **Given** a source and target branch, **When** the user copies with mode "replace existing", **Then** the system requests explicit confirmation before overwriting, and upon confirmation the target's configuration is replaced to match the source for the copied services.
3. **Given** the user initiates a "replace" copy, **When** they cancel at the confirmation prompt, **Then** no changes are made to the target branch.
4. **Given** a service is globally inactive, **When** its configuration is copied, **Then** its branch-level entries copy as specified but the service remains non-selectable while globally inactive.
5. **Given** a user without `services.manage`, **When** they attempt a copy operation, **Then** the action is blocked at UI and server layers.
6. **Given** a copy operation runs, **When** it completes, **Then** the change is recorded in the audit log with source branch, target branch, mode, and affected services.

---

### Edge Cases

- Attempt to add a service to an invoice at a branch where the service is unassigned, branch-inactive, or globally inactive: not offered and rejected server-side if forced.
- Attempt to add the same service twice: quantity increments; no duplicate line is created.
- Invoice created exactly on a promotion start or end date: promotion applies (inclusive on both ends).
- Promotion configured with price equal to the effective branch price: allowed (price ≤ effective branch price).
- Branch override set to 0 (free service): allowed as a valid non-negative price; effective price is 0.
- Service assigned to "all branches" and a new branch is later created: the new branch is NOT auto-assigned; an administrator is prompted through the new-branch service setup step (select from catalog / copy entirely from another branch / copy-then-modify) per FR-031.
- Editing a service's default price while an invoice is in `draft`: the draft's already-added lines keep their snapshot; newly added lines use the new resolution. (Consistent with V1-6 draft item immutability of unit price.)
- Duplicate service name differing only by case or surrounding whitespace: treated as a duplicate and rejected.
- Soft-deleting a service that appears on historical invoices: hidden from all selectors and catalog lists by default; historical invoice items remain intact and viewable.
- Copy "replace" targeting a branch with in-progress draft invoices: only future line additions are affected; existing draft snapshots are unchanged.
- Cross-organization service access attempt: always denied in verification scenarios.
- Concurrent edits to the same service or branch configuration: optimistic concurrency on the record's `updated_at`; stale edits are rejected with a refresh prompt.
- Subscription-degraded/read-only mode: catalog remains readable and invoices can still select existing services; catalog mutations follow the platform's degraded-mode policy (never data loss).
- AI is not part of this feature; AI unavailability MUST not block any catalog or invoicing workflow.
- Backend-first fetch: catalog list, service editor, and the invoice service selector MUST consult the backend before rendering actionable content.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce a **Service** record scoped to an organization with fields: `id`, `organization_id`, `name`, `default_price` (exact decimal, scale 2, ≥ 0), `global_status` (`active` | `inactive`), plus standard audit and soft-delete columns.
- **FR-002**: The system MUST introduce a **ServiceBranch** configuration record with fields: `id`, `service_id`, `branch_id`, `status` (`active` | `inactive`), `price_override` (nullable exact decimal, scale 2, ≥ 0), `promotion_price` (nullable exact decimal, scale 2, ≥ 0), `promotion_start_date` (nullable date), `promotion_end_date` (nullable date), plus standard audit and soft-delete columns. A `ServiceBranch` row exists only for branches the service is assigned to.
- **FR-003**: The system MUST allow only users with `services.manage` to create, edit, assign branches, configure branch activation/override/promotion, change global status, soft-delete, and copy configuration. All other users MUST be blocked at UI and server layers.
- **FR-004**: The system MUST allow a service to be assigned to **all branches** or to **one or more selected branches**, and MUST make a service selectable on an invoice only for branches to which it is assigned.
- **FR-005**: The system MUST enforce a unique service name per organization among non-deleted services, compared case-insensitively and trimmed of surrounding whitespace.
- **FR-006**: The system MUST validate that `default_price`, `price_override`, and `promotion_price` are non-negative exact decimals with scale 2.
- **FR-007**: The system MUST permit a promotion only when **both** `promotion_start_date` and `promotion_end_date` are provided, with `promotion_start_date ≤ promotion_end_date`, and MUST treat the promotion window as **inclusive of both dates**.
- **FR-008**: The system MUST enforce the invariant `promotion_price ≤ effective branch price` (`price_override` if set, otherwise `default_price`) at all times. It MUST reject a `promotion_price` greater than the effective branch price at promotion save time, AND MUST reject any later change to `default_price` or `price_override` that would leave an existing promotion priced above the new effective price for that service and branch. In such cases the administrator MUST first adjust or clear the affected promotion; the system MUST NOT silently keep or auto-alter a violating promotion.
- **FR-009**: The system MUST store at most **one promotion window per service per branch**; saving a new promotion for a service/branch that already has one MUST replace it.
- **FR-010**: The system MUST resolve the **effective unit price** at add-to-invoice time using this priority, evaluated against the invoice's branch and the **current date at the moment the line is added** (the "add-to-invoice date"): (1) `promotion_price` when the add-to-invoice date falls within the inclusive promotion window; else (2) `price_override` when set; else (3) service `default_price`. The resolved price MUST be locked into the item snapshot at add time and MUST NOT re-resolve if the invoice is issued on a later date or if the promotion window changes afterward.
- **FR-011**: The system MUST make a service **eligible for invoice selection** only when ALL hold: the service `global_status` is `active`, the service is assigned to the invoice's branch, and the `ServiceBranch.status` for that branch is `active`.
- **FR-012**: The system MUST require every invoice item to originate from a catalog selection; the free-text service-name entry mechanism MUST be removed entirely (not merely hidden or disabled as an alternate path) so no new free-text invoice item can be authored.
- **FR-013**: The system MUST store an immutable snapshot on each invoice item at add time consisting of: `service_id`, `service_name`, applied `unit_price`, `quantity`, and computed `total_price` (`quantity × unit_price`). Subsequent changes to the service, branch configuration, or promotion MUST NOT alter previously created invoice items.
- **FR-014**: The system MUST default invoice-item `quantity` to 1, allow it to be changed to a positive integer, and MUST NOT allow staff to free-type the snapshot `unit_price` on the invoice editor.
- **FR-015**: The system MUST ensure a service appears at most once per invoice; re-selecting an already-present service MUST increase that line's quantity rather than creating a duplicate line.
- **FR-016**: The system MUST ensure editing a service (name, default price, assignments, branch configuration, global status) affects only future invoice selection/pricing and never mutates previously issued invoice items.
- **FR-017**: The system MUST make a **globally inactive** service non-selectable at every branch regardless of any branch-level `active` status.
- **FR-018**: The system MUST support copying branch configuration from a source branch to a target branch including assignments, activation status, price overrides, and promotional pricing, with two modes: **replace existing** and **merge missing only**.
- **FR-019**: The system MUST require explicit confirmation before a **replace** copy overwrites existing target configuration, and MUST make no changes if the user cancels.
- **FR-020**: The system MUST use soft delete for services and branch configuration; a service referenced by any invoice MUST never be hard-deleted, and soft-deleted services MUST be excluded from selectors and catalog lists while remaining available for historical invoice display.
- **FR-021**: The system MUST enforce organization-scoped isolation for services and branch-scoped access for branch configuration; no cross-organization reads or writes may occur.
- **FR-022**: The system MUST enforce these permission keys at UI and server layers: `services.view` (browse the catalog management surface), `services.manage` (all catalog mutations), and MUST allow users holding `invoices.create` to **read/select eligible services** for their branch within the invoice editor without `services.view`.
- **FR-023**: V1 role seeding MUST grant `services.view` and `services.manage` to `owner` and `administrator` only; `receptionist`, `doctor`, and `lab_staff` MUST NOT receive catalog management keys by default (receptionists retain service **selection** via `invoices.create`).
- **FR-024**: The system MUST perform all catalog mutations (create, edit, assign, configure branch, set/clear override, set/clear promotion, change global status, soft-delete, copy) through secured server-side functions with permission, scope, and validation checks — not unguarded direct client writes.
- **FR-025**: The system MUST record catalog events in the audit log with actor, action, target, and meaningful payload: service create/edit, branch assignment change, activation change, override set/clear, promotion set/clear/replace, global-status change, soft-delete, and copy (source, target, mode, affected services).
- **FR-026**: The system MUST expose the effective price resolution to the client for display (e.g., a "price preview" for a service at a branch/date) using the same server-side rules used at add-to-invoice time, so the UI never computes pricing independently as a source of truth.
- **FR-027**: The system MUST use optimistic concurrency (record `updated_at`) for service and branch-configuration edits, rejecting stale writes with a refresh prompt.
- **FR-028**: When opening the catalog list, the service editor, or the invoice service selector, the client MUST perform a backend-first fetch before rendering actionable content.
- **FR-029**: The system MUST NOT deliver as part of this feature: service categories/taxonomies, package/bundle pricing, tax rules, cost/margin tracking, inventory/consumables, multi-currency, revenue/analytics dashboards, or AI-assisted pricing.
- **FR-030**: The system MUST NOT modify previously issued invoices or auto-migrate historical free-text invoice items; the catalog-selection requirement applies to invoice items created after this feature is enabled.
- **FR-031**: The system MUST NOT auto-assign existing services to a newly created branch. When a branch is created, the system MUST offer a **service setup step** for that branch that lets an administrator with `services.manage` either (a) select the services the branch needs from the catalog, (b) copy the entire service configuration from an existing branch, or (c) copy from an existing branch and then modify. Until setup is completed, the new branch has no assigned services and cannot select any on invoices. This step reuses the copy-configuration capability (FR-018/FR-019).

### Non-Functional Requirements

- **NFR-001**: Catalog and invoice-selection screens MUST use plain language suitable for reception/billing staff, and MUST display all monetary values with the organization's configured currency symbol.
- **NFR-002**: The service selector in the invoice editor MUST return eligible services and their resolved prices within a responsive, debounced search under normal local clinic LAN conditions (perceived-interactive latency).
- **NFR-003**: The catalog list MUST remain navigable with pagination/lazy loading for organizations with up to 2,000 services.
- **NFR-004**: Permission and scope checks MUST follow defense in depth: client gating for usability, secured server functions for domain enforcement, and data-layer policies for hard isolation.
- **NFR-005**: All monetary values MUST be stored as exact decimals with fixed scale 2 (no floating point) across `default_price`, `price_override`, `promotion_price`, and invoice-item snapshots, consistent with `specs/007-billing` NFR-007.
- **NFR-006 (Modular Design)**: The feature MUST be delivered as a self-contained, replaceable module (`frontend/lib/features/service_catalog`) that other features depend on only through its public repository/provider surface, preserving the constitution's replaceable-layer-boundaries principle. Its only cross-feature coupling is the well-defined invoice-item contract consumed by billing.
- **NFR-007 (Clean Architecture)**: The client implementation MUST separate concerns into distinct layers — `domain` (pure models, value objects, and pricing-resolution contracts with no framework/SDK imports), `data` (repository + backend/SDK access), `application` (state/notifiers/providers and use-case orchestration), and `presentation` (widgets/pages/routing) — with dependencies pointing inward (presentation → application → data → domain) and no reverse dependencies.
- **NFR-008 (Clean Code)**: Business rules (eligibility and price-resolution) MUST have the database/RPC layer as source of truth, with client-side logic limited to display/orchestration; shared logic MUST be factored into small, testable units (e.g., a pure price-preview formatter, an eligibility descriptor) rather than duplicated across widgets.
- **NFR-009 (UI/UX)**: The catalog UX MUST provide clear empty/loading/error/permission-denied states; a create/edit form with inline validation and a per-branch configuration matrix (status, override, promotion) that is scannable at a glance; and an invoice service selector with type-ahead search, eligibility-aware results, a visible price and an "on promotion" indicator, keyboard-navigable selection, and confirmation dialogs for destructive actions (replace-copy, soft-delete). The design MUST reuse the existing `core/ui` design system and be responsive to narrow desktop windows.
- **NFR-010**: Save and mutation failures (connectivity or validation) MUST surface clear errors and MUST NOT leave the user believing a change was saved.

### Key Entities *(include if feature involves data)*

- **Service**: Organization-scoped billable service with a name, default price, and global status; the catalog's root record.
- **ServiceBranch**: Per-branch configuration of a service (assignment presence, activation status, optional price override, optional single promotion window); absence of a row means the service is unassigned to that branch. A null `price_override` means "use default price"; a null promotion means "no promotion configured".
- **Invoice Item** (modified from `specs/007-billing`): Itemized service line on an invoice; now carries a required `service_id` link and immutable snapshot fields (`service_name`, `unit_price`, `quantity`, `total_price`).
- **Branch** (existing): Isolation and configuration scope for service assignment, activation, and pricing.
- **Organization** (existing): Tenancy boundary; every service belongs to exactly one organization.
- **Invoice** (existing): The add-to-invoice date (the date a line is added) drives promotion-window evaluation for price resolution and is captured in the item snapshot.

### Data Model

- **Service**: `id`, `organization_id`, `name`, `default_price` (decimal scale 2, ≥ 0), `global_status` (`active`|`inactive`), audit + soft-delete columns.
- **ServiceBranch**: `id`, `service_id`, `branch_id`, `status` (`active`|`inactive`), `price_override` (nullable decimal scale 2), `promotion_price` (nullable decimal scale 2), `promotion_start_date` (nullable date), `promotion_end_date` (nullable date), audit + soft-delete columns. Unique on (`service_id`, `branch_id`) among non-deleted rows.
- **Invoice Item** (extends V1-6): add `service_id` (FK to Service, required for new rows) and retain/repurpose `service_name`/`unit_price`/`quantity`/`total_price` as immutable snapshots. Historical rows keep prior values.

A null `price_override` indicates the branch uses the service default price. A null promotion (any of price/start/end null) indicates no promotional pricing is currently configured; a valid promotion requires all three.

### Pricing Resolution Rules

| Priority | Condition | Effective Unit Price |
| -------- | --------- | -------------------- |
| 1 | Promotion configured AND add-to-invoice date within `[promotion_start_date, promotion_end_date]` inclusive | `promotion_price` |
| 2 | No active promotion AND `price_override` is set | `price_override` |
| 3 | Otherwise | service `default_price` |

The "add-to-invoice date" is the current date when the line is added; the resolved price is locked into the item snapshot at that moment and does not re-resolve at issue time. Eligibility precondition for selection and pricing: service `global_status = active` AND service assigned to invoice branch AND `ServiceBranch.status = active`.

### Copy Rules

| Mode | Behavior | Confirmation |
| ---- | -------- | ------------ |
| Merge missing only | Create target entries that do not exist from source; leave existing target entries unchanged | Not required |
| Replace existing | Overwrite target configuration to match source for the copied services | Required before overwrite; cancel makes no changes |

Copied attributes: assignment, activation status, price override, promotion (price + start + end).

### RPC Functions

Exact names follow architecture; required capabilities (all `services.manage`-gated unless noted, organization/branch-scoped, audit-logged):

- **Create service**: validate `services.manage`, unique trimmed case-insensitive name, non-negative default price; create service and requested branch assignments (all/selected).
- **Update service**: validate `services.manage`, name uniqueness on change, price validity; update name/default price/global status; reject a `default_price` reduction that would leave any branch's existing promotion above the new effective price (invariant guard); never touch historical invoice items.
- **Set branch assignment**: assign/unassign branches; unassignment retains history via soft delete of the `ServiceBranch` row.
- **Configure branch status/override**: set branch `active`/`inactive`; set/clear non-negative `price_override`; reject an override change that would leave that branch's existing promotion above the new effective price (invariant guard); reject configuration for unassigned branches.
- **Set/clear promotion**: validate both dates present, start ≤ end, `promotion_price ≤` effective branch price; replace any existing single promotion; clearing removes the promotion window.
- **Change global status**: set `active`/`inactive`; inactive hides from all selectors.
- **Soft-delete service**: soft delete; forbidden as hard delete when referenced by invoices.
- **Copy branch configuration**: source → target, mode `replace`|`merge`; confirmation enforced client-side and idempotent server-side; audit with affected services.
- **Resolve effective price (read)**: given service, branch, and date, return the resolved price and which rule applied (promo/override/default); used for price preview and reused by add-to-invoice.
- **Add catalog service to invoice** (billing integration): validate eligibility, resolve effective price for invoice branch/date, create-or-increment the invoice item with snapshot fields; reuses V1-6 draft-only item mutation rules.
- **List/search services (read)**: filter by name, global status, branch; paginated; `services.view` or `services.manage`.

### RLS Policies

Policies on catalog tables MUST enforce:

- Authenticated access only.
- Organization isolation for services: `organization_id` must match the user's organization.
- Branch scoping for `ServiceBranch`: `branch_id` must be within the user's organization; management mutations require `services.manage`.
- Read access for service selection permitted to users with `invoices.create` for their assigned branches (eligible services only).
- Exclusion of soft-deleted rows from operational queries; historical invoice items reference retained (soft-deleted) services for display.
- Direct INSERT/UPDATE/DELETE on catalog tables denied; mutations occur via secured functions only.
- No cross-organization reads or writes in verification scenarios.

### Permissions

Only administrators (`owner`, `administrator`) may create services, edit services, configure branch assignments/activation/overrides, configure promotions, change global status, soft-delete, and copy configuration (`services.manage`). Browsing the catalog management surface requires `services.view`. Users issuing invoices (`invoices.create`) may only select existing eligible services; they may not manage the catalog or free-type service names.

### UI States

- **Catalog List — Loading / Results (name, default price, global status, branch summary) / Empty / Filter active (name, status, branch) / Pagination / Permission Denied / Error**
- **Service Create/Edit — Idle / Validating (inline name & price validation) / Duplicate-name error / Saving / Saved / Stale conflict (refresh prompt) / Permission Denied / Error**
- **Branch Configuration Matrix — Per-branch rows: Assigned toggle / Active toggle / Price override input (empty = default) / Promotion editor (price + start + end, inclusive) / Validation error (promo > effective, missing/invalid dates) / Saving / Saved**
- **Promotion Editor — Empty (no promotion) / Configured (price + inclusive window) / Expired indicator / Validation Error**
- **Copy Configuration — Source & target branch pickers / Mode selector (Merge missing / Replace) / Replace confirmation dialog / Copying / Success (affected services summary) / Permission Denied / Error**
- **New-Branch Service Setup — Prompt on branch creation / Setup method (Select services from catalog · Copy entirely from another branch · Copy-then-modify) / Selecting or copying / Saved / Skipped (branch has no services yet) / Permission Denied / Error**
- **Invoice Service Selector (in billing editor) — Type-ahead search / Eligible results with price + "on promotion" badge / No eligible services (empty) / Selected (line added, quantity 1) / Quantity edit / Duplicate → increment / Backend-first loading / Error**
- **Global Status Toggle — Active / Inactive (non-selectable everywhere) / Saving**

### Validation Rules

- Service name is required, trimmed, and unique per organization (case-insensitive) among non-deleted services.
- `default_price`, `price_override`, `promotion_price` MUST be non-negative decimals at scale 2.
- A promotion requires both start and end dates with start ≤ end; the window is inclusive on both ends.
- `promotion_price ≤` effective branch price (override if set, else default), enforced both when saving a promotion and when later changing the default price or override (a change violating this invariant is rejected until the promotion is adjusted or cleared).
- Branch configuration (activation/override/promotion) is allowed only for branches the service is assigned to.
- Invoice items MUST reference an eligible catalog service; free-text names are rejected.
- Invoice-item quantity MUST be a positive integer; unit price is server-resolved and not user-typed.
- A service may appear at most once per invoice (re-selection increments quantity).
- Editing/soft-deleting a service MUST NOT alter previously issued invoice items.

### AI Hooks

This feature introduces no AI-assisted workflow. Catalog management and invoice service selection remain fully manual. Any future AI assistance (e.g., pricing suggestions) MUST be approval-gated per product principles and MUST NOT be required for any acceptance scenario here.

### Audit Requirements

- Service create/edit, branch assignment change, branch activation change, price override set/clear, promotion set/clear/replace, global-status change, and soft-delete MUST write audit entries with prior and new key values.
- Copy operations MUST write an audit entry with source branch, target branch, mode, and affected services.
- Add-to-invoice pricing resolution is captured via the invoice item snapshot (and the existing billing audit trail); catalog reads are not individually audited unless architecture mandates it later.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics that need a single governed list of billable services with per-branch pricing and simple, time-boxed promotions. Enterprise/hospital concerns (service taxonomies, bundles, tax engines, cost/margin, inventory, multi-currency, analytics) are explicitly out of scope.
- **Layer Placement**: The Flutter desktop client owns the catalog management UI (list, create/edit form, per-branch configuration matrix, promotion editor, copy flow), the invoice service selector, price-preview display, permission-aware controls, and validation messaging — organized as a modular clean-architecture feature (`domain` / `data` / `application` / `presentation`) under `frontend/lib/features/service_catalog`, exposing only a repository/provider surface to billing. Supabase exposes the secured RPCs and RLS-scoped reads. PostgreSQL owns the `services` and `service_branches` schema, uniqueness and non-negative-price constraints, eligibility and price-resolution logic, one-promotion-per-branch enforcement, invoice-item snapshotting on add, soft-delete, audit writes, and verification utilities. The AI layer is not involved.
- **Data Integrity & Security**: Mutations run through secured, permission-gated functions; RLS enforces organization isolation for services and branch scoping for configuration; price resolution and eligibility are server-authoritative and reused by both price-preview and add-to-invoice so the client never becomes the source of truth; monetary values use exact decimals at scale 2; soft delete preserves history; audit logs capture all sensitive changes; defense in depth spans UI, functions, and policies.
- **Failure Handling**: Save/mutation failures surface clear errors without false success; catalog list and selectors use backend-first fetches and degrade to last-known-good with connectivity messaging; concurrent edits are protected by optimistic concurrency; AI unavailability does not affect any workflow; subscription-degraded mode never deletes data and, at worst, limits mutations to read-only while existing services remain selectable for invoicing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of invoice-selection test scenarios, only services that are globally active, assigned to the invoice branch, and branch-active are selectable; all other services are excluded.
- **SC-002**: In 100% of pricing test scenarios, the effective unit price applied equals the priority resolution (active promotion → branch override → default) for the invoice's branch and date, including inclusive promotion boundaries.
- **SC-003**: In 100% of history-stability test scenarios, changing or soft-deleting a service after invoicing leaves previously issued invoice items unchanged.
- **SC-004**: In 100% of permission test scenarios, users without `services.manage` cannot mutate the catalog, and users without `services.view`/`services.manage` cannot open the management surface, while `invoices.create` users can still select eligible services.
- **SC-005**: In 100% of promotion-validation scenarios, promotions with a price above the effective branch price, missing a start or end date, or with start after end are rejected; and any later default-price or override change that would leave an existing promotion above the new effective price is also rejected until the promotion is adjusted or cleared.
- **SC-006**: In 100% of copy scenarios, "merge missing only" leaves existing target entries untouched, and "replace" overwrites only after explicit confirmation (and makes no changes on cancel).
- **SC-007**: In 100% of isolation scenarios, cross-organization service access is blocked and unassigned-branch configuration is rejected.
- **SC-008**: An administrator can create a service, assign branches, set an override and a promotion for a branch, and confirm the price appears correctly in the invoice selector in under 3 minutes in usability testing with representative data.
- **SC-009**: Reception staff can add a correctly-priced service to an invoice via search-and-select in under 15 seconds under normal local clinic network conditions in 95% of test runs, with no ability to mistype the price.

## Assumptions

- `specs/002-auth-rbac`, `specs/003-org-branch-management`, `specs/004-patient-management`, `specs/006-visit-medical-records`, and `specs/007-billing` are implemented; this feature builds on the existing organization, branch, permission, audit, and billing foundations.
- Services are **organization-scoped** and isolated via the existing branch-based multi-tenant design; there is no global/shared service registry across organizations.
- New permission keys `services.view` and `services.manage` are seeded to `owner` and `administrator` only; no new role is introduced; `receptionist` retains service **selection** through the existing `invoices.create` key.
- The invoice-item contract from `specs/007-billing` is extended: new invoice items require a catalog `service_id` and store name/unit-price/quantity/total snapshots; the free-text description entry path is **removed entirely** and totally replaced by catalog selection. Historical invoice items are not migrated and remain valid (immutable) for display.
- Unit price is server-resolved and immutable on the line; per-invoice price reduction, where permitted, continues to use the V1-6 line-level/invoice-level **discount** mechanism rather than a typed unit price. Promotions are an administrator/catalog-level pricing concern, not a per-invoice typed value.
- Monetary amounts use exact decimals at scale 2 (per `specs/007-billing` NFR-007); each organization operates in a single configured currency (multi-currency is out of scope).
- Only one promotion window per service per branch is modeled; overlapping or scheduled multi-promotion campaigns are out of scope.
- "All branches" assignment is resolved to explicit per-branch configuration rows at save time; branches created **after** a service was saved as "all branches" are **not** retroactively auto-assigned. Instead, newly created branches go through a service setup step (select from catalog / copy entirely from another branch / copy-then-modify per FR-031) so branch onboarding is explicit and auditable; silent auto-propagation to future branches is out of scope.
- Soft delete follows the shared schema conventions; services referenced by invoices are never hard-deleted.
- Catalog list, service editor, and invoice service selector follow the backend-first fetch principle established in prior features.
- AI remains optional and non-blocking; no AI capability is required for any catalog or invoicing workflow in this feature.
- The client is a Flutter desktop app; the feature is delivered as a modular clean-architecture unit (`domain`/`data`/`application`/`presentation`) reusing the existing `core/ui` design system, Riverpod state management, and GoRouter navigation, consistent with the rest of the codebase.
