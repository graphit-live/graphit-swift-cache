# AGENTS.md

## Purpose

This file is the always-loaded engineering standard for any production Swift SDK built in 2026 with Swift 6.3.x.

Use it for reusable Swift packages, Apple-platform frameworks, server/client SDKs, internal platform libraries, and optional app-facing adapter packages. It is intentionally domain-neutral. Do not add product-specific policy, feature names, backend names, or cache-specific examples here.

The goal is simple: build SDKs that feel obvious to call, safe under Swift 6, fast for reasons we can explain, and maintainable for years.

## Baseline

- Swift 6.3.x.
- Swift language mode 6.
- Swift Package Manager source package by default.
- Platform-neutral core unless the repository explicitly declares otherwise.
- Apple-platform adapters may exist, but they must depend on the core package. The core package must not depend on UI frameworks.
- Public APIs are long-lived product surface. Treat every public symbol as a permanent cost until proven otherwise.
- Prefer official Apple and Swift.org tools before third-party dependencies.

If the repository pins a more specific Swift 6.3 patch release, honor the repository. Do not introduce language, package, or tooling requirements beyond the declared support floor without an explicit reason.

## Companion Guides

Load these only when the task needs them:

- `.agents/PUBLIC_API_DESIGN.md` for public API design, naming, errors, versioning, and migration.
- `.agents/SWIFT_CONCURRENCY_6_3.md` for isolation, Sendable, actors, tasks, streams, cancellation, and low-level synchronization.
- `.agents/PERFORMANCE_MEMORY.md` for profiling, allocation, ARC, collections, decoding, unsafe code, and optimization review.
- `.agents/TESTING_QUALITY.md` for Swift Testing, XCTest, determinism, coverage, concurrency tests, memory tests, and CI gates.
- `.agents/PACKAGE_RELEASE.md` for package structure, manifests, documentation, CI, release readiness, and consumer integration.
- `.agents/OFFICIAL_SOURCES.md` for Apple and Swift.org references that should shape technical decisions.

The root file defines the standard. Companion files add depth. Do not duplicate entire companion files into task prompts unless the task needs that area.

## Product Posture

Build a productized SDK, not a bag of utilities and not an app hidden inside a package.

A great Swift SDK is:

- small at the public surface
- explicit about work, state, failure, cancellation, and ownership
- boring to call
- hard to misuse
- stable across releases
- documented enough that a caller does not need source access
- internally replaceable without breaking callers
- fast through good data design and measurement
- simple enough that a strong engineer can understand it quickly

Good taste means fewer moving parts, better names, clearer data, smaller interfaces, and no hidden behavior.

## Decision Order

When principles conflict, use this order:

1. Correctness, safety, and data-race freedom.
2. Clear ownership and isolation.
3. Public API simplicity and stability.
4. Long-term maintainability.
5. Measured performance and memory efficiency.
6. Testability and observability.
7. Local brevity.

Local convenience never outranks a stable, understandable public API.

## The 17 SDK Engineering Rules

These are Unix-style rules adapted for modern Swift SDK work.

1. **Modularity**: build small modules and types with one reason to change.
2. **Clarity**: make code readable before making it clever.
3. **Composition**: compose behavior from small values and focused services.
4. **Separation**: keep domain, transport, storage, concurrency, observability, and UI adapters distinct.
5. **Simplicity**: choose the smallest design that survives real requirements.
6. **Parsimony**: do not build frameworks, registries, providers, or adapters before the need is present.
7. **Transparency**: make ownership, side effects, isolation, cost, and failure visible.
8. **Robustness**: treat invalid input, cancellation, unavailable resources, and malformed external data as normal engineering cases.
9. **Representation**: model data well so control flow stays simple.
10. **Least surprise**: follow Swift API Design Guidelines and platform conventions.
11. **Silence**: do not log, notify, allocate, spawn tasks, or perform I/O without value.
12. **Repair**: expose recoverable failures with enough context for the caller to recover.
13. **Economy**: prefer standard library, Foundation, Apple frameworks, and Swift.org packages before new dependencies.
14. **Generation**: generate code only from canonical, reviewable sources; never let generated shapes become the main human-facing API by accident.
15. **Optimization**: measure first, then optimize the real bottleneck.
16. **Diversity**: allow replaceable internals behind stable contracts where change is expected.
17. **Extensibility**: add seams only for current variation or highly likely future variation, not for appearance.

