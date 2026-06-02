# Performance and Memory Standard

## Purpose

This guide defines performance and memory discipline for production Swift SDKs.

The goal is not micro-optimized code everywhere. The goal is simple code that is naturally efficient, with specialist optimization only where evidence proves it matters.

## Primary Rule

Measure first.

No performance claim is accepted without evidence from profiling, benchmarks, traces, or before/after measurements.

Use evidence to answer:

- where time is spent
- how many allocations occur
- whether ARC traffic matters
- whether values are copied too often
- whether decoding or parsing dominates
- whether actor hops hurt latency
- whether task creation is excessive
- whether buffering or retained storage grows without bound
- whether an optimization improves real consumer scenarios

Optimize the measured bottleneck, not the suspected one.

## Swift Cost Model

Every engineer should understand these costs:

- heap allocation
- retain/release traffic
- large value copies
- Foundation bridging
- string and data conversion
- encoding and decoding
- repeated model materialization
- task creation and scheduling
- actor hops
- lock contention
- buffering and retained storage
- dynamic dispatch and type erasure
- cross-module optimization constraints
- unsafe-code maintenance cost

A codebase is fast when its data and ownership are clear.

## Data Design

Good performance begins with representation.

Prefer:

- small explicit value types
- dedicated identifiers
- one representation per layer
- immutable snapshots across boundaries
- clear optionality
- normalized data at the boundary
- single-pass transformations when clarity is preserved

Avoid:

- god models carrying unrelated state
- raw dictionaries and `Any`
- partially decoded external payloads spread through core logic
- repeated transformations of the same data
- broad reference graphs
- large values copied repeatedly without awareness

## Allocation Discipline

Common allocation problems:

- temporary arrays from eager chains
- repeated encoder/decoder creation in hot paths
- repeated regular expression or formatter construction
- repeated string/data conversions
- wrapper objects around wrapper objects
- many tiny tasks for tiny work
- unbounded buffers, registries, or memoized values

Rules:

- Prefer clear code first, then profile.
- Reserve collection capacity when size is known and the path matters.
- Reuse expensive infrastructure when safe.
- Avoid long eager collection pipelines on large inputs.
- Do not cargo-cult `lazy`; use it when semantics remain clear and it helps.
- Keep retained storage bounded.

## Value Types and Copying

Value semantics usually improve clarity and Sendable reasoning, but values are not free.

Watch for:

- large arrays copied through layers
- nested values copied during mapping
- repeated sorting/filtering creating new collections
- `Data` copies
- string slicing or conversion surprises

Prefer immutable snapshots and clear ownership. Use borrowing-oriented or low-level tools only where the code path deserves the complexity.

## Reference Types and ARC

ARC is predictable, not free.

Use classes when semantics require identity, lifecycle coupling, Objective-C interoperability, framework constraints, or intentional reference sharing.

Avoid:

- class use just for convenient mutation
- reference-heavy abstractions in hot loops
- closure captures of entire objects when only a few values are needed
- accidental retain cycles
- weak/unowned references as automatic leak bandages

Closure capture policy:

- Capture specific immutable values where possible.
- Use `[weak self]` when the closure may outlive the owner and dropping work is correct.
- Do not use `[weak self]` reflexively when the operation must complete.
- Use `unowned` only with a documented lifetime invariant.
- Never use `unowned(unsafe)` in production code.

## Collections and Algorithms

Start with the clearest implementation.

Then ask:

- Is this input large enough to matter?
- Are intermediate arrays being created?
- Can this be a single pass without reducing clarity?
- Should capacity be reserved?
- Is sorting required?
- Can work be avoided by better representation?
- Is this path hot enough for specialization?

Prefer better data shape over clever control flow.

## Strings, Data, Encoding, and Decoding

Boundary work is often expensive.

Rules:

- Decode once at the boundary when possible.
- Normalize external quirks at the boundary.
- Avoid decode -> re-encode -> decode cycles.
- Avoid repeatedly converting between `String`, `Data`, and Foundation representations.
- Stream large data when appropriate.
- Keep large payload duplication low.
- Validate external data where it enters the SDK.

## Concurrency Performance

Concurrency improves structure and throughput when used correctly. It also has costs.

