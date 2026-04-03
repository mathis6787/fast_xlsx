import 'dart:io';

import 'package:fast_xlsx/fast_xlsx.dart';

Future<void> main() async {
  final streamWriter = FastXlsxWriter(sheetName: 'StreamSheet');
  streamWriter.addRow([
    const XlsxCell.text('name'),
    const XlsxCell.integer(3),
    const XlsxCell.boolean(true),
  ]);

  final bytes = <int>[];
  await for (final chunk in streamWriter.finish()) {
    bytes.addAll(chunk);
  }

  final streamReader = await FastXlsxReader.open(Stream.value(bytes));
  print('stream sheet: ${streamReader.sheetName}');
  await for (final row in streamReader.rows()) {
    print(row);
  }

  final file = File('${Directory.systemTemp.path}/fast_xlsx_example.xlsx');
  if (await file.exists()) {
    await file.delete();
  }

  final pathWriter = FastXlsxWriter(sheetName: 'PathSheet');
  pathWriter.addRow([
    const XlsxCell.text('orange'),
    const XlsxCell.doubleValue(4.5),
    const XlsxCell.blank(),
  ]);
  await pathWriter.writeToFile(file);

  final pathReader = await FastXlsxReader.openFile(file);
  print('path sheet: ${pathReader.sheetName}');
  await for (final row in pathReader.rows()) {
    print(row);
  }
}
