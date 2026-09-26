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
- Matching prebuilt native libraries downloaded automatically from GitHub
  Releases

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

## Performance

In a benchmark on one macOS arm64 machine (Dart 3.13.4), `fast_xlsx` 0.1.0
with a locally built Rust backend exported two 1M-cell sheets 1.9–2.1× faster
and fully imported them 4.8× faster than the fastest of `excel_plus` 2.23.0
and `excel_community` 2.4.1. The peer with the lowest peak process memory
used 2.6–2.9× as much as `fast_xlsx`.

These results cover generated, single-sheet files with basic cell values.
In the competitor-style all-text test, `fast_xlsx` took longer to create the
cells, despite a shorter combined create, encode, and A1-access time. Timings
vary by hardware and workload; run all three libraries on the same machine,
back to back, for a fair comparison. See the [benchmark method](https://github.com/mathis6787/fast_xlsx/blob/main/benchmark/README.md)
and [dated results](https://github.com/mathis6787/fast_xlsx/blob/main/benchmark/results/2026-09-26_200119.md).

## Native library

The build hook downloads the prebuilt native library for your platform from
GitHub Releases. Contributors who need to build the Rust backend locally can
follow the [contribution and release instructions](CONTRIBUTING.md).

## Notes

- v1 only reads the first worksheet in a workbook.
- v1 writes a single worksheet per workbook.
- Styling, formulas, merged cells, and CSV are intentionally out of scope.
