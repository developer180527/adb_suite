# adb_suite

Product repo: feature packages and the consumer apps built on them.

The protocol layer lives in the public [`adb_dart`](https://github.com/venugopal/adb_dart)
repo (`adb_core`, `adb_ui`). Dependencies point one way only — product depends
on protocol, never the reverse.

## Layout

```
packages/     feature modules: service + widgets, one concern each
apps/         compositions of those modules
```

A feature package owns its service *and* its UI, and knows nothing about which
app hosts it. Adding or splitting an app is a pubspec change, not a refactor.

## Local setup

Check out both repos as siblings:

```
~/Developer/adb_dart
~/Developer/adb_suite
```

Then create `pubspec_overrides.yaml` at this repo's root (it is gitignored):

```yaml
dependency_overrides:
  adb_core:
    path: ../adb_dart/packages/adb_core
  adb_ui:
    path: ../adb_dart/packages/adb_ui
```

Edits to `adb_core` are then live here immediately. The committed pubspecs pin
a git ref, so CI and fresh clones resolve reproducibly without the override.

To adopt a new protocol release, bump the `ref:` in the feature pubspecs to the
new tag from `adb_dart`.
