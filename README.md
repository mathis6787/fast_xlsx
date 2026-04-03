# fast_xlsx

`fast_xlsx` is a backend-focused Dart package for streaming XLSX import and
export through Rust FFI. It is designed for large files where the Dart side
should avoid holding the entire workbook in memory while also supporting
direct local-file workflows.

## Features

- Streaming XLSX import from `Stream<List<int>>`
- Streaming XLSX export to `Stream<List<int>>`
- Direct XLSX import/export from filesystem paths
- Typed cell model for blank, int, double, bool, text, date-like text, and
  error values
- Prebuilt native assets downloaded automatically from GitHub Releases
- `local_build=true` override for compiling Rust locally with `native_toolchain_rs`

## Usage

```dart
import 'dart:async';
import 'dart:io';

import 'package:fast_xlsx/fast_xlsx.dart';

Future<void> main() async {
  final streamWriter = FastXlsxWriter(sheetName: 'StreamSheet');
  streamWriter.addRow([
    const XlsxCell.text('name'),
    const XlsxCell.integer(42),
  ]);

  final bytes = <int>[];
  await for (final chunk in streamWriter.finish()) {
    bytes.addAll(chunk);
  }

  final streamReader = await FastXlsxReader.open(Stream.value(bytes));
  await for (final row in streamReader.rows()) {
    print('stream: ${row.rowIndex}: ${row.cells}');
  }

  final file = File('/tmp/output.xlsx');
  final pathWriter = FastXlsxWriter(sheetName: 'PathSheet');
  pathWriter.addRow([
    const XlsxCell.text('orange'),
    const XlsxCell.doubleValue(4.5),
  ]);
  await pathWriter.writeToFile(file);

  final pathReader = await FastXlsxReader.openFile(file);
  await for (final row in pathReader.rows()) {
    print('path: ${row.rowIndex}: ${row.cells}');
  }
}
```

## Build Modes

`fast_xlsx` now supports two native-asset distribution modes:

- Default consumer mode: the build hook downloads a prebuilt native library
  from the GitHub release configured in
  [`lib/src/hook/version.dart`](lib/src/hook/version.dart).
- Maintainer/dev mode: pass `local_build=true` to compile the Rust crate
  locally instead of downloading a release asset.
- Bootstrap mode in this repository: while
  [`lib/src/hook/hashes.dart`](lib/src/hook/hashes.dart) is still empty before
  the first asset release is published, the hook falls back to a local Rust
  build automatically.

Examples:

```sh
dart test --define=fast_xlsx:local_build=true
dart run --define=fast_xlsx:local_build=true example/fast_xlsx_example.dart
```

If the pinned release assets have not been published yet, use `local_build=true`
for consumer projects. For local development in this repository, the current
hooks tooling is more reliable with an environment variable:

```sh
FAST_XLSX_LOCAL_BUILD=true dart test
FAST_XLSX_LOCAL_BUILD=true dart run example/fast_xlsx_example.dart
```

## Maintainer Flow

- Build a specific backend target locally with `dart run tool/build.dart`.
- Publish backend binaries by pushing a tag like `fast-xlsx-assets-v0.1.0`.
- Regenerate [`lib/src/hook/hashes.dart`](lib/src/hook/hashes.dart) after the
  release assets exist:

```sh
dart run tool/generate_asset_hashes.dart
```

Or point the hash generator at a local `libs/` directory produced by CI:

```sh
dart run tool/generate_asset_hashes.dart --assets-dir libs
```

## Notes

- v1 only reads the first worksheet in a workbook.
- v1 writes a single worksheet per workbook.
- Styling, formulas, merged cells, and CSV are intentionally out of scope.
