library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'fast_xlsx_bindings.g.dart' as native;
import 'fast_xlsx_models.dart';

typedef _UploadCloseNative =
    ffi.Void Function(ffi.Pointer<native.FxUploadHandle>);
typedef _ReaderCloseNative =
    ffi.Void Function(ffi.Pointer<native.FxReaderHandle>);
typedef _WriterCloseNative =
    ffi.Void Function(ffi.Pointer<native.FxWriterHandle>);
typedef _OutputCloseNative =
    ffi.Void Function(ffi.Pointer<native.FxOutputHandle>);

final class NativeFastXlsx {
  NativeFastXlsx._();

  static final NativeFastXlsx instance = NativeFastXlsx._();
  static final ffi.DynamicLibrary _processLibrary =
      ffi.DynamicLibrary.process();

  static final ffi.NativeFinalizer _uploadFinalizer = ffi.NativeFinalizer(
    _processLibrary
        .lookup<ffi.NativeFunction<_UploadCloseNative>>('fx_upload_close')
        .cast(),
  );
  static final ffi.NativeFinalizer _readerFinalizer = ffi.NativeFinalizer(
    _processLibrary
        .lookup<ffi.NativeFunction<_ReaderCloseNative>>('fx_reader_close')
        .cast(),
  );
  static final ffi.NativeFinalizer _writerFinalizer = ffi.NativeFinalizer(
    _processLibrary
        .lookup<ffi.NativeFunction<_WriterCloseNative>>('fx_writer_close')
        .cast(),
  );
  static final ffi.NativeFinalizer _outputFinalizer = ffi.NativeFinalizer(
    _processLibrary
        .lookup<ffi.NativeFunction<_OutputCloseNative>>('fx_output_close')
        .cast(),
  );

  UploadHandle beginUpload() {
    return using((arena) {
      final outHandle = arena<ffi.Pointer<native.FxUploadHandle>>();
      final status = native.fx_begin_upload(outHandle);
      _throwOnStatus(status, ffi.nullptr);
      return UploadHandle._(outHandle.value);
    });
  }

  ReaderHandle openReaderPath(
    String path, {
    FastXlsxReadMode readMode = FastXlsxReadMode.streaming,
  }) {
    return using((arena) {
      final outHandle = arena<ffi.Pointer<native.FxReaderHandle>>();
      final pathPointer = path.toNativeUtf8(allocator: arena);
      final status = native.fx_reader_open_path_with_mode(
        pathPointer.cast(),
        readMode.toNative().value,
        outHandle,
      );
      _throwOnStatus(status, ffi.nullptr);
      return ReaderHandle._(outHandle.value);
    });
  }

  WriterHandle openWriter(String sheetName) {
    return using((arena) {
      final outHandle = arena<ffi.Pointer<native.FxWriterHandle>>();
      final sheetNamePointer = sheetName.toNativeUtf8(allocator: arena);
      final status = native.fx_writer_open(sheetNamePointer.cast(), outHandle);
      _throwOnStatus(status, ffi.nullptr);
      return WriterHandle._(outHandle.value);
    });
  }

  String errorMessage(ffi.Pointer<ffi.Void> handle) {
    final pointer = native.fx_error_message(handle);
    if (pointer == ffi.nullptr) {
      return 'Unknown native error';
    }

    return pointer.cast<Utf8>().toDartString();
  }

  void _throwOnStatus(native.FxStatus status, ffi.Pointer<ffi.Void> handle) {
    if (status == native.FxStatus.FX_STATUS_OK ||
        status == native.FxStatus.FX_STATUS_DONE) {
      return;
    }

    throw FastXlsxException(errorMessage(handle));
  }
}

extension on FastXlsxReadMode {
  native.FxReaderMode toNative() => switch (this) {
    FastXlsxReadMode.streaming => native.FxReaderMode.FX_READER_MODE_STREAMING,
    FastXlsxReadMode.buffered => native.FxReaderMode.FX_READER_MODE_BUFFERED,
  };
}

/// A native XLSX validation, parsing, or I/O failure.
///
/// A worksheet error cell is represented by [XlsxCell.error] instead of throwing
/// this exception. Invalid object lifecycle operations throw [StateError].
final class FastXlsxException implements Exception {
  /// Creates an exception with the backend's error [message].
  FastXlsxException(this.message);

  /// Description supplied by the native backend.
  final String message;

  @override
  String toString() => 'FastXlsxException: $message';
}

final class UploadHandle implements ffi.Finalizable {
  UploadHandle._(this._pointer) {
    NativeFastXlsx._uploadFinalizer.attach(this, _pointer.cast(), detach: this);
  }

  ffi.Pointer<native.FxUploadHandle> _pointer;

