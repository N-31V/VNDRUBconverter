import 'dart:async';

import 'package:currency_tracker/constants.dart';
import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/screens/settings_screen.dart';
import 'package:currency_tracker/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SettingsDatabase extends DatabaseHelper {
  _SettingsDatabase(super.database, {this.readGate}) : super.withDatabase();

  final Future<void>? readGate;
  final loaded = Completer<void>();
  Completer<void>? saved;
  int _reads = 0;

  @override
  Future<Rate?> getLatestRate(String source, String base, String quote) async {
    try {
      await readGate;
      return await super.getLatestRate(source, base, quote);
    } finally {
      if (++_reads == 3) loaded.complete();
    }
  }

  @override
  Future<void> insertRateIfChanged(Rate rate) async {
    try {
      await super.insertRateIfChanged(rate);
    } finally {
      saved?.complete();
    }
  }
}

Finder _section(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

Finder _field(String title) =>
    find.descendant(of: _section(title), matching: find.byType(TextField));

Finder _saveButton(String title) => find.descendant(
  of: _section(title),
  matching: find.widgetWithText(ElevatedButton, 'Сохранить'),
);

String _fieldText(WidgetTester tester, String title) =>
    tester.widget<TextField>(_field(title)).controller!.text;

Future<void> _show(WidgetTester tester, _SettingsDatabase helper) async {
  await tester.pumpWidget(MaterialApp(home: SettingsScreen(database: helper)));
  await tester.pump();
  await helper.loaded.future;
  await tester.pump();
}

Future<void> _save(WidgetTester tester, _SettingsDatabase helper) async {
  helper.saved = Completer<void>();
  await tester.tap(_saveButton('Bybit (USDT/RUB)'));
  await tester.pump();
  await helper.saved!.future;
  await tester.pumpAndSettle();
}

void main() {
  late Database database;
  late _SettingsDatabase helper;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
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
    helper = _SettingsDatabase(database);
  });
  tearDown(() => database.close());

  Future<void> seed(String source, String base, String quote, double value) =>
      helper.insertRate(
        Rate(
          source: source,
          base: base,
          quote: quote,
          value: value,
          timestamp: DateTime(2026, 1, 1),
        ),
      );

  Future<List<Map<String, Object?>>> bybitRubHistory() => database.query(
    'rates',
    where: 'source = ? AND base = ? AND quote = ?',
    whereArgs: [Sources.bybitQr, Currencies.usdt, Currencies.rub],
    orderBy: 'id ASC',
  );

  testWidgets('saves both decimal separators and keeps other pairs unchanged', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(Sources.cbr, Currencies.usd, Currencies.rub, 90);
      await seed(Sources.bybitQr, Currencies.usdt, Currencies.vnd, 25000);
      await seed(Sources.tbankQr, Currencies.rub, Currencies.vnd, 270);
      final previous = await database.query('rates');
      await _show(tester, helper);

      expect(_fieldText(tester, 'Bybit (USDT/RUB)'), isEmpty);
      expect(_fieldText(tester, 'Bybit QR (USDT/VND)'), '25000');
      expect(_fieldText(tester, 'Т-банк QR (руб за 10000 VND)'), '37.04');

      await tester.enterText(_field('Bybit (USDT/RUB)'), '92,1234567');
      await _save(tester, helper);
      await tester.enterText(_field('Bybit (USDT/RUB)'), '93.7654321');
      await _save(tester, helper);

      final history = await bybitRubHistory();
      expect(history.map((row) => row['value']), [92.1234567, 93.7654321]);
      final unchanged = await database.query(
        'rates',
        where: 'id <= 3',
        orderBy: 'id ASC',
      );
      expect(unchanged, previous);
    });
  });

  testWidgets('reopens saved precision and skips an unchanged save', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _show(tester, helper);
      await tester.enterText(_field('Bybit (USDT/RUB)'), '92.123456789');
      await _save(tester, helper);
      await tester.pumpWidget(const SizedBox());

      helper = _SettingsDatabase(database);
      await _show(tester, helper);
      expect(_fieldText(tester, 'Bybit (USDT/RUB)'), '92.123456789');
      await _save(tester, helper);

      final history = await bybitRubHistory();
      expect(history, hasLength(1));
      expect(history.single['value'], 92.123456789);
    });
  });

  testWidgets('rejects empty, nonnumeric, nonpositive and nonfinite rates', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _show(tester, helper);
      for (final input in ['', 'abc', '0', '-1', 'NaN', 'Infinity', '1e309']) {
        await tester.enterText(_field('Bybit (USDT/RUB)'), input);
        await tester.tap(_saveButton('Bybit (USDT/RUB)'));
        await tester.pumpAndSettle();
        expect(
          find.text('Введите корректный курс USDT/RUB (например 92.50)'),
          findsOneWidget,
        );
        ScaffoldMessenger.of(tester.element(_field('Bybit (USDT/RUB)')))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      expect(await bybitRubHistory(), isEmpty);
    });
  });

  testWidgets('late loading does not replace a value the user already typed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(Sources.bybitQr, Currencies.usdt, Currencies.rub, 90);
      final gate = Completer<void>();
      helper = _SettingsDatabase(database, readGate: gate.future);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(database: helper)),
      );
      await tester.enterText(_field('Bybit (USDT/RUB)'), '95,25');
      gate.complete();
      await tester.pump();
      await helper.loaded.future;
      await tester.pump();

      expect(_fieldText(tester, 'Bybit (USDT/RUB)'), '95,25');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('finishing a read after the screen closes is safe', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(Sources.bybitQr, Currencies.usdt, Currencies.rub, 90);
      final gate = Completer<void>();
      helper = _SettingsDatabase(database, readGate: gate.future);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(database: helper)),
      );
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      await helper.loaded.future;
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
