library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'fast_xlsx_models.dart';
import 'native_api.dart';

final class FastXlsxReader {
  FastXlsxReader._(this._handle, this.sheetName);

  static const int defaultChunkSize = 64 * 1024;

  final ReaderHandle _handle;
  final String sheetName;

  bool _rowsOpened = false;

  static Future<FastXlsxReader> open(Stream<List<int>> source) async {
    final upload = NativeFastXlsx.instance.beginUpload();
    try {
      await for (final chunk in source) {
        upload.writeChunk(Uint8List.fromList(chunk));
      }
      final reader = upload.finish();
      return FastXlsxReader._(reader, reader.sheetName);
    } catch (_) {
      upload.close();
      rethrow;
    }
  }

  static Future<FastXlsxReader> openPath(String path) async {
    final reader = NativeFastXlsx.instance.openReaderPath(path);
    return FastXlsxReader._(reader, reader.sheetName);
  }

  static Future<FastXlsxReader> openFile(File file) {
    return openPath(file.path);
  }

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

  void close() {
    _handle.close();
  }
}

final class FastXlsxWriter {
  FastXlsxWriter({required String sheetName})
    : _handle = NativeFastXlsx.instance.openWriter(sheetName);

  final WriterHandle _handle;
  bool _finished = false;

  void addRow(List<XlsxCell> cells) {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _handle.addRow(cells);
  }

  Stream<List<int>> finish({int chunkSize = FastXlsxReader.defaultChunkSize}) {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _finished = true;
    final output = _handle.finish();
    return _readOutput(output, chunkSize);
  }

  Future<void> writeToPath(String path) async {
    if (_finished) {
      throw StateError('Writer has already been finished.');
    }

    _finished = true;
    _handle.finishToPath(path);
  }

  Future<void> writeToFile(File file) {
    return writeToPath(file.path);
  }

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
