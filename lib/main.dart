import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/database_helper.dart';
import 'services/cbr_api.dart';
import 'services/tbank_api.dart';
import 'constants.dart';
import 'screens/settings_screen.dart';
import 'widgets/history_chart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Currency Tracker',
      theme: ThemeData.dark(),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Ключ для доступа к состоянию HistoryChart
  final GlobalKey<HistoryChartState> _graphKey = GlobalKey<HistoryChartState>();

  double? _cbrUsd;
  double? _cbrVnd;
  double? _bybitUsdtVnd;
  double? _tbankQrVndRub;
  double? _tbankTransferVndRub;

  int _amountThousands = 10;
  String _resultText = 'Загрузка данных...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshAllRates();
  }

  // Обновить все курсы (ЦБ + Т-Банк) и график
  Future<void> _refreshAllRates() async {
    setState(() => _isLoading = true);
    try {
      await CbrApiClient.fetchAndSaveRates();
      await TbankApiClient.fetchAndSaveTbankRates();
      await _loadData();
      // Обновляем график
      _graphKey.currentState?.refresh();
    } catch (e) {
      setState(() {
        _resultText = 'Ошибка обновления: $e';
        _isLoading = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Загрузка данных из БД
  Future<void> _loadData() async {
    try {
      final db = DatabaseHelper();

      final cbrUsd = await db.getLatestRate(Sources.cbr, Currencies.usd, Currencies.rub);
      final cbrVnd = await db.getLatestRate(Sources.cbr, Currencies.vnd, Currencies.rub);
      final bybitQr = await db.getLatestRate(Sources.bybitQr, Currencies.usdt, Currencies.vnd);
      final tbankQr = await db.getLatestRate(Sources.tbankQr, Currencies.rub, Currencies.vnd);
      final tbankTransfer = await db.getLatestRate(Sources.tbankTransfer, Currencies.rub, Currencies.vnd);

      setState(() {
        _cbrUsd = cbrUsd?.value;
        _cbrVnd = cbrVnd?.value;
        _bybitUsdtVnd = bybitQr?.value;
        _tbankQrVndRub = tbankQr?.value;
        _tbankTransferVndRub = tbankTransfer?.value;
      });

      _updateResult();
    } catch (e) {
      setState(() {
        _resultText = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  void _updateResult() {
    if (_cbrUsd == null || _cbrVnd == null || _bybitUsdtVnd == null ||
        _tbankQrVndRub == null || _tbankTransferVndRub == null) {
      setState(() {
        _resultText = 'Не все курсы загружены. Обновите данные или введите вручную.';
      });
      return;
    }

    final double cbrUsdVal = _cbrUsd!;
    final double cbrVndVal = _cbrVnd!;
    final double bybitUsdtVndVal = _bybitUsdtVnd!;
    final double tbankQrRubVnd = _tbankQrVndRub!;
    final double tbankTransferRubVnd = _tbankTransferVndRub!;

    const double usdtSpread = 1.005;
    final double usdtRubVal = cbrUsdVal * usdtSpread;

    final cbrVndRub10000 = cbrVndVal * 10000;
    final cbrUsdRub = cbrUsdVal;
    final cbrUsdVnd = cbrUsdVal / cbrVndVal;
    final cbrRubVnd = 1 / cbrVndVal;

    final bybitVndRub = usdtRubVal / bybitUsdtVndVal;
    final bybitVndRub10000 = bybitVndRub * 10000;
    final bybitUsdRub = usdtRubVal;
    final bybitUsdVnd = bybitUsdtVndVal;
    final bybitRubVnd = 1 / bybitVndRub;

    final tbankQrVndRub10000 = 10000 / tbankQrRubVnd;
    final tbankTransferVndRub10000 = 10000 / tbankTransferRubVnd;

    final lossBybit = ((bybitVndRub - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankQr = ((1 / tbankQrRubVnd - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankTransfer = ((1 / tbankTransferRubVnd - cbrVndVal) / cbrVndVal) * 100;

    final buffer = StringBuffer();

    buffer.writeln('📊 КУРСЫ ВАЛЮТ\n');
    buffer.writeln('        | ЦБ РФ | Bybit | T-QR  | T-tr');
    buffer.writeln('--------|-------|-------|-------|------');

    buffer.writeln(
        'VND/RUB | ${cbrVndRub10000.toStringAsFixed(2)} | ${bybitVndRub10000.toStringAsFixed(2)} | ${tbankQrVndRub10000.toStringAsFixed(2)} | ${tbankTransferVndRub10000.toStringAsFixed(2)}');

    buffer.writeln(
        'USD/RUB | ${cbrUsdRub.toStringAsFixed(2)} | ${bybitUsdRub.toStringAsFixed(2)} | —     | —');

    buffer.writeln(
        'USD/VND | ${cbrUsdVnd.toStringAsFixed(0)} | ${bybitUsdVnd.toStringAsFixed(0)} | —     | —');

    buffer.writeln(
        'RUB/VND | ${cbrRubVnd.toStringAsFixed(1)} | ${bybitRubVnd.toStringAsFixed(1)} | ${tbankQrRubVnd.toStringAsFixed(1)} | ${tbankTransferRubVnd.toStringAsFixed(1)}');

    buffer.writeln(
        'loss %  | 0.00  | ${lossBybit.toStringAsFixed(2)}  | ${lossTbankQr.toStringAsFixed(2)}  | ${lossTbankTransfer.toStringAsFixed(2)}');

    final amountVnd = _amountThousands * 1000.0;
    final rubBybit = amountVnd * bybitVndRub;
    final rubTbankQr = amountVnd * (1 / tbankQrRubVnd);
    final rubTbankTransfer = amountVnd * (1 / tbankTransferRubVnd);
    final rubCbr = amountVnd * cbrVndVal;

    final lossRubBybit = rubBybit - rubCbr;
    final lossRubTbankQr = rubTbankQr - rubCbr;
    final lossRubTbankTransfer = rubTbankTransfer - rubCbr;

    buffer.writeln('\n💰 ${amountVnd.toStringAsFixed(0)} VND:');
    buffer.writeln(
        '  Bybit:   ${rubBybit.toStringAsFixed(2)} руб  (+ ${lossRubBybit.toStringAsFixed(2)} руб)');
    buffer.writeln(
        '  T-QR:    ${rubTbankQr.toStringAsFixed(2)} руб  (+ ${lossRubTbankQr.toStringAsFixed(2)} руб)');
    buffer.writeln(
        '  T-trans: ${rubTbankTransfer.toStringAsFixed(2)} руб  (+ ${lossRubTbankTransfer.toStringAsFixed(2)} руб)');
    buffer.writeln(
        '  ЦБ РФ:   ${rubCbr.toStringAsFixed(2)} руб');

    setState(() {
      _resultText = buffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Курсы валют'),
        actions: [
          IconButton(
            icon: _isLoading
                ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshAllRates,
            tooltip: 'Обновить все курсы',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Таблица – занимает ровно столько, сколько нужно
            Flexible(
              fit: FlexFit.loose,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _resultText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
            SizedBox(height: 6),
            // Поле ввода и кнопка
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Сумма (тыс. VND)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final int? parsed = int.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          _amountThousands = parsed;
                        });
                        _updateResult();
                      }
                    },
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    );
                    await _loadData();
                    _graphKey.currentState?.refresh();
                  },
                  child: Text('Ввести курсы'),
                ),
              ],
            ),
            SizedBox(height: 6),
            // График – с ключом для обновления
            Expanded(
              child: HistoryChart(key: _graphKey),
            ),
          ],
        ),
      ),
    );
  }
}