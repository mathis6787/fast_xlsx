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
- Native asset build with Rust via `native_toolchain_rs`

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

## Notes

- v1 only reads the first worksheet in a workbook.
- v1 writes a single worksheet per workbook.
- Styling, formulas, merged cells, and CSV are intentionally out of scope.
