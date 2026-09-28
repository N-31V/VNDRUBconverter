/// Fits each column to its widest displayed cell, including missing values.
String compactTableText(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final widths = List<int>.filled(rows.first.length, 0);
  for (final row in rows) {
    for (var column = 0; column < widths.length; column++) {
      if (row[column].length > widths[column]) {
        widths[column] = row[column].length;
      }
    }
  }

  String line(List<String> row) => [
    for (var column = 0; column < widths.length; column++)
      column == 0
          ? row[column].padRight(widths[column])
          : row[column].padLeft(widths[column]),
  ].join('| ');

  return [
    line(rows.first),
    widths.map((width) => '-' * width).join('|-'),
    ...rows.skip(1).map(line),
  ].join('\n');
}
