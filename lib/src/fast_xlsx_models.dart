library;

enum FastXlsxReadMode { streaming, buffered }

enum XlsxCellType {
  blank,
  integer,
  doubleValue,
  boolean,
  text,
  dateLikeText,
  error,
}

final class XlsxCell {
  const XlsxCell._(this.type, this.value);

  const XlsxCell.blank() : this._(XlsxCellType.blank, null);

  const XlsxCell.integer(int value) : this._(XlsxCellType.integer, value);

  const XlsxCell.doubleValue(double value)
    : this._(XlsxCellType.doubleValue, value);

  const XlsxCell.boolean(bool value) : this._(XlsxCellType.boolean, value);

  const XlsxCell.text(String value) : this._(XlsxCellType.text, value);

  const XlsxCell.dateLikeText(String value)
    : this._(XlsxCellType.dateLikeText, value);

  const XlsxCell.error(String value) : this._(XlsxCellType.error, value);

  final XlsxCellType type;
  final Object? value;

  int? get asInt => value as int?;
  double? get asDouble => value as double?;
  bool? get asBool => value as bool?;
  String? get asString => value as String?;

  @override
  String toString() => 'XlsxCell(type: $type, value: $value)';

  @override
  bool operator ==(Object other) {
    return other is XlsxCell && other.type == type && other.value == value;
  }

  @override
  int get hashCode => Object.hash(type, value);
}

final class XlsxRow {
  const XlsxRow({required this.rowIndex, required this.cells});

  final int rowIndex;
  final List<XlsxCell> cells;

  @override
  String toString() => 'XlsxRow(rowIndex: $rowIndex, cells: $cells)';

  @override
  bool operator ==(Object other) {
    if (other is! XlsxRow || other.rowIndex != rowIndex) {
      return false;
    }

    if (other.cells.length != cells.length) {
      return false;
    }

    for (var index = 0; index < cells.length; index++) {
      if (other.cells[index] != cells[index]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(rowIndex, Object.hashAll(cells));
}