## Architecture

### Core package

The core package owns reusable SDK behavior:

- domain values and invariants
- package-owned request and response types
- transport abstractions and concrete transports
- persistence or storage policy when the SDK requires it
- state machines and shared mutable state owners
- parsing, validation, normalization, and mapping
- authentication or authorization policy when applicable
- observability hooks
- deterministic business or protocol behavior

The core package must not own:

- SwiftUI views
- app navigation
- screen presentation state
- localized UI copy
- animations
- app lifecycle
- hidden app-wide singletons
- UI-only task orchestration

### Adapter packages

Adapters translate the core package into a specific consumer style.

Examples:

- SwiftUI or Observation adapters
- UIKit/AppKit integration
- command-line adapters
- server-framework adapters
- dependency-injection adapters for a consuming app

Adapters may depend on the core package. The core package must not depend on adapters.

### Dependency direction

Keep the dependency graph one-way:

- simple values depend on almost nothing
- parsing and transport depend on values
- feature or protocol logic depends on transport, storage, and values
- public facade depends on internal implementation
- adapters depend on public facade
- tests may depend on test support

Do not let transport types become domain types. Do not let storage entities become public models. Do not let UI concerns shape core contracts.

## Public API Design

Public APIs must be tiny, explicit, and stable.

A caller should understand:

- what the operation does
- what inputs matter
- what can fail
- whether work is synchronous, asynchronous, or streaming
- whether cancellation is respected
- which actor, if any, owns execution
- whether the result is a snapshot, handle, stream, or durable resource
- who owns cleanup

Rules:

- Prefer package-owned types at the public boundary.
- Prefer `async` and `async throws` for one-shot asynchronous work.
- Use `AsyncSequence` only for genuine streams.
- Keep configuration explicit. No service locators or hidden mutable singletons.
- Do not expose `URLSession`, raw protocol responses, generated-client types, vendor-specific types, or persistence entities as the main public surface unless that is the SDK's explicit purpose.
- No fire-and-forget public APIs.
- No macros, property wrappers, dynamic member lookup, or task-local values that hide I/O, dependency lookup, persistence, networking, task creation, or behavior-changing side effects.
- Public APIs must document failure, cancellation, isolation, and ownership when relevant.

## Type Design

Use the simplest type that expresses the semantics.

- Prefer `struct` and `enum` for data and state.
- Use `actor` for shared mutable state that crosses concurrency domains.
- Use `final class` only for identity, lifecycle, Objective-C interoperability, framework constraints, or intentional reference semantics.
- Mark classes `final` unless subclassing is a deliberate public feature.
- Prefer `let` over `var`.
- Prefer small values over large mutable reference graphs.
- Prefer domain-specific identifiers over raw strings and integers at boundaries.
- Make invalid states hard to express.
- Use the narrowest access level that works.

Abstraction choices:

- Prefer concrete types when there is no current substitution boundary.
- Prefer generics when the caller and callee should preserve concrete type relationships.
- Use `some Protocol` when the concrete type is fixed but should remain hidden.
- Use `any Protocol` only when existential type erasure is intentional: heterogeneous storage, runtime substitution, plugin-like composition, or stable dependency slots.
- Do not add a protocol for one implementation unless it protects a real boundary or enables meaningful tests of behavior.

## Ownership and State

Every mutable resource needs one obvious owner.

Good owners are explicit:

- a value owns immutable data
- an actor owns shared mutable state
- an operation scope owns retry counters and temporary state
- a facade owns configuration and dependency wiring
- a caller owns lifecycle when the API returns a handle

