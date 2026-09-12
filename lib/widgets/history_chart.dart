import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_helper.dart';
import '../models/rate.dart';
import '../constants.dart';

class HistoryChart extends StatefulWidget {
  const HistoryChart({super.key});

  @override
  State<HistoryChart> createState() => HistoryChartState();
}

class HistoryChartState extends State<HistoryChart> {
  int _days = 7;
  String _selectedPair = 'VND/RUB (10000)';
  bool _isLoading = false;
  List<Map<String, dynamic>> _series = [];
  String _error = '';
  final List<int> _dayOptions = [1, 7, 14, 30, 60, 90];
  final List<String> _pairOptions = [
    'VND/RUB (10000)',
    'USD/RUB',
    'USD/VND',
    'RUB/VND',
  ];

  List<FlSpot> _extendToNow(List<FlSpot> spots) {
    if (spots.isEmpty) return spots;
    final last = spots.last;
    final nowX = DateTime.now().millisecondsSinceEpoch.toDouble();
    if (last.x < nowX) {
      spots.add(FlSpot(nowX, last.y));
    }
    return spots;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void refresh() {
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final db = DatabaseHelper();
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: _days));

      final cbrUsdRates = await db.getRatesForPeriod(
        Sources.cbr,
        Currencies.usd,
        Currencies.rub,
        startDate,
        now,
      );
      final cbrVndRates = await db.getRatesForPeriod(
        Sources.cbr,
        Currencies.vnd,
        Currencies.rub,
        startDate,
        now,
      );
      final tbankQrRates = await db.getRatesForPeriod(
        Sources.tbankQr,
        Currencies.rub,
        Currencies.vnd,
        startDate,
        now,
      );
      final tbankTransferRates = await db.getRatesForPeriod(
        Sources.tbankTransfer,
        Currencies.rub,
        Currencies.vnd,
        startDate,
        now,
      );
      final bybitQrRates = await db.getRatesForPeriod(
        Sources.bybitQr,
        Currencies.usdt,
        Currencies.vnd,
        startDate,
        now,
      );

      final cbrUsdDaily = _toDailyMap(cbrUsdRates);
      final cbrVndDaily = _toDailyMap(cbrVndRates);

      List<Map<String, dynamic>> series = [];

