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
    expect(requests.length, 10);
    for (var i = 5; i < 10; i++) {
      requests[i].complete(i == 6 ? [cbrVnd(0.004)] : []);
    }
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
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
