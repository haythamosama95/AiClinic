---
name: web-feature-design
description: >-
  Designs and implements production-quality React web UI as the canonical visual
  specification for Flutter features. Use when building web reference UIs,
  implementing a feature spec for Flutter reproduction, or when the user mentions
  web feature design, UI reference, visual source of truth, or canonical web spec.
---

# Web Feature Design

## Purpose

Design and implement a production-quality web version of a single application feature that serves as the canonical visual specification for the Flutter implementation.

This is **not** the production frontend.

It is the authoritative UI reference that Flutter will faithfully reproduce.

---

# Input

A feature specification describing the feature to implement.

---

# Responsibilities

## 1. Understand the project

Before making any implementation decisions:

- Read the existing design system.
- Read the existing UI kit/component library.
- Understand the project's conventions.
- Identify reusable components.
- Reuse existing patterns whenever possible.

Assume these resources are the source of truth unless the feature specification explicitly overrides them.

---

## 2. Understand the feature

Read the feature specification carefully.

Understand:

- User goals
- Business rules
- Required interactions
- Displayed information
- Success criteria

Do not invent functionality.

If anything is ambiguous, choose the most consistent interpretation with the rest of the application.

---

## 3. Consult Frontend Design

Before implementing the UI, consult the `frontend-design` skill.

Use its recommendations to:

- Refine the visual hierarchy.
- Improve layout and composition.
- Optimize spacing and alignment.
- Enhance usability.
- Apply appropriate motion and interactions.
- Ensure the interface feels modern, polished, and premium.

Treat the recommendations as design guidance rather than strict requirements.

The existing design system, component library, and established project conventions always take precedence.

Do not redesign existing reusable components. The purpose of the consultation is to improve how the feature is composed and presented, not to redefine the application's visual language unless the feature explicitly requires extending the design system.

---

## 4. Reuse existing components

Always reuse existing components whenever possible.

Never create a new component if an existing one can satisfy the requirement.

Consistency always takes priority over novelty.

---

## 5. Create reusable components only when necessary

If the feature introduces any reusable UI element or behavior, it must become part of the application's reusable library rather than remaining local to the feature.

Examples include:

- Components
- Layout primitives
- Dialogs
- Form controls
- Navigation elements
- Motion presets
- Animations
- Transitions
- Visual effects
- Interaction patterns

Each addition should:

- Be reusable.
- Be configurable where appropriate.
- Follow the design system.
- Be documented through the UI Kit/component library.
- Be independent of any single feature.

Avoid feature-specific implementations when the solution represents part of the application's design language.

---

## 6. Focus on presentation only

Implement only the presentation layer.

Ignore:

- Backend
- APIs
- Authentication
- Database
- Business logic
- Networking

Mock any required data.

---

## 7. Produce premium-quality UI

The interface should feel modern, polished, and intentionally designed.

Prioritize:

- Excellent visual hierarchy
- Consistent spacing
- Beautiful typography
- High readability
- Clear information architecture
- Professional aesthetics
- Tasteful use of whitespace

Every visual decision should improve usability.

---

## 8. Motion

Use animations intentionally.

Examples include:

- Fade
- Slide
- Scale
- Hover effects
- Page transitions
- Loading transitions
- Micro-interactions

Animations should enhance the experience without becoming distracting.

Whenever a reusable motion pattern is introduced, add it to the project's reusable UI library rather than implementing it only within the current feature.

---

## 9. Responsiveness

Design for:

- Desktop
- Tablet
- Mobile

Layouts should adapt naturally while maintaining visual quality.

---

## 10. Accessibility

Ensure the interface supports:

- Keyboard navigation
- Visible focus states
- Appropriate ARIA attributes
- Sufficient color contrast
- Screen reader compatibility

Accessibility is a requirement, not an enhancement.

---

## 11. Follow the design system

Do not introduce:

- New colors
- New typography
- New spacing rules
- New shadows
- New border radius values
- New animation styles

Unless explicitly extending the design system.

---

## 12. Application ownership policy

The application should own every reusable piece of its presentation layer.

Whenever introducing something expected to be reused, expose it through an application abstraction rather than scattering raw implementations throughout the project.

Examples include:

- Buttons
- Cards
- Dialogs
- Form controls
- Layout primitives
- Navigation components
- Motion presets
- Animations
- Page transitions
- Decorations
- Visual effects

The rest of the application should consume these reusable abstractions rather than feature-specific implementations.

---

## 13. Deliverables

Produce:

- Complete feature implementation.
- Any newly required reusable components.
- Updates to the UI Kit/component library if new reusable components were added.
- Updates to reusable motion, animation, or transition libraries if new reusable behaviors were introduced.

---

# Technology Stack

- React
- TypeScript
- Vite
- Tailwind CSS
- Radix UI
- Lucide React
- Motion

Use the existing project stack and conventions.

---

# Rules

- Never redesign existing reusable components.
- Never duplicate components.
- Prefer composition over customization.
- Prefer readability over cleverness.
- Build small, reusable components.
- Keep pages declarative and maintainable.
- Maintain consistency across the application.
- Treat the web implementation as the visual source of truth for Flutter.
- Every reusable visual element or behavior should belong to the application's reusable UI library rather than an individual feature.

---

# Success Criteria

The resulting feature should:

- Look production-ready.
- Match the application's design language.
- Reuse existing components wherever possible.
- Extend the component library only when necessary.
- Add reusable components, animations, transitions, and motion patterns to the shared UI library when introduced.
- Require no visual interpretation during Flutter implementation.
- Serve as the canonical reference for all future Flutter work.
