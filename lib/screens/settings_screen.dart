import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../models/rate.dart';
import '../constants.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bybitQrController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLastValues();
    });
  }

  @override
  void dispose() {
    _bybitQrController.dispose();
    super.dispose();
  }

  Future<void> _loadLastValues() async {
    try {
      final db = DatabaseHelper();
      final bybitQr = await db.getLatestRate(Sources.bybitQr, Currencies.usdt, Currencies.vnd);
      if (!mounted) return;
      setState(() {
        if (bybitQr != null) {
          _bybitQrController.text = bybitQr.value.toStringAsFixed(0);
        }
      });
    } catch (e) {
      print('Ошибка загрузки последних курсов: $e');
    }
  }

  Future<void> _saveBybitQr() async {
    final value = double.tryParse(_bybitQrController.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Введите корректный курс USDT/VND (например 24800)')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final db = DatabaseHelper();
      await db.insertRateIfChanged(Rate(
        base: Currencies.usdt,
        quote: Currencies.vnd,
        value: value,
        source: Sources.bybitQr,
        timestamp: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курс Bybit QR сохранён: $value VND за 1 USDT')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ручной ввод курсов')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bybit QR (USDT/VND)', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bybitQrController,
                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    hintText: 'например 24800',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _loading ? null : _saveBybitQr,
                                child: Text('Сохранить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Курсы Т-Банка обновляются автоматически.\nРучной ввод не требуется.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              child: Text('Назад'),
            ),
          ],
        ),
      ),
    );
  }
}