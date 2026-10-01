# Contributing

## Native library

Consuming applications use prebuilt native libraries by default. The build hook
downloads the library for the target platform from GitHub Releases and verifies
it against a pinned SHA-256 hash. Builds that fetch assets need access to GitHub
and its release download servers. A cached build may reuse its native asset;
do not assume a clean build works offline.

This repository enables local Rust builds for development. Compiling locally
requires a Rust toolchain and the appropriate native linker.

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

## Regenerating FFI bindings

The Dart generator in `tool/ffigen.dart` reads `src/fast_xlsx.h` and writes
`lib/src/fast_xlsx_bindings.g.dart`. Install LLVM/libclang before regenerating
bindings; ffigen searches standard installation locations.

```sh
dart run tool/ffigen.dart
```

The generator resolves paths relative to its script, so it can also be invoked
from another directory. It includes only `fx_` functions and `Fx` types and
preserves the native asset ID used by the build hook. Update the generator or
header when changing bindings; do not edit the generated file directly.

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

## Release verification

Before publishing the Dart package, run the **Verify package and released
assets** workflow from the GitHub Actions tab. It also runs on pull requests
and pushes to `main`. It tests source builds and released binaries on Linux,
macOS, and Windows, each on arm64 and x64, and verifies all six pinned SHA-256
hashes.
The release tag comes from `lib/src/hook/version.dart`.

To verify the released files locally without updating any pins:

```sh
dart tool/verify_asset_hashes.dart
```

For already downloaded binaries, add `--assets-dir libs`. Missing files,
missing or unexpected pins, and mismatched hashes fail verification. Hash
generation is a separate, intentional step after publishing new native assets.

To test the released binary for your current machine:

```sh
dart tool/verify_consumer.dart
```

This creates a fresh temporary Dart project with a path dependency on this
checkout, disables local Rust builds, and runs the XLSX stream, filesystem,
typed-value, and malformed-input tests against the downloaded release library.
It removes the temporary project afterward. CI passes `--target=linux_arm64`
(or the corresponding platform and architecture) to ensure the Dart SDK is
running with the expected ABI.

For a new native release: build and publish the assets, update the release tag
and pinned hashes in this checkout, then run verification. Publish to pub.dev
only after the hash job and all six platform jobs pass. A green asset-build
workflow alone does not verify runtime compatibility.
