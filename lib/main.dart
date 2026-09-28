import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'models/rate.dart';
import 'screens/settings_screen.dart';
import 'services/cbr_api.dart';
import 'services/database_helper.dart';
import 'services/tbank_api.dart';
import 'widgets/compact_table_text.dart';
import 'widgets/history_chart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Currency Tracker',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

typedef RateLoader = Future<Rate?> Function(
  String source,
  String base,
  String quote,
);

enum _RateKey {
  cbrUsd(Sources.cbr, Currencies.usd, Currencies.rub, 'ЦБ USD'),
  cbrVnd(Sources.cbr, Currencies.vnd, Currencies.rub, 'ЦБ VND'),
  bybit(Sources.bybitQr, Currencies.usdt, Currencies.vnd, 'Bybit QR'),
  tbankQr(Sources.tbankQr, Currencies.rub, Currencies.vnd, 'Т-Банк QR'),
  tbankTransfer(
    Sources.tbankTransfer,
    Currencies.rub,
    Currencies.vnd,
    'Т-Банк перевод',
  );

  const _RateKey(this.source, this.base, this.quote, this.label);

  final String source;
  final String base;
  final String quote;
  final String label;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.loadRate,
    this.refreshCbr,
    this.refreshTbank,
    this.historyChart,
  });

  final RateLoader? loadRate;
  final Future<void> Function()? refreshCbr;
  final Future<void> Function()? refreshTbank;
  final Widget? historyChart;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _graphKey = GlobalKey<HistoryChartState>();
  final _rates = <_RateKey, Rate?>{};
  final _readErrors = <_RateKey, String>{};
  final _sourceErrors = <String, String>{};
  final _pendingSources = <String>{};
  double? _amountThousands = 10;
  String? _amountError;
  bool _isRefreshing = false;
  bool _isLoadingLocal = true;

  @override
  void initState() {
    super.initState();
    _refreshAllRates();
  }

  Future<void> _refreshAllRates() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _sourceErrors.clear();
    });

    // Показываем сохранённые данные до любых сетевых запросов.
    await _loadRates(_RateKey.values);
    if (!mounted) return;
    setState(() => _isLoadingLocal = false);

    // Каждый источник обновляет только свои поля сразу по завершении.
    await Future.wait([
      _refreshSource(Sources.cbr, [
        _RateKey.cbrUsd,
        _RateKey.cbrVnd,
      ], widget.refreshCbr ?? CbrApiClient.fetchAndSaveRates),
      _refreshSource(Sources.tbankTransfer, [
        _RateKey.tbankTransfer,
      ], widget.refreshTbank ?? TbankApiClient.fetchAndSaveTbankRates),
    ]);
    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  Future<void> _refreshSource(
    String source,
    List<_RateKey> keys,
    Future<void> Function() refresh,
  ) async {
    setState(() => _pendingSources.add(source));
    try {
      await refresh();
      if (!mounted) return;
      await _loadRates(keys);
      if (!mounted) return;
      _graphKey.currentState?.refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _sourceErrors[source] = _describeError(error));
    } finally {
      if (mounted) setState(() => _pendingSources.remove(source));
    }
  }

  Future<void> _loadRates(Iterable<_RateKey> keys) async {
    final load = widget.loadRate ?? DatabaseHelper().getLatestRate;
    await Future.wait(
      keys.map((key) async {
        try {
          final rate = await load(key.source, key.base, key.quote);
          if (!mounted) return;
          setState(() {
            _rates[key] = rate;
            _readErrors.remove(key);
          });
        } catch (error) {
          if (!mounted) return;
          // Ошибка чтения одного курса не стирает остальные и ранее показанный.
          setState(() => _readErrors[key] = _describeError(error));
        }
      }),
    );
  }

  String _describeError(Object error) {
    if (error is TimeoutException) return 'Сервер не ответил вовремя.';
    final message = error.toString();
    if (message.toUpperCase().contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'Не удалось проверить сертификат сервера.';
    }
    return message.replaceFirst(RegExp(r'^Exception: '), '');
  }

  double? _value(_RateKey key) {
    final value = _rates[key]?.value;
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  double? _divide(double? a, double? b) =>
      a == null || b == null || b == 0 ? null : a / b;

  double? _multiply(double? a, double? b) =>
      a == null || b == null ? null : a * b;

  String _format(double? value, [int digits = 2]) =>
      value == null || !value.isFinite ? '—' : value.toStringAsFixed(digits);

  String _resultText() {
    final cbrUsd = _value(_RateKey.cbrUsd);
    final cbrVnd = _value(_RateKey.cbrVnd);
    final bybitUsdtVnd = _value(_RateKey.bybit);
    final tbankQrRubVnd = _value(_RateKey.tbankQr);
    final tbankTransferRubVnd = _value(_RateKey.tbankTransfer);
    final usdtRub = _multiply(cbrUsd, 1.005);
    final bybitVndRub = _divide(usdtRub, bybitUsdtVnd);
    final tbankQrVndRub = _divide(1, tbankQrRubVnd);
    final tbankTransferVndRub = _divide(1, tbankTransferRubVnd);
    final costs = [cbrVnd, bybitVndRub, tbankQrVndRub, tbankTransferVndRub];
    final buffer = StringBuffer('📊 КУРСЫ ВАЛЮТ\n\n');

    buffer.writeln(
      compactTableText([
        ['', 'ЦБ РФ', 'Bybit', 'T-QR', 'T-tr'],
        ['VND/RUB', ...costs.map((cost) => _format(_multiply(cost, 10000)))],
        ['USD/RUB', _format(cbrUsd), _format(usdtRub), '—', '—'],
        [
          'USD/VND',
          _format(_divide(cbrUsd, cbrVnd), 0),
          _format(bybitUsdtVnd, 0),
          '—',
          '—',
        ],
        [
          'RUB/VND',
          _format(_divide(1, cbrVnd), 1),
          _format(_divide(1, bybitVndRub), 1),
          _format(tbankQrRubVnd, 1),
          _format(tbankTransferRubVnd, 1),
        ],
        [
          'к ЦБ %',
          ...costs.map((cost) {
            final relative = _divide(cost, cbrVnd);
            final loss = relative == null ? null : (relative - 1) * 100;
            return '${loss != null && loss > 0 ? '+' : ''}${_format(loss)}';
          }),
        ],
      ]),
    );

    final amountVnd = _multiply(_amountThousands, 1000);
    final amountUsdt = _divide(amountVnd, bybitUsdtVnd);
    final rubCbr = _multiply(cbrVnd, amountVnd);
    String price(double? cost) {
      final rub = _multiply(cost, amountVnd);
      final difference = rub == null || rubCbr == null ? null : rub - rubCbr;
      final sign = difference != null && difference >= 0 ? '+' : '';
      return '${_format(rub)} ₽ ($sign${_format(difference)} ₽)';
    }

    buffer.writeln('\n💰 ${_format(amountVnd, 0)} VND:');
    buffer.writeln(
      '  Bybit:   ${price(bybitVndRub)} · ${_format(amountUsdt, 4)} USDT',
    );
    buffer.writeln('  T-QR:    ${price(tbankQrVndRub)}');
    buffer.writeln('  T-tr:    ${price(tbankTransferVndRub)}');
    buffer.write('  ЦБ РФ:   ${_format(rubCbr)} ₽');
    return buffer.toString();
  }

  Widget _sourceStatus(String source, String label) {
    final error = _sourceErrors[source];
    if (error != null) {
      final hasSaved = _RateKey.values.any(
        (key) => key.source == source && _value(key) != null,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$label: не удалось обновить. $error '
          '${hasSaved ? 'Используются сохранённые данные.' : 'Сохранённых данных нет.'}',
          key: ValueKey('error-$source'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      );
    }
    if (_pendingSources.contains(source)) {
      return Text('$label: обновление…', style: const TextStyle(fontSize: 12));
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Курсы валют'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshAllRates,
            tooltip: 'Обновить все курсы',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _isLoadingLocal
                      ? 'Загрузка сохранённых данных…'
                      : _resultText(),
                  key: const ValueKey('rate-results'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('amount-input'),
                    initialValue: '10',
                    decoration: InputDecoration(
                      labelText: 'Сумма (тыс. VND)',
                      errorText: _amountError,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (value) {
                      final parsed = double.tryParse(
                        value.trim().replaceAll(',', '.'),
                      );
                      final valid =
                          parsed != null &&
                          parsed.isFinite &&
                          parsed > 0 &&
                          (parsed * 1000).isFinite;
                      setState(() {
                        _amountThousands = valid ? parsed : null;
                        _amountError = valid
                            ? null
                            : (value.trim().isEmpty
                                  ? 'Введите сумму'
                                  : 'Введите число больше нуля');
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    );
                    if (!mounted) return;
                    await _loadRates(_RateKey.values);
                    if (!mounted) return;
                    _graphKey.currentState?.refresh();
                  },
                  child: const Text('Ввести курсы'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _sourceStatus(Sources.cbr, 'ЦБ РФ'),
            _sourceStatus(Sources.tbankTransfer, 'Т-Банк перевод'),
            for (final entry in _readErrors.entries)
              Text(
                '${entry.key.label}: ошибка чтения сохранённого курса. ${entry.value}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 8),
            widget.historyChart ?? HistoryChart(key: _graphKey),
          ],
        ),
      ),
    );
  }
}
