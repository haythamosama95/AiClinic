# Contract: Branch Switcher (Main Shell)

## Purpose

Primary active-branch selection for multi-branch staff after V1-2 (replaces placeholder-shell selector as main control).

## Data source

**Provider**: Reuse `staffAssignableBranchesProvider` — branches from assignments where `is_active = true` and `is_deleted = false` (align with JWT claim filter).

**Session**: `AuthSessionContext.activeBranchId` updated locally; no re-login required.

## Placement

Per `docs/architecture/07-frontend.md` → Navigation Architecture:

- **Target**: Status bar region — `Branch | User | Connection`
- **Migration**: Remove or demote `ShellBranchSelector` in `AuthShellPage` AppBar when main shell layout lands; until full sidebar shell ships, status bar may be implemented as `BottomNavigationBar` strip or footer bar on `AuthShellPage` with documented follow-up to full sidebar shell (V1-3+).

## Behavior

| Condition                   | UI                                                      |
| --------------------------- | ------------------------------------------------------- |
| Multiple active assignments | Dropdown / menu of branch names                         |
| Single assignment           | Show branch name; no misleading empty dropdown          |
| Zero active assignments     | Disabled + link to blocked guidance (same copy as V1-1) |

**Performance**: Perceived switch &lt; 2s (NFR-005)

## Authorization

No separate permission — any authenticated user with active assignments may switch among **their** assigned active branches only.

## Out of scope

- Changing branch assignments (staff management)
- Cross-org branch list
