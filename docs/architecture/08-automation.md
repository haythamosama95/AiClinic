# Automation

- Purpose: Capture the future workflow automation engine without forcing every feature to load that context.
- Read this when: working on trigger-action workflows, notification automation, WhatsApp integrations, or future rule execution behavior.
- Canonical for: workflow trigger events, action types, and rule configuration.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/07-frontend.md`, and future workflow-related specs.
- Not covered here: core patient/appointment/billing flows that do not involve the workflow engine.

---

## Workflow Automation System

> **Note:** Workflow automation is defined architecturally for future reference but is not included in the current project phases. It will be implemented in a future iteration.

### Architecture

The workflow system is a lightweight, configurable trigger-action engine. It is intentionally simple -- no DAGs, no complex branching, no conditional logic trees.

```
Event occurs (e.g., appointment created)
        │
        ▼
PostgreSQL trigger fires
  → inserts record into `workflow_event_queue` table
        │
        ▼
Flutter app polls `workflow_event_queue` (or receives via Realtime subscription)
        │
        ▼
Workflow Engine (in Flutter service layer) evaluates matching rules
        │
        ▼
For each matching rule, executes the action:
  - In-app notification: insert into notifications table
  - WhatsApp message: HTTP call to third-party API
  - Status update: supabase.rpc() call
        │
        ▼
Log execution result to `workflow_executions`
```

### Trigger Events

Triggers are database-level events emitted by PostgreSQL triggers into a `workflow_event_queue` table:

| Trigger Event                | Fired When                                                          |
| ---------------------------- | ------------------------------------------------------------------- |
| `appointment.created`        | New appointment inserted                                            |
| `appointment.cancelled`      | Appointment status changed to cancelled                             |
| `appointment.status_changed` | Any appointment status transition                                   |
| `invoice.created`            | New invoice inserted                                                |
| `invoice.overdue`            | Invoice past due_date and not fully paid (checked by scheduled job) |
| `patient.created`            | New patient registered                                              |
| `shift.assigned`             | Staff member assigned to a shift                                    |
| `visit.completed`            | Visit status set to completed                                       |

### Action Types

| Action Type           | Mechanism                         | Config Schema                                                          |
| --------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| `in_app_notification` | Insert into `notifications` table | `{ "title_template": "...", "body_template": "..." }`                  |
| `whatsapp_message`    | HTTP POST to WhatsApp API gateway | `{ "template_id": "...", "recipient_field": "patient.phone" }`         |
| `status_update`       | Supabase RPC call                 | `{ "target_table": "...", "target_field": "...", "new_value": "..." }` |

### Rule Configuration

Rules are stored in the `workflow_rules` table and managed via a settings UI. Each rule defines:

- Which trigger event to listen for
- Which action to execute
- A JSON configuration for the action (templates, target fields)
- Whether the rule applies to a specific branch or all branches

---
