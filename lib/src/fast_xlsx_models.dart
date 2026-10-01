library;

/// Controls how the native backend reads worksheet rows after opening a file.
///
/// Both modes expose a one-time row stream. Stream uploads are fully staged on
/// disk first, regardless of this setting.
enum FastXlsxReadMode {
  /// Parses worksheet cells incrementally as rows are requested.
  ///
  /// Avoids buffering all worksheet rows. Workbook metadata and shared strings
  /// can still consume memory; this does not guarantee a fixed memory limit.
  streaming,

  /// Parses the first worksheet and buffers its rows in native memory at open.
  ///
  /// Memory use grows with worksheet contents. This does not enable repeated
  /// traversal or random access through the Dart API.
  buffered,
}

/// Describes the value stored by an [XlsxCell].
enum XlsxCellType {
  /// An empty cell with a null value.
  blank,

  /// An integer value.
  integer,

  /// A floating-point value.
  doubleValue,

  /// A boolean value.
  boolean,

  /// Ordinary text.
  text,

  /// The backend's string representation of a date, time, or duration.
  dateLikeText,

  /// A worksheet error represented as text, rather than a thrown exception.
  error,
}

/// A typed worksheet cell, usable for both reading and writing.
///
/// Date-like values are strings, not Dart `DateTime` objects. Error cells are
/// worksheet values, not [Exception] instances. When writing, both kinds become
/// ordinary text and read back as [XlsxCellType.text].
final class XlsxCell {
  const XlsxCell._(this.type, this.value);

  /// Creates a blank cell.
  const XlsxCell.blank() : this._(XlsxCellType.blank, null);

  /// Creates an integer cell.
  ///
  /// XLSX numeric storage can lose precision for large integers.
  const XlsxCell.integer(int value) : this._(XlsxCellType.integer, value);

  /// Creates a floating-point cell.
  ///
  /// A whole-valued number may read back as [XlsxCellType.integer].
  const XlsxCell.doubleValue(double value)
    : this._(XlsxCellType.doubleValue, value);

  /// Creates a boolean cell.
  const XlsxCell.boolean(bool value) : this._(XlsxCellType.boolean, value);

  /// Creates an ordinary text cell.
  const XlsxCell.text(String value) : this._(XlsxCellType.text, value);

  /// Creates date-like text; export writes [value] as an ordinary string.
  ///
  /// Imported date/time/duration cells use the backend's string representation,
  /// which is not guaranteed to be ISO 8601 and may represent an Excel serial
  /// value. No date parsing, timezone conversion, or date formatting is applied.
  const XlsxCell.dateLikeText(String value)
    : this._(XlsxCellType.dateLikeText, value);

  /// Creates error text; export writes [value] as an ordinary string.
  ///
  /// Importing a worksheet error such as `#DIV/0!` produces this cell type
  /// without throwing. File and parsing failures are reported separately.
  const XlsxCell.error(String value) : this._(XlsxCellType.error, value);

  /// The cell's value category.
  final XlsxCellType type;

  /// The value: null, int, double, bool, or String, according to [type].
  final Object? value;

  /// Casts [value] to int; returns null for blank cells.
  ///
  /// Throws [TypeError] for other value types. Check [type] first.
  int? get asInt => value as int?;

  /// Casts [value] to double; returns null for blank cells.
  ///
  /// Throws [TypeError] for other value types. It does not convert integers.
  double? get asDouble => value as double?;

  /// Casts [value] to bool; returns null for blank cells.
  ///
  /// Throws [TypeError] for other value types.
  bool? get asBool => value as bool?;

  /// Returns text, date-like text, or error text; null for blank cells.
  ///
  /// Throws [TypeError] for numeric and boolean values.
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

/// A worksheet row with its original zero-based index.
final class XlsxRow {
  /// Creates a row with [rowIndex] and [cells].
  const XlsxRow({required this.rowIndex, required this.cells});

  /// Original worksheet row index, starting at zero.
  ///
  /// Blank rows are omitted during import, so indices may have gaps.
  final int rowIndex;

  /// Cell values in order, with trailing blank cells removed during import.
  ///
  /// The constructor retains this list without copying it. Treat it as
  /// immutable, especially when using this row as a map key or set member.
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
