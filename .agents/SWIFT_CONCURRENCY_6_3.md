# Swift Concurrency Standard for Swift 6.3 SDKs

## Purpose

This guide defines concurrency policy for production Swift SDKs using Swift 6.3.x.

Concurrency is an architectural design problem. The compiler helps enforce data-race safety, but it cannot choose ownership, isolation, or cancellation semantics for you.

## Baseline

- Use Swift 6 language mode for new SDK code.
- Treat data-race safety diagnostics as design feedback.
- Keep reusable core SDK targets explicitly isolated.
- Use MainActor-by-default only for UI-facing adapters or executable targets where single-threaded-by-default behavior is intentional.
- Use `@concurrent` only when the function truly should execute concurrently and the design supports it.

Swift 6.3 builds on the Swift 6 data-race safety model and the Swift 6.2 concurrency ergonomics around default actor isolation, caller-context async execution, and explicit concurrent execution. Design for the Swift 6 model, not the old Swift 5 habit of adding tasks until warnings disappear.

## Isolation Strategy

### Core SDK targets

Examples:

- models
- validation
- parsing
- transport
- storage
- public facades
- protocol/state machines
- observability

Rules:

- Do not make the entire core target `MainActor`-isolated.
- Keep pure values nonisolated.
- Make values crossing isolation boundaries `Sendable` whenever possible.
- Put shared mutable state behind actors or carefully reviewed synchronization.
- Annotate isolation deliberately on types or methods that require it.
- Keep UI lifetime and presentation state out of core targets.

### UI adapter targets

Examples:

- SwiftUI stores
- Observation models
- UIKit/AppKit bridge objects
- presentation-friendly state adapters

Rules:

- `MainActor` isolation is acceptable and often correct.
- Heavy work still moves off the main actor.
- Adapter state may be UI-shaped; core state must not be.
- Adapters consume core facades instead of changing core architecture.

### Low-level or hot-path targets

Examples:

- parsers
- binary encoders
- memory-sensitive buffers
- interop wrappers
- high-frequency synchronization

Rules:

- Use explicit isolation.
- Review `Sendable`, lifetime, and ownership assumptions aggressively.
- Keep synchronization local and small.
- Prefer safe low-level features before unsafe pointers.
- Measure before choosing specialist primitives.

## Structured Concurrency

Prefer structured tools:

- direct `async` calls
- `async let`
- `withTaskGroup`
- `withThrowingTaskGroup`

Structured concurrency makes lifetime visible, cancellation compositional, and task hierarchy understandable.

Use task groups for dynamic fan-out/fan-in work. Bound concurrency for large workloads. Do not create thousands of tiny child tasks when a loop or bounded group is clearer.

## Unstructured Tasks

`Task` is not a general control-flow tool.

Use `Task` only when:

- an owning object stores the handle
- lifetime is explicit
- cancellation is explicit
- the operation is intentionally unstructured
- tests can prove cleanup behavior

Bad reasons to use `Task`:

- to silence isolation diagnostics
- to make synchronous design look asynchronous
- to hide work from callers
- to avoid writing a better API
- to ignore cancellation

`Task.detached` is rare. Use it only when breaking task hierarchy or actor context is deliberate, documented, and reviewed.

## Cancellation

Cancellation is part of behavior.

Every async operation should answer:

- Who owns the work?
- Who cancels it?
- What state remains after cancellation?
- Are partial results possible?
- Is cleanup eager or deferred?
- Can the caller retry safely?

Rules:

- Check cancellation at natural boundaries.
- Use `Task.checkCancellation()` when work should stop immediately.
- Use `Task.isCancelled` when cleanup or partial-result logic is needed.
- Use `withTaskCancellationHandler` when underlying resources must be cancelled or temporary state must be cleaned.
- Preserve `CancellationError` or equivalent cancellation semantics.
- Do not report cancellation as a generic network, storage, or unknown error.

## Sendable

Values crossing isolation boundaries should be `Sendable` or otherwise proven safe by the compiler.

Usually `Sendable`:

- identifiers
- request values
- response values
- configuration values
- error enums
- state snapshots
- pagination or continuation tokens
- immutable policy values

Avoid sending mutable reference types across isolation boundaries. Prefer immutable values or actor-owned state.