Avoid:

- hidden globals
- mutable process-wide singletons
- ambient dependency lookup
- state mutation hidden in property observers
- shared dictionaries or registries with unclear lifetime
- task handles no object owns

If nobody can name the owner, the design is not ready.

## Concurrency

Swift 6 data-race safety is a design requirement, not a cleanup task.

Rules:

- Compile new code in Swift 6 language mode.
- Keep core SDK targets explicitly isolated. Do not make the entire core package `MainActor`-isolated.
- Use `MainActor` for UI adapters, presentation state, and platform callbacks that truly require it.
- Heavy work must not run on the main actor: decoding, parsing, compression, hashing, file I/O, large transforms, database work, or expensive formatting loops.
- Prefer structured concurrency: `async let`, task groups, and scoped async calls.
- Use `Task` only when an owner stores the handle and controls cancellation.
- Use `Task.detached` only after review and only when breaking task-tree or actor context is intentional.
- Propagate cancellation. Never turn cancellation into an unrelated generic failure.
- Use actors for shared mutable state; design actor methods for reentrancy.
- Prefer `Sendable` values across isolation boundaries.
- `@unchecked Sendable` requires a written safety argument, stress tests, and focused review.
- Continuations belong only at tiny legacy or callback-based edges.
- Task-local values are allowed for trace metadata, not dependency injection.

Fix concurrency diagnostics by correcting ownership and isolation. Do not silence them with broad annotations.

## Error Handling

Use Swift-native error handling.

- Use `throws` and `async throws` by default.
- Use `Result` only when a result must be stored, deferred, or passed as data.
- Use typed throws only when the failure type is intentionally part of the API contract and unlikely to change.
- Translate infrastructure failures at package boundaries.
- Do not erase errors before policy has been applied.
- Use optionals only for true absence.
- Do not use optionals, broad default values, or force unwraps to hide invalid states.
- Preserve cancellation as cancellation.

Error messages and error types should help the caller decide whether to retry, repair input, wait, authenticate, inspect configuration, or report a bug.

## Performance and Memory

Performance is required, but folklore is not.

Rules:

- Measure before optimizing.
- Know the cost model: allocations, ARC traffic, large value copies, bridging, decoding, actor hops, task creation, buffering, and main-actor blocking.
- Keep hot data representations small and honest.
- Avoid needless temporary arrays, repeated decoding, repeated formatter construction, and reference-heavy wrapper stacks.
- Reuse expensive infrastructure objects when reuse is safe and meaningful.
- Bound memory growth for registries, buffers, in-memory stores, and memoized data.
- Avoid actor ping-pong. Batch work per actor hop and pass immutable snapshots.
- Use `@inlinable`, `@usableFromInline`, `@specialize`, `@inline(always)`, and `@export(implementation)` only for reviewed, stable, performance-sensitive library APIs where the benefit is justified.
- Use `Span`, `InlineArray`, noncopyable types, `Mutex`, atomics, and unsafe APIs only in contained paths with evidence and review.
- Ban `unowned(unsafe)`.
- Use `unowned` only with a documented lifetime invariant. Otherwise prefer values, explicit ownership, or `weak`.
- Unsafe code must be boxed in a tiny safe wrapper with documented lifetime, alignment, and ownership assumptions.

A fast implementation that the team cannot safely maintain is not world-class. The best optimization removes cost without making the design fragile.

## Testing and Quality

Tests prove behavior. Coverage numbers alone do not.

Use Swift Testing for most package behavior tests. Use XCTest where mature Apple tooling is a better fit, especially performance measurement and UI/app integration layers.

Required testing posture:

- Target complete meaningful coverage of handwritten core logic.
- Generated code does not need vanity coverage; wrapper behavior and contract compatibility do.
- Test success, failure, edge cases, cancellation, retry/timeout behavior, and concurrent access where relevant.
- Make time, UUIDs, randomness, transport, storage, file locations, clocks, locale, and credentials injectable when they affect behavior.
- Tests must be deterministic and parallel-safe unless a test explicitly proves serialized behavior.
- Add memory tests for long-lived objects, streams, task cancellation, and bounded resources.
- Add performance tests or benchmarks for known hot paths.
- Do not add mock frameworks, fake protocols, or test infrastructure until multiple real tests need them.

A test is useful when it would fail for a regression that users or maintainers would care about.

## Documentation

Documentation is part of the SDK product.

- Every public type and public member needs documentation comments.
- Public docs must cover purpose, parameters, return values, failure semantics, cancellation, isolation, ownership, and examples when relevant.
- DocC should build cleanly for public products.
- Examples should compile.
- Architecture decisions belong in concise markdown near the code.
- Comments explain intent, policy, invariants, and non-obvious trade-offs. They do not narrate syntax.
- Migration notes are required for breaking public API changes.

A caller should not need to read implementation source to understand the public contract.

## Dependencies

Start from zero external dependencies.

Add a dependency only when it clearly beats package-owned code on correctness, maintenance cost, security, compatibility, and long-term fit.

Rules:

- Prefer official Apple and Swift.org packages when they fit.
- Avoid thin convenience dependencies.
- Keep third-party types behind package-owned boundaries.
- Do not let dependencies define your public API by accident.
- Pin and review dependency versions through the repository's normal package-resolution policy.
- Remove dependencies that no longer pay for themselves.

## Observability

Observability should explain behavior without creating noise or leaking data.

- Use structured logging for operational events.
- Use signposts for measured performance spans.
- Prefer stable operation names, result categories, durations, and correlation identifiers.
- Do not log secrets, credentials, private payloads, sensitive URLs, raw tokens, or full external responses by default.
- Do not use logs as control flow.
- Make observability optional or configurable when SDK consumers need control.

## Package and Release Discipline

A production SDK release should include:

- debug and release builds
- Swift 6 language mode
- no concurrency warnings
- deterministic tests
- meaningful coverage for handwritten core logic
- documentation build
- examples or sample integration build
- public API review
- dependency review
- performance checks for critical paths
- memory/leak checks for long-lived components
- migration notes for breaking changes

Use semantic versioning or the repository's declared release policy consistently. Public API churn requires migration intent.

## Code Style

- Explicit names over clever names.
- Domain words over generic words.
- Short focused methods.
- One primary type or one cohesive extension group per file.
- Minimal imports.
- `private` by default.
- `package` for cross-target collaboration inside the same package.
- `public` only for intentional product surface.
- No custom operators unless they are domain-standard and materially improve clarity.
- No broad `Any`, erased closures, or existential use without a boundary reason.
- No giant manager types.
- No helpers or utils folders full of unrelated code.

## Simplicity Bar

Before adding a new type, protocol, layer, task, dependency, setting, script, or abstraction, answer:

- Who owns it?
- Who calls it?
- What invariant does it protect?
- What cost does it hide or expose?
- Is it used more than once?
- Does it remove more complexity than it adds?
- Can it be deleted later?
- Can internals change without callers changing?
- Does a native Swift, Foundation, Apple, or Swift.org API already solve this?

If the answer is unclear, choose the smaller design.

## Refactoring Behavior

Improve surrounding code when required for correctness, clarity, isolation, performance, or public API quality.

Do not broaden refactors to chase style purity. If existing code violates this standard, fix the part required for the current change and record the rest as follow-up.

## Non-Negotiables

- No hidden mutable global state.
- No service locator.
- No core-package `MainActor` pollution.
- No unchecked concurrency escape without written review.
- No unowned unsafe references.
- No undocumented unsafe code.
- No public API churn without migration intent.
- No fake abstraction.
- No one-implementation protocol unless a real boundary exists.
- No fire-and-forget public API.
- No generated or vendor type leakage through the main public surface unless intentional.
- No fake coverage.
- No performance claims without evidence.
- No domain-specific examples or product policy in this reusable standard.
