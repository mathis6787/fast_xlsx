import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_xlsx/fast_xlsx.dart';

import '../../common/peak_monitor.dart';
import '../../common/workload.dart';

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    throw ArgumentError(
      'Usage: worker.dart MODE ROWS COLUMNS INPUT OUTPUT WARMUP_INPUT',
    );
  }
  final mode = args[0];
  final rows = int.parse(args[1]);
  final columns = int.parse(args[2]);
  final input = args[3];
  final output = args[4];
  final warmupInput = args[5];

  if (mode == 'parity') {
    await _parity(16, 10);
    late List<int> bytes;
    final result = await PeakMonitor.measure(() async {
      final measured = await _parity(rows, columns);
      bytes = measured.$2;
      return measured.$1;
    });
    await File(output).writeAsBytes(bytes, flush: true);
    stdout.writeln(jsonEncode(result));
    return;
  }

  final warmupOutput = '$output.warmup.xlsx';
  await _run(mode, 16, 10, warmupInput, warmupOutput);
  if (File(warmupOutput).existsSync()) {
    File(warmupOutput).deleteSync();
  }

  final result = await PeakMonitor.measure(
    () => _run(mode, rows, columns, input, output),
  );
  stdout.writeln(jsonEncode(result));
}

Future<Map<String, Object>> _run(
  String mode,
  int rows,
  int columns,
  String input,
  String output,
) async {
  if (mode.startsWith('write_')) {
    final timer = Stopwatch()..start();
    final writer = FastXlsxWriter(sheetName: 'Sheet1');
    var checksum = 0;
    for (var row = 0; row < rows; row++) {
      final cells = <XlsxCell>[];
      for (var column = 0; column < columns; column++) {
        final value = benchmarkValue(row, column);
        checksum = addToChecksum(checksum, row, column, value);
        cells.add(switch (value) {
          int value => XlsxCell.integer(value),
          double value => XlsxCell.doubleValue(value),
          String value => XlsxCell.text(value),
          bool value => XlsxCell.boolean(value),
          _ => throw StateError('Unexpected value'),
        });
      }
      writer.addRow(cells);
    }
    final createUs = timer.elapsedMicroseconds;
    if (mode == 'write_path') {
      await writer.writeToPath(output);
    } else if (mode == 'write_stream') {
      final sink = File(output).openWrite();
      await for (final chunk in writer.finish()) {
        sink.add(chunk);
      }
      await sink.close();
    } else {
      throw ArgumentError.value(mode, 'mode');
    }
    timer.stop();
    return {
      'create_us': createUs,
      'output_us': timer.elapsedMicroseconds - createUs,
      'total_us': timer.elapsedMicroseconds,
      'rows': rows,
      'cells': rows * columns,
      'checksum': checksum,
      'file_bytes': File(output).lengthSync(),
    };
  }

  final timer = Stopwatch()..start();
  final FastXlsxReader reader;
  final profile = mode.startsWith('read_profile_')
      ? mode.substring('read_profile_'.length)
      : 'mixed';
  if (mode == 'read_path' || mode.startsWith('read_profile_')) {
    reader = await FastXlsxReader.openPath(input);
  } else if (mode == 'read_buffered') {
    reader = await FastXlsxReader.openPath(
      input,
      readMode: FastXlsxReadMode.buffered,
    );
  } else if (mode == 'read_stream') {
    reader = await FastXlsxReader.open(File(input).openRead());
  } else {
    throw ArgumentError.value(mode, 'mode');
  }
  final openUs = timer.elapsedMicroseconds;
  var checksum = 0;
  var seenRows = 0;
  var seenCells = 0;
  await for (final row in reader.rows()) {
    if (row.rowIndex != seenRows || row.cells.length != columns) {
      throw StateError('Unexpected row shape at $seenRows');
    }
    for (var column = 0; column < columns; column++) {
      final cell = row.cells[column];
      if (profile == 'sparse_mixed' &&
          isSparseBlank(seenRows, column, columns)) {
        if (cell.type != XlsxCellType.blank) {
          throw StateError('Expected blank at $seenRows/$column: $cell');
        }
        continue;
      }
      final Object value = switch (cell.type) {
        XlsxCellType.integer => cell.asInt!,
        XlsxCellType.doubleValue => cell.asDouble!,
        XlsxCellType.text => cell.asString!,
        XlsxCellType.boolean => cell.asBool!,
        _ => throw StateError('Unexpected cell at $seenRows/$column: $cell'),
      };
      checksum = addToChecksum(checksum, seenRows, column, value);
      seenCells++;
    }
    seenRows++;
  }
  timer.stop();
  if (seenRows != rows) {
    throw StateError('Expected $rows rows, found $seenRows');
  }
  return {
    'open_us': openUs,
    'iterate_us': timer.elapsedMicroseconds - openUs,
    'total_us': timer.elapsedMicroseconds,
    'rows': seenRows,
    'cells': seenCells,
    'checksum': checksum,
    'file_bytes': File(input).lengthSync(),
  };
}

Future<(Map<String, Object>, List<int>)> _parity(int rows, int columns) async {
  final timer = Stopwatch()..start();
  final writer = FastXlsxWriter(sheetName: 'Sheet1');
  for (var row = 0; row < rows; row++) {
    writer.addRow([
      for (var column = 0; column < columns; column++)
        XlsxCell.text(parityText(row, column)),
    ]);
  }
  final createUs = timer.elapsedMicroseconds;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in writer.finish()) {
    builder.add(chunk);
  }
  final bytes = builder.takeBytes();
  final encodeUs = timer.elapsedMicroseconds - createUs;
  final reader = await FastXlsxReader.open(Stream.value(bytes));
  final firstRow = await reader.rows().first;
  final firstCell = firstRow.cells.first.asString;
  timer.stop();
  if (firstRow.rowIndex != 0 || firstCell != 'R0C0') {
    throw StateError('Parity A1 mismatch: $firstCell');
  }
  return (
    {
      'create_us': createUs,
      'output_us': encodeUs,
      'open_us': timer.elapsedMicroseconds - createUs - encodeUs,
      'total_us': timer.elapsedMicroseconds,
      'rows': rows,
      'cells': rows * columns,
      'first_cell': firstCell!,
      'file_bytes': bytes.length,
    },
    bytes,
  );
}
