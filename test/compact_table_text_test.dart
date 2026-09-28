import 'package:currency_tracker/widgets/compact_table_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing values and signed losses keep every separator aligned', () {
    final result = compactTableText([
      ['', 'ЦБ РФ', 'Bybit', 'T-QR', 'T-tr'],
      ['VND/RUB', '36.00', '—', '37.04', '38.46'],
      ['USD/RUB', '90.00', '90.45', '—', '—'],
      ['USD/VND', '25000', '25000', '—', '—'],
      ['к ЦБ %', '0.00', '—', '-12.34', '+123.45'],
    ]);
    final lines = result.split('\n');
    List<int> separators(String line) => [
      for (var i = 0; i < line.length; i++)
        if (line[i] == '|') i,
    ];
    for (final line in lines) {
      expect(separators(line), separators(lines.first));
      expect(line.length, lines.first.length);
    }
    expect(lines.first.length, 38);
    expect(lines[2].split('|')[2], '     —');
    expect(lines.last, contains('-12.34| +123.45'));
  });

  test('all missing values use only the widths required by the headings', () {
    final result = compactTableText([
      ['', 'ЦБ РФ', 'Bybit', 'T-QR', 'T-tr'],
      ['VND/RUB', '—', '—', '—', '—'],
      ['к ЦБ %', '—', '—', '—', '—'],
    ]);
    expect(result.split('\n').every((line) => line.length == 33), isTrue);
    expect(result.split('\n').last, 'к ЦБ % |     —|     —|    —|    —');
  });
}
