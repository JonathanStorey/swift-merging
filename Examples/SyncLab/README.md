# Sync Lab

An iOS app that checks `MergingSwiftData` end to end, one test at a time, from plain merges up to three
stores syncing through CloudKit. Each test checks off as it passes, and a live diagram shows who is editing,
sending, receiving, merging, or waiting.

## The stages

| Stage | What talks to what | What it shows |
| --- | --- | --- |
| Merge rules | Snapshots, no store | 3-way merges with 2 and 3 editors keep every edit. A 2-way merge, with no base, may refuse but never quietly drops an edit. |
| One store, 2 editors | Main context and a background context | The main context's unsaved edit and the other context's save both survive the main context's save. |
| One store, 3 editors | Main context and two background contexts | The same, with two saves stacked before the main context saves. |
| 2 stores via CloudKit | Devices A and B | Both devices end up with both edits, and with the same values. |
| 3 stores via CloudKit | Devices A, B and C | The same, with three devices. |

Every stage runs one test for each kind of data:

- **String**, merged `.byWord`: each editor upper-cases a different word of the title.
- **[String]**, merged `.byElement`: each editor appends a step.
- **Codable struct**, merged `.byNode`: a struct SwiftData stores as itself, one column per field, with a
  nested struct, a dictionary and an array of structs. It can't hold an optional or an enum: SwiftData on
  iOS 18.6 stops the app as soon as a store opens ("Failed to materialize a keypath" for a `String?`,
  "Failed to validate … is not a member of" for a `String`-backed enum). The first is a
  [known bug](https://developer.apple.com/forums/thread/784036) in reading the store's history, which
  merging relies on.
- **Codable as JSON**, merged `.json(Spec.self)`: the same kind of struct, with an optional and an enum,
  kept in a `Data` property as JSON and read through a computed property. SwiftData stores one column, so
  neither problem applies, and the merge decodes the JSON and merges it field by field.
- **Relationship**, merged `.byMembership`: each editor adds a label.
- **External storage blob**: one editor replaces a 256 KB blob while the others edit the title.

## How the stores stand in for devices

Each device is its own store file with its own CloudKit mirror, merge coordinator and ledger, all on the same
CloudKit container and zone. That's what separate devices have. What they share that real devices don't is
this one process and its pushes, so a push can wake them together. To keep that from hiding problems, each
CloudKit test uses one of three timings, rotated so each kind of data meets two of them across the stages:

- **Everyone saves at once**: the exports race at the server.
- **Edit while A's change arrives**: B and C hold unsaved edits while A's change imports, then save.
- **Edit offline, then reconnect**: B and C reopen their stores without CloudKit, edit and save, wait for A
  to export, then come back online one at a time. This is the case where CloudKit keeps this device's
  unexported value and the merge has to fetch the other device's from the server.

While waiting for devices to agree, the lab reopens a device every 30 seconds, which makes CloudKit import
at once instead of waiting for a push.

## Running it

The first three stages need nothing: open `SyncLab.xcodeproj`, pick a simulator, and run. Xcode asks you to
trust the package's macros the first time.

For the CloudKit stages:

1. Set `SYNCLAB_TEAM`, `SYNCLAB_BUNDLE_ID` and `SYNCLAB_CLOUDKIT_CONTAINER` in `Config.xcconfig`. Use a
   container only for testing: the lab writes and deletes items there.
2. Sign in to iCloud on the device or simulator.
3. Run, and tap the play button on the CloudKit stages. The cloud button shows each device's sync state and
   can erase everything to start over.

CI builds the app and runs the first three stages in a simulator with `-autorun local`, which prints each
result and quits.
