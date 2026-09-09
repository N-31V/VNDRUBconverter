import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/database_helper.dart';
import 'services/cbr_api.dart';
import 'services/tbank_api.dart';
import 'constants.dart';
import 'screens/settings_screen.dart';

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
  double? _cbrUsd;
  double? _cbrVnd;
  double? _bybitUsdtVnd;
  double? _tbankQrVndRub; // VND за 1 RUB (из БД)
  double? _tbankTransferVndRub; // VND за 1 RUB

  int _amountThousands = 10;
  String _resultText = 'Загрузка данных...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshAllRates(); // обновляем при запуске
  }


  // Обновить все курсы (ЦБ + Т-Банк)
  Future<void> _refreshAllRates() async {
    setState(() => _isLoading = true);
    try {
      // Обновляем ЦБ
      await CbrApiClient.fetchAndSaveRates();
      // Обновляем Т-Банк
      await TbankApiClient.fetchAndSaveTbankRates();
      // Загружаем данные в UI
      await _loadData();
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
    final double cbrVndVal = _cbrVnd!; // VND/RUB (за 1 VND)
    final double bybitUsdtVndVal = _bybitUsdtVnd!;
    final double tbankQrRubVnd = _tbankQrVndRub!; // VND/RUB (сколько VND за 1 RUB)
    final double tbankTransferRubVnd = _tbankTransferVndRub!;

    // Аппроксимация USDT/RUB = USD/RUB * 1.005
    const double usdtSpread = 1.005;
    final double usdtRubVal = cbrUsdVal * usdtSpread;

    // Производные курсы для каждого источника
    final cbrVndRub10000 = cbrVndVal * 10000; // 10000 VND в рублях
    final cbrUsdRub = cbrUsdVal;
    final cbrUsdVnd = cbrUsdVal / cbrVndVal;
    final cbrRubVnd = 1 / cbrVndVal;

    final bybitVndRub = usdtRubVal / bybitUsdtVndVal; // VND/RUB
    final bybitVndRub10000 = bybitVndRub * 10000;
    final bybitUsdRub = usdtRubVal;
    final bybitUsdVnd = bybitUsdtVndVal;
    final bybitRubVnd = 1 / bybitVndRub;

    // Т-банк QR: у нас уже VND/RUB, пересчитываем
    final tbankQrVndRub10000 = 10000 / tbankQrRubVnd; // сколько руб за 10000 VND

    final tbankTransferVndRub10000 = 10000 / tbankTransferRubVnd;

    // Потери в процентах (относительно ЦБ VND/RUB)
    final lossBybit = ((bybitVndRub - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankQr = ((1 / tbankQrRubVnd - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankTransfer = ((1 / tbankTransferRubVnd - cbrVndVal) / cbrVndVal) * 100;

    // Формируем таблицу
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

    buffer.writeln('\n💡 Для Bybit USDT/RUB = USD/RUB × 1.005');

    // Расчёт стоимости для введённой суммы
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Сумма (тыс. VND)',
                      border: OutlineInputBorder(),
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
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    );
                    _loadData(); // перезагружаем данные после возврата
                  },
                  child: Text('Ввести курсы'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _resultText,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}