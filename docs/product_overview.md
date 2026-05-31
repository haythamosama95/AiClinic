# AI-First Clinic Operating System

## Product Overview Document

Version: 1.0
Status: Foundational Product Definition
Target Audience: AI Planning Agents, Architects, Developers, Product Managers
Primary Stack: Flutter + Supabase + Local AI Models
Architecture Style: Modular Domain-Driven Hybrid Local/Cloud SaaS

---

# 1. Product Vision

The product is an AI-first clinic operating system designed for multi-branch clinic organizations.

The system combines:

- traditional clinic management workflows
- deterministic backend business logic
- local-first AI execution
- optional cloud infrastructure
- modular workflow automation
- analytics and operational intelligence

The AI layer acts as an operational interaction interface rather than an autonomous decision maker.

The platform is NOT:

- an AI doctor
- a diagnostic engine
- a hospital ERP
- a fully autonomous agentic platform

The AI system is primarily responsible for:

- natural language interaction
- intent extraction
- structured command generation
- workflow acceleration
- operational assistance
- summarization
- analytics querying

All critical operations are validated and executed by deterministic backend systems.

---

# 2. Core Product Philosophy

## 2.1 AI as Interaction Layer

AI is treated as:

- a structured orchestration layer
- an intent parser
- an assistant

AI is NOT treated as:

- a business logic engine
- a direct database actor
- an autonomous executor

All writes and business rules are handled by backend validation layers.

---

## 2.2 Deterministic Backend Execution

AI-generated actions must always follow this flow:

User Prompt
→ AI Intent Parsing
→ Structured Command
→ Backend Validation
→ Human Approval
→ Execution

AI must NEVER:

- write directly to the database
- bypass validations
- bypass permissions
- mutate invoices directly
- mutate medical records directly

All actions require approval and confirmation.

---

## 2.3 Local-First Cost Optimization

The system is designed around:

- low operational cost
- low hardware requirements
- local AI execution
- lightweight deployment
- support for low-resource clinic environments

Minimum expected hardware:

- 8GB RAM
- no GPU
- older CPUs acceptable

Recommended hardware:

- 16GB RAM

AI systems must remain lightweight and modular.

---

## 2.4 Modular Architecture

The system must remain highly modular.

Architecture decisions:

- modular domains
- feature isolation
- strict boundaries
- independent specifications
- deterministic workflows

Monolithic feature coupling must be avoided.

---

# 3. Target Market

## Initial Market

- Egypt-based clinic organizations

## Future Expansion

- broader MENA region
- potentially global expansion

## Target Organizations

- multi-branch clinic organizations
- polyclinics
- medical centers
- specialty clinics

Not targeted:

- hospitals
- highly specialized enterprise medical ERP systems

## Users

- Applications users do not have a software or technical background.
- They appreciate straight forward appealing UI/UX experience.

---

# 4. Deployment Model

The platform supports multiple deployment tiers depending on subscription plans.

---

## 4.1 Tier 1 — Offline Local

Characteristics:

- local database only
- no cloud synchronization
- periodic local versioned backups

Use cases:

- highly cost-sensitive clinics
- clinics with unstable internet
- standalone branches

---

## 4.2 Tier 2 — Local + Cloud Backup

Characteristics:

- local operational database
- encrypted periodic cloud backup
- disaster recovery support

Use cases:

- clinics needing backup redundancy
- organizations wanting recovery capabilities

---

## 4.3 Tier 3 — Cloud Connected

Characteristics:

- Supabase cloud database
- remote access
- centralized analytics
- online synchronization

Use cases:

- multi-site organizations
- centralized administration

---

# 5. Internet Connectivity Policy

The application requires internet periodically for:

- subscription validation
- cloud synchronization
- optional cloud services

However:

- clinics must continue functioning during temporary internet outages

Recommended strategy:

- cached subscription validation
- grace period between 7–14 days
- local systems continue operating offline

The system must NEVER hard-lock clinics immediately after connectivity loss.

---

# 6. Core Functional Modes

The application supports two primary operating modes.

---

## 6.1 Standard Mode

Traditional UI-driven clinic management workflows.

Examples:

- appointment booking
- patient registration
- invoice creation
- SOAP documentation
- shift management

---

## 6.2 AI Mode

Natural language interaction mode.

Users interact with AI prompts.

Examples:

- “Book Ahmed tomorrow at 5 PM with Dr Ali”
- “Generate invoice for today’s visit”
- “Show busiest hours this week”
- “Assign shifts for next Friday”

