---
name: design-knowledge-manager
description: >-
  Maintains and evolves the project's reusable design knowledge after a feature
  has been reviewed and approved. Use when updating design documentation from
  approved features, extracting reusable UI patterns, or when the user mentions
  design knowledge manager, design docs update, or reusable design patterns.
---

# Design Knowledge Manager

## Purpose

Maintain and evolve the project's reusable design knowledge after a feature has been reviewed and approved.

This skill does **not** design features or implement code.

Its responsibility is to extract reusable knowledge from approved work and keep the project's design documentation up to date.

The goal is to ensure the project continuously becomes smarter, more consistent, and easier to extend.

---

# Input

An approved feature implementation.

The feature may be:

- A web feature
- A Flutter feature
- A component
- A UI improvement
- A design system enhancement

Only approved work should be processed.

---

# Responsibilities

## 1. Understand the project

Before making any modifications:

- Read the existing design documentation.
- Read the existing design system.
- Read the component library documentation.
- Read all relevant design knowledge files.

Treat the existing documentation as the source of truth.

---

## 2. Analyze the approved feature

Determine whether the feature introduces reusable knowledge.

Examples include:

- New reusable component
- New component variant
- New layout pattern
- New navigation pattern
- New interaction pattern
- New motion pattern
- New transition
- New visual effect
- New design token
- New accessibility guideline
- New responsive pattern

Ignore feature-specific implementation details.

Focus only on knowledge that benefits future features.

---

## 3. Determine whether documentation changes are required

For every discovered improvement, determine whether it is:

- Completely new
- An extension of existing knowledge
- A refinement of existing knowledge
- Already documented

Never duplicate information.

Prefer updating existing documentation over creating redundant entries.

---

## 4. Update existing knowledge

Modify documentation only where appropriate.

Possible updates include:

- Registering new reusable components
- Adding component variants
- Documenting reusable layouts
- Documenting reusable interaction patterns
- Recording motion presets
- Recording transitions
- Recording visual effects
- Recording responsive patterns
- Updating design tokens
- Updating accessibility guidance

Always keep documentation concise and organized.

---

## 5. Create new documentation only when necessary

If reusable knowledge does not fit into any existing document:

Create a new document.

Choose a logical location and naming convention.

Avoid creating unnecessary files.

---

## 6. Preserve consistency

Do not allow documentation to drift.

Ensure:

- Naming is consistent.
- Terminology is consistent.
- Similar concepts are grouped together.
- Duplicate information is eliminated.

Prefer refining existing documentation over expanding it indefinitely.

---

## 7. Preserve project philosophy

Do not modify the project's design philosophy unless the approved feature intentionally extends it.

The purpose of this skill is to evolve the design knowledge—not to reinvent it.

---

# Suggested Documentation Structure

The project may contain documents such as:

docs/ui/principles

- design-system.md
- components.md
- layouts.md
- patterns.md
- motions.md
- transitions.md
- effects.md
- tokens.md
- accessibility.md
- responsive.md

This structure is flexible.

Prefer updating existing documentation rather than enforcing new files.
If no files are found for the principle, create one.

---

# Rules

- Never process unapproved work.
- Never document feature-specific behavior as reusable knowledge.
- Never duplicate existing documentation.
- Prefer updating existing files over creating new ones.
- Keep documentation implementation-agnostic whenever possible.
- Keep documentation concise.
- Organize information for future AI consumption.
- Preserve consistency across all design documentation.

---

# Success Criteria

After the skill completes:

- The project's design knowledge reflects the approved feature.
- Reusable concepts are documented.
- Existing documentation is improved rather than duplicated.
- Future features can discover and reuse the new knowledge.
- The project's design documentation becomes progressively more complete and consistent over time.
