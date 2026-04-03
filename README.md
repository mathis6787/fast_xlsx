# fast_xlsx

`fast_xlsx` is a backend-focused Dart package for streaming XLSX import and
export through Rust FFI. It is designed for large files where the Dart side
should avoid holding the entire workbook in memory.

## Features

- Streaming XLSX import from `Stream<List<int>>`
- Streaming XLSX export to `Stream<List<int>>`
- Typed cell model for blank, int, double, bool, text, date-like text, and
  error values
- Native asset build with Rust via `native_toolchain_rs`

## Usage

```dart
import 'dart:async';

import 'package:fast_xlsx/fast_xlsx.dart';

Future<void> main() async {
  final writer = FastXlsxWriter(sheetName: 'Sheet1');
  writer.addRow([
    const XlsxCell.text('name'),
    const XlsxCell.integer(42),
  ]);

  final bytes = <int>[];
  await for (final chunk in writer.finish()) {
    bytes.addAll(chunk);
  }

  final reader = await FastXlsxReader.open(Stream.value(bytes));
  await for (final row in reader.rows()) {
    print('${row.rowIndex}: ${row.cells}');
  }
}
```

## Notes

- v1 only reads the first worksheet in a workbook.
- v1 writes a single worksheet per workbook.
- Styling, formulas, merged cells, and CSV are intentionally out of scope.
