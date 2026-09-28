import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late DatabaseHelper helper;
  final start = DateTime(2026, 9, 21);
  final end = DateTime(2026, 9, 28);

  Rate rate(DateTime time, double value, {String source = 'test'}) => Rate(
    base: 'RUB',
    quote: 'VND',
    source: source,
    value: value,
    timestamp: time,
  );

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base TEXT NOT NULL,
        quote TEXT NOT NULL,
        value REAL NOT NULL,
        source TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
    helper = DatabaseHelper.withDatabase(database);
  });
  tearDown(() => database.close());

  test('period query includes just the latest prior observation and window changes', () async {
    final old = start.subtract(const Duration(days: 20));
    final latestOld = start.subtract(const Duration(days: 10));
    final changedAt = start.add(const Duration(days: 2));
    for (final item in [
      rate(old, 250),
      rate(latestOld, 251),
      rate(changedAt, 252),
      rate(end.add(const Duration(days: 1)), 253),
      rate(start, 999, source: 'another-source'),
    ]) {
      await helper.insertRate(item);
    }
    final result = await helper.getRatesForPeriod(
      'test',
      'RUB',
      'VND',
      start,
      end,
    );
    expect(result.map((item) => item.value), [251, 252]);
    expect(result.map((item) => item.timestamp), [latestOld, changedAt]);
    final rows = await database.query('rates', orderBy: 'timestamp ASC');
    expect(rows.length, 5);
    expect(rows.first['timestamp'], old.toIso8601String());
  });

  test(
    'old unchanged rates remain available for both day and week windows',
    () async {
      final old = start.subtract(const Duration(days: 20));
      await helper.insertRateIfChanged(rate(old, 250));
      await helper.insertRateIfChanged(rate(end, 250));
      for (final days in [1, 7]) {
        final result = await helper.getRatesForPeriod(
          'test',
          'RUB',
          'VND',
          end.subtract(Duration(days: days)),
          end,
        );
        expect(result.single.timestamp, old);
        expect(result.single.value, 250);
      }
      expect(await database.query('rates'), hasLength(1));
    },
  );

  test(
    'changes append within a day, repeats are skipped, and reversals survive',
    () async {
      final second = start.add(const Duration(hours: 1));
      final third = start.add(const Duration(hours: 2));
      await helper.insertRateIfChanged(rate(start, 250));
      await helper.insertRateIfChanged(
        rate(start.add(const Duration(minutes: 1)), 250),
      );
      await helper.insertRateIfChanged(rate(second, 260));
      await helper.insertRateIfChanged(rate(third, 250));
      await helper.insertRateIfChanged(rate(end, 250));
      final result = await helper.getRatesForPeriod(
        'test',
        'RUB',
        'VND',
        start,
        end,
      );
      expect(result.map((item) => item.value), [250, 260, 250]);
      expect(result.map((item) => item.timestamp), [start, second, third]);
    },
  );

  test('concurrent repeated writes do not duplicate an observation', () async {
    await Future.wait(
      List.generate(5, (_) => helper.insertRateIfChanged(rate(start, 250))),
    );
    expect(await database.query('rates'), hasLength(1));
  });

  test('duplicate legacy timestamps use newest insertion as anchor and latest value', () async {
    final old = start.subtract(const Duration(days: 1));
    await helper.insertRate(rate(old, 250));
    await helper.insertRate(rate(old, 260));
    expect((await helper.getLatestRate('test', 'RUB', 'VND'))!.value, 260);
    final result = await helper.getRatesForPeriod(
      'test',
      'RUB',
      'VND',
      start,
      end,
    );
    expect(result.single.value, 260);
    expect(await database.query('rates'), hasLength(2));
  });

  test(
    'window boundaries are inclusive, future observations are excluded',
    () async {
      await helper.insertRate(rate(start, 250));
      await helper.insertRate(rate(end, 260));
      await helper.insertRate(rate(end.add(const Duration(seconds: 1)), 270));
      final result = await helper.getRatesForPeriod(
        'test',
        'RUB',
        'VND',
        start,
        end,
      );
      expect(result.map((item) => item.timestamp), [start, end]);
      expect(
        await helper.getRatesForPeriod('test', 'USD', 'RUB', start, end),
        isEmpty,
      );
    },
  );
}
