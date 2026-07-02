# Service Catalog

## Overview

A Service Catalog shall be introduced to manage the services provided by the clinic.

Services are configured by administrators and are the only services that may be added to invoices.

Each service has a default price. Branches may optionally override this price, activate or deactivate the service independently, and configure promotional pricing.

---

# Functional Requirements

## Service Management

### Create Service

The administrator shall be able to create a service with the following information:

- Name
- Default Price
- Branch Assignment
  - All branches
  - Selected branches
- Optional branch-specific configuration
- Global Status
  - Active
  - Inactive

### Branch Assignment

When creating or editing a service, the administrator shall configure the branches in which the service is available.

The service may be assigned to:

- All branches
- One or more selected branches

Only assigned branches shall be able to use the service when issuing invoices.

### Branch Configuration

Each assigned branch may configure the following independently:

- Active / Inactive
- Price Override
- Promotional Price (optional)
- Promotion Start Date
- Promotion End Date

If no branch-specific price is configured, the branch shall use the service's default price.

A promotional price may only be configured when both a start and end date are provided.

The promotional period shall be inclusive of both the start and end dates.

Example:

| Branch | Status | Price Override | Promotion |
|---------|--------|---------------:|-----------|
| Branch A | Active | Default | None |
| Branch B | Active | 150 | None |
| Branch C | Active | 120 | 100 (01-Jan to 31-Jan) |
| Branch D | Inactive | Default | None |

### Edit Service

The administrator shall be able to modify:

- Name
- Default Price
- Assigned branches
- Branch-specific configuration
- Global Status

Editing a service shall only affect future invoices.

Previously issued invoices shall remain unchanged.

### Global Status

Services may be marked as:

- Active
- Inactive

A globally inactive service shall not be selectable in any branch regardless of its branch-specific configuration.

Historical invoices shall remain unchanged.

---

## Copy Services Between Branches

Administrators shall be able to copy branch configuration from one branch to another.

The copy operation shall include:

- Service assignments
- Activation status
- Price overrides
- Promotional pricing

The copy operation shall support:

- Replace existing configuration
- Merge missing configuration only

The system shall request confirmation before replacing existing configuration.

---

## Invoice Integration

When creating or editing an invoice, users shall select one or more services from the Service Catalog.

Users shall not be allowed to manually enter service names.

Only services that satisfy all of the following conditions shall be available:

- The service is globally active.
- The service is assigned to the invoice's branch.
- The service is active for the invoice's branch.

The system shall determine the unit price using the following priority:

1. Active promotional price (if the invoice date falls within the promotion period).
2. Branch-specific price override.
3. Service default price.

Each invoice item shall contain:

- Service
- Quantity
- Unit Price
- Total Price

Quantity shall default to **1** and may be modified.

The total price shall be calculated as:

```
Quantity × Unit Price
```

---

## Promotional Pricing

Promotional pricing shall be configured per branch.

Each promotion shall contain:

- Promotional Price
- Start Date
- End Date

Business Rules:

- The promotional price shall be lower than or equal to the effective branch price.
- Start Date shall be earlier than or equal to End Date.
- Only one active promotion shall exist for a service within the same branch at any point in time.
- Promotions shall automatically become active and expire based on the current date.
- Outside the promotion period, the branch price override or default service price shall be used.

---

## Invoice Snapshot

When a service is added to an invoice, the system shall store an immutable snapshot containing:

- Service ID
- Service Name
- Applied Unit Price
- Quantity
- Total Price

Subsequent modifications to the service, branch configuration, or promotional pricing shall not affect previously issued invoices.

---

## Permissions

Only administrators shall be allowed to:

- Create services
- Edit services
- Configure branch assignments
- Configure branch activation
- Configure branch price overrides
- Configure promotional pricing
- Change global service status
- Copy services between branches

Users issuing invoices may only select existing services.

---

# Business Rules

- Only globally active services may be used.
- Only services assigned to the invoice's branch may be used.
- Only branch-active services may be used.
- Manual entry of service names is prohibited.
- Historical invoices shall remain immutable.
- Promotional pricing takes precedence over all other pricing.
- Branch price overrides take precedence over the default service price.
- If no branch override exists, the default service price shall be used.
- Multiple services may be added to the same invoice.
- A service may appear only once within an invoice. Selecting it again shall increase its quantity.

---

# Data Model

## Service

| Field | Description |
|--------|-------------|
| Id | Unique identifier |
| Name | Service name |
| DefaultPrice | Default price |
| GlobalStatus | Active / Inactive |
| CreatedAt | Creation timestamp |
| UpdatedAt | Last modification timestamp |

## ServiceBranch

| Field | Description |
|--------|-------------|
| ServiceId | Service identifier |
| BranchId | Branch identifier |
| Status | Active / Inactive |
| PriceOverride | Nullable branch-specific price |
| PromotionPrice | Nullable promotional price |
| PromotionStartDate | Nullable |
| PromotionEndDate | Nullable |

A null `PriceOverride` indicates that the branch uses the service's default price.

A null promotion indicates that no promotional pricing is currently configured.

## InvoiceItem

| Field | Description |
|--------|-------------|
| InvoiceId | Invoice identifier |
| ServiceId | Service identifier |
| ServiceName | Snapshot of the service name |
| UnitPrice | Snapshot of the applied unit price |
| Quantity | Quantity |
| TotalPrice | Snapshot of the calculated total |

---

## Implementation (015)

Delivered in feature branch `015-service-catalog`. Authoritative design artifacts:

- Specification: [`specs/015-service-catalog/spec.md`](../specs/015-service-catalog/spec.md)
- Plan & tasks: [`specs/015-service-catalog/plan.md`](../specs/015-service-catalog/plan.md), [`specs/015-service-catalog/tasks.md`](../specs/015-service-catalog/tasks.md)
- RPC contracts: [`specs/015-service-catalog/contracts/`](../specs/015-service-catalog/contracts/)
- Verification walkthrough: [`specs/015-service-catalog/quickstart.md`](../specs/015-service-catalog/quickstart.md)

Key code locations:

- Backend migrations: `backend/supabase/migrations/20260712090000_service_catalog.sql` through `20260712091500_service_catalog_billing_integration.sql`
- Backend tests: `backend/tests/service_catalog_*.sql`
- Flutter feature: `frontend/lib/features/service_catalog/`
- Branch copy UI: `copy_configuration_dialog.dart` on the catalog list page
- New-branch setup (FR-031): `new_branch_service_setup.dart` shown after branch creation in settings
