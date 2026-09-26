# XLSX benchmark

This benchmark compares `fast_xlsx` 0.1.0 with pinned `excel_plus` 2.23.0 and
`excel_community` 2.4.1 on the Dart VM. Each library has its own Dart package so
dependency resolution and memory accounting stay separate.

## Run

Prerequisites: Dart SDK 3.11.4 or newer, Rust toolchain 1.92.0, and
enough free disk for temporary XLSX files. The benchmark builds `fast_xlsx`
locally using `hooks.user_defines` in `fast_xlsx/pubspec.yaml`; it does not
download a release asset.

```sh
cd benchmark/runner
dart pub get
dart run bin/run.dart --smoke
dart run bin/run.dart
dart run bin/run.dart --stress  # Optional 5M-cell case
dart run bin/run.dart --suite parity  # Competitor-style all-text lifecycle
dart run bin/run.dart --suite representative  # Input variants
```

Set `DART_BIN` to a Dart executable if `dart` is not on `PATH`. `--skip-setup`
uses previously resolved Dart dependencies. The full run writes a dated JSON
file and Markdown report to `benchmark/results/`. The default is three
repetitions; `--repetitions N` changes this for exploratory runs. `--case 100k`
selects one size in the core suite. The default `--suite all` runs the core,
parity, and representative suites. `--suite core` runs only the original
complete-file comparison. The optional `--stress` case applies to core.

The first run needs network access to download the pinned Dart packages and
possibly Rust crates. The runner creates fixtures and outputs in a temporary
directory and deletes them when finished.

## Method

- The runner generates single-sheet XLSX fixtures independently of all three
  libraries. They contain deterministic integers, half-integer doubles,
  repeated text, and booleans. Exports generate the same logical cells.
- Every process warms up on 16 × 10 cells before timing. The runner rotates
  library order across repetitions. Startup, dependency resolution, and native
  compilation are outside the measured interval.
- Export runs from workbook construction through a completed XLSX file. Import
  runs from opening the same file through traversal of every cell. Counts and a
  typed, position-sensitive checksum must match. Smoke tests cross-read every
  writer's output with every reader; the first large export from each writer
  is also checked by a different library.
- A second Dart isolate in each worker samples process RSS and files under its dedicated `TMPDIR` every
  10 ms. This includes native allocations but may miss short-lived peaks,
  especially for small cases. It reports absolute RSS, not incremental memory.
  `excel_plus` uses `appendRow` and `encodeToStream`; `excel_community` uses
  direct `updateCell` calls and `save()` followed by a file write;
  `fast_xlsx` uses `addRow` and `writeToPath`. In `excel_community` 2.4.1,
  `appendRow` rescans the complete sheet on each call, so direct updates are
  the practical API for tall sheets.
- Sizes are 1,000 × 10, 10,000 × 10, 100,000 × 10, and 20,000 × 50 cells.
  The last two have the same cell count but different row widths. The optional
  stress case is 500,000 × 10 cells. Extra `fast_xlsx` measurements compare
  streaming and buffered reads and path and stream I/O.
- The parity suite uses all-text 10 × 50 and 20,000 × 50 sheets. It times
  creation, encoding to an in-memory byte array, and opening those bytes to
  access A1, following the competitors' published method. It then writes the
  bytes outside the timed phases and has another library fully cross-read the
  file. A1 timing is reported separately from complete import.
- The representative suite fully imports five neutral 100,000 × 10 inputs:
  repeated and unique text stored both inline and in a shared string table,
  plus mixed values with 20% of cells omitted. Every cell position and value
  is checked with a checksum. These fixtures are generated outside timing.

Only shared import/export features are compared. No styles, formulas, or
multiple worksheets are included. Timings vary by hardware and system load.
Run all three libraries on the same machine, back to back, for a fair
comparison. Rerun locally before using results as performance claims.
