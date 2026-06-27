# Senior QA Review — `<head-branch>`

**Base branch:** `<base-branch>`
**Head:** `<head-branch>` (`<head-sha>`)
**Scope:** <N> files, +<additions> / −<deletions> lines across <brief module summary>.

This document analyzes every commit and functional change between `<base-branch>` and `<head-branch>`, identifies regression and risk areas, and defines a production-oriented test suite. Findings assume the implementation may contain defects.

---

## Executive summary

<One paragraph: what the branch does and overall release risk.>

**Release confidence blockers to verify manually:**

| Area | Risk |
| ---- | ---- |
| <area> | <concise risk> |

---

## Commit-by-commit change analysis

### `<short-sha>` — <commit subject>

| Category | Detail |
| -------- | ------ |
| **<category>** | <what changed> |

**Affected systems:** <modules, routes, RPCs, tables>

**Regression areas:** <existing features at risk>

**Risks:** <specific failure modes>

---

## Cross-cutting findings

### Missing test coverage

- <item>

### Potential bugs

| ID | Severity | Area | Description | Related change |
| -- | -------- | ---- | ----------- | -------------- |
| BUG-001 | Critical/High/Medium/Low | <module> | <description> | `<sha>` |

### Potential performance issues

- <item>

### Potential security concerns

- <item>

### Risky implementation decisions

- <item>

### Manual testing required before release

- <item>

---

## Test suite

### Functional tests

#### FUNC-001 — <title>

| Field | Value |
| ----- | ----- |
| **Area/Module** | <module> |
| **Related commit** | `<sha>` — <subject> |
| **Priority** | Critical / High / Medium / Low |
| **Type** | Frontend / Backend / Integration / E2E / Regression |
| **Preconditions** | <setup> |

**Steps:**

1. <step>
2. <step>

**Expected result:** <outcome>

---

### Frontend tests

#### FE-001 — <title>

(same table format)

---

### Backend tests

#### BE-001 — <title>

(same table format)

---

### Integration tests

#### INT-001 — <title>

(same table format)

---

### Edge & corner cases

#### EDGE-001 — <title>

(same table format)

---

### Regression tests

#### REG-001 — <title>

(same table format)

---

### User abuse tests

#### ABUSE-001 — <title>

(same table format)

---

## Verification commands

<List concrete commands to run existing automated tests affected by this branch, e.g. `flutter test`, migration apply, RPC tests. Omit if none apply.>

---

## Coverage matrix (optional)

| Change area | Automated coverage | Manual only | Gap |
| ----------- | ------------------ | ----------- | --- |
| <area> | Yes/Partial/No | Yes/No | <note> |
