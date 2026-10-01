## 0.1.0

- Initial release of the Rust-backed XLSX reader and writer for Dart backends.
- Import XLSX files from byte streams or filesystem paths, with streaming and
  buffered read modes.
- Export single-worksheet XLSX files to byte streams or filesystem paths.
- Support typed cell values and automatic downloads of prebuilt native libraries
  for Linux, macOS, and Windows on arm64 and x64.
- Read the first worksheet only; styling, formulas, merged cells, and CSV are
  outside this release's scope.
