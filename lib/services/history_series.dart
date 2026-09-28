import 'dart:math' as math;

import '../models/rate.dart';

class HistoryPoint {
  const HistoryPoint(this.timestamp, this.value);

  final DateTime timestamp;
  final double value;
}

/// A rate remains effective until the next observation. Earlier observations
/// establish the value at [from]; later observations never fill earlier gaps.
List<HistoryPoint> buildRateHistory({
  required List<Rate> rates,
  required DateTime from,
  required DateTime to,
  required double Function(double) convert,
}) => _buildHistory([rates], from, to, (values) => convert(values.first));

/// Recalculates at a change in either input, using only values known by then.
List<HistoryPoint> buildDerivedHistory({
  required List<Rate> left,
  required List<Rate> right,
  required DateTime from,
  required DateTime to,
  required double Function(double, double) calculate,
}) => _buildHistory(
  [left, right],
  from,
  to,
  (values) => calculate(values[0], values[1]),
);

List<HistoryPoint> _buildHistory(
  List<List<Rate>> inputs,
  DateTime from,
  DateTime to,
  double Function(List<double>) calculate,
) {
  if (from.isAfter(to)) return [];
  final events = <({int input, int order, Rate rate})>[];
  for (var input = 0; input < inputs.length; input++) {
    for (final rate in inputs[input]) {
      if (rate.timestamp.isAfter(to) ||
          !rate.value.isFinite ||
          rate.value <= 0) {
        continue;
      }
      events.add((input: input, order: events.length, rate: rate));
    }
  }
  events.sort((a, b) {
    final timeOrder = a.rate.timestamp.compareTo(b.rate.timestamp);
    if (timeOrder != 0) return timeOrder;
    final idOrder = (a.rate.id ?? 0).compareTo(b.rate.id ?? 0);
    return idOrder != 0 ? idOrder : a.order.compareTo(b.order);
  });

  final current = List<double?>.filled(inputs.length, null);
  final result = <HistoryPoint>[];
  var index = 0;
  while (index < events.length) {
    final time = events[index].rate.timestamp;
    // Apply simultaneous observations together to avoid transient cross rates.
    do {
      final event = events[index++];
      current[event.input] = event.rate.value;
    } while (index < events.length &&
        events[index].rate.timestamp.isAtSameMomentAs(time));

    if (current.any((value) => value == null)) continue;
    final value = calculate(current.cast<double>());
    if (!value.isFinite || value <= 0) continue;
    final point = HistoryPoint(time.isBefore(from) ? from : time, value);
    if (result.isNotEmpty &&
        result.last.timestamp.isAtSameMomentAs(point.timestamp)) {
      result[result.length - 1] = point;
    } else if (result.isEmpty || result.last.value != value) {
      result.add(point);
    }
  }
  if (result.isNotEmpty && result.last.timestamp.isBefore(to)) {
    result.add(HistoryPoint(to, result.last.value));
  }
  return result;
}

class HistoryValueRange {
  const HistoryValueRange(this.min, this.max);

  final double min;
  final double max;

  static HistoryValueRange? fromValues(Iterable<double> values) {
    final finite = values.where((value) => value.isFinite);
    if (finite.isEmpty) return null;
    final min = finite.reduce(math.min);
    final max = finite.reduce(math.max);
    final padding = math.max(
      (max - min) * 0.1,
      math.max(max.abs() * 0.01, 1e-6),
    );
    return HistoryValueRange(min - padding, max + padding);
  }
}
