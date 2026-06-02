# Public API Design Standard

## Purpose

This guide defines how to design, review, document, and evolve public APIs for a production Swift SDK.

Public API is product. Internal code can be rewritten; public contracts create obligations.

## Public API Philosophy

A great SDK is easy to call correctly and hard to call incorrectly.

Public API should be:

- small
- explicit
- stable
- discoverable
- documented
- testable
- cancellable when async
- clear about isolation
- clear about ownership
- independent from generated, transport, persistence, and vendor details

Do not expose implementation shape as API shape. The public API should express the domain or protocol the SDK owns, not the accident of how it is implemented today.

## Public Surface Budget

Every public symbol must justify itself.

Before making a symbol `public`, answer:

- Who is the caller?
- What real use case does this enable?
- Why is `internal` or `package` insufficient?
- What invariants must the caller know?
- What can fail?
- What is cancellable?
- What is the isolation story?
- How will this evolve without breaking users?
- How will this be documented and tested?

Avoid publishing convenience that can be expressed by callers in one obvious line unless the SDK must protect an invariant or encode policy.

## Facade Shape

Prefer one coherent primary facade per SDK product.

A good facade:

- exposes stable package-owned types
- groups related operations predictably
- avoids leaking transport or generated APIs
- keeps configuration explicit
- lets internals change without caller changes
- keeps advanced policy visible but not noisy

Do not create a giant object with every operation mixed together. Do not create dozens of tiny facades that force users to learn internal architecture.

## Names

Names are API design.

Rules:

- Prefer clarity over brevity.
- Use domain words the caller understands.
- Type names are nouns.
- Functions are verbs or verb phrases.
- Boolean names read as facts.
- Abbreviate only when the abbreviation is universal: `ID`, `URL`, `HTTP`, `JSON`, `XML`, `TLS`.
- Avoid `Manager`, `Helper`, `Util`, `Provider`, `Controller`, and `Service` unless the word is genuinely precise.
- Avoid names that encode implementation: `DTO`, `Entity`, `Record`, `SQL`, `HTTP`, `Generated`, unless the API intentionally exposes that layer.

A caller should not need to know the internal folder structure to guess an API name.

## Inputs and Outputs

Inputs should make invalid states hard to express.

Prefer:

- small request value types for operations with multiple parameters
- dedicated identifier types for stable identity
- enums for closed sets of states or modes
- validated value types for values with strong invariants
- clear optionality only for true absence
- immutable values crossing isolation boundaries

Avoid:

- long parameter lists
- raw dictionaries
- raw strings for typed concepts
- broad `Any` and `AnyObject`
- optionals that hide invalid state
- flags that create unclear mode combinations
- overloaded methods whose behavior differs in non-obvious ways

Return package-owned values, not transport payloads or persistence entities. If the SDK returns a handle, document ownership and cleanup.

## Async API Shape

Use `async` and `async throws` for one-shot operations.

Use `AsyncSequence` only when the concept is genuinely streaming:

- events over time
- progress updates
- incremental bytes or records
- state changes
- long-lived observations

Do not use streams to disguise a single callback. Do not use callbacks where async/await is clearer.

Async public APIs must document:

- what starts the work
- what cancels the work
- what state remains after cancellation
- whether partial results are possible
- whether work is isolated to an actor
- whether the method can be called concurrently

No public API should spawn unowned background work.

## Errors

Use `throws` and `async throws` by default.

Design failure semantics before designing error names.

A good public error model helps callers know whether to:

- retry
- repair input
- wait
- authenticate or reconfigure
- inspect their environment
- report a bug

Rules:

- Translate infrastructure failures at the SDK boundary.
- Preserve cancellation.
- Use typed throws only when the precise thrown type is intentionally part of the contract.
- Do not erase errors too early.
- Do not leak random low-level errors without policy.
- Use optionals only for true absence.
- Do not turn missing required data into a default value.

## Configuration

Configuration should be explicit, small, and stable.

Good configuration:

- has clear defaults
- separates required and optional fields
- uses value types
- validates invalid combinations early
- does not depend on hidden global state
- does not perform I/O during property access
- keeps secrets out of logs and descriptions

Avoid:

- configuration registries
- process-wide mutable configuration
- task-local dependency lookup
- property wrappers for runtime dependency resolution
- large builder chains unless they materially improve correctness

Static configuration set once does not need a framework.

## Protocols, Generics, and Existentials

Choose abstraction based on the boundary.

Concrete types are best when no current substitution exists.

Generics are best when:

- static type relationships matter
- the caller supplies behavior
- performance benefits from preserving concrete types
- the abstraction should not erase type information

`some Protocol` is best when:

- the concrete type is fixed by the implementation
- callers should not depend on that type
- static type identity should be preserved

`any Protocol` is best when:

- values are heterogeneous
- runtime substitution is required
- the value must be stored without making the owner generic
- a dependency slot is intentionally type-erased

Do not create protocols only to mock trivial pass-throughs. Protocols should protect real seams, not decorate code.

## Access Control

Use the narrowest useful access level.

- `private`: default for implementation details.
- `fileprivate`: only when file-scoped sharing is clearer.
- `internal`: target-local implementation.
- `package`: collaboration across targets inside the same package.
- `public`: intentional SDK surface.
- `open`: rare; only when subclassing outside the module is a designed feature.

Making a symbol public creates documentation, testing, compatibility, and migration obligations.

## Generated and Vendor Code

Generated code is acceptable when the source is canonical and reviewable.

Rules:

- Do not hand-edit generated output.
- Keep generated types out of the main public API unless the SDK is explicitly a generated-client SDK.
- Wrap generated operations in package-owned facades.
- Test wrapper behavior, mapping, failure policy, and contract compatibility.
- Keep generation settings in source control.

Third-party types should not become contagious. Keep them behind package-owned boundaries unless exposing them is the entire point of the SDK.

## Library Evolution and Versioning

Define release policy before broad API release.

For public APIs:

- Prefer additive changes.
- Avoid source-breaking changes without migration notes.
- Avoid binary-breaking changes if the package promises binary stability.
- Deprecate intentionally with a replacement and rationale.
- Keep old APIs long enough for realistic migration when the SDK has external consumers.
- Document behavior changes even when signatures stay the same.

If `BUILD_LIBRARY_FOR_DISTRIBUTION` or binary framework distribution is used, treat implementation visibility and ABI decisions as part of API review.

## Documentation Requirements

Every public type and public member needs documentation.

Document:

- purpose
- parameters
- return value
- thrown errors or failure categories
- cancellation behavior
- actor isolation
- ownership and cleanup
- thread-safety or concurrent-call guarantees
- examples for non-trivial use

DocC should build cleanly. Public examples should compile.

## Public API Review Checklist

Before approving public API, ask:

- Does the caller need this symbol?
- Is the name obvious without internal context?
- Are inputs and outputs package-owned and stable?
- Are invalid states hard to express?
- Is async behavior explicit?
- Is cancellation preserved and documented?
- Is actor isolation explicit?
- Are errors useful and not over-specified?
- Does the API avoid leaking generated, vendor, transport, or persistence details?
- Can the implementation change without caller changes?
- Are documentation and tests ready?
- Is there a migration path if this changes later?

## Anti-Patterns

Avoid:

- public APIs shaped like backend endpoints by accident
- broad manager objects
- one-implementation protocols
- global configuration mutation
- convenience wrappers that hide real cost
- macros or property wrappers that hide I/O
- callbacks for normal async work
- streams for one-shot operations
- public force unwrap assumptions
- public types with unclear ownership
- public APIs added for hypothetical future use
