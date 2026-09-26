# Contributing

## Local development

The repository's root `pubspec.yaml` sets `hooks.user_defines.fast_xlsx.local_build`
to `true`, so tests and examples compile the Rust crate locally through
`native_toolchain_rust`.

```sh
dart test
dart run example/fast_xlsx_example.dart
```

To compile the local Rust backend from a consuming application, set the same
option in that application's root `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    fast_xlsx:
      local_build: true
```

The consuming application must set this option itself; a dependency cannot set
build options for its consumers.

## Native asset releases

Build one backend target locally with `dart run tool/build.dart`, passing the
target operating system and architecture. For example:

```sh
dart run tool/build.dart -omacos -aarm64
```

Supported operating systems are `linux`, `macos`, and `windows`; supported
architectures are `arm64` and `x64`.

Publish backend binaries by pushing a new versioned `fast-xlsx-assets` tag.
After the release assets exist, regenerate
[`lib/src/hook/hashes.dart`](lib/src/hook/hashes.dart):

```sh
dart run tool/generate_asset_hashes.dart
```

To generate hashes from a local `libs/` directory produced by CI, pass its path
instead:

```sh
dart run tool/generate_asset_hashes.dart --assets-dir libs
```
