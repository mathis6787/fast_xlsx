const int checksumModulus = 1000000007;

const representativeProfiles = [
  'inline_repeated',
  'shared_repeated',
  'inline_unique',
  'shared_unique',
  'sparse_mixed',
];

String parityText(int row, int column) => 'R${row}C$column';

bool isSparseBlank(int row, int column, int columns) =>
    column != columns - 1 && (row * columns + column) % 5 == 0;

Object? profileValue(String profile, int row, int column, int columns) {
  switch (profile) {
    case 'mixed':
      return benchmarkValue(row, column);
    case 'inline_repeated':
    case 'shared_repeated':
      return 'item_${row % 97}_$column';
    case 'inline_unique':
    case 'shared_unique':
      return parityText(row, column);
    case 'sparse_mixed':
      if (isSparseBlank(row, column, columns)) {
        return null;
      }
      return benchmarkValue(row, column);
    default:
      throw ArgumentError.value(profile, 'profile');
  }
}

({int cells, int checksum}) expectedProfile(
  String profile,
  int rows,
  int columns,
) {
  var cells = 0;
  var checksum = 0;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final value = profileValue(profile, row, column, columns);
      if (value == null) continue;
      cells++;
      checksum = addToChecksum(checksum, row, column, value);
    }
  }
  return (cells: cells, checksum: checksum);
}

Object benchmarkValue(int row, int column) {
  switch (column % 4) {
    case 0:
      return row * 10 + column;
    case 1:
      return (row % 1000) + column + 0.5;
    case 2:
      return 'item_${row % 97}_$column';
    default:
      return (row + column).isEven;
  }
}

int addToChecksum(int checksum, int row, int column, Object value) {
  final int code;
  if (value is int) {
    code = 1000000 + value;
  } else if (value is double) {
    code = 2000000 + (value * 2).toInt();
  } else if (value is String) {
    code = 3000000 + value.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  } else if (value is bool) {
    code = 4000000 + (value ? 1 : 0);
  } else {
    throw StateError('Unexpected cell value: $value');
  }
  return (checksum * 131 + (row + 1) * 31 + (column + 1) * 17 + code) %
      checksumModulus;
}

int expectedChecksum(int rows, int columns) {
  var checksum = 0;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      checksum = addToChecksum(
        checksum,
        row,
        column,
        benchmarkValue(row, column),
      );
    }
  }
  return checksum;
}
