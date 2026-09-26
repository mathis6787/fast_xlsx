import 'dart:io';

import 'package:archive/archive_io.dart';

import '../../common/workload.dart';

const _contentTypes = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''';
const _rootRels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';
const _workbook = '''<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>''';
const _workbookRels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';
const _styles = '''<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="0"/><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';

Future<int> generateFixture(File output, int rows, int columns) async =>
    (await generateProfileFixture(output, rows, columns, 'mixed')).checksum;

Future<({int cells, int checksum})> generateProfileFixture(
  File output,
  int rows,
  int columns,
  String profile,
) async {
  final sheetFile = File('${output.path}.sheet.xml');
  final sharedFile = File('${output.path}.shared.xml');
  final hasSharedStrings = profile.startsWith('shared_');
  var checksum = 0;
  var cells = 0;
  try {
    if (hasSharedStrings) {
      final distinctRows = profile == 'shared_repeated'
          ? rows.clamp(0, 97)
          : rows;
      final shared = sharedFile.openWrite();
      shared.write(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'count="${rows * columns}" uniqueCount="${distinctRows * columns}">',
      );
      for (var row = 0; row < distinctRows; row++) {
        final xml = StringBuffer();
        for (var column = 0; column < columns; column++) {
          xml.write(
            '<si><t>${profileValue(profile, row, column, columns)}</t></si>',
          );
        }
        shared.write(xml);
        if (row % 1000 == 999) await shared.flush();
      }
      shared.write('</sst>');
      await shared.close();
    }
    final sheet = sheetFile.openWrite();
    sheet.write(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
    );
    for (var row = 0; row < rows; row++) {
      final xml = StringBuffer('<row r="${row + 1}">');
      for (var column = 0; column < columns; column++) {
        final value = profileValue(profile, row, column, columns);
        if (value == null) continue;
        cells++;
        checksum = addToChecksum(checksum, row, column, value);
        final reference = '${_columnName(column)}${row + 1}';
        if (hasSharedStrings) {
          final index = profile == 'shared_repeated'
              ? (row % 97) * columns + column
              : row * columns + column;
          xml.write('<c r="$reference" t="s"><v>$index</v></c>');
        } else if (value is String) {
          xml.write(
            '<c r="$reference" t="inlineStr"><is><t>$value</t></is></c>',
          );
        } else if (value is bool) {
          xml.write('<c r="$reference" t="b"><v>${value ? 1 : 0}</v></c>');
        } else {
          xml.write('<c r="$reference"><v>$value</v></c>');
        }
      }
      xml.write('</row>');
      sheet.write(xml);
      if (row % 1000 == 999) await sheet.flush();
    }
    sheet.write('</sheetData></worksheet>');
    await sheet.close();

    final zip = ZipFileEncoder()..create(output.path, level: 6);
    zip.addArchiveFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        hasSharedStrings
            ? _contentTypes.replaceFirst(
                '</Types>',
                '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>',
              )
            : _contentTypes,
      ),
    );
    zip.addArchiveFile(ArchiveFile.string('_rels/.rels', _rootRels));
    zip.addArchiveFile(ArchiveFile.string('xl/workbook.xml', _workbook));
    zip.addArchiveFile(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        hasSharedStrings
            ? _workbookRels.replaceFirst(
                '</Relationships>',
                '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
              )
            : _workbookRels,
      ),
    );
    zip.addArchiveFile(ArchiveFile.string('xl/styles.xml', _styles));
    if (hasSharedStrings) {
      await zip.addFile(sharedFile, 'xl/sharedStrings.xml', 6);
    }
    await zip.addFile(sheetFile, 'xl/worksheets/sheet1.xml', 6);
    await zip.close();
    return (cells: cells, checksum: checksum);
  } finally {
    if (await sheetFile.exists()) {
      await sheetFile.delete();
    }
    if (await sharedFile.exists()) {
      await sharedFile.delete();
    }
  }
}

String _columnName(int zeroBasedIndex) {
  var index = zeroBasedIndex + 1;
  var result = '';
  while (index > 0) {
    final remainder = (index - 1) % 26;
    result = '${String.fromCharCode(65 + remainder)}$result';
    index = (index - 1) ~/ 26;
  }
  return result;
}
