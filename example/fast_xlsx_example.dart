import 'package:fast_xlsx/fast_xlsx.dart';

Future<void> main() async {
  final writer = FastXlsxWriter(sheetName: 'Sheet1');
  writer.addRow([
    const XlsxCell.text('name'),
    const XlsxCell.integer(3),
    const XlsxCell.boolean(true),
  ]);
  writer.addRow([
    const XlsxCell.text('orange'),
    const XlsxCell.doubleValue(4.5),
    const XlsxCell.blank(),
  ]);

  final bytes = <int>[];
  await for (final chunk in writer.finish()) {
    bytes.addAll(chunk);
  }

  final reader = await FastXlsxReader.open(Stream.value(bytes));
  print('sheet: ${reader.sheetName}');
  await for (final row in reader.rows()) {
    print(row);
  }
}