Watch for:

- excessive task creation
- actor ping-pong
- blocking the main actor
- unbounded fan-out
- streams with unexamined buffering
- detached tasks with unclear lifetime
- synchronization around too much code

Rules:

- Batch work per actor hop.
- Pass immutable snapshots.
- Bound task groups for large workloads.
- Keep heavy pure work outside actors.
- Do not use async merely to hide slow synchronous work.

## Reuse and Retained Storage

Reuse expensive infrastructure when safe and beneficial:

- sessions and clients
- encoders and decoders
- parsers
- formatters when truly expensive
- compiled regular expressions
- bounded in-memory stores
- long-lived transport configuration

Every retained store or memoized result must have:

- owner
- bound or eviction strategy
- invalidation behavior if relevant
- memory expectation
- test coverage for cleanup

Unbounded convenience becomes production risk.

## Instrumentation

Use the right tool for the question:

- Time Profiler for CPU.
- Allocations for heap behavior.
- Leaks for retention mistakes.
- Swift Concurrency instrument for tasks and actor behavior.
- Hangs or hitches instruments for responsiveness.
- Network and file activity instruments where relevant.
- Signposts for conceptual spans the tools cannot infer.

Always keep traces comparable: same build mode, similar data, similar device conditions, and clear scenario description.

## Signposts and Logs

Use signposts around meaningful spans:

- request execution
- decoding or parsing
- mapping
- local expensive transforms
- synchronization-sensitive operations
- stream lifecycle

Logs should explain outcomes, not create noise. Do not log secrets or private payloads.

## Advanced Swift Tools

Use advanced tools only when the path deserves them.

### `@inlinable` and `@usableFromInline`

`@inlinable` exposes implementation details and constrains future changes. Use it only for small, pure, stable APIs where cross-module optimization matters.

`@usableFromInline` exists to support approved inlinable APIs. Do not add it as a style preference.

### Swift 6.3 library optimization controls

Swift 6.3 adds library-author controls such as specialization, guaranteed inlining for direct calls, and implementation visibility for ABI-stable libraries. These are powerful and should be rare.

Use `@specialize`, `@inline(always)`, and `@export(implementation)` only when:

- the API is stable enough
- measurement or strong cost-model evidence supports it
- code size impact is acceptable
- review approves the future maintenance cost

### `Span`, `InlineArray`, and noncopyable types

Use these when the data model truly benefits:

- `Span` for safe direct access to contiguous memory in specialized paths.
- `InlineArray` for fixed-size storage where allocation avoidance matters.
- Noncopyable types for unique ownership and resource management.

They are not default style for ordinary SDK logic.

### Mutexes and atomics

Use `Mutex` for tiny synchronous state when actors are the wrong shape.

Use atomics only in specialist code with understood memory ordering.

## Unsafe Code Policy

Unsafe code is allowed only when all are true:

- profiling or interoperability justifies it
- scope is minimal
- a safe wrapper owns the danger
- lifetime assumptions are documented
- alignment and ownership assumptions are documented
- tests exercise the wrapper
- review is focused

Unsafe code should not spread beyond the wrapper.

## Memory and Leak Discipline

Memory-sensitive components need tests that verify:

- objects deallocate after owner release
- tasks release captured state after cancellation
- streams finish and release continuations
- retained stores respect bounds
- temporary files or resources are cleaned up when the API promises cleanup

Do not rely on incidental `deinit` timing as hidden control flow.

## Optimization Review Checklist

Before approving an optimization, ask:

- What was measured?
- What improved?
- What got worse?
- Is the scenario representative?
- Did allocation count change?
- Did actor hopping or task count change?
- Did memory growth change?
- Did code size change?
- Did public API stability suffer?
- Did readability suffer?
- Is the optimization covered by tests or benchmarks?
- Can this be removed later if it stops helping?

## Anti-Patterns

Avoid:

- performance claims without traces or benchmarks
- speculative `@inlinable`
- `@inline(always)` as a habit
- unsafe code for minor convenience
- unbounded retained state
- many tiny tasks for tiny work
- actor ping-pong
- unnecessary type erasure in hot paths
- wrapper stacks that hide simple work
- optimizing the wrong layer
