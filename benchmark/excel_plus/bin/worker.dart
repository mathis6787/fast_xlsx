import 'dart:convert';
import 'dart:io';

import 'package:excel_plus/excel_plus.dart';

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
    _parity(16, 10);
    late List<int> bytes;
    final result = await PeakMonitor.measure(() async {
      final measured = _parity(rows, columns);
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
  if (mode == 'write_path') {
    final timer = Stopwatch()..start();
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    var checksum = 0;
    for (var row = 0; row < rows; row++) {
      final cells = <CellValue>[];
      for (var column = 0; column < columns; column++) {
        final value = benchmarkValue(row, column);
        checksum = addToChecksum(checksum, row, column, value);
        cells.add(switch (value) {
          int value => IntCellValue(value),
          double value => DoubleCellValue(value),
          String value => TextCellValue(value),
          bool value => BoolCellValue(value),
          _ => throw StateError('Unexpected value'),
        });
      }
      sheet.appendRow(cells);
    }
    final createUs = timer.elapsedMicroseconds;
    final sink = File(output).openWrite();
    excel.encodeToStream(sink.add);
    await sink.close();
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
  if (mode != 'read_path' && !mode.startsWith('read_profile_')) {
    throw ArgumentError.value(mode, 'mode');
  }
  final profile = mode.startsWith('read_profile_')
      ? mode.substring('read_profile_'.length)
      : 'mixed';

  final timer = Stopwatch()..start();
  final inputStream = InputFileStream(input);
  try {
    final excel = Excel.decodeBuffer(inputStream);
    final openUs = timer.elapsedMicroseconds;
    final sheet = excel.tables['Sheet1']!;
    var checksum = 0;
    var seenRows = 0;
    var seenCells = 0;
    for (final row in sheet.rows) {
      if (row.length != columns) {
        throw StateError('Unexpected row width at $seenRows: ${row.length}');
      }
      for (var column = 0; column < columns; column++) {
        final cellValue = row[column]?.value;
        if (profile == 'sparse_mixed' &&
            isSparseBlank(seenRows, column, columns)) {
          if (cellValue != null) {
            throw StateError('Expected blank at $seenRows/$column: $cellValue');
          }
          continue;
        }
        final Object value = switch (cellValue) {
          IntCellValue value => value.value,
          DoubleCellValue value => value.value,
          TextCellValue value => value.value.toString(),
          BoolCellValue value => value.value,
          _ => throw StateError(
            'Unexpected cell at $seenRows/$column: $cellValue',
          ),
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
  } finally {
    await inputStream.close();
  }
}

(Map<String, Object>, List<int>) _parity(int rows, int columns) {
  final timer = Stopwatch()..start();
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
        TextCellValue(parityText(row, column)),
      );
    }
  }
  final createUs = timer.elapsedMicroseconds;
  final bytes = excel.encode()!;
  final encodeUs = timer.elapsedMicroseconds - createUs;
  final decoded = Excel.decodeBytes(bytes);
  final first = decoded['Sheet1'].cell(CellIndex.indexByString('A1')).value;
  timer.stop();
  if (first is! TextCellValue || first.value.toString() != 'R0C0') {
    throw StateError('Parity A1 mismatch: $first');
  }
  return (
    {
      'create_us': createUs,
      'output_us': encodeUs,
      'open_us': timer.elapsedMicroseconds - createUs - encodeUs,
      'total_us': timer.elapsedMicroseconds,
      'rows': rows,
      'cells': rows * columns,
      'first_cell': 'R0C0',
      'file_bytes': bytes.length,
    },
    bytes,
  );
}