AI converts prompts into structured commands.

All commands require:

- backend validation
- human approval

## 6.3 IMPORTANT NOTE

The AI system has the following specifications:

- The AI system is treated as an isolated layer from flutter frontend and supabase backend.
- Think of it as [Frontend(flutter)] [AIService(Technology to be defined)] [Backend(Supabase)].
- The AI Service layer communicate with the front end only, never communicates with Backend.
- Backend knows nothing about AI existing. It sees requests to database alike.
- AI Service layer can accept prompt requests from any device on the local network and sends the results back.

---

# 7. User Types

AI access is available to staff members only.

Supported staff roles may include:

- doctors
- receptionists
- owners
- administrators
- lab staff

Patients do NOT directly interact with the AI system.

---

# 8. Branch & Organization Model

---

## 8.1 Organizations

An organization represents the clinic business entity.

An organization may contain multiple branches.

---

## 8.2 Branches

Each branch:

- has independent operational data
- maintains separate schedules
- maintains separate appointment numbering
- maintains separate invoice numbering

Branches are NOT implemented as separate database tables.

Instead:

- all operational records reference branch_id.
- the branch record references the organization_id.

This ensures:

- scalability
- analytics consistency
- easier migrations
- easier maintenance

---

## 8.3 Shared Data

Shared across branches:

- patients
- staff.

Not shared:

- schedules
- invoices
- appointment numbering

---

# 9. Staff Model

Staff members:

- may belong to multiple branches
- may be restricted to specific branches
- are configurable by organization administrators

The system does not enforce hierarchy.

Access is role-based.

Examples:

- doctor
- receptionist
- administrator
- lab staff

Roles affect:

- feature access
- operational permissions

---

# 10. Patient Management

Capabilities include:

- patient registration
- patient editing
- patient archival
- cross-branch patient lookup
- attachment management
- medical history tracking

Supported attachments:

- PDFs
- scans
- lab reports
- examination documents

---

# 11. Appointment Management

Supported appointment types:

- planned appointments (staff-chosen date and time)

Rules:

- appointments cannot overlap
- only one doctor per appointment
- no room/resource allocation
- no partial attendance support

Capabilities:

- conflict validation
- doctor schedule validation
- queue management
- cancellation handling
- status tracking

---

# 12. Shift Management

Shift system requirements:

- branch-specific
- generic scheduling model
- non-recurring capable
- no overlapping shifts
- one or more staff member at a shift

The system must support:

- flexible future extension
- staff assignment
- schedule validation

---

# 13. Visit & Medical Records

The system supports detailed clinical documentation.

---

## 13.1 SOAP Notes

Supported:

- full SOAP documentation
- specialty-specific forms

Future AI capabilities may include:

- summarization
- draft generation

All AI-generated medical content requires approval.

---

## 13.2 Treatment Plans

Treatment plans support:

- medication name
- dosage
- frequency
- end date

The system does NOT automatically:

- create appointments
- enforce tracking
- generate reminders

Doctors remain responsible for follow-up scheduling.

---

# 14. Prescriptions

Prescription capabilities:

- doctor-authored prescriptions
- printable outputs
- medication tracking

The system does NOT:

- validate drug interactions
- enforce dosage intelligence

---

# 15. Lab & Examination Support

Clinic organizations may contain:

- examination centers
- lab operations

Current scope:

- upload PDFs only

The system does NOT initially:

- generate lab reports internally
- integrate external lab systems

---

# 16. Billing & Financial Operations

Supported billing capabilities:

- invoice generation
- multi-line invoice items
- partial payments
- discounts
- insurance coverage split

Discounts may be permission-restricted.

The system does NOT process payments directly.

---

## 16.1 Insurance Support

Initial insurance scope includes:

- insurance provider
- coverage percentage
- insurance visit indication

Full claims workflows are out of scope initially.

---

# 17. Workflow Automation

The platform includes lightweight workflow automation.

---

## 17.1 Supported Triggers

Examples:

- appointment created
- appointment cancelled
- invoice overdue
- new patient created
- shift assigned

---

## 17.2 Supported Actions

Examples:

- WhatsApp message
- notification
- status update

The workflow engine is intentionally simple initially.

---

# 18. Analytics

Analytics capabilities include:

- revenue analytics
- doctor performance
- doctor assignment analytics
- appointment statistics
- busiest hours
- operational reporting

