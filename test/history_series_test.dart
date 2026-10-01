import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/services/history_series.dart';
import 'package:flutter_test/flutter_test.dart';

Rate observation(DateTime time, double value, {int? id}) => Rate(
  id: id,
  base: 'USD',
  quote: 'RUB',
  value: value,
  source: 'test',
  timestamp: time,
);

void main() {
  final start = DateTime(2026, 9, 21);
  final end = DateTime(2026, 9, 28);

  test('an old rate spans the whole window without changing its timestamp', () {
    final old = observation(DateTime(2026, 8, 1), 250);
    final points = buildRateHistory(
      rates: [old],
      from: start,
      to: end,
      convert: (value) => value,
    );
    expect(points.map((point) => point.timestamp), [start, end]);
    expect(points.map((point) => point.value), [250, 250]);
    expect(old.timestamp, DateTime(2026, 8, 1));
    final range = HistoryValueRange.fromValues(
      points.map((point) => point.value),
    )!;
    expect(range.min, lessThan(250));
    expect(range.max, greaterThan(250));
  });

  test(
    'a change inside the window preserves the old value until the change',
    () {
      final changedAt = start.add(const Duration(days: 2, hours: 3));
      final points = buildRateHistory(
        rates: [
          observation(start.subtract(const Duration(days: 20)), 250),
          observation(changedAt, 260),
        ],
        from: start,
        to: end,
        convert: (value) => 10000 / value,
      );
      expect(points.map((point) => point.timestamp), [start, changedAt, end]);
      expect(points.map((point) => point.value), [
        40,
        10000 / 260,
        10000 / 260,
      ]);
    },
  );

  test('Bybit history reacts to staggered changes in either manual rate', () {
    final rubChange = start.add(const Duration(days: 1));
    final vndChange = start.add(const Duration(days: 3));
    final points = buildDerivedHistory(
      left: [
        observation(start.subtract(const Duration(days: 14)), 90),
        observation(rubChange, 100),
      ],
      right: [
        observation(start.subtract(const Duration(days: 10)), 25000),
        observation(vndChange, 26000),
      ],
      from: start,
      to: end,
      calculate: (rub, vnd) => rub / vnd * 10000,
    );
    expect(points.map((point) => point.timestamp), [
      start,
      rubChange,
      vndChange,
      end,
    ]);
    expect(points.map((point) => point.value), [
      90 / 25000 * 10000,
      100 / 25000 * 10000,
      100 / 26000 * 10000,
      100 / 26000 * 10000,
    ]);
  });

  test(
    'cross rate begins only when both values are known; no future backfill',
    () {
      final firstVnd = start.add(const Duration(days: 2));
      final usdChange = start.add(const Duration(days: 4));
      final points = buildDerivedHistory(
        left: [
          observation(start.subtract(const Duration(days: 1)), 90),
          observation(usdChange, 95),
          observation(end.add(const Duration(days: 1)), 100),
        ],
        right: [observation(firstVnd, 0.0036)],
        from: start,
        to: end,
        calculate: (usd, vnd) => usd / vnd,
      );
      expect(points.map((point) => point.timestamp), [
        firstVnd,
        usdChange,
        end,
      ]);
      expect(points.map((point) => point.value), [
        90 / 0.0036,
        95 / 0.0036,
        95 / 0.0036,
      ]);
    },
  );

  test('a single input also never backfills before the first observation', () {
    final first = start.add(const Duration(hours: 12));
    final points = buildRateHistory(
      rates: [observation(first, 90)],
      from: start,
      to: end,
      convert: (value) => value,
    );
    expect(points.map((point) => point.timestamp), [first, end]);
  });

  test('future-only and missing components produce no derived history', () {
    final left = [observation(start, 90)];
    for (final right in <List<Rate>>[
      [],
      [observation(end.add(const Duration(hours: 1)), 25000)],
    ]) {
      expect(
        buildDerivedHistory(
          left: left,
          right: right,
          from: start,
          to: end,
          calculate: (usd, vnd) => usd / vnd,
        ),
        isEmpty,
      );
    }
  });

  test(
    'simultaneous changes produce one cross rate and last duplicate wins',
    () {
      final changedAt = start.add(const Duration(days: 2));
      final points = buildDerivedHistory(
        left: [observation(start, 90), observation(changedAt, 100)],
        right: [
          observation(start, 0.0036),
          observation(changedAt, 0.0038, id: 1),
          observation(changedAt, 0.0040, id: 2),
        ],
        from: start,
        to: end,
        calculate: (usd, vnd) => usd / vnd,
      );
      // Both resulting values are 25000: no transient intermediate spike.
      expect(points.map((point) => point.timestamp), [start, end]);
      expect(points.map((point) => point.value), [25000, 25000]);
    },
  );
}
