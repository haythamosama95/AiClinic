# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`

**Created**: [DATE]

**Status**: Draft

**Input**: User description: "$ARGUMENTS"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - [Brief Title] (Priority: P1)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently - e.g., "Can be fully tested by [specific action] and delivers [specific value]"]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]
2. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 3 - [Brief Title] (Priority: P3)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

[Add more user stories as needed, each with an assigned priority]

### Edge Cases

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right edge cases.
-->

- What happens when AI is unavailable during a workflow that normally offers assistance?
- How does the feature behave when a user lacks tenant-scoped or branch-scoped
  permission for the requested action?
- What happens when network, sync, or backend connectivity is degraded but clinic work
  still needs to continue safely?

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

- **FR-001**: System MUST [identify which responsibilities belong in Flutter, Supabase,
  PostgreSQL, and the AI service]
- **FR-002**: System MUST [enforce tenant-scoped and branch-scoped permissions for
  protected data and actions]
- **FR-003**: System MUST [keep domain validation, transactional correctness, and source
  of truth in PostgreSQL-backed mechanisms]
- **FR-004**: System MUST [preserve auditability, shared schema conventions, and soft
  deletion where records are operationally significant]
- **FR-005**: System MUST [degrade safely when AI or backend dependencies are
  unavailable]

*Example of marking unclear requirements:*

- **FR-006**: System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]
- **FR-007**: System MUST retain user data for [NEEDS CLARIFICATION: retention period not specified]

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [What it represents, key attributes without implementation]
- **[Entity 2]**: [What it represents, relationships to other entities]

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: [Explain how this feature serves small-to-mid-size multi-branch
  clinics and note any explicitly out-of-scope enterprise or hospital needs]
- **Layer Placement**: [State what lives in Flutter, Supabase, PostgreSQL, and AI
  service for this feature]
- **Data Integrity & Security**: [List required constraints, RLS, RPC/functions,
  permissions, audit fields/logs, and soft-delete expectations]
- **Failure Handling**: [Describe behavior when AI, network, or backend services are
  unavailable or degraded]

## Success Criteria *(mandatory)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: [Measurable metric, e.g., "Users can complete account creation in under 2 minutes"]
- **SC-002**: [Measurable metric, e.g., "System handles 1000 concurrent users without degradation"]
- **SC-003**: [User satisfaction metric, e.g., "90% of users successfully complete primary task on first attempt"]
- **SC-004**: [Business metric, e.g., "Reduce support tickets related to [X] by 50%"]

## Assumptions

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right assumptions based on reasonable defaults
  chosen when the feature description did not specify certain details.
-->

- [Assumption about target users, e.g., "Primary users are clinic staff operating on
  Windows desktop systems"]
- [Assumption about scope boundaries, e.g., "Mobile support and enterprise integrations
  are out of scope unless explicitly requested"]
- [Assumption about data/environment, e.g., "Branch-aware authentication and tenant
  isolation patterns will be reused"]
- [Dependency on existing system/service, e.g., "AI assistance remains optional and must
  fail back to manual workflows"]
