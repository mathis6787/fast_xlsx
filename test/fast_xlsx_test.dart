import 'dart:async';

import 'package:fast_xlsx/fast_xlsx.dart';
import 'package:test/test.dart';

void main() {
  group('fast_xlsx', () {
    test('writes and reads typed rows through chunked streams', () async {
      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([
        const XlsxCell.text('name'),
        const XlsxCell.integer(3),
        const XlsxCell.boolean(true),
        const XlsxCell.blank(),
        const XlsxCell.dateLikeText('2026-04-03T12:00:00Z'),
      ]);
      writer.addRow([
        const XlsxCell.text('orange'),
        const XlsxCell.doubleValue(4.5),
        const XlsxCell.boolean(false),
        const XlsxCell.text('kept'),
      ]);

      final bytes = <int>[];
      await for (final chunk in writer.finish(chunkSize: 7)) {
        bytes.addAll(chunk);
      }

      final reader = await FastXlsxReader.open(_chunk(bytes, 5));
      expect(reader.sheetName, 'Inventory');
      final rows = await reader.rows().toList();

      expect(rows, [
        const XlsxRow(
          rowIndex: 0,
          cells: [
            XlsxCell.text('name'),
            XlsxCell.integer(3),
            XlsxCell.boolean(true),
            XlsxCell.blank(),
            XlsxCell.text('2026-04-03T12:00:00Z'),
          ],
        ),
        const XlsxRow(
          rowIndex: 1,
          cells: [
            XlsxCell.text('orange'),
            XlsxCell.doubleValue(4.5),
            XlsxCell.boolean(false),
            XlsxCell.text('kept'),
          ],
        ),
      ]);
    });

    test('rejects malformed xlsx input', () async {
      expect(
        () => FastXlsxReader.open(Stream.value(<int>[1, 2, 3, 4])),
        throwsA(isA<FastXlsxException>()),
      );
    });

    test('writer cannot be finished twice', () async {
      final writer = FastXlsxWriter(sheetName: 'Sheet1');
      writer.addRow([const XlsxCell.text('value')]);
      await writer.finish().drain<void>();

      expect(() => writer.finish(), throwsStateError);
    });
  });
}

Stream<List<int>> _chunk(List<int> bytes, int chunkSize) async* {
  for (var index = 0; index < bytes.length; index += chunkSize) {
    final end = (index + chunkSize < bytes.length)
        ? index + chunkSize
        : bytes.length;
    yield bytes.sublist(index, end);
  }
}
