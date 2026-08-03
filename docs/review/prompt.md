# Flutter Feature Code Review

You are reviewing **one feature** from a large Flutter application built using **Clean Architecture**.

Your goal is to perform a **thorough and skeptical code review** of this feature. Your objective is to identify hidden bugs, architectural weaknesses, Clean Architecture violations, SOLID violations, incorrect assumptions, redundant code, duplicate code, missing edge cases, performance issues, and maintainability problems.

Do **not** assume code is correct because it compiles or works in basic scenarios. Verify every important assumption against the implementation.

## Scope

Review everything that belongs to this feature, including:

* Feature structure
* Dependency injection
* State management
* Controllers / Cubits / Blocs / ViewModels
* Domain layer
* Use cases
* Repositories
* Data sources
* Models / Entities
* DTOs
* Validation
* Routing logic
* Error handling
* Logging

If the feature depends on shared code (core, networking, storage, authentication, utilities, etc.), review only the parts necessary to verify this feature's correctness.

---

## Review Process

### 1. Understand the Feature

Before making recommendations:

* Determine the feature's purpose.
* Understand the data flow from presentation to data source.
* Identify the responsibilities of each layer.
* Verify that Clean Architecture boundaries are respected.
* Verify dependency direction.

Do not suggest refactoring until you understand the existing design.

---

### 2. Review Every File

Review every file belonging to this feature.

For each file, verify:

* Correctness
* Clean Architecture compliance
* SOLID principles
* Separation of responsibilities
* Dependency direction
* Error handling
* Null safety
* Async correctness
* State consistency
* Resource management
* Performance implications
* Readability
* Maintainability
* Redundant logic
* Duplicate code
* Dead or unused code
* Unnecessary abstractions

Do not skip files because they appear simple.

---

### 3. Cross-File Validation

Compare related components and verify consistency between:

* State Management ↔ Use Cases
* Use Cases ↔ Repositories
* Repositories ↔ Data Sources
* Models ↔ Entities
* Validation ↔ Business Rules
* Dependency Injection ↔ Usage

Also verify:

* Dependencies always point inward.
* Business logic exists only in the correct layer.
* Responsibilities are not duplicated across layers.
* There are no circular dependencies.
* There are no duplicated implementations.
* There are no redundant classes or services.
* Shared functionality has not been unnecessarily copied.

Many defects only become visible when comparing multiple files.

---

### 4. Special Focus Areas

Pay particular attention to:

* Clean Architecture violations
* SOLID violations
* Race conditions
* Async and Future handling
* Stream lifecycle
* Resource disposal
* Memory leaks
* Exception handling
* Retry logic
* Cancellation handling
* State synchronization
* Data consistency
* Caching consistency
* Performance bottlenecks
* Tight coupling
* Low cohesion
* Duplicate code
* Redundant logic
* Dead code
* Over-engineering
* Unnecessary abstractions
* Missing edge cases

Challenge implementation decisions instead of assuming they are correct.

---

## Output

Organize findings into:

1. Critical Issues
2. High Priority Issues
3. Medium Priority Issues
4. Low Priority Issues
5. Clean Architecture Violations
6. SOLID Violations
7. Code Duplication & Redundancy
8. Performance Issues
9. Test Coverage Gaps
10. Recommended Refactoring

For every finding include:

* Severity
* Files involved
* Evidence from the code
* Why it is a problem
* Potential impact
* Recommended solution

For duplicate or redundant code, explain:

* Why duplication exists
* Whether it should be extracted, removed, or consolidated
* The recommended refactoring approach

Support every conclusion with concrete evidence from the code. Avoid generic comments or stylistic opinions. Prioritize correctness, reliability, maintainability, scalability, simplicity, and adherence to Clean Architecture.

Spawn parallel agents each focused on part of the feature. Do not spawn one agent only. Prefer thinking than finishing fast. Write the output in docs/review