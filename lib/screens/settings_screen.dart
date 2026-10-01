import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../models/rate.dart';
import '../constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.database});

  final DatabaseHelper? database;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bybitRubController = TextEditingController();
  final _bybitQrController = TextEditingController();
  final _tbankQrController = TextEditingController();
  final _editedControllers = <TextEditingController>{};
  bool _loading = false;

  DatabaseHelper get _database => widget.database ?? DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadLastValues();
  }

  @override
  void dispose() {
    _bybitRubController.dispose();
    _bybitQrController.dispose();
    _tbankQrController.dispose();
    super.dispose();
  }

  Future<void> _loadLastValues() async {
    await Future.wait([
      _loadLastValue(
        controller: _bybitRubController,
        source: Sources.bybitQr,
        base: Currencies.usdt,
        quote: Currencies.rub,
        format: (value) => value.toString(),
      ),
      _loadLastValue(
        controller: _bybitQrController,
        source: Sources.bybitQr,
        base: Currencies.usdt,
        quote: Currencies.vnd,
        format: (value) => value.toStringAsFixed(0),
      ),
      _loadLastValue(
        controller: _tbankQrController,
        source: Sources.tbankQr,
        base: Currencies.rub,
        quote: Currencies.vnd,
        format: (value) => (10000 / value).toStringAsFixed(2),
      ),
    ]);
  }

  Future<void> _loadLastValue({
    required TextEditingController controller,
    required String source,
    required String base,
    required String quote,
    required String Function(double) format,
  }) async {
    try {
      final rate = await _database.getLatestRate(source, base, quote);
      if (!mounted || _editedControllers.contains(controller)) return;
      if (rate != null) controller.text = format(rate.value);
    } catch (e) {
      debugPrint('Ошибка загрузки последних курсов: $e');
    }
  }

  Future<void> _saveBybitRub() async {
    final value = double.tryParse(
      _bybitRubController.text.replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректный курс USDT/RUB (например 92.50)'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _database.insertRateIfChanged(
        Rate(
          base: Currencies.usdt,
          quote: Currencies.rub,
          value: value,
          source: Sources.bybitQr,
          timestamp: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курс Bybit сохранён: $value руб за 1 USDT')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveBybitQr() async {
    final value = double.tryParse(_bybitQrController.text.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите корректный курс USDT/VND (например 24800)'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _database.insertRateIfChanged(
        Rate(
          base: Currencies.usdt,
          quote: Currencies.vnd,
          value: value,
          source: Sources.bybitQr,
          timestamp: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курс Bybit QR сохранён: $value VND за 1 USDT')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveTbankQr() async {
    final rubPer10000 = double.tryParse(
      _tbankQrController.text.replaceAll(',', '.'),
    );
    if (rubPer10000 == null || !rubPer10000.isFinite || rubPer10000 <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Введите корректный курс (руб за 10000 VND), например 35.60',
          ),
        ),
      );
      return;
    }
    // Пересчитываем в VND за 1 RUB
    final vndPerRub = 10000 / rubPer10000;
    setState(() => _loading = true);
    try {
      await _database.insertRateIfChanged(
        Rate(
          base: Currencies.rub,
          quote: Currencies.vnd,
          value: vndPerRub,
          source: Sources.tbankQr,
          timestamp: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Курс Т-банк QR сохранён: ${rubPer10000.toStringAsFixed(2)} руб за 10000 VND',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
                  _buildInputSection(
                    title: 'Bybit (USDT/RUB)',
                    hint: 'например 92.50',
                    controller: _bybitRubController,
                    onSave: _saveBybitRub,
                    isLoading: _loading,
                  ),
                  _buildInputSection(
                    title: 'Bybit QR (USDT/VND)',
                    hint: 'например 24800',
                    controller: _bybitQrController,
                    onSave: _saveBybitQr,
                    isLoading: _loading,
                  ),
                  _buildInputSection(
                    title: 'Т-банк QR (руб за 10000 VND)',
                    hint: 'например 35.60',
                    controller: _tbankQrController,
                    onSave: _saveTbankQr,
                    isLoading: _loading,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Курс Т-Банка для переводов обновляется автоматически.\nКурс для QR-оплаты вводится вручную (см. на экране подтверждения платежа).',
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

  Widget _buildInputSection({
    required String title,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onSave,
    required bool isLoading,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: (_) => _editedControllers.add(controller),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: isLoading ? null : onSave,
                  child: Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
