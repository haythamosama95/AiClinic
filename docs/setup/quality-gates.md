# Quality gates

Baseline automated checks for the AiClinic desktop foundation (User Story 3). Run these before opening a pull request or merging feature work.

## Local commands

From the repository root:

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

| Step                    | Purpose                                                              |
| ----------------------- | -------------------------------------------------------------------- |
| `flutter analyze`       | Static analysis and lint rules from `analysis_options.yaml`          |
| `flutter test`          | Unit, widget, and integration tests under `frontend/test/`           |
| `flutter build windows` | Confirms the Windows desktop target compiles for clinic workstations |

## CI workflow

GitHub Actions runs the same gates on push and pull requests (`.github/workflows/ci.yml`):

- Checkout
- Flutter stable (cached)
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build windows --release`

CI uses `windows-latest` because V1-0 targets Windows desktop clients.

## Shared UI foundations

New screens should reuse components under `frontend/lib/core/widgets/` and theming from `frontend/lib/app/theme/`:

| Need                | Use                                            |
| ------------------- | ---------------------------------------------- |
| Actions             | `AppButton` (`primary`, `secondary`, `danger`) |
| Grouped content     | `AppCard`                                      |
| Forms               | `AppFormField`                                 |
| Tables              | `AppDataTable`                                 |
| Blocking load       | `AppLoadingState`                              |
| Recoverable errors  | `ErrorStatePanel`                              |
| Transient feedback  | `SnackbarService`                              |
| Confirmations       | `AppDialog`                                    |
| Theme mode          | `themeModeProvider` / `setAppThemeMode`        |
| Connectivity status | `connectivityStatusProvider`                   |

A reference screen that exercises these building blocks lives at `frontend/lib/features/foundation_demo/`. Reach it from the startup entry screen via **View shared foundations** when configuration is valid.

## Backend smoke (optional)

Stack validation is separate from frontend quality gates:

```bash
./backend/tests/validate_local_stack.sh
```

See [verification-checklist.md](./verification-checklist.md) for full workstation sign-off.
