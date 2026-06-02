# Deferred features

This file records what is intentionally **not** part of lean v1.

## Codecs are deferred

V1 has no public codec API:

- no `CacheValueKey<Value>`;
- no `CacheValueCodec`;
- no `JSONCacheValueCodec`;
- no `CacheCodecID`;
- no `get<Value>` / `set<Value>`.

Reason: GraphitCache stores bytes. Consumers know whether their bytes are JSON, protobuf, SQLite snapshots, custom binary, or image data.

Consumer example:

```swift
let data = try JSONEncoder().encode(profile)
try await profiles.setData(
    data,
    for: .profile(userID),
    options: .init(tags: [AppCache.Tags.profile, AppCache.Tags.user(userID)])
)

if let cached = try await profiles.data(.profile(userID)) {
    let profile = try JSONDecoder().decode(Profile.self, from: cached.data)
}
```

Protobuf/custom formats use the same `setData` / `data` APIs with app-defined tags when useful.

## Kind/content-type APIs are deferred

V1 has no public semantic kind or MIME/content-type API:

- no `CacheKind`;
- no `BucketPolicy.defaultKind`;
- no `removeAll(kind:)`;
- no `CacheContentType`;
- no content-type constants;
- no grouped usage by kind/content type.

Reason: semantic categories and content labels are easy for apps to express as tags. The cache does not need MIME knowledge for correctness.

Examples:

```swift
CacheTag("kind:profile")
CacheTag("format:json")
CacheTag("media:mp4")
```

File path extensions are handled by `CacheFileOptions.fileExtension`, which is only a path hint for file usability, not content metadata.

## Usage details are deferred

V1 usage answers: “how much cache storage exists?”

It does not expose:

- data/file size breakdowns;
- data/file entry counts;
- expired size/count usage fields;
- grouped usage by tag/kind/content type;
- public usage query structs.

Reason: a smaller usage snapshot is enough for common storage UI and easier to evolve. Cleanup results still report what cleanup removed.

## Instrumentation is deferred

V1 has no public event sink:

- no `CacheInstrumentation`;
- no `CacheEventSink`;
- no event structs;
- no background event task;
- no OSLog adapter.

Reason: event design is useful but broad. It adds public surface, reentrancy concerns, privacy decisions around raw keys, and latency semantics. Add it later after core behavior stabilizes.

## Consequences for implementation

- Do not add placeholder public codec/event/kind/content types.
- Do not add no-op event recorder just for future shape.
- Do not add usage detail fields “because SQLite can calculate them.”
- Keep internal logging/testing local if needed, but not public API.
- Errors should be enough for v1 user-facing diagnostics.
