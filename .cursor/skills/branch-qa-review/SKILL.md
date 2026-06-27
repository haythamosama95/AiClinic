---
name: branch-qa-review
description: Compare a feature branch against a base branch, analyze every commit and functional change, and produce a comprehensive QA test suite with risk assessment. Use when the user provides branch names for review, asks for QA analysis, test case generation, regression testing plans, pre-merge quality review, or release confidence assessment.
---

# Branch QA Review

## User Input

```text
$ARGUMENTS
```

Parse **two required inputs** from `$ARGUMENTS`:

| Input | Description |
|-------|-------------|
| **Head branch** | The feature branch to review |
| **Base branch** | The branch to compare against (e.g. `main`, `ui/master`) |

If either branch is missing, ask the user before proceeding.

---

## Workflow

Copy this checklist and track progress:

```
Task Progress:
- [ ] Step 1: Gather git diff and commit history
- [ ] Step 2: Read changed files and understand functional impact
- [ ] Step 3: Apply QA analysis methodology (below)
- [ ] Step 4: Generate test cases and risk findings
- [ ] Step 5: Write output markdown file
```

### Step 1: Gather git diff and commit history

Run from repo root:

```bash
# Verify branches exist
git rev-parse --verify <head-branch>
git rev-parse --verify <base-branch>

# Commit list (oldest first for narrative)
git log --oneline --reverse <base-branch>..<head-branch>

# Scope summary
git diff --stat <base-branch>...<head-branch>

# Full diff for analysis
git diff <base-branch>...<head-branch>

# Per-commit patches (use when commits are granular)
git log --reverse --format='%H %s' <base-branch>..<head-branch> | while read hash subject; do
  echo "=== $hash $subject ==="
  git show --stat "$hash"
done
```

Record: head SHA, base branch name, file count, line additions/deletions.

### Step 2: Read changed files

For each changed path, read the actual code — do not infer behavior from filenames alone.

Prioritize:

- Feature modules touched (frontend `lib/features/**`, backend `supabase/migrations/**`, RPCs, RLS)
- Shared widgets, services, providers, repositories
- Router/navigation, auth/RBAC, database schema
- Existing tests in the diff (note gaps, do not assume they pass)

Cross-reference `docs/architecture/` and related `docs/implementation/` guides when the change touches documented systems.

### Step 3–4: QA analysis methodology

Act as a Senior QA Engineer, Senior Software Tester, and Code Reviewer.

For every commit and every functional change:

1. Identify:
   - New features
   - Bug fixes
   - Refactors
   - UI changes
   - API changes
   - Database changes
   - State management changes
   - Permission/security changes
   - Performance-related changes

2. Explain:
   - What changed
   - Which parts of the system are affected
   - Potential regression areas
   - Potential risks introduced by the change

3. Generate a comprehensive test suite that covers:

   Functional Testing
   - Happy paths
   - Alternative flows
   - Negative scenarios
   - Validation scenarios
   - Error handling

   Frontend Testing
   - UI rendering
   - Responsive behavior
   - Navigation
   - State updates
   - Loading states
   - Empty states
   - Error states
   - Animations
   - Transitions
   - Visual consistency

   Backend Testing
   - Business logic
   - API endpoints
   - Input validation
   - Authorization
   - Authentication
   - Data integrity
   - Database interactions
   - Concurrency scenarios

   Integration Testing
   - Frontend ↔ Backend communication
   - API contract validation
   - Data synchronization
   - Cache behavior
   - Offline/network interruption scenarios

   Edge & Corner Cases
   - Boundary values
   - Null values
   - Empty values
   - Extremely large inputs
   - Duplicate actions
   - Rapid repeated user actions
   - Invalid states
   - Race conditions
   - Unexpected navigation patterns
   - Partial failures

   Regression Testing
   - Existing functionality that could be affected
   - Shared components
   - Reused services
   - Global state changes

   User Abuse Testing
   - Random clicking
   - Double clicks
   - Rapid navigation
   - Multiple tabs
   - Refresh during operations
   - Back/forward browser navigation
   - Invalid URLs
   - Interrupted workflows

4. For each test case provide:
   - Test ID
   - Area/Module
   - Related commit/change
   - Priority (Critical/High/Medium/Low)
   - Test type (Frontend, Backend, Integration, E2E, Regression)
   - Preconditions
   - Steps
   - Expected result

5. After generating the test cases, identify:
   - Missing test coverage
   - Potential bugs
   - Potential performance issues
   - Potential security concerns
   - Risky implementation decisions
   - Areas that should be manually tested before release

Assume the implementation may contain bugs. Be skeptical and actively search for failure scenarios rather than assuming the code is correct.

The goal is to achieve production-release confidence and uncover defects before merge.

### Step 5: Write output markdown file

**Output path** (default):

```
docs/tests/QA_REVIEW_<sanitized-head-branch>.md
```

Sanitize the branch name: replace `/` with `-`, lowercase, strip invalid characters (e.g. `ui/008-calendar` → `ui-008-calendar`).

If the change is UI-only and the repo convention applies, use `docs/ui/QA_REVIEW_<sanitized-head-branch>.md` instead.

**Do not overwrite** an existing review without confirming with the user. If the file exists, append a dated section or ask whether to replace.

Use the structure in [output-template.md](output-template.md). Match the depth and tone of existing reviews such as `docs/ui/QA_REVIEW_ui-008-calendar.md`.

After writing the file, tell the user the full path and summarize top release blockers (if any).

---

## Test ID convention

Prefix test IDs by area for traceability:

| Prefix | Area |
|--------|------|
| `FUNC-` | Functional |
| `FE-` | Frontend |
| `BE-` | Backend |
| `INT-` | Integration |
| `E2E-` | End-to-end |
| `REG-` | Regression |
| `EDGE-` | Edge/corner cases |
| `ABUSE-` | User abuse |

Number sequentially within each prefix (e.g. `FE-001`, `BE-012`).

---

## Additional resources

- Output document structure: [output-template.md](output-template.md)
