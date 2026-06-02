# Package and Release Standard

## Purpose

This guide defines package structure, manifest policy, documentation, CI, and release discipline for production Swift SDKs.

## Package Shape

Default to a source package with one primary public library product.

A good package shape:

- has a small public product surface
- keeps internals replaceable
- uses targets to protect real boundaries
- avoids target sprawl before boundaries are real
- keeps platform-specific adapters separate from the platform-neutral core
- includes tests and test support without leaking test hooks into production API

Do not split targets for optics. Split targets when build time, platform support, dependency direction, binary boundaries, generated code, or ownership justify it.

## Target Categories

Common target categories:

- core public target
- internal implementation targets
- generated-code targets
- platform adapter targets
- test support targets
- examples or sample integration targets

Rules:

- The core target should not depend on UI adapters.
- Generated code should not dictate public API shape by accident.
- Test support must not be imported by production targets.
- Platform-specific dependencies should stay in platform-specific targets.
- Keep imports minimal.

## Package Manifest Policy

Set the tools version to the oldest toolchain the repository officially supports.

Use Swift 6 language mode for targets that are part of the modern SDK baseline.

Use default actor isolation deliberately:

- Core targets: explicit isolation; no MainActor-by-default.
- UI adapter or executable targets: MainActor-by-default is acceptable when it improves clarity.
- Low-level targets: explicit isolation and focused review.

Use strict memory safety as a dedicated lane or for targets that need stronger checking around unsafe or low-level code.

Do not use unsafe flags as a normal escape hatch. If a target needs unusual compiler settings, document why.

## Platform Support

Declare platform support explicitly.

A platform-neutral SDK should avoid importing Apple-only frameworks in core targets. Use conditional compilation only at narrow boundaries.

Rules:

- Keep `#if` regions small.
- Prefer platform adapter targets over platform branches scattered throughout core logic.
- Do not let Apple UI frameworks leak into reusable core targets.
- Test supported platforms in CI when practical.
- Do not claim support for platforms not exercised by builds or tests.

## Resources

Package resources are part of the API contract when consumers rely on them.

Rules:

- Keep resources minimal and purposeful.
- Localize package resources when user-facing text exists.
- Avoid hidden runtime assumptions about resource availability.
- Test resource loading when it affects behavior.
- Do not put secrets in package resources.

## Documentation

SDK documentation should include:

- public API documentation comments
- DocC catalog when the public surface is significant
- quick start
- installation instructions
- platform support
- configuration guide
- error/failure semantics
- concurrency and cancellation notes
- migration guide for breaking releases
- examples that compile

Docs should be concise and enforceable. Do not write architecture essays nobody will maintain.

## Examples

Examples should demonstrate real SDK use without becoming a second product.

Good examples:

- compile in CI
- use public APIs only
- show cancellation where relevant
- show error handling where relevant
- avoid private implementation shortcuts
- keep secrets out of source
- stay small enough to maintain

Examples are part of API review. If examples are hard to write, the API may be too hard to use.

## Dependency Resolution

Rules:

- Prefer zero dependencies at package start.
- Prefer Apple and Swift.org packages where they fit.
- Pin and review versions according to repository policy.
- Do not expose dependency types publicly unless intentional.
- Avoid thin convenience dependencies.
- Audit transitive dependency risk.
- Remove dependencies that no longer pay rent.

## Generated Code

Generation is acceptable when the input is canonical.

Rules:

- Commit generation inputs.
- Keep generation commands documented.
- Do not hand-edit generated output.
- Keep generated targets isolated when helpful.
- Wrap generated code behind package-owned APIs.
- Test wrapper behavior and contract compatibility.

## Binary Distribution and Library Evolution

If distributing binary frameworks or promising ABI stability:

- review public and ABI surface carefully
- understand library evolution constraints
- avoid exposing implementation details
- document compatibility policy
- treat inlinable and implementation-visibility attributes as API decisions
- test consumer integration

Source packages still need source compatibility discipline. SemVer matters even without binary distribution.

## CI Expectations

A production-ready package pipeline should include:

- clean checkout build
- debug build
- release build
- supported-platform builds
- unit tests
- integration or boundary tests
- concurrency/cancellation tests
- documentation build
- examples/sample build
- dependency resolution check
- formatting or style checks if adopted by the repo
- performance lane for critical paths
- memory/leak lane for long-lived components

CI should catch real mistakes, not create ceremony.

## Release Checklist

Before releasing:

- Public API changes reviewed.
- SemVer or repository version policy applied.
- Breaking changes documented.
- Deprecations include replacements.
- DocC builds cleanly.
- Examples compile.
- Tests pass deterministically.
- Concurrency warnings are resolved.
- Dependency changes reviewed.
- Critical performance checked.
- Unsafe code reviewed.
- Release notes explain behavior changes.

## Consumer Integration

Think like the consuming engineer.

A consumer should know:

- how to install
- supported Swift and platform versions
- how to configure
- what can fail
- what is async or streaming
- what is cancellable
- what is thread-safe or actor-isolated
- what must be retained
- what must be cleaned up
- how to migrate between versions

An SDK that works only when the consumer guesses internal assumptions is not production-quality.

## Anti-Patterns

Avoid:

- target sprawl without boundaries
- app code moved into `Sources/`
- platform-specific imports in core targets
- generated types as accidental public API
- test hooks in production API
- warnings hidden because CI is noisy
- docs that do not match examples
- release notes that omit behavior changes
- scripts that duplicate SwiftPM/Xcode/CI without preventing a real repeated mistake
