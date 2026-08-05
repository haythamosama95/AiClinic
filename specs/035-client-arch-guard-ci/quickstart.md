# Quickstart: Client architecture guard in CI (E1)

E1 installs a permanent CI lint that fails the Flutter build when prompt-like strings,
provider names, or model identifiers appear anywhere in client source — proven by
deliberately failing fixtures and a clean-tree pass with full path coverage.

## 1. Architecture context

- **Delivery plan** — [§3.6 row E1](../../docs/architecture/17b-ai-platform-delivery-plan.md)
  (Band E, `Needs: —`). Must land before any client AI code (DP-6).
- **Architecture** — [`17-ai-platform.md` §13.5](../../docs/architecture/17-ai-platform.md)
  Architecture guard (R-12); [§3.4.1](../../docs/architecture/17-ai-platform.md) item 1
  (client-side lint as an architectural component, not an optional test).
- **Spec** — Five named CI-lint tests (T1–T5) proving detection of three forbidden
  categories plus clean-tree pass and full client-source coverage (FR-001–FR-006).
- **Plan** — Standalone Dart script under `frontend/tool/architecture_guard/`, fixtures
  outside clean scan roots, dedicated CI step on `frontend-quality` triggered on the
  `ai/**` branch line.

## 2. What was implemented

- Standalone Dart guard script (`architecture_guard.dart`) scanning `lib/`, `test/`,
  `windows/`, `linux/`, and `web/` (Dart + native/web text) with whole-file /
  whitespace-tolerant matching; exit 1 = violations/coverage gaps, exit 2 = missing
  scan root.
- Deliberately failing fixtures (multi-line prompt, platform-integrated provider id,
  current vendor + platform model ids) invoked with expect-fail exit-code-1 + category
  assertions; multi-root and `test/` probes prove every configured root is live.
- Tree-wide coverage discovery with an explicit exclusion list (T5), plus a lib-only
  omission case that must fail.
- Dedicated architecture-guard CI step; workflow triggers include `ai/**` pushes and
  PRs targeting `ai/master`.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/tool/architecture_guard/architecture_guard.dart` | Standalone CI lint script; detection patterns and coverage assertion |
| `frontend/tool/architecture_guard/fixtures/prompt_like_string/forbidden.dart` | T1 fixture — multi-line prompt-like string |
| `frontend/tool/architecture_guard/fixtures/provider_name/forbidden.dart` | T2 fixture — platform-integrated provider name |
| `frontend/tool/architecture_guard/fixtures/model_identifier/forbidden.dart` | T3 fixture — model identifiers |
| `frontend/tool/architecture_guard/fixtures/multi_root/` | Second-root scan proof |
| `.github/workflows/ci.yml` | Triggers + architecture-guard step (expect-fail + clean-tree gate) |

## 4. Prerequisites

Dart SDK `^3.11.5` (declared in `frontend/pubspec.yaml`). Flutter is not required to
run the guard script itself — only `dart` from the SDK.

## 5. Run the automated suite

From the repository root:

```bash
cd frontend

# T1 — guard_prompt_like_string_fails_build (expect exit 1 + "prompt-like string")
dart tool/architecture_guard/architecture_guard.dart \
  tool/architecture_guard/fixtures/prompt_like_string/

# T2 — guard_provider_name_fails_build (expect exit 1 + "provider name")
dart tool/architecture_guard/architecture_guard.dart \
  tool/architecture_guard/fixtures/provider_name/

# T3 — guard_model_identifier_fails_build (expect exit 1 + "model identifier")
dart tool/architecture_guard/architecture_guard.dart \
  tool/architecture_guard/fixtures/model_identifier/

# Multi-root second-root proof (expect exit 1)
dart tool/architecture_guard/architecture_guard.dart \
  tool/architecture_guard/fixtures/multi_root/root_a \
  tool/architecture_guard/fixtures/multi_root/root_b

# T5 omission case (expect non-zero)
dart tool/architecture_guard/architecture_guard.dart lib --assert-coverage

# Missing root is operator error (expect exit 2)
dart tool/architecture_guard/architecture_guard.dart \
  tool/architecture_guard/fixtures/does_not_exist

# T4 + T5 — guard_clean_tree_passes + coverage (expect zero)
dart tool/architecture_guard/architecture_guard.dart --assert-coverage
```

Expected: fixture / multi-root invocations exit 1; omission exits non-zero; missing root
exits 2; clean-tree exits zero with
`architecture_guard: clean — no forbidden content detected.`

## 6. Inspect the changes

```bash
# Open the guard script and fixtures
ls frontend/tool/architecture_guard/
cat frontend/tool/architecture_guard/architecture_guard.dart

# Confirm the CI step name and ai/** triggers in the workflow
grep -n "Architecture guard\|ai/\*\*\|ai/master" .github/workflows/ci.yml
```
