import 'dart:async';

import 'package:currency_tracker/constants.dart';
import 'package:currency_tracker/main.dart';
import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/widgets/history_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _key(String source, String base, String quote) => '$source/$base/$quote';

Map<String, Rate> _savedRates() {
  final timestamp = DateTime(2026, 9, 1, 12, 30);
  final rates = [
    Rate(
      base: Currencies.usd,
      quote: Currencies.rub,
      value: 90,
      source: Sources.cbr,
      timestamp: timestamp,
    ),
    Rate(
      base: Currencies.vnd,
      quote: Currencies.rub,
      value: 0.0036,
      source: Sources.cbr,
      timestamp: timestamp,
    ),
    Rate(
      base: Currencies.usdt,
      quote: Currencies.vnd,
      value: 25000,
      source: Sources.bybitQr,
      timestamp: timestamp,
    ),
    Rate(
      base: Currencies.rub,
      quote: Currencies.vnd,
      value: 270,
      source: Sources.tbankQr,
      timestamp: timestamp,
    ),
    Rate(
      base: Currencies.rub,
      quote: Currencies.vnd,
      value: 260,
      source: Sources.tbankTransfer,
      timestamp: timestamp,
    ),
  ];
  return {
    for (final rate in rates) _key(rate.source, rate.base, rate.quote): rate,
  };
}

String _results(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('rate-results'))).data!;

Future<void> _showDashboard(
  WidgetTester tester, {
  required RateLoader load,
  required Future<void> Function() cbr,
  required Future<void> Function() tbank,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        loadRate: load,
        refreshCbr: cbr,
        refreshTbank: tbank,
        historyChart: const SizedBox(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'shows cache first and CBR update while T-Bank is still pending',
    (tester) async {
      final saved = _savedRates();
      final cbr = Completer<void>();
      final tbank = Completer<void>();
      var localReads = 0;
      var cbrStarted = false;
      var tbankStarted = false;

      await _showDashboard(
        tester,
        load: (source, base, quote) async {
          localReads++;
          return saved[_key(source, base, quote)];
        },
        cbr: () {
          expect(localReads, 5);
          cbrStarted = true;
          return cbr.future;
        },
        tbank: () {
          expect(localReads, 5);
          tbankStarted = true;
          return tbank.future;
        },
      );

      expect(cbrStarted && tbankStarted, isTrue);
      expect(_results(tester), contains('Bybit:   36.18 ₽'));
      expect(
        _results(tester)
            .split('\n')
            .singleWhere((line) => line.contains('Bybit:')),
        contains('0.4000 USDT'),
      );
      expect(_results(tester), contains('T-tr:    38.46 ₽'));

      saved[_key(Sources.cbr, Currencies.usd, Currencies.rub)] = Rate(
        base: Currencies.usd,
        quote: Currencies.rub,
        source: Sources.cbr,
        value: 100,
        timestamp: DateTime(2026, 9, 28, 13),
      );
      cbr.complete();
      await tester.pump();
      await tester.pump();

      expect(_results(tester), contains('Bybit:   40.20 ₽'));
      expect(find.text('Т-Банк перевод: обновление…'), findsOneWidget);

      tbank.completeError(Exception('CERTIFICATE_VERIFY_FAILED'));
      await tester.pumpAndSettle();

      expect(_results(tester), contains('T-tr:    38.46 ₽'));
      expect(
        find.textContaining('Не удалось проверить сертификат сервера.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Используются сохранённые данные.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing CBR still allows fresh transfer price and manual QR', (
    tester,
  ) async {
    final saved = _savedRates()
      ..removeWhere((_, rate) => rate.source == Sources.cbr);
    await _showDashboard(
      tester,
      load: (source, base, quote) async => saved[_key(source, base, quote)],
      cbr: () async => throw Exception('ЦБ недоступен'),
      tbank: () async {
        saved[_key(
          Sources.tbankTransfer,
          Currencies.rub,
          Currencies.vnd,
        )] = Rate(
          base: Currencies.rub,
          quote: Currencies.vnd,
          source: Sources.tbankTransfer,
          value: 250,
          timestamp: DateTime(2026, 9, 28),
        );
      },
    );
    await tester.pumpAndSettle();

    expect(_results(tester), contains('Bybit:   — ₽'));
    expect(_results(tester), contains('0.4000 USDT'));
    expect(_results(tester), contains('T-QR:    37.04 ₽ (— ₽)'));
    expect(_results(tester), contains('T-tr:    40.00 ₽ (— ₽)'));
    expect(_results(tester), contains('25000'));
    expect(find.textContaining('Сохранённых данных нет.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('amount-input')), '20');
    await tester.pump();
    expect(_results(tester), contains('T-QR:    74.07 ₽'));
    expect(_results(tester), contains('T-tr:    80.00 ₽'));
    expect(_results(tester), contains('0.8000 USDT'));
  });

  testWidgets(
    'fractional amounts update USDT and clearing input clears totals',
    (tester) async {
      final saved = _savedRates();
      await _showDashboard(
        tester,
        load: (source, base, quote) async => saved[_key(source, base, quote)],
        cbr: () async {},
        tbank: () async {},
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('amount-input'));
      for (final amount in ['25,5', '25.5']) {
        await tester.enterText(input, amount);
        await tester.pump();
        expect(_results(tester), contains('25500 VND:'));
        expect(_results(tester), contains('1.0200 USDT'));
        expect(_results(tester), contains('Bybit:   92.26 ₽'));
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );

      for (final amount in ['', '0', '-1', 'abc', 'Infinity']) {
        await tester.enterText(input, amount);
        await tester.pump();
        expect(_results(tester), contains('Bybit:   — ₽'));
        expect(_results(tester), contains('— USDT'));
        expect(_results(tester), isNot(contains('25500 VND:')));
        // Invalid calculator input must not hide the rate table.
        expect(_results(tester), contains('90.45'));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a local read error preserves other sources', (tester) async {
    final saved = _savedRates();
    await _showDashboard(
      tester,
      load: (source, base, quote) async {
        if (source == Sources.tbankTransfer) throw Exception('Ошибка SQLite');
        return saved[_key(source, base, quote)];
      },
      cbr: () async {},
      tbank: () async {},
    );
    await tester.pumpAndSettle();

    expect(_results(tester), contains('Bybit:   36.18 ₽'));
    expect(_results(tester), contains('T-tr:    — ₽'));
    expect(
      find.textContaining('ошибка чтения сохранённого курса'),
      findsOneWidget,
    );
  });

  testWidgets('invalid stored rates never produce Infinity or NaN', (
    tester,
  ) async {
    await _showDashboard(
      tester,
      load: (source, base, quote) async => Rate(
        source: source,
        base: base,
        quote: quote,
        value: 0,
        timestamp: DateTime(2026, 9, 1),
      ),
      cbr: () async {},
      tbank: () async {},
    );
    await tester.pumpAndSettle();

    expect(_results(tester), contains('T-QR:    — ₽'));
    expect(_results(tester), isNot(contains('Infinity')));
    expect(_results(tester), isNot(contains('NaN')));
  });

  testWidgets('network completion after disposal does not update state', (
    tester,
  ) async {
    final cbr = Completer<void>();
    final tbank = Completer<void>();
    await _showDashboard(
      tester,
      load: (_, _, _) async => null,
      cbr: () => cbr.future,
      tbank: () => tbank.future,
    );
    await tester.pumpWidget(const SizedBox());
    cbr.complete();
    tbank.completeError(Exception('Сеть недоступна'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal during local load does not start network work', (
    tester,
  ) async {
    final local = Completer<Rate?>();
    var networkCalls = 0;
    await _showDashboard(
      tester,
      load: (_, _, _) => local.future,
      cbr: () async {
        networkCalls++;
      },
      tbank: () async {
        networkCalls++;
      },
    );
    await tester.pumpWidget(const SizedBox());
    local.complete(null);
    await tester.pump();

    expect(networkCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen scrolls without overflow when requests fail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = _savedRates();
    await _showDashboard(
      tester,
      load: (source, base, quote) async => saved[_key(source, base, quote)],
      cbr: () async => throw TimeoutException('timeout'),
      tbank: () async => throw Exception('CERTIFICATE_VERIFY_FAILED'),
    );
    await tester.pumpAndSettle();
    expect(_results(tester), contains('T-tr:    38.46 ₽'));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard scrolls a real chart with old rates on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = _savedRates();
      final now = DateTime(2026, 9, 28);
      final historyReads = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            loadRate: (source, base, quote) async =>
                saved[_key(source, base, quote)],
            refreshCbr: () async {},
            refreshTbank: () async {},
            historyChart: HistoryChart(
              now: () => now,
              loadRates: (source, base, quote, from, to) async {
                final key = _key(source, base, quote);
                historyReads.add(key);
                // Every component predates the chart's default seven-day window.
                final anchor = saved[key]!;
                expect(anchor.timestamp.isBefore(from), isTrue);
                return [anchor];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_results(tester), contains('T-tr:    38.46 ₽'));

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(historyReads, hasLength(5));
      expect(find.byType(LineChart), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData, hasLength(4));
      for (final line in chart.data.lineBarsData) {
        expect(line.spots, hasLength(2));
        expect(
          line.spots.first.x,
          now
              .subtract(const Duration(days: 7))
              .millisecondsSinceEpoch
              .toDouble(),
        );
        expect(line.spots.last.x, now.millisecondsSinceEpoch.toDouble());
        expect(line.spots.first.y, line.spots.last.y);
      }

      await tester.ensureVisible(find.byType(LineChart));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart).hitTestable(), findsOneWidget);
      final period = tester.getRect(find.byType(DropdownButton<int>));
      final pair = tester.getRect(find.byType(DropdownButton<String>));
      final plot = tester.getRect(find.byType(LineChart));
      expect(period.top, greaterThanOrEqualTo(plot.bottom));
      expect(pair.top, period.top);
      expect(period.right, lessThan(pair.left));
      expect(tester.takeException(), isNull);
    },
  );
}
