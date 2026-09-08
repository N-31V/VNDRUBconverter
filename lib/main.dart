import 'package:flutter/material.dart';
import 'services/database_helper.dart';
import 'constants.dart';
import 'screens/settings_screen.dart';

void main() async {
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
  double? _tbankQrVndRub;
  double? _tbankTransferVndRub;

  int _amountThousands = 10;
  String _resultText = 'Загрузка данных...';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = DatabaseHelper();

      final cbrUsd = await db.getLatestRate(Sources.cbr, Currencies.usd, Currencies.rub);
      final cbrVnd = await db.getLatestRate(Sources.cbr, Currencies.vnd, Currencies.rub);
      final bybitQr = await db.getLatestRate(Sources.bybitQr, Currencies.usdt, Currencies.vnd);
      final tbankQr = await db.getLatestRate(Sources.tbankQr, Currencies.vnd, Currencies.rub);
      final tbankTransfer = await db.getLatestRate(Sources.tbankTransfer, Currencies.vnd, Currencies.rub);

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
      });
    }
  }

  void _updateResult() {
    if (_cbrUsd == null || _cbrVnd == null || _bybitUsdtVnd == null ||
        _tbankQrVndRub == null || _tbankTransferVndRub == null) {
      setState(() {
        _resultText = 'Не все курсы загружены. Введите недостающие курсы через "Ввести курсы".';
      });
      return;
    }

    final double cbrUsdVal = _cbrUsd!;
    final double cbrVndVal = _cbrVnd!;
    final double bybitUsdtVndVal = _bybitUsdtVnd!;
    final double tbankQrVal = _tbankQrVndRub!;
    final double tbankTransferVal = _tbankTransferVndRub!;

    const double usdtSpread = 1.005;
    final double usdtRubVal = cbrUsdVal * usdtSpread;

    // Производные курсы
    final cbrVndRub10000 = cbrVndVal * 10000;
    final cbrUsdRub = cbrUsdVal;
    final cbrUsdVnd = cbrUsdVal / cbrVndVal;
    final cbrRubVnd = 1 / cbrVndVal;

    final bybitVndRub = usdtRubVal / bybitUsdtVndVal;
    final bybitVndRub10000 = bybitVndRub * 10000;
    final bybitUsdRub = usdtRubVal;
    final bybitUsdVnd = bybitUsdtVndVal;
    final bybitRubVnd = 1 / bybitVndRub;

    final tbankQrVndRub10000 = tbankQrVal * 10000;
    final tbankQrRubVnd = 1 / tbankQrVal;

    final tbankTransferVndRub10000 = tbankTransferVal * 10000;
    final tbankTransferRubVnd = 1 / tbankTransferVal;

    // Потери в процентах (относительно ЦБ)
    final lossBybit = ((bybitVndRub - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankQr = ((tbankQrVal - cbrVndVal) / cbrVndVal) * 100;
    final lossTbankTransfer = ((tbankTransferVal - cbrVndVal) / cbrVndVal) * 100;

    // Формируем таблицу
    final buffer = StringBuffer();

    buffer.writeln('📊 КУРСЫ ВАЛЮТ\n');
    buffer.writeln('        | ЦБ РФ | Bybit | T-QR  | T-tr');
    buffer.writeln('--------|-------|-------|-------|------');

    // Строка 1: 10k VND/RUB
    buffer.writeln(
        'VND/RUB | ${cbrVndRub10000.toStringAsFixed(2)} | ${bybitVndRub10000.toStringAsFixed(2)} | ${tbankQrVndRub10000.toStringAsFixed(2)} | ${tbankTransferVndRub10000.toStringAsFixed(2)}');

    // Строка 2: USD/RUB
    buffer.writeln(
        'USD/RUB | ${cbrUsdRub.toStringAsFixed(2)} | ${bybitUsdRub.toStringAsFixed(2)} | —     | —');

    // Строка 3: USD/VND
    buffer.writeln(
        'USD/VND | ${cbrUsdVnd.toStringAsFixed(0)} | ${bybitUsdVnd.toStringAsFixed(0)} | —     | —');

    // Строка 4: RUB/VND
    buffer.writeln(
        'RUB/VND | ${cbrRubVnd.toStringAsFixed(1)} | ${bybitRubVnd.toStringAsFixed(1)} | ${tbankQrRubVnd.toStringAsFixed(1)} | ${tbankTransferRubVnd.toStringAsFixed(1)}');

    // Строка 5: Потери (%)
    buffer.writeln(
        'loss %  | 0.00  | ${lossBybit.toStringAsFixed(2)}  | ${lossTbankQr.toStringAsFixed(2)}  | ${lossTbankTransfer.toStringAsFixed(2)}');

    buffer.writeln('\n💡 Для Bybit USDT/RUB = USD/RUB × 1.005');

    // Расчёт стоимости для введённой суммы
    final amountVnd = _amountThousands * 1000.0;
    final rubBybit = amountVnd * bybitVndRub;
    final rubTbankQr = amountVnd * tbankQrVal;
    final rubTbankTransfer = amountVnd * tbankTransferVal;
    final rubCbr = amountVnd * cbrVndVal;

    // Потери в рублях (абсолютные)
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
      appBar: AppBar(title: Text('Курсы валют')),
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
                    _loadData();
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