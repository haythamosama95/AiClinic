---
name: web-to-flutter
description: >-
  Translates an approved web feature into Flutter while preserving visual
  appearance, interactions, motion, and UX. Use when implementing Flutter UI from
  a web reference, reproducing web feature design in Flutter, or when the user
  mentions web to Flutter translation, Flutter reproduction, or porting web UI.
---

# Web to Flutter Translation

## Purpose

Translate an approved web feature into Flutter while preserving its visual appearance, interaction patterns, motion, and overall user experience.

The objective is **not** to translate HTML or CSS.

The objective is to faithfully reproduce the experience using Flutter best practices while integrating seamlessly into the existing Flutter project.

---

## Input

An approved web feature implementation.

---

## Responsibilities

### 1. Understand the project

Before making any implementation decisions:

- Read the existing Flutter design system.
- Read the existing Flutter component library.
- Understand the project's architecture.
- Identify reusable components.
- Follow existing project conventions.

Assume these resources are the source of truth unless the web implementation requires a legitimate extension.

---

### 2. Analyze the web implementation

Before writing any Flutter code, fully understand the web feature.

Analyze:

- Layout hierarchy
- Component hierarchy
- Visual hierarchy
- Spacing
- Typography
- Colors
- Elevation
- Responsiveness
- Motion
- Interactions
- States (loading, empty, error, disabled, hover, selected, focused)

Understand the intent behind the design rather than the implementation details.

---

### 3. Reuse existing Flutter components

Always prefer existing Flutter components.

If an equivalent application component already exists:

- Reuse it.
- Do not duplicate it.
- Do not modify it unless the change benefits every usage.

Consistency takes priority over convenience.

---

### 4. Choose the appropriate implementation strategy

Before implementing any new UI element, determine the best approach.

Prefer the following order:

1. Existing application component
2. Flutter SDK widget
3. Mature Flutter package wrapped inside an application component
4. New reusable application component

Avoid custom implementations when a mature, well-maintained solution already exists.

---

### 5. Extend the application UI library when necessary

If the feature introduces any reusable UI element or behavior, it must become part of the application's reusable library rather than remaining local to the feature.

Examples include:

- Widgets
- Layout primitives
- Decorations
- Motion presets
- Animations
- Page transitions
- Dialog patterns
- Visual effects
- Interactive behaviors
- Wrappers around third-party packages

Each addition should:

- Be reusable.
- Be configurable where appropriate.
- Follow the design system.
- Be documented through the component library.
- Be independent of any single feature.

Avoid feature-specific implementations when the solution represents part of the application's design language.

---

### 6. Follow the project architecture

Only implement the Presentation Layer.

Do not implement:

- APIs
- Repositories
- Services
- Data sources
- Business logic

Respect the project's architectural boundaries.

---

### 7. Implement using Flutter best practices

Recreate the experience using Flutter-native patterns.

Do **not** imitate:

- HTML structure
- CSS layout
- DOM hierarchy

Instead, use Flutter's layout and rendering model appropriately.

Prefer:

- Row
- Column
- Stack
- Wrap
- CustomScrollView
- Slivers
- LayoutBuilder
- Animated widgets
- Material widgets
- Cupertino widgets where appropriate

Build idiomatic Flutter, not translated web code.

---

### 8. Match the user experience

The Flutter implementation should preserve:

- Visual appearance
- Spacing
- Typography
- Motion
- Timing
- Animation curves
- Navigation behavior
- Responsive behavior
- Interaction feedback

Implementation details may differ, but the experience should feel equivalent.

---

### 9. Responsiveness

Adapt the layout using Flutter techniques.

Do not copy CSS breakpoints directly.

Use Flutter's layout system to produce natural adaptive layouts across supported screen sizes.

---

### 10. Performance

Produce efficient Flutter code.

Prefer:

- `const` widgets where appropriate
- Widget composition
- Lazy construction
- Efficient rebuilds
- Clean widget trees

Avoid unnecessary nesting or complexity.

---

### 11. Application ownership policy

The application should own every reusable piece of its presentation layer.

Whenever introducing something expected to be reused, expose it through an application abstraction rather than using raw implementations throughout the codebase.

Examples include:

- `AppButton`
- `AppCard`
- `AppDialog`
- `AppTooltip`
- `AppPageTransition`
- `AppMotion`
- `AppAnimation`
- `AppDecorations`
- `AppShadows`
- `AppSpacing`
- `AppCharts`
- `AppRichTextEditor`

When using third-party packages:

- Wrap them inside application components.
- Do not expose package-specific APIs across the project.
- Ensure packages can be replaced with minimal impact.

The rest of the application should depend on application abstractions rather than implementation details.

---

## Rules

- Never translate HTML line-by-line.
- Never imitate CSS.
- Never duplicate existing components.
- Never bypass the application's component library.
- Never rebuild mature Flutter packages unnecessarily.
- Prefer composition over inheritance.
- Keep widgets small, reusable, and maintainable.
- Preserve the approved web design while implementing idiomatic Flutter.

---

## Success Criteria

The resulting Flutter feature should:

- Match the approved web feature visually.
- Match its interactions and motion.
- Feel like a native Flutter implementation.
- Reuse the existing Flutter component library whenever possible.
- Extend the component library whenever new reusable elements or behaviors are introduced.
- Wrap reusable widgets, animations, transitions, motion presets, effects, and third-party packages behind application-owned abstractions.
- Follow the project's architecture and conventions.
- Be maintainable, performant, and production-ready.
