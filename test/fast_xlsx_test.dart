import 'dart:async';
import 'dart:io';

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

    test('supports explicit buffered read mode for streamed input', () async {
      final writer = FastXlsxWriter(sheetName: 'Buffered');
      writer.addRow([
        const XlsxCell.text('left'),
        const XlsxCell.blank(),
        const XlsxCell.text('right'),
      ]);

      final bytes = <int>[];
      await for (final chunk in writer.finish()) {
        bytes.addAll(chunk);
      }

      final reader = await FastXlsxReader.open(
        _chunk(bytes, 4),
        readMode: FastXlsxReadMode.buffered,
      );
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [
            XlsxCell.text('left'),
            XlsxCell.blank(),
            XlsxCell.text('right'),
          ],
        ),
      ]);
    });

    test('writer cannot be finished twice', () async {
      final writer = FastXlsxWriter(sheetName: 'Sheet1');
      writer.addRow([const XlsxCell.text('value')]);
      await writer.finish().drain<void>();

      expect(() => writer.finish(), throwsStateError);
    });

    test('writes directly to a path and reads back from a path', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/inventory.xlsx');

      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([const XlsxCell.text('apple'), const XlsxCell.integer(7)]);
      await writer.writeToPath(output.path);

      final reader = await FastXlsxReader.openPath(output.path);
      expect(reader.sheetName, 'Inventory');
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [XlsxCell.text('apple'), XlsxCell.integer(7)],
        ),
      ]);
    });

    test('supports explicit streaming read mode for path input', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/inventory_streaming.xlsx');

      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([
        const XlsxCell.text('alpha'),
        const XlsxCell.blank(),
        const XlsxCell.integer(8),
      ]);
      await writer.writeToPath(output.path);

      final reader = await FastXlsxReader.openPath(
        output.path,
        readMode: FastXlsxReadMode.streaming,
      );
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [
            XlsxCell.text('alpha'),
            XlsxCell.blank(),
            XlsxCell.integer(8),
          ],
        ),
      ]);
    });

    test('supports File wrappers for path-based read and write', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/inventory_file.xlsx');

      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([
        const XlsxCell.text('pear'),
        const XlsxCell.boolean(true),
      ]);
      await writer.writeToFile(output);

      final reader = await FastXlsxReader.openFile(output);
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [XlsxCell.text('pear'), XlsxCell.boolean(true)],
        ),
      ]);
    });

    test('supports stream write to path read interoperability', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/interop_stream_to_path.xlsx');

      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([
        const XlsxCell.text('banana'),
        const XlsxCell.doubleValue(1.5),
      ]);

      final bytes = <int>[];
      await for (final chunk in writer.finish()) {
        bytes.addAll(chunk);
      }
      await output.writeAsBytes(bytes);

      final reader = await FastXlsxReader.openPath(output.path);
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [XlsxCell.text('banana'), XlsxCell.doubleValue(1.5)],
        ),
      ]);
    });

    test('supports path write to stream read interoperability', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/interop_path_to_stream.xlsx');

      final writer = FastXlsxWriter(sheetName: 'Inventory');
      writer.addRow([const XlsxCell.text('grape'), const XlsxCell.integer(9)]);
      await writer.writeToPath(output.path);

      final reader = await FastXlsxReader.open(output.openRead());
      expect(await reader.rows().toList(), const [
        XlsxRow(
          rowIndex: 0,
          cells: [XlsxCell.text('grape'), XlsxCell.integer(9)],
        ),
      ]);
    });

    test('path export fails if the target already exists', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = File('${tempDir.path}/existing.xlsx');
      await output.writeAsBytes(const [1, 2, 3]);

      final writer = FastXlsxWriter(sheetName: 'Sheet1');
      writer.addRow([const XlsxCell.text('value')]);

      await expectLater(
        writer.writeToPath(output.path),
        throwsA(isA<FastXlsxException>()),
      );
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