`@unchecked Sendable` is restricted. It requires:

- a type that cannot reasonably be expressed safely otherwise
- documented invariants
- small implementation
- stress tests
- senior review

Frequent `@unchecked Sendable` usually means the design is wrong.

## Actors

Use actors for shared mutable state touched by concurrent tasks.

Good actor responsibilities:

- coordinating shared state
- deduplicating in-flight work
- protecting mutable registries
- serializing access to a resource
- coordinating refresh or renewal operations
- maintaining bounded mutable buffers or stores

Actor design rules:

- Actor methods are reentrant.
- State can change across `await`.
- Keep mutation phases small and synchronous where possible.
- Do expensive pure work outside the actor.
- Re-read or revalidate invariants after suspension.
- Batch actor work to avoid ping-pong.
- Pass immutable snapshots out of actors.

Do not use an actor as a dumping ground for unrelated state.

## MainActor

MainActor belongs to UI and main-thread-bound platform work.

Good uses:

- SwiftUI/Observation adapter state
- UI-facing stores
- app or executable entry points when appropriate
- platform callbacks that must run on the main actor

Bad uses:

- making the whole core SDK appear safe
- hiding non-Sendable reference sharing
- running decoding, parsing, hashing, compression, file I/O, or database work
- avoiding a real isolation design

MainActor does not make blocking work acceptable.

## `@concurrent`

Use `@concurrent` when an async function should execute concurrently rather than remain serialized on the caller's actor.

Good candidates:

- expensive parsing
- heavy pure transforms
- compression or hashing
- ranking or sorting large inputs
- work that does not require actor-owned mutable state

Do not use `@concurrent` just to quiet diagnostics or claim performance. The function must be safe to execute concurrently, and the boundary should be intentional.

## Async Sequences and Streams

Use streams only for real streams:

- events over time
- incremental data
- progress
- observations
- state changes
- long-lived external feeds

Every stream must define:

- who owns the continuation
- when it finishes
- whether it can fail
- buffering policy
- cancellation behavior
- backpressure or dropping behavior
- resource cleanup

Do not leave continuations in broad object state unless the design truly requires it.

## Continuations

Continuations belong at legacy edges.

Rules:

- Use checked continuations by default.
- Keep wrappers tiny.
- Resume exactly once.
- Define cancellation and timeout behavior.
- Do not spread continuation logic into core business code.

If many core functions need continuations, the SDK is not using native concurrency cleanly.

## Task-Local Values

Task-local values are for contextual metadata:

- trace IDs
- correlation IDs
- request-scoped logging metadata

Do not use task-local values for dependency injection, configuration, authorization policy, or behavior-changing inputs. Pass those explicitly.

## Low-Level Synchronization

Prefer actors first.

Use `Mutex` when:

- state is tiny
- access is synchronous
- actor shape is unnecessary
- the lock is local and easy to audit
- measurement or simplicity justifies it

Use atomics only when:

- there is a proven need
- memory ordering is understood
- the implementation is small
- alternatives were considered
- review is focused

Unsafe pointers are a last resort. Put unsafe behavior behind a tiny safe wrapper.

## Diagnostics Playbook

### “Sending value risks causing data races”

Usually means:

- value is not Sendable
- ownership is unclear
- the boundary should transfer instead of share
- state should be actor-owned
- isolation is wrong

Fix the ownership model.

### “Capture of non-Sendable type in @Sendable closure”

Usually means:

- a reference type is being shared unsafely
- capture should be narrowed to immutable values
- state needs actor ownership
- a closure is crossing a concurrency boundary it should not cross

Fix the capture and ownership model.

### MainActor warnings in core code

Usually means UI contamination or a wrongly isolated type. Do not paper over it with more `@MainActor`.

## Review Checklist

Ask:

- What owns the mutable state?
- What owns the task?
- Is the operation structured or unstructured?
- Who cancels it?
- What happens after cancellation?
- Can state change across this `await`?
- Is actor hopping necessary?
- Are values crossing isolation boundaries Sendable?
- Is `@unchecked Sendable` hiding a design flaw?
- Does MainActor belong here?
- Is this stream truly a stream?
- Are continuations tiny and exactly-once?
