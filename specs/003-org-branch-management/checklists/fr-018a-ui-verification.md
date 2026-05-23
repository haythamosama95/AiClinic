# FR-018a UI verification: no soft-delete for branches or staff

**Purpose**: Manual sign-off that V1-2 management screens use `is_active` deactivate/reactivate only (spec FR-018a, acceptance criteria — no soft-delete UI).

**Date**: 2026-05-23
**Feature**: [spec.md](../spec.md)

## Branch list (`/settings/branches`)

- [ ] Row actions menu offers **Deactivate** or **Reactivate** only
- [ ] No **Delete**, **Remove permanently**, or **Soft delete** labels
- [ ] Inactive filter shows deactivated branches; active pickers elsewhere exclude them

## Branch form (`/settings/branches/new`, `.../edit`)

- [ ] No delete control on the form
- [ ] Save updates name/code/contact fields only

## Staff list (`/settings/staff`)

- [ ] Row actions menu offers **Deactivate** or **Reactivate** only
- [ ] No delete control

## Staff form (`/settings/staff/new`, `.../edit`)

- [ ] No delete control
- [ ] Deactivate lifecycle is from list menu or RPC-backed toggle, not `is_deleted` UI

## Automated smoke (CI)

`frontend/test/integration/settings/org_branch_management_acceptance_test.dart` → group **FR-018a — no soft-delete UI** asserts **Delete** text is absent on branch and staff lists.

## Sign-off

| Role     | Name | Date | Notes |
| -------- | ---- | ---- | ----- |
| Verifier |      |      |       |

When all boxes are checked, T058 manual checklist is satisfied.
