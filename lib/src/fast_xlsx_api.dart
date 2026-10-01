library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'fast_xlsx_models.dart';
import 'native_api.dart';

/// Reads the first worksheet of an XLSX workbook once.
///
/// Use [open] for byte streams or [openFile]/[openPath] for existing files.
/// [rows] closes native resources on completion, error, or cancellation. Call
/// [close] explicitly if you open a reader without consuming its rows.
///
/// Native parsing runs synchronously on the calling isolate, even though the
/// API exposes futures and streams. Use a worker isolate for large workloads
/// when the calling isolate must remain responsive.
final class FastXlsxReader {
  FastXlsxReader._(this._handle, this.sheetName);

  /// Default output chunk size, in bytes, for [FastXlsxWriter.finish].
  static const int defaultChunkSize = 64 * 1024;

  final ReaderHandle _handle;

  /// Name of the workbook's first worksheet.
  final String sheetName;

  bool _rowsOpened = false;

  /// Consumes all of [source] into a temporary file, then opens a reader.
  ///
  /// No rows are available until the source stream completes. [readMode]
  /// controls worksheet parsing after upload; it does not bypass staging.
  /// The temporary file is retained until the reader closes. Upload failures
  /// release upload resources and propagate the error.
  static Future<FastXlsxReader> open(
    Stream<List<int>> source, {
    FastXlsxReadMode readMode = FastXlsxReadMode.streaming,
  }) async {
    final upload = NativeFastXlsx.instance.beginUpload();
    try {
      await for (final chunk in source) {
        upload.writeChunk(Uint8List.fromList(chunk));
      }
      final reader = upload.finish(readMode: readMode);
      return FastXlsxReader._(reader, reader.sheetName);
    } catch (_) {
      upload.close();
      rethrow;
    }
  }

  /// Opens an existing XLSX file at [path] without copying it to temporary disk.
  ///
  /// The reader holds the file open until it closes. [readMode] controls whether
  /// worksheet rows are parsed incrementally or buffered in native memory.
  static Future<FastXlsxReader> openPath(
    String path, {
    FastXlsxReadMode readMode = FastXlsxReadMode.streaming,
  }) async {
    final reader = NativeFastXlsx.instance.openReaderPath(
      path,
      readMode: readMode,
    );
    return FastXlsxReader._(reader, reader.sheetName);
  }

  /// Opens [file] with the same behavior as [openPath].
  static Future<FastXlsxReader> openFile(
    File file, {
    FastXlsxReadMode readMode = FastXlsxReadMode.streaming,
  }) {
    return openPath(file.path, readMode: readMode);
  }

  /// Returns a single-subscription stream of worksheet rows.
  ///
  /// A reader permits only one row traversal, in either read mode. Attempting
  /// to consume another stream from this reader throws [StateError]. Reopen
  /// the workbook for another traversal.
  ///
  /// Completion, errors, and cancellation close the reader. For manual
  /// subscriptions, await cancellation to complete cleanup. Entirely blank
  /// rows are omitted and trailing blank cells are removed.
  Stream<XlsxRow> rows() async* {
    if (_rowsOpened) {
      throw StateError('Rows can only be consumed once.');
    }

    _rowsOpened = true;
    try {
      while (true) {
        final row = _handle.nextRow();
        if (row == null) {
          break;
        }
        yield row;
      }
    } finally {
      close();
    }
  }

  /// Releases native resources and any staged input file.
  ///
  /// Repeated calls are safe. Further reading fails with [StateError]. Use
  /// `try/finally` when a reader might be opened but never consumed.
  void close() {
    _handle.close();
  }
}

/// Writes one XLSX worksheet using temporary disk for worksheet data.
///
/// Add rows in order, then finalize once using [finish], [writeToPath], or
/// [writeToFile]. Call [close] to discard an unfinished writer. Native writing
/// and finalization run synchronously on the calling isolate.
final class FastXlsxWriter {
  /// Creates a worksheet named [sheetName] and allocates native resources.
  ///
  /// An invalid worksheet name throws [FastXlsxException].
  FastXlsxWriter({required String sheetName})
    : _handle = NativeFastXlsx.instance.openWriter(sheetName);

  final WriterHandle _handle;
  bool _finished = false;

  /// Appends [cells] as the next row, starting with row zero.
  ///
  /// Date-like and error values are written as ordinary text. Calls after
  /// finalization or [close] throw [StateError]. Native validation or write
  /// failures throw [FastXlsxException].
  void addRow(List<XlsxCell> cells) {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _handle.addRow(cells);
  }

  /// Finalizes the workbook to a temporary XLSX file and streams its bytes.
  ///
  /// Finalization happens before this method returns. The file is then read in
  /// chunks of at most [chunkSize] bytes, which must be positive. This is not
  /// incremental XLSX output while [addRow] is still accepting rows.
  ///
  /// Consume the returned single-subscription stream once. It owns the output
  /// resources and releases them on completion, error, or cancellation. Do not
  /// create a stream and leave it unconsumed: [close] cannot dispose of that
  /// output after finalization. Await cancellation for manual subscriptions.
  ///
  /// Calling another finalization method or [addRow] afterward throws
  /// [StateError], including when finalization failed.
  Stream<List<int>> finish({int chunkSize = FastXlsxReader.defaultChunkSize}) {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _finished = true;
    final output = _handle.finish();
    return _readOutput(output, chunkSize);
  }

  /// Finalizes the workbook directly to a new file at [path].
  ///
  /// The parent directory must exist and the target must not already exist.
  /// Violations and native save failures throw [FastXlsxException]. Worksheet
  /// data still uses temporary disk; the completed XLSX is saved to [path].
  /// This consumes the writer, including on failure. Further writes or
  /// finalization attempts throw [StateError].
  Future<void> writeToPath(String path) async {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _finished = true;
    _handle.finishToPath(path);
  }

  /// Saves to [file] with the same behavior as [writeToPath].
  Future<void> writeToFile(File file) {
    return writeToPath(file.path);
  }

  /// Discards an unfinished workbook and releases its native resources.
  ///
  /// Repeated calls are safe. After finalization has been attempted this is a
  /// no-op; in particular, it does not close the stream returned by [finish].
  void close() {
    if (_finished) {
      return;
    }

    _finished = true;
    _handle.close();
  }

  Stream<List<int>> _readOutput(OutputHandle output, int chunkSize) async* {
    try {
      while (true) {
        final chunk = output.readChunk(chunkSize);
        if (chunk == null) {
          break;
        }
        yield chunk;
      }
    } finally {
      output.close();
    }
  }
}
