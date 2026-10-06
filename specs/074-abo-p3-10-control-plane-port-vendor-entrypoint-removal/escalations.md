# P3.10 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Plan catalogue behaviours in `plan-catalogue.test.ts`

**Question:** `plan-catalogue.test.ts` still exercises removed HTTP plan/entitle/override control handlers and the dropped `plan` / `entitlement` tables end-to-end. The plan says setup goes through `coverClinic` and `plan_version`, but it does not spell out which catalogue behaviours (create/update/delete plan rows, entitle copying economics, override, config-cache entitlement reads) should be re-targeted to `publishPlanVersion` / `VendorEntrypoint` versus dropped from this workers-pool file.

**Assumption:** In `plan-catalogue.test.ts`, creating a catalogue row is one call to the existing `publishPlanVersion` on `env.VENDOR` (the HP access JWT, passkey assertion, and arguments that method already accepts — the same publish `coverClinic` performs, without calling `coverClinic`). The case reads that `plan_version` row and expects `status` `published` and the method's existing `ok` detail. Plan update, plan delete, non-operator rejection of those HTTP handlers, entitle copying economics, per-installation override, and config-cache reads of `plans` and `entitlements` are removed from this file. They are not calls to `publishPlanVersion`, `retirePlanVersion`, or any other `VendorEntrypoint` method. `publishPlanVersion` and `retirePlanVersion` result rules stay as they are. The other T029 files stay on `coverClinic` and `plan_version` setup.

**Why:** 04 §6.5 rewrites this file, so it stays in the workers pool, and the only catalogue write this unit still has is immutable `publishPlanVersion` into `plan_version` (FR-008). Update, delete, entitle, and override were HTTP handlers this unit removes (FR-007); putting them on `publishPlanVersion` would change result rules the plan freezes. Config-cache `plans` and `entitlements` already return `"miss"` without querying the dropped tables (Sequencing step 19, FR-009). Former `/control` plan, entitle, and override paths stay the 404s in E2E-P3.10-01.

**Amended:** `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/plan.md` (Files paragraph, Test Layout `plan-catalogue.test.ts` mapping, Sequencing step 28); `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/tasks.md` (T029).
