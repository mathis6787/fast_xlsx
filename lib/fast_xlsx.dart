/// XLSX import and export for desktop and server Dart through Rust FFI.
///
/// Supports Linux, macOS, and Windows on arm64 and x64. Builds that fetch native
/// assets require access to GitHub Releases; XLSX operations use local resources.
/// Readers process the first worksheet and writers produce one worksheet.
///
/// Stream input is staged on temporary disk before reading. Writers also use
/// temporary disk, including when returning a byte stream. See [FastXlsxReader],
/// [FastXlsxWriter], and [FastXlsxReadMode] for resource ownership and read modes.
library;

export 'src/fast_xlsx_api.dart';
export 'src/fast_xlsx_models.dart';
export 'src/native_api.dart' show FastXlsxException;
