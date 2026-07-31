# Data Model: Project Scaffolding

This feature introduces no clinic-domain database tables. The model below captures the configuration and runtime entities needed to implement V1-0 safely.

## Entity: DeploymentProfile

**Purpose**: Defines how a device connects to the clinic-local backend during startup.

| Field                | Kind   | Required | Notes                                                                                  |
| -------------------- | ------ | -------- | -------------------------------------------------------------------------------------- |
| `deployment_mode`    | enum   | Yes      | Fixed to `local` for V1-0. Any other value is invalid.                                 |
| `supabase_url`       | string | Yes      | Clinic LAN URL for the Supabase gateway, typically `http://<receptionist-ip>:54321`.   |
| `supabase_anon_key`  | string | Yes      | Public/anon client key required for client initialization.                             |
| `ai_service_url`     | string | No       | Reserved for later features; may exist in the profile but must not block V1-0 startup. |
| `source_device_role` | enum   | No       | Optional hint such as `server-node` or `client-node` for setup guidance and docs.      |

**Validation rules**

- `deployment_mode` must be `local`.
- `supabase_url` must be non-empty and syntactically valid.
- `supabase_anon_key` must be present before startup can proceed.
- Missing or invalid required fields place startup in the invalid-configuration state.

## Entity: StartupSessionState

**Purpose**: Represents the current pre-auth startup experience visible to the user before authentication exists.

| Field                  | Kind      | Required | Notes                                                                                     |
| ---------------------- | --------- | -------- | ----------------------------------------------------------------------------------------- |
| `configuration_status` | enum      | Yes      | `unknown`, `valid`, `missing`, or `invalid`.                                              |
| `connectivity_status`  | enum      | Yes      | `unknown`, `healthy`, `degraded`, or `unreachable`.                                       |
| `current_view`         | enum      | Yes      | `startup-check`, `unauthenticated-entry`, `setup-guidance`, or `protected-route-blocked`. |
| `theme_mode`           | enum      | Yes      | `light`, `dark`, or `system`.                                                             |
| `blocked_reason`       | string    | No       | Human-readable reason shown when protected access is denied or configuration is invalid.  |
| `last_health_check`    | timestamp | No       | Most recent backend reachability check used for visible status.                           |

**State transitions**

- `startup-check -> unauthenticated-entry` when configuration is valid and backend is reachable.
- `startup-check -> setup-guidance` when configuration is missing or invalid.
- `startup-check -> unauthenticated-entry` with `connectivity_status=degraded` when configuration is valid but the backend is unreachable.
- `unauthenticated-entry -> protected-route-blocked` when the user attempts to access a protected route without auth context.
- `protected-route-blocked -> unauthenticated-entry` after the redirect/notice is shown.

## Entity: SharedUIComponent

**Purpose**: Defines reusable interface primitives established in V1-0 for use by future features.

| Field                    | Kind    | Required | Notes                                                                        |
| ------------------------ | ------- | -------- | ---------------------------------------------------------------------------- |
| `component_name`         | string  | Yes      | Examples: button, card, data table, dialog, form field, loading state.       |
| `supports_loading`       | boolean | Yes      | Indicates whether the primitive has a loading representation.                |
| `supports_error_display` | boolean | Yes      | Indicates whether the primitive integrates with shared failure presentation. |
| `theme_aware`            | boolean | Yes      | Must render correctly in light and dark modes.                               |
| `usage_scope`            | enum    | Yes      | `startup-only` or `shared-across-features`.                                  |

**Validation rules**

- All shared components must support the selected theme system.
- Components used in startup flows must expose consistent loading and error states.

## Entity: EnvironmentSetupGuide

**Purpose**: Captures the documentation package needed to prepare development machines and clinic devices consistently.

| Field                    | Kind | Required | Notes                                                                      |
| ------------------------ | ---- | -------- | -------------------------------------------------------------------------- |
| `audience`               | enum | Yes      | `developer`, `server-node operator`, or `client-device operator`.          |
| `prerequisites`          | list | Yes      | Docker, Flutter, Supabase CLI, and other required tools for that audience. |
| `steps`                  | list | Yes      | Ordered setup steps the audience must follow.                              |
| `verification_checks`    | list | Yes      | Concrete checks proving the setup succeeded.                               |
| `failure_recovery_notes` | list | No       | What to do when setup or connectivity verification fails.                  |

## Relationships

- A `DeploymentProfile` drives one `StartupSessionState`.
- `SharedUIComponent` instances are rendered inside the `StartupSessionState` views.
- An `EnvironmentSetupGuide` produces the validated `DeploymentProfile` expected by startup.
