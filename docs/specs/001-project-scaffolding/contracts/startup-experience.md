# Contract: Startup Experience

## Purpose

Defines the user-visible behavior for the V1-0 pre-auth startup flow.

## Required States

| State                     | Entry Condition                                                     | Required Behavior                                                                              |
| ------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `startup-check`           | App launches and begins configuration/health evaluation             | Show loading/progress feedback.                                                                |
| `setup-guidance`          | Deployment profile is missing or invalid                            | Show actionable instructions and block protected routes.                                       |
| `unauthenticated-entry`   | Profile is valid                                                    | Show connection status and clear next-step guidance without exposing authenticated navigation. |
| `degraded-startup`        | Profile is valid but backend is unreachable                         | Keep the startup experience visible, show degraded status, and block unsafe protected actions. |
| `protected-route-blocked` | User attempts to enter a protected destination without auth context | Show a short explanation and return the user to `unauthenticated-entry`.                       |

## Guard Rules

- Any protected route request without authenticated context must be denied.
- Denied navigation must always return the user to the unauthenticated entry experience.
- Startup must never expose protected feature navigation in V1-0.

## Visible UI Requirements

- Connection status is always visible in the startup experience.
- Setup/configuration problems are presented with actionable guidance.
- Shared loading and error treatments are used consistently.
- Light and dark theme behavior is supported from the start.

## Out of Scope

- Full authenticated shell navigation
- Post-login user or branch context
- AI-assisted startup decisions
