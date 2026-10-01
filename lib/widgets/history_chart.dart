import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/rate.dart';
import '../services/database_helper.dart';
import '../services/history_series.dart';

typedef HistoryRateLoader = Future<List<Rate>> Function(
  String source,
  String base,
  String quote,
  DateTime from,
  DateTime to,
);

class HistoryChart extends StatefulWidget {
  const HistoryChart({super.key, this.loadRates, this.now});

  final HistoryRateLoader? loadRates;
  final DateTime Function()? now;

  @override
  State<HistoryChart> createState() => HistoryChartState();
}

class _HistoryLine {
  const _HistoryLine(this.label, this.color, this.points);

  final String label;
  final Color color;
  final List<HistoryPoint> points;
}

class HistoryChartState extends State<HistoryChart> {
  int _days = 7;
  String _selectedPair = 'VND/RUB (10000)';
  bool _isLoading = false;
  List<_HistoryLine> _series = [];
  String _error = '';
  int _loadGeneration = 0;
  DateTime? _windowStart;
  DateTime? _windowEnd;
  static const _dayOptions = [1, 7, 14, 30, 60, 90];
  static const _pairOptions = [
    'VND/RUB (10000)',
    'USD/RUB',
    'USD/VND',
    'RUB/VND',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void refresh() => _loadData();

  Future<void> _loadData() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final pair = _selectedPair;
    final now = widget.now?.call() ?? DateTime.now();
    final start = now.subtract(Duration(days: _days));
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final load = widget.loadRates ?? DatabaseHelper().getRatesForPeriod;
      final histories = await Future.wait([
        load(Sources.cbr, Currencies.usd, Currencies.rub, start, now),
        load(Sources.cbr, Currencies.vnd, Currencies.rub, start, now),
        load(Sources.tbankQr, Currencies.rub, Currencies.vnd, start, now),
        load(Sources.tbankTransfer, Currencies.rub, Currencies.vnd, start, now),
        load(Sources.bybitQr, Currencies.usdt, Currencies.vnd, start, now),
        load(Sources.bybitQr, Currencies.usdt, Currencies.rub, start, now),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final [cbrUsd, cbrVnd, tbankQr, tbankTransfer, bybitVnd, bybitRub] =
          histories;
      final series = <_HistoryLine>[];

      void addRate(
        List<Rate> rates,
        double Function(double) convert,
        String label,
        Color color,
      ) {
        final points = buildRateHistory(
          rates: rates,
          from: start,
          to: now,
          convert: convert,
        );
        if (points.isNotEmpty) series.add(_HistoryLine(label, color, points));
      }

      void addDerived(
        List<Rate> left,
        List<Rate> right,
        double Function(double, double) calculate,
        String label,
        Color color,
      ) {
        final points = buildDerivedHistory(
          left: left,
          right: right,
          from: start,
          to: now,
          calculate: calculate,
        );
        if (points.isNotEmpty) series.add(_HistoryLine(label, color, points));
      }

      switch (pair) {
        case 'VND/RUB (10000)':
          addRate(cbrVnd, (v) => v * 10000, 'ЦБ РФ', Colors.cyan);
          addRate(tbankQr, (v) => 10000 / v, 'Т-банк QR', Colors.green);
          addRate(
            tbankTransfer,
            (v) => 10000 / v,
            'Т-банк перевод',
            Colors.orange,
          );
          addDerived(
            bybitRub,
            bybitVnd,
            (rub, vnd) => rub / vnd * 10000,
            'Bybit (расч.)',
            Colors.purple,
          );
        case 'USD/RUB':
          addRate(cbrUsd, (v) => v, 'ЦБ РФ', Colors.cyan);
          addRate(bybitRub, (v) => v, 'Bybit USDT', Colors.purple);
        case 'USD/VND':
          addRate(bybitVnd, (v) => v, 'Bybit QR', Colors.purple);
          addDerived(
            cbrUsd,
            cbrVnd,
            (usd, vnd) => usd / vnd,
            'ЦБ (кросс)',
            Colors.cyan,
          );
        case 'RUB/VND':
          addRate(tbankQr, (v) => v, 'Т-банк QR', Colors.green);
          addRate(tbankTransfer, (v) => v, 'Т-банк перевод', Colors.orange);
          addRate(cbrVnd, (v) => 1 / v, 'ЦБ РФ (инв.)', Colors.cyan);
          addDerived(
            bybitRub,
            bybitVnd,
            (rub, vnd) => vnd / rub,
            'Bybit (расч.)',
            Colors.purple,
          );
      }
      setState(() {
        _series = series;
        _windowStart = start;
        _windowEnd = now;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 250, child: _buildPlot()),
        if (!_isLoading && _error.isEmpty && _series.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: _series
                .map((line) => _legendItem(line.color, line.label))
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Период', style: TextStyle(color: Colors.white70)),
                  SizedBox(
                    height: 48,
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _days,
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      underline: const SizedBox.shrink(),
                      items: _dayOptions
                          .map(
                            (days) => DropdownMenuItem(
                              value: days,
                              child: Text('$days д.'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null || value == _days) return;
                        setState(() => _days = value);
                        _loadData();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Пара', style: TextStyle(color: Colors.white70)),
                  SizedBox(
                    height: 48,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedPair,
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      underline: const SizedBox.shrink(),
                      items: _pairOptions
                          .map(
                            (pair) => DropdownMenuItem(
                              value: pair,
                              child: Text(
                                pair,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null || value == _selectedPair) return;
                        setState(() => _selectedPair = value);
                        _loadData();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlot() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return Center(child: Text('Ошибка: $_error'));
    final range = HistoryValueRange.fromValues(
      _series.expand((line) => line.points.map((point) => point.value)),
    );
    if (range == null) {
      return const Center(child: Text('Нет данных для отображения'));
    }
    final intervalMs = switch (_days) {
      1 => 14400000.0,
      <= 7 => 86400000.0,
      <= 30 => 172800000.0,
      _ => (86400000 * (_days ~/ 7)).toDouble(),
    };
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: intervalMs,
              // Window edges can lie close to a regular tick and overlap it.
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                final label = intervalMs < 86400000
                    ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                    : '${date.day}.${date.month}';
                return Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.white38, width: 0.5),
        ),
        minX: _windowStart!.millisecondsSinceEpoch.toDouble(),
        maxX: _windowEnd!.millisecondsSinceEpoch.toDouble(),
        minY: range.min,
        maxY: range.max,
        lineBarsData: _series
            .map(
              (line) => LineChartBarData(
                spots: line.points
                    .map(
                      (point) => FlSpot(
                        point.timestamp.millisecondsSinceEpoch.toDouble(),
                        point.value,
                      ),
                    )
                    .toList(),
                isCurved: false,
                color: line.color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 4, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