  bool get _isClosed => _pointer == ffi.nullptr;

  void writeChunk(Uint8List chunk) {
    if (_isClosed) {
      throw StateError('Upload handle is closed.');
    }

    using((arena) {
      final buffer = arena<ffi.Uint8>(chunk.length);
      buffer.asTypedList(chunk.length).setAll(0, chunk);
      final status = native.fx_upload_write_chunk(
        _pointer,
        buffer,
        chunk.length,
      );
      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
    });
  }

  ReaderHandle finish({
    FastXlsxReadMode readMode = FastXlsxReadMode.streaming,
  }) {
    if (_isClosed) {
      throw StateError('Upload handle is closed.');
    }

    return using((arena) {
      final outReader = arena<ffi.Pointer<native.FxReaderHandle>>();
      final status = native.fx_upload_finish_open_reader_with_mode(
        _pointer,
        readMode.toNative().value,
        outReader,
      );
      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
      final pointer = outReader.value;
      NativeFastXlsx._uploadFinalizer.detach(this);
      _pointer = ffi.nullptr;
      return ReaderHandle._(pointer);
    });
  }

  void close() {
    if (_isClosed) {
      return;
    }

    NativeFastXlsx._uploadFinalizer.detach(this);
    native.fx_upload_close(_pointer);
    _pointer = ffi.nullptr;
  }
}

final class ReaderHandle implements ffi.Finalizable {
  ReaderHandle._(this._pointer) {
    NativeFastXlsx._readerFinalizer.attach(this, _pointer.cast(), detach: this);
  }

  ffi.Pointer<native.FxReaderHandle> _pointer;

  bool get _isClosed => _pointer == ffi.nullptr;

  String get sheetName {
    if (_isClosed) {
      throw StateError('Reader handle is closed.');
    }

    return using((arena) {
      final outName = arena<ffi.Pointer<ffi.Char>>();
      final status = native.fx_reader_sheet_name(_pointer, outName);
      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
      return outName.value.cast<Utf8>().toDartString();
    });
  }

  XlsxRow? nextRow() {
    if (_isClosed) {
      throw StateError('Reader handle is closed.');
    }

    return using((arena) {
      final outRow = arena<ffi.Pointer<native.FxRowHandle>>();
      final status = native.fx_reader_next_row(_pointer, outRow);
      if (status == native.FxStatus.FX_STATUS_DONE) {
        return null;
      }

      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
      final rowHandle = RowHandle._(outRow.value);
      try {
        return rowHandle.toRow();
      } finally {
        rowHandle.close();
      }
    });
  }

  void close() {
    if (_isClosed) {
      return;
    }

    NativeFastXlsx._readerFinalizer.detach(this);
    native.fx_reader_close(_pointer);
    _pointer = ffi.nullptr;
  }
}

final class RowHandle {
  RowHandle._(this._pointer);

  ffi.Pointer<native.FxRowHandle> _pointer;

  XlsxRow toRow() {
    final length = native.fx_row_len(_pointer);
    final rowIndex = native.fx_row_index(_pointer);
    final cells = <XlsxCell>[];

    for (var index = 0; index < length; index++) {
      final type = native.fx_row_cell_type(_pointer, index);
      cells.add(switch (type) {
        native.FxCellType.FX_CELL_BLANK => const XlsxCell.blank(),
        native.FxCellType.FX_CELL_INT => XlsxCell.integer(
          native.fx_row_cell_int(_pointer, index),
        ),
        native.FxCellType.FX_CELL_DOUBLE => XlsxCell.doubleValue(
          native.fx_row_cell_double(_pointer, index),
        ),
        native.FxCellType.FX_CELL_BOOL => XlsxCell.boolean(
          native.fx_row_cell_bool(_pointer, index),
        ),
        native.FxCellType.FX_CELL_TEXT => XlsxCell.text(_readString(index)),
        native.FxCellType.FX_CELL_DATE_TEXT => XlsxCell.dateLikeText(
          _readString(index),
        ),
        native.FxCellType.FX_CELL_ERROR => XlsxCell.error(_readString(index)),
      });
    }

    return XlsxRow(rowIndex: rowIndex, cells: cells);
  }

  String _readString(int index) {
    final pointer = native.fx_row_cell_string(_pointer, index);
    return pointer.cast<Utf8>().toDartString();
  }

  void close() {
    if (_pointer == ffi.nullptr) {
      return;
    }

    native.fx_row_release(_pointer);
    _pointer = ffi.nullptr;
  }
}

final class WriterHandle implements ffi.Finalizable {
  WriterHandle._(this._pointer) {
    NativeFastXlsx._writerFinalizer.attach(this, _pointer.cast(), detach: this);
  }