      switch (_selectedPair) {
        case 'VND/RUB (10000)':
          if (cbrVndDaily.isNotEmpty) {
            series.add(_buildLineFromDaily(cbrVndDaily, (v) => v * 10000, 'ЦБ РФ', Colors.cyan));
          }
          if (tbankQrRates.isNotEmpty) {
            series.add(_buildLineFromRates(tbankQrRates, (r) => 10000 / r.value, 'Т-банк QR', Colors.green));
          }
          if (tbankTransferRates.isNotEmpty) {
            series.add(_buildLineFromRates(tbankTransferRates, (r) => 10000 / r.value, 'Т-банк перевод', Colors.orange));
          }
          if (cbrUsdDaily.isNotEmpty && bybitQrRates.isNotEmpty) {
            final bybitSpots = _computeBybitVndRubFromRates(bybitQrRates, cbrUsdDaily, multiplier: 10000);
            if (bybitSpots.isNotEmpty) {
              series.add({
                'label': 'Bybit (расч.)',
                'color': Colors.purple,
                'spots': bybitSpots,
              });
            }
          }
          break;

        case 'USD/RUB':
          if (cbrUsdDaily.isNotEmpty) {
            series.add(_buildLineFromDaily(cbrUsdDaily, (v) => v, 'ЦБ РФ', Colors.cyan));
          }
          if (cbrUsdDaily.isNotEmpty) {
            final bybitSpots = cbrUsdDaily.entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value * 1.005);
            }).toList()..sort((a, b) => a.x.compareTo(b.x));
            if (bybitSpots.isNotEmpty) {
              series.add({
                'label': 'Bybit (аппрокс.)',
                'color': Colors.purple,
                'spots': _extendToNow(bybitSpots),
              });
            }
          }
          break;

        case 'USD/VND':
          if (bybitQrRates.isNotEmpty) {
            series.add(_buildLineFromRates(bybitQrRates, (r) => r.value, 'Bybit QR', Colors.purple));
          }
          if (cbrUsdDaily.isNotEmpty && cbrVndDaily.isNotEmpty) {
            final crossSpots = _computeCrossUsdVnd(cbrUsdDaily, cbrVndDaily);
            if (crossSpots.isNotEmpty) {
              series.add({
                'label': 'ЦБ (кросс)',
                'color': Colors.cyan,
                'spots': crossSpots,
              });
            }
          }
          break;

        case 'RUB/VND':
          if (tbankQrRates.isNotEmpty) {
            series.add(_buildLineFromRates(tbankQrRates, (r) => r.value, 'Т-банк QR', Colors.green));
          }
          if (tbankTransferRates.isNotEmpty) {
            series.add(_buildLineFromRates(tbankTransferRates, (r) => r.value, 'Т-банк перевод', Colors.orange));
          }
          if (cbrVndDaily.isNotEmpty) {
            series.add(_buildLineFromDaily(cbrVndDaily, (v) => 1 / v, 'ЦБ РФ (инв.)', Colors.cyan));
          }
          if (cbrUsdDaily.isNotEmpty && bybitQrRates.isNotEmpty) {
            final bybitVndRubSpots = _computeBybitVndRubFromRates(bybitQrRates, cbrUsdDaily, multiplier: 1.0);
            if (bybitVndRubSpots.isNotEmpty) {
              final bybitRubVndSpots = bybitVndRubSpots.map((spot) => FlSpot(spot.x, 1 / spot.y)).toList();
              series.add({
                'label': 'Bybit (расч.)',
                'color': Colors.purple,
                'spots': bybitRubVndSpots,
              });
            }
          }
          break;
      }

      setState(() {
        _series = series;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<int, double> _toDailyMap(List<Rate> rates) {
    final map = <int, double>{};
    for (var r in rates) {
      final day = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day).millisecondsSinceEpoch;
      if (!map.containsKey(day)) {
        map[day] = r.value;
      }
    }
    return map;
  }

  List<FlSpot> _buildLineFromDailyMap(Map<int, double> dailyMap, double Function(double) converter) {
    final spots = dailyMap.entries
        .map((e) => FlSpot(e.key.toDouble(), converter(e.value)))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    return _extendToNow(spots);
  }

  Map<String, dynamic> _buildLineFromDaily(Map<int, double> dailyMap, double Function(double) converter, String label, Color color) {
    final spots = _buildLineFromDailyMap(dailyMap, converter);
    return {'label': label, 'color': color, 'spots': spots};
  }

  List<FlSpot> _buildLineFromRatesList(List<Rate> rates, double Function(Rate) converter) {
    final spots = rates
        .map((r) => FlSpot(r.timestamp.millisecondsSinceEpoch.toDouble(), converter(r)))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    return _extendToNow(spots);
  }

  Map<String, dynamic> _buildLineFromRates(List<Rate> rates, double Function(Rate) converter, String label, Color color) {
    final spots = _buildLineFromRatesList(rates, converter);
    return {'label': label, 'color': color, 'spots': spots};
  }

  List<FlSpot> _computeBybitVndRubFromRates(List<Rate> bybitRates, Map<int, double> cbrUsdDaily, {double multiplier = 1.0}) {
    const double spread = 1.005;
    List<FlSpot> spots = [];
    for (var bybitRate in bybitRates) {
      final day = DateTime(bybitRate.timestamp.year, bybitRate.timestamp.month, bybitRate.timestamp.day).millisecondsSinceEpoch;
      if (cbrUsdDaily.containsKey(day)) {
        final usdRub = cbrUsdDaily[day]!;
        final usdtVnd = bybitRate.value;
        final vndRub = (usdRub * spread) / usdtVnd;
        spots.add(FlSpot(bybitRate.timestamp.millisecondsSinceEpoch.toDouble(), vndRub * multiplier));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return _extendToNow(spots);
  }

  List<FlSpot> _computeCrossUsdVnd(Map<int, double> cbrUsdDaily, Map<int, double> cbrVndDaily) {
    final commonDays = cbrUsdDaily.keys.where((day) => cbrVndDaily.containsKey(day)).toList()..sort();
    List<FlSpot> spots = [];
    for (var day in commonDays) {
      final usdRub = cbrUsdDaily[day]!;
      final vndRub = cbrVndDaily[day]!;
      spots.add(FlSpot(day.toDouble(), usdRub / vndRub));
    }
    return _extendToNow(spots);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text('Ошибка: $_error'));
    }

    double minY = double.infinity;
    double maxY = -double.infinity;
    for (var series in _series) {
      for (var spot in series['spots']) {
        if (spot.y < minY) minY = spot.y;
        if (spot.y > maxY) maxY = spot.y;
      }
    }
    if (minY == double.infinity) {
      return const Center(child: Text('Нет данных для отображения'));
    }
    final yPadding = (maxY - minY) * 0.1;
    minY -= yPadding;
    maxY += yPadding;

    final startDate = DateTime.now().subtract(Duration(days: _days));
    final startX = startDate.millisecondsSinceEpoch.toDouble();
    final nowX = DateTime.now().millisecondsSinceEpoch.toDouble();

    double minX = double.infinity;
    double maxX = -double.infinity;
    for (var series in _series) {
      final spots = series['spots'] as List<FlSpot>;
      if (spots.isNotEmpty) {
        if (spots.first.x < minX) minX = spots.first.x;
        if (spots.last.x > maxX) maxX = spots.last.x;
      }
    }

    if (minX == double.infinity) {
      return const Center(child: Text('Нет данных для отображения'));
    }

    minX = minX < startX ? minX : startX;
    maxX = maxX > nowX ? maxX : nowX;

    final xPadding = (maxX - minX) * 0.02;
    minX -= xPadding;
    maxX += xPadding;

    // Интервал оси X
    double intervalMs;
    if (_days == 1) {
      intervalMs = 14400000.0; // 4 часа
    } else if (_days <= 7) {
      intervalMs = 86400000.0; // 1 день
    } else if (_days <= 30) {
      intervalMs = 172800000.0; // 2 дня
    } else {
      intervalMs = (86400000 * (_days ~/ 7)).toDouble(); // ~ неделя
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Период: ', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _days,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: _dayOptions.map((days) {
                return DropdownMenuItem<int>(
                  value: days,
                  child: Text('$days д.'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _days = value;
                  });
                  _loadData();
                }
              },
            ),
            const SizedBox(width: 16),
            const Text('Пара: ', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _selectedPair,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: _pairOptions.map((pair) {
                return DropdownMenuItem<String>(
                  value: pair,
                  child: Text(pair),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedPair = value;
                  });
                  _loadData();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: intervalMs,
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      if (intervalMs < 86400000) {
                        return Text(
                          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        );
                      } else {
                        return Text(
                          '${date.day}.${date.month}',
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        );
                      }
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      );
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.white38, width: 0.5),
              ),
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              lineBarsData: _series.map((series) {
                return LineChartBarData(
                  spots: series['spots'] as List<FlSpot>,
                  isCurved: false,
                  color: series['color'],
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: _series.map((series) {
            return _legendItem(series['color'] as Color, series['label'] as String);
          }).toList(),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 4, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}