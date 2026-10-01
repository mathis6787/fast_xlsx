# fast_xlsx

`fast_xlsx` is a backend-focused Dart package for streaming XLSX import and
export through Rust FFI. It is designed for large files where the Dart side
should avoid holding the entire workbook in memory while also supporting
direct local-file workflows.

Version 0.1.0 targets **desktop and server Dart** on Linux, macOS, and Windows,
on arm64 and x64, with Dart 3.13.4 or newer (below 4.0.0). Web, Android, and iOS
are not supported.
Builds that fetch the prebuilt native library require network access to GitHub
Releases, including clean CI builds. Reading and writing XLSX files does not
require network access at runtime.

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
import 'dart:io';

import 'package:fast_xlsx/fast_xlsx.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('fast_xlsx_example_');
  try {
    final file = File('${directory.path}/output.xlsx');
    final writer = FastXlsxWriter(sheetName: 'Inventory');
    try {
      writer.addRow([
        const XlsxCell.text('orange'),
        const XlsxCell.integer(42),
      ]);
      await writer.writeToFile(file);
    } finally {
      writer.close();
    }

    final reader = await FastXlsxReader.openFile(file);
    try {
      await for (final row in reader.rows()) {
        print('${row.rowIndex}: ${row.cells}');
      }
    } finally {
      reader.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
```

`writeToFile` and `writeToPath` require a new destination file and an existing
parent directory. They fail instead of overwriting an existing file.

For stream output, pipe the returned stream directly to your destination rather
than collecting the entire workbook in a Dart list:

```dart
Future<void> exportStream(File destination) async {
  final writer = FastXlsxWriter(sheetName: 'Inventory');
  try {
    writer.addRow([const XlsxCell.text('orange'), const XlsxCell.integer(42)]);
    await writer.finish().pipe(destination.openWrite());
  } finally {
    writer.close();
  }
}
```

`File.openWrite()` in this example replaces an existing file; use `writeToFile`
when you need the package's check that rejects an existing destination. For
stream input, call `FastXlsxReader.open(sourceStream)` and consume `rows()` in
the same `try/finally` pattern.

## Read modes and temporary disk

Choose a mode through `readMode` on `open`, `openFile`, or `openPath`:

| Mode | Behavior | Memory use |
| --- | --- | --- |
| `FastXlsxReadMode.streaming` (default) | Parses worksheet cells as rows are requested. | Avoids storing every worksheet row; metadata and shared strings still use memory. |
| `FastXlsxReadMode.buffered` | Parses and buffers the first worksheet's rows in the native backend when opening. | Grows with worksheet contents. |

Both modes allow one traversal only. Buffered mode does not add random access or
allow you to read the rows a second time.

`FastXlsxReader.open(sourceStream)` consumes the **entire input stream** into a
temporary file before returning a reader. Rows cannot be read while the upload
is still arriving. That file remains until the reader closes. `openFile` and
`openPath` read the existing file without making this staging copy.

Writers use temporary disk for worksheet data, including direct path exports.
`finish()` first saves a complete XLSX file to temporary disk, then returns a
stream that reads it in chunks. It does not emit XLSX bytes while you add rows.
Its `chunkSize` must be positive and defaults to 64 KiB.

The native backend uses the operating system's temporary directory. Ensure it
is writable and has room for staged uploads, worksheet data, and completed
stream exports. Streaming reduces row buffering; it does not mean zero disk use
or a fixed memory limit.

Native parsing and writing run synchronously on the calling isolate. Futures
and streams do not move that work to another isolate. Use a worker isolate for
large operations when responsiveness matters.

## Resource cleanup and one-time consumption

- A reader's `rows()` stream is single-subscription. Each reader permits one
  traversal; consuming another `rows()` stream throws `StateError`. Reopen the
  workbook to read again.
- Row-stream completion, errors, and cancellation close the reader. An early
  `break` in `await for` cancels the stream. For manual subscriptions, await
  `subscription.cancel()` to finish cleanup.
- Call `reader.close()` if you open a reader but never consume its rows.
  `try/finally`, as shown above, also covers errors before iteration starts.
- Call `writer.close()` to discard an unfinished writer, including after an
  `addRow` failure. A writer can be finalized only once; finalization attempts
  prevent further writing even if they fail.
- The stream returned by `finish()` owns the output file and releases it on
  completion, error, or cancellation. Consume it once and await completion or
  cancellation. Do not leave it unconsumed: `writer.close()` is a no-op after
  finalization and cannot close that output stream.

Repeated `close()` calls are safe. Native finalizers provide fallback cleanup
for abandoned handles, but garbage collection does not provide prompt cleanup.
Explicitly close readers and unfinished writers, and complete or cancel output
streams so resources are released predictably.

## Cell values

| Cell type | Import behavior | Export behavior |
| --- | --- | --- |
| `blank` | Empty cell with a null value. | Empty cell. |
| `integer`, `doubleValue`, `boolean`, `text` | Typed numeric, boolean, and string values. | Corresponding numeric, boolean, or string values. |
| `dateLikeText` | Date/time/duration values represented as a backend-provided string. | Ordinary text, not an Excel date or duration. |
| `error` | Worksheet errors, such as `#DIV/0!`, represented as strings. | Ordinary text, not a native Excel error cell. |

Date-like strings are not Dart `DateTime` objects, are not guaranteed to be ISO
8601, and may represent Excel serial values. The package does not parse dates,
convert timezones, or apply date formatting. Exported `dateLikeText` and `error`
cells read back as `text`, so those types do not round-trip unchanged.

A worksheet error cell does not throw an exception. Native file, validation,
and parsing failures throw `FastXlsxException`; source-stream errors propagate
from the source. Invalid lifecycle operations throw `StateError`.

Check `cell.type` before using `asInt`, `asDouble`, `asBool`, or `asString`.
These getters cast the stored value: blank cells return null, and incompatible
types throw `TypeError`. `asString` works for text, date-like text, and errors;
`asDouble` does not convert an integer. Whole-valued numeric imports may become
`integer`, and large integer exports may lose precision in XLSX numeric storage.

Row indices are zero-based worksheet indices. Entirely blank rows are omitted,
so indices can have gaps; trailing blank cells are removed.

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

## Notes

- Version 0.1.0 only reads the first worksheet in a workbook.
- Version 0.1.0 writes a single worksheet per workbook.
- Styling, formulas, merged cells, and CSV are intentionally out of scope.