Future AI analytics may support:

- natural language analytics queries
- chart generation
- summaries

---

# 19. AI Architecture

---

## 19.1 Internal Agent Model

Internally the system may contain multiple specialized agents:

- scheduling agent
- billing agent
- analytics agent
- SOAP summarizer
- workflow assistant

However:

- users interact with a unified AI interface

---

## 19.2 AI Context Strategy

AI agents are intentionally lightweight.

Constraints:

- no long-term memory
- no shared autonomous memory
- limited context windows
- low RAM usage

This supports:

- low-resource local execution
- deterministic behavior
- reduced operational cost

---

## 19.3 AI Execution Constraints

AI systems:

- never directly write to database
- may optionally read limited context
- generate structured actions only

Backend systems:

- validate
- authorize
- approve
- execute

---

# 20. Local AI Strategy

Primary AI execution strategy:

- local inference
- lightweight models
- CPU-friendly models

Online AI models may be supported later.

The architecture must remain model-provider agnostic.

---

# 21. Desktop-First UX Strategy

Primary platform:

- Windows desktop application

Secondary platforms:

- Web
- Mobile (future)

The UX must prioritize:

- keyboard efficiency
- dense information layouts
- operational speed
- receptionist workflows
- modern polished design

The product must NOT be designed mobile-first.

---

# 22. Technical Stack

Frontend:

- Flutter
- Follows TDD Clean Architecture Best Practices
-

Cloud Services:

- Supabase Auth
- Supabase Database
- Supabase Storage

Architecture:

- modular feature-first architecture
- deterministic service layer
- local-first infrastructure

---

# 23. State Management

Recommended:

- Riverpod

Avoid:

- oversized global state systems
- tightly coupled architecture

---

# 24. Local Database Strategy

Recommended local database:

- PostgreSQL local instance

Avoid:

- SQLite for multi-device clinic networks

Receptionist PC acts as:

- lightweight clinic node/server

Other local devices access through network.

---

# 25. Audit & Versioning

Supported audit fields:

- created_by
- created_at
- updated_by
- updated_at
- soft delete support

Medical records remain editable.

Versioning:

- periodic backup versioning
- configurable retention policies

---

# 26. Crash Reporting & Version Enforcement

Supported:

- version enforcement
- crash reporting

Not supported initially:

- silent auto-updates

---

# 27. Security Principles

Core principles:

- approval-gated AI
- deterministic validation
- role-based access
- auditability
- soft deletion
- backend ownership of business rules

---

# 28. Spec-Driven Development Strategy

The project follows modular specification-driven development.

Specifications are:

- domain-based
- modular
- deterministic
- implementation-constrained

---

# 29. Spec Structure

Each domain receives independent specifications.

Examples:

- /specs/appointments
- /specs/patients
- /specs/billing
- /specs/ai

---

# 30. Required Spec Sections

Every specification should contain:

- business context
- functional requirements
- non-functional requirements
- UI states
- validation rules
- database schema
- API contracts
- AI hooks
- workflow triggers
- audit requirements
- edge cases
- acceptance criteria
- test cases
- implementation constraints

---

# 31. Development Workflow

---

## 31.1 Planning Phase

Claude 4.6 responsibilities:

- architecture
- schema design
- workflows
- API contracts
- edge cases
- planning

Cheap implementation models are forbidden from architectural decisions.

---

## 31.2 Implementation Phase

Implementation models:

- receive exact instructions
- execute deterministic tasks
- must not redesign architecture
- must not alter schemas
- must not introduce new dependencies

---

## 31.3 Validation Phase

Claude reviews:

- architecture compliance
- implementation quality
- specification adherence

---

# 32. MVP Definition

The initial MVP prioritizes:

- polished clinic operations
- modern UI/UX
- deterministic workflows
- operational reliability

AI integration starts simple.

---

## MVP Core Modules

Foundation:

- authentication
- organizations
- branches
- staff
- RBAC
- audit infrastructure

Operations:

- patients
- appointments
- visits
- SOAP notes
- invoices
- shifts

Initial AI:

- appointment commands
- invoice commands
- scheduling commands

---

# 33. Long-Term Strategic Advantage

The primary competitive advantage is NOT chatbot interaction.

The primary advantage is:

Turning clinic operations into structured executable workflows with AI as the interaction layer.

This allows:

- low operational cost
- safer AI behavior
- deterministic workflows
- scalable architecture
- maintainable systems
- practical real-world adoption

---