  ffi.Pointer<native.FxWriterHandle> _pointer;

  bool get _isClosed => _pointer == ffi.nullptr;

  void addRow(List<XlsxCell> cells) {
    if (_isClosed) {
      throw StateError('Writer handle is closed.');
    }

    using((arena) {
      final cellBuffer = arena<native.FxCellValue>(cells.length);
      for (var index = 0; index < cells.length; index++) {
        final cell = cells[index];
        final nativeCell = cellBuffer[index];
        nativeCell.int_value = 0;
        nativeCell.double_value = 0;
        nativeCell.bool_value = false;
        nativeCell.string_value = ffi.nullptr;
        switch (cell.type) {
          case XlsxCellType.blank:
            nativeCell.cell_type = native.FxCellType.FX_CELL_BLANK.value;
            break;
          case XlsxCellType.integer:
            nativeCell.cell_type = native.FxCellType.FX_CELL_INT.value;
            nativeCell.int_value = cell.asInt!;
            break;
          case XlsxCellType.doubleValue:
            nativeCell.cell_type = native.FxCellType.FX_CELL_DOUBLE.value;
            nativeCell.double_value = cell.asDouble!;
            break;
          case XlsxCellType.boolean:
            nativeCell.cell_type = native.FxCellType.FX_CELL_BOOL.value;
            nativeCell.bool_value = cell.asBool!;
            break;
          case XlsxCellType.text:
            nativeCell.cell_type = native.FxCellType.FX_CELL_TEXT.value;
            nativeCell.string_value = cell.asString!
                .toNativeUtf8(allocator: arena)
                .cast();
            break;
          case XlsxCellType.dateLikeText:
            nativeCell.cell_type = native.FxCellType.FX_CELL_DATE_TEXT.value;
            nativeCell.string_value = cell.asString!
                .toNativeUtf8(allocator: arena)
                .cast();
            break;
          case XlsxCellType.error:
            nativeCell.cell_type = native.FxCellType.FX_CELL_ERROR.value;
            nativeCell.string_value = cell.asString!
                .toNativeUtf8(allocator: arena)
                .cast();
            break;
        }
      }

      final status = native.fx_writer_add_row(
        _pointer,
        cellBuffer,
        cells.length,
      );
      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
    });
  }

  OutputHandle finish() {
    if (_isClosed) {
      throw StateError('Writer handle is closed.');
    }

    return using((arena) {
      final outOutput = arena<ffi.Pointer<native.FxOutputHandle>>();
      final status = native.fx_writer_finish_open_output(_pointer, outOutput);
      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
      final output = OutputHandle._(outOutput.value);
      NativeFastXlsx._writerFinalizer.detach(this);
      _pointer = ffi.nullptr;
      return output;
    });
  }

  void finishToPath(String path) {
    if (_isClosed) {
      throw StateError('Writer handle is closed.');
    }

    using((arena) {
      final pathPointer = path.toNativeUtf8(allocator: arena);
      final pointer = _pointer;
      NativeFastXlsx._writerFinalizer.detach(this);
      _pointer = ffi.nullptr;
      final status = native.fx_writer_finish_to_path(
        pointer,
        pathPointer.cast(),
      );
      NativeFastXlsx.instance._throwOnStatus(status, ffi.nullptr);
    });
  }

  void close() {
    if (_isClosed) {
      return;
    }

    NativeFastXlsx._writerFinalizer.detach(this);
    native.fx_writer_close(_pointer);
    _pointer = ffi.nullptr;
  }
}

final class OutputHandle implements ffi.Finalizable {
  OutputHandle._(this._pointer) {
    NativeFastXlsx._outputFinalizer.attach(this, _pointer.cast(), detach: this);
  }

  ffi.Pointer<native.FxOutputHandle> _pointer;

  bool get _isClosed => _pointer == ffi.nullptr;

  Uint8List? readChunk(int chunkSize) {
    if (_isClosed) {
      throw StateError('Output handle is closed.');
    }

    return using((arena) {
      final buffer = arena<ffi.Uint8>(chunkSize);
      final outLength = arena<ffi.UintPtr>();
      final status = native.fx_output_read_chunk(
        _pointer,
        buffer,
        chunkSize,
        outLength,
      );
      if (status == native.FxStatus.FX_STATUS_DONE) {
        return null;
      }

      NativeFastXlsx.instance._throwOnStatus(status, _pointer.cast());
      return Uint8List.fromList(buffer.asTypedList(outLength.value));
    });
  }

  void close() {
    if (_isClosed) {
      return;
    }

    NativeFastXlsx._outputFinalizer.detach(this);
    native.fx_output_close(_pointer);
    _pointer = ffi.nullptr;
  }
}
