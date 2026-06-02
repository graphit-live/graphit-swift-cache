# Testing and Quality Standard

## Purpose

This guide defines how a production Swift SDK proves correctness, safety, performance, and maintainability.

The goal is confidence, not a beautiful coverage dashboard.

## Philosophy

A strong SDK is easy to test because its design is explicit:

- dependencies are visible
- state has owners
- time is injectable
- external systems are behind boundaries
- failure policy is explicit
- async work has cancellation semantics
- public APIs are small

If tests are hard to write, the design is usually too implicit.

## Framework Selection

Use Swift Testing for most package tests:

- pure logic
- state transitions
- async behavior
- cancellation behavior
- parameterized behavior
- serialization and mapping
- integration tests that do not need XCTest tooling

Use XCTest when it is the better tool:

- performance measurement APIs
- UI or app integration tests
- legacy suites
- platform automation
- specialized Apple tooling

The choice is pragmatic. Do not make framework ideology more important than signal.

## Test Layers

Use focused layers.

### Unit tests

Test pure local behavior:

- validation
- mapping
- parsing
- normalization
- state transitions
- error mapping
- policy decisions
- identifier and value semantics

### Boundary tests

Test integration boundaries:

- request construction
- response decoding
- status or failure mapping
- storage serialization
- file/resource behavior
- platform adapter assumptions
- generated-client wrappers

### Integration tests

Test composed SDK behavior:

- public facade operation through internal layers
- storage plus transport interactions
- retry or timeout policy
- state restoration
- stream lifecycle
- adapter-to-core interaction

### Concurrency tests

Test race-prone behavior:

- actor-owned state
- concurrent callers
- in-flight deduplication when present
- cancellation at suspension points
- task cleanup
- stream termination
- exactly-once continuation behavior

### Performance tests

Test known hot paths:

- decoding or parsing
- mapping large inputs
- synchronization-heavy operations
- streaming behavior
- sorting/ranking/filtering pipelines
- transport setup overhead when relevant

### Memory tests

Test retention and cleanup:

- object release
- task cancellation releasing captures
- streams releasing continuations
- bounded retained stores
- resource cleanup

## Coverage Policy

Target complete meaningful coverage of handwritten core logic.

Generated code follows a different rule:

- Do not chase vanity line coverage in generated output.
- Validate the generation source.
- Validate wrapper behavior.
- Validate contract compatibility.
- Validate integration behavior.

Coverage is not enough. A touched line is not a trusted behavior.

A meaningful test suite covers:

- success
- representative failure
- edge cases
- cancellation
- concurrency where relevant
- memory cleanup where relevant
- performance-sensitive paths where relevant

## Determinism

Tests must be deterministic by default.

Inject or control:

- time
- clocks
- UUIDs
- randomness
- locale
- calendar
- transport
- storage path
- file system state
- credentials or auth state
- process environment when relevant

No test should depend on real network, wall-clock timing, random ordering, or machine-specific state unless that is the explicit target of the test.

## Test Data

Use realistic fixtures.

Prefer:

- small inline values for pure logic
- builders for readable setup
- golden files for external payloads
- edge-case fixtures for observed failures
- test-support modules for shared helpers

Fixtures should be honest enough to catch real bugs. Toy payloads often hide decoding, optionality, pagination, and boundary mistakes.

## Async Testing

Use native async test functions for async code.

Rules:

- Do not use sleeps to wait for work unless testing time itself.
- Prefer controllable clocks or explicit synchronization.
- Use time limits for tests that can hang.
- Test cancellation before start, while suspended, and during retry/backoff when applicable.
- Test post-cancellation state.
- Ensure unstructured tasks are owned and cancelled in teardown.

## Stream Testing

For `AsyncSequence` APIs, test:

- first element delivery
- multiple element delivery when applicable
- normal finish
- error finish when applicable
- cancellation
- buffering or dropping policy
- cleanup after termination
- no retained continuation leak

A stream API without termination tests is incomplete.

## Concurrency Testing

Actor and synchronization tests should prove:

- sequential correctness
- concurrent correctness
- state consistency after suspension
- no duplicate work when deduplication is part of the contract
- no lost cancellation
- no leaked tasks

Use parameterized or repeated tests carefully. Stress tests are useful but should not be the only proof.

## Mocking Policy

Prefer real values, fakes, and focused test doubles.

Good test doubles:

- fake transport
- in-memory storage
- deterministic clock
- deterministic ID generator
- small spy at a boundary
- failing implementation for error paths

Avoid:

- protocols added only for mocks
- mocking trivial pass-through wrappers
- asserting private implementation steps
- broad mock frameworks that make tests more complex than code

Protocols belong at real boundaries.

## Performance Testing

Performance tests must measure meaningful paths.

Rules:

- Use realistic input sizes.
- Separate microbenchmarks from end-to-end benchmarks.
- Record the scenario and build configuration.
- Track regressions for critical operations.
- Avoid performance tests for trivial code.
- Keep measurements comparable.

A benchmark that does not represent real SDK use can mislead more than help.

## Memory Testing

Memory tests should answer one ownership question at a time.

Verify:

- expected deallocation
- cancellation releases state
- stream termination releases resources
- retained stores stay bounded
- wrappers around unsafe or platform resources clean up correctly

Broad integration tests are poor leak tests because they hide the retaining object.

## CI Gates

A strong SDK CI pipeline should include:

- debug build
- release build
- Swift 6 language mode
- no concurrency warnings
- unit tests
- integration tests
- contract or boundary tests
- concurrency and cancellation tests
- documentation build
- example or sample integration build
- dependency resolution check
- performance lane for critical paths
- memory or leak lane for long-lived components
- strict memory safety lane for low-level or security-sensitive targets

Do not put warnings-as-errors policy in a public package manifest if it harms consumers. Enforce it in repository validation scripts or CI where appropriate.

## Release Gates

A change is not release-ready unless:

- public API changes are reviewed
- new public APIs are documented
- examples compile
- tests are deterministic
- failure behavior is covered
- cancellation behavior is covered for async APIs
- no new concurrency warnings exist
- no unsafe code lacks review
- critical performance has not materially regressed
- migration notes exist for breaking changes

## Test Review Checklist

Ask:

- Does this test prove behavior or touch implementation?
- Would it fail for a meaningful regression?
- Is setup understandable?
- Is time controlled?
- Is external I/O controlled?
- Are failure and cancellation covered?
- Is concurrency behavior covered where relevant?
- Is memory cleanup covered where relevant?
- Is the fixture realistic?
- Is the test stable in parallel?

## Anti-Patterns

Avoid:

- fake coverage
- testing implementation trivia
- sleeps as synchronization
- real network in ordinary tests
- real wall-clock dependence
- protocols created only for mocks
- shared mutable test state
- giant fixture objects hiding the scenario
- broad integration tests used as leak tests
- performance tests with unrealistic inputs
