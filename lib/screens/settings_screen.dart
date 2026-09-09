import 'package:flutter/material.dart';
import '../services/cbr_api.dart';
import '../services/database_helper.dart';
import '../models/rate.dart';
import '../constants.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bybitQrController = TextEditingController();
  final _tbankQrController = TextEditingController();
  final _tbankTransferController = TextEditingController();
  bool _loading = false;
  bool _updatingCbr = false;

  @override
  void initState() {
    super.initState();
    // Загружаем последние значения после первой отрисовки
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLastValues();
    });
    _updateCbrRates();
  }

  @override
  void dispose() {
    _bybitQrController.dispose();
    _tbankQrController.dispose();
    _tbankTransferController.dispose();
    super.dispose();
  }

  // Загружаем последние сохранённые курсы и подставляем в поля
  Future<void> _loadLastValues() async {
    try {
      final db = DatabaseHelper();
      final bybitQr = await db.getLatestRate(Sources.bybitQr, Currencies.usdt, Currencies.vnd);
      final tbankQr = await db.getLatestRate(Sources.tbankQr, Currencies.vnd, Currencies.rub);
      final tbankTransfer = await db.getLatestRate(Sources.tbankTransfer, Currencies.vnd, Currencies.rub);

      if (!mounted) return;
      setState(() {
        if (bybitQr != null) {
          _bybitQrController.text = bybitQr.value.toStringAsFixed(0);
        } else {
          _bybitQrController.text = ''; // если нет — оставляем пустым, placeholder сработает
        }
        if (tbankQr != null) {
          _tbankQrController.text = (tbankQr.value * 10000).toStringAsFixed(2);
        } else {
          _tbankQrController.text = '';
        }
        if (tbankTransfer != null) {
          _tbankTransferController.text = (tbankTransfer.value * 10000).toStringAsFixed(2);
        } else {
          _tbankTransferController.text = '';
        }
      });
    } catch (e) {
      print('Ошибка загрузки последних курсов: $e');
      // Не показываем ошибку пользователю, просто оставляем поля пустыми
    }
  }

  Future<void> _updateCbrRates() async {
    if (_updatingCbr) return;
    setState(() => _updatingCbr = true);
    try {
      final cbr = CbrApiClient();
      await cbr.fetchAndSaveRates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курсы ЦБ обновлены')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления ЦБ: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingCbr = false);
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
      await db.insertRate(Rate(
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

  Future<void> _saveTbankQr() async {
    final rubPer10000 = double.tryParse(_tbankQrController.text.replaceAll(',', '.'));
    if (rubPer10000 == null || rubPer10000 <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Введите корректный курс (руб за 10000 VND), например 34.67')),
      );
      return;
    }
    final rubPer1Vnd = rubPer10000 / 10000;
    setState(() => _loading = true);
    try {
      final db = DatabaseHelper();
      await db.insertRate(Rate(
        base: Currencies.vnd,
        quote: Currencies.rub,
        value: rubPer1Vnd,
        source: Sources.tbankQr,
        timestamp: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курс Т-банк QR сохранён: ${rubPer10000.toStringAsFixed(2)} руб за 10000 VND')),
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

  Future<void> _saveTbankTransfer() async {
    final rubPer10000 = double.tryParse(_tbankTransferController.text.replaceAll(',', '.'));
    if (rubPer10000 == null || rubPer10000 <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Введите корректный курс (руб за 10000 VND), например 36.33')),
      );
      return;
    }
    final rubPer1Vnd = rubPer10000 / 10000;
    setState(() => _loading = true);
    try {
      final db = DatabaseHelper();
      await db.insertRate(Rate(
        base: Currencies.vnd,
        quote: Currencies.rub,
        value: rubPer1Vnd,
        source: Sources.tbankTransfer,
        timestamp: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Курс Т-банк перевод сохранён: ${rubPer10000.toStringAsFixed(2)} руб за 10000 VND')),
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
      appBar: AppBar(
        title: Text('Ручной ввод курсов'),
        actions: [
          if (_updatingCbr)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  _buildInputSection(
                    title: 'Bybit QR (USDT/VND)',
                    hint: 'например 24800',
                    controller: _bybitQrController,
                    onSave: _saveBybitQr,
                    isLoading: _loading,
                  ),
                  _buildInputSection(
                    title: 'Т-банк QR (руб за 10000 VND)',
                    hint: 'например 34.67',
                    controller: _tbankQrController,
                    onSave: _saveTbankQr,
                    isLoading: _loading,
                  ),
                  _buildInputSection(
                    title: 'Т-банк перевод (руб за 10000 VND)',
                    hint: 'например 36.33',
                    controller: _tbankTransferController,
                    onSave: _saveTbankTransfer,
                    isLoading: _loading,
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
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
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