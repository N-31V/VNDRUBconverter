import 'dart:async';

import 'package:currency_tracker/constants.dart';
import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/widgets/history_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12);
  Rate cbrVnd(double value) => Rate(
    base: Currencies.vnd,
    quote: Currencies.rub,
    source: Sources.cbr,
    value: value,
    timestamp: now.subtract(const Duration(days: 20)),
  );

  Widget app(HistoryChart chart) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: chart),
  );

  Rate rate(
    String source,
    String base,
    String quote,
    double value,
    DateTime time,
  ) => Rate(
    base: base,
    quote: quote,
    source: source,
    value: value,
    timestamp: time,
  );

  HistoryRateLoader historyLoader(List<Rate> history) =>
      (source, base, quote, from, to) async => history
          .where(
            (rate) =>
                rate.source == source &&
                rate.base == base &&
                rate.quote == quote,
          )
          .toList();

  Future<void> selectPair(WidgetTester tester, String pair) async {
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(pair).last);
    await tester.pumpAndSettle();
  }

  Iterable<LineChartBarData> bybitLines(WidgetTester tester) => tester
      .widget<LineChart>(find.byType(LineChart))
      .data
      .lineBarsData
      .where((line) => line.color == Colors.purple);

  testWidgets('Bybit uses both manual rates and ignores CBR USD changes', (
    tester,
  ) async {
    final start = now.subtract(const Duration(days: 7));
    final old = now.subtract(const Duration(days: 20));
    final rubChange = now.subtract(const Duration(days: 4));
    final cbrChange = now.subtract(const Duration(days: 3));
    final vndChange = now.subtract(const Duration(days: 2));
    await tester.pumpWidget(
      app(
        HistoryChart(
          now: () => now,
          loadRates: historyLoader([
            rate(Sources.cbr, Currencies.usd, Currencies.rub, 80, old),
            rate(Sources.cbr, Currencies.usd, Currencies.rub, 200, cbrChange),
            rate(Sources.bybitQr, Currencies.usdt, Currencies.rub, 90, old),
            rate(
              Sources.bybitQr,
              Currencies.usdt,
              Currencies.rub,
              100,
              rubChange,
            ),
            rate(Sources.bybitQr, Currencies.usdt, Currencies.vnd, 25000, old),
            rate(
              Sources.bybitQr,
              Currencies.usdt,
              Currencies.vnd,
              26000,
              vndChange,
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var line = bybitLines(tester).single;
    expect(line.spots.map((spot) => spot.x), [
      start.millisecondsSinceEpoch,
      rubChange.millisecondsSinceEpoch,
      vndChange.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    ]);
    expect(line.spots.map((spot) => spot.y), [
      90 / 25000 * 10000,
      100 / 25000 * 10000,
      100 / 26000 * 10000,
      100 / 26000 * 10000,
    ]);

    await selectPair(tester, 'USD/RUB');
    line = bybitLines(tester).single;
    expect(line.spots.map((spot) => spot.y), [90, 100, 100]);
    expect(line.spots.map((spot) => spot.x), [
      start.millisecondsSinceEpoch,
      rubChange.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    ]);
    final cbrLine = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .singleWhere((line) => line.color == Colors.cyan);
    expect(cbrLine.spots.map((spot) => spot.y), [80, 200, 200]);
    expect(find.text('Bybit USDT'), findsOneWidget);

    await selectPair(tester, 'RUB/VND');
    line = bybitLines(tester).single;
    expect(line.spots.map((spot) => spot.y), [
      25000 / 90,
      25000 / 100,
      26000 / 100,
      26000 / 100,
    ]);
  });

  testWidgets('missing manual RUB has no CBR fallback and keeps USDT/VND', (
    tester,
  ) async {
    final old = now.subtract(const Duration(days: 20));
    await tester.pumpWidget(
      app(
        HistoryChart(
          now: () => now,
          loadRates: historyLoader([
            rate(Sources.cbr, Currencies.usd, Currencies.rub, 90, old),
            cbrVnd(0.004),
            rate(Sources.bybitQr, Currencies.usdt, Currencies.vnd, 25000, old),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(bybitLines(tester), isEmpty);
    for (final pair in ['USD/RUB', 'RUB/VND']) {
      await selectPair(tester, pair);
      expect(bybitLines(tester), isEmpty);
    }
    await selectPair(tester, 'USD/VND');
    expect(bybitLines(tester).single.spots.map((spot) => spot.y), [
      25000,
      25000,
    ]);
  });

  testWidgets(
    'Bybit RUB history starts at first manual rate without backfill',
    (tester) async {
      final old = now.subtract(const Duration(days: 20));
      final firstRub = now.subtract(const Duration(days: 2));
      await tester.pumpWidget(
        app(
          HistoryChart(
            now: () => now,
            loadRates: historyLoader([
              rate(Sources.cbr, Currencies.usd, Currencies.rub, 90, old),
              cbrVnd(0.004),
              rate(
                Sources.bybitQr,
                Currencies.usdt,
                Currencies.vnd,
                25000,
                old,
              ),
              rate(
                Sources.bybitQr,
                Currencies.usdt,
                Currencies.rub,
                100,
                firstRub,
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final pair in ['VND/RUB (10000)', 'USD/RUB', 'RUB/VND']) {
        if (pair != 'VND/RUB (10000)') await selectPair(tester, pair);
        expect(bybitLines(tester).single.spots.map((spot) => spot.x), [
          firstRub.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        ]);
      }
    },
  );

  testWidgets('old anchor draws a flat line across the selected window', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        HistoryChart(
          now: () => now,
          loadRates: (source, base, quote, from, to) async =>
              source == Sources.cbr && base == Currencies.vnd
              ? [cbrVnd(0.004)]
              : [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    final line = data.lineBarsData.single;
    expect(line.spots.map((spot) => spot.y), [40, 40]);
    expect(
      line.spots.first.x,
      now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    );
    expect(line.spots.last.x, now.millisecondsSinceEpoch);
    expect(data.minY, lessThan(40));
    expect(data.maxY, greaterThan(40));
    expect(line.isStepLineChart, isFalse);
    expect(line.isCurved, isFalse);
  });

  testWidgets(
    'selectors stay accessible for empty data and let user change the pair',
    (tester) async {
      await tester.pumpWidget(
        app(
          HistoryChart(
            now: () => now,
            loadRates: (source, base, quote, from, to) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Нет данных для отображения'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD/RUB').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'USD/RUB',
      );
      expect(find.text('Нет данных для отображения'), findsOneWidget);
    },
  );

  testWidgets('selectors stay accessible on a load error', (tester) async {
    await tester.pumpWidget(
      app(
        HistoryChart(
          now: () => now,
          loadRates: (source, base, quote, from, to) async =>
              throw StateError('storage unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.textContaining('storage unavailable'), findsOneWidget);
  });

  testWidgets('an older overlapping load cannot overwrite a newer result', (
    tester,
  ) async {
    final requests = <Completer<List<Rate>>>[];
    final key = GlobalKey<HistoryChartState>();
    await tester.pumpWidget(
      app(
        HistoryChart(
          key: key,
          now: () => now,
          loadRates: (source, base, quote, from, to) {
            final request = Completer<List<Rate>>();
            requests.add(request);
            return request.future;
          },
        ),
      ),
    );
    key.currentState!.refresh();
    expect(requests.length, 12);
    for (var i = 6; i < 12; i++) {
      requests[i].complete(i == 7 ? [cbrVnd(0.004)] : []);
    }
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      requests[i].complete(i == 1 ? [cbrVnd(0.003)] : []);
    }
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData.single.spots.map((spot) => spot.y), [40, 40]);
  });

  testWidgets('finishing a load after disposal never calls setState', (
    tester,
  ) async {
    final pending = Completer<List<Rate>>();
    await tester.pumpWidget(
      app(
        HistoryChart(
          now: () => now,
          loadRates: (source, base, quote, from, to) => pending.future,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
