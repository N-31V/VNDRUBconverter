import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rate.dart';
import '../services/database_helper.dart';
import '../constants.dart';

class CbrApiClient {
  static const String _url = 'https://www.cbr.ru/scripts/XML_daily.asp';
  static const String _lastUpdateKey = 'cbr_last_update_date'; // ключ для SharedPreferences

  /// Проверить, был ли уже запрос сегодня
  Future<bool> isTodayUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString(_lastUpdateKey);
    if (lastDateStr == null) return false;
    final lastDate = DateTime.tryParse(lastDateStr);
    if (lastDate == null) return false;
    final now = DateTime.now();
    // Сравниваем год, месяц, день
    return lastDate.year == now.year &&
        lastDate.month == now.month &&
        lastDate.day == now.day;
  }

  /// Сохранить дату сегодняшнего обновления
  Future<void> _saveUpdateDate() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_lastUpdateKey, now.toIso8601String());
  }

  /// Загрузить и сохранить курсы. Если force = true, игнорировать проверку даты.
  Future<bool> fetchAndSaveRates({bool force = false}) async {
    // Если не принудительно и уже обновлялись сегодня — выходим
    if (!force && await isTodayUpdated()) {
      print('Курсы ЦБ уже обновлены сегодня. Запрос пропущен.');
      return false;
    }

    try {
      final response = await http.get(Uri.parse(_url));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final document = XmlDocument.parse(response.body);

      // USD
      final usdNode = document.findAllElements('Valute').firstWhere(
            (node) => node.findElements('CharCode').single.text == 'USD',
      );
      final usdValueStr = usdNode.findElements('Value').single.text;
      final usdNominalStr = usdNode.findElements('Nominal').single.text;
      final usdValue = double.parse(usdValueStr.replaceFirst(',', '.'));
      final usdNominal = int.parse(usdNominalStr);
      final usdRub = usdValue / usdNominal;

      // VND
      final vndNode = document.findAllElements('Valute').firstWhere(
            (node) => node.findElements('CharCode').single.text == 'VND',
      );
      final vndValueStr = vndNode.findElements('Value').single.text;
      final vndNominalStr = vndNode.findElements('Nominal').single.text;
      final vndValue = double.parse(vndValueStr.replaceFirst(',', '.'));
      final vndNominal = int.parse(vndNominalStr);
      final vndRub = vndValue / vndNominal;

      // Сохраняем в БД
      final db = DatabaseHelper();
      await db.insertRate(Rate(
        base: Currencies.usd,
        quote: Currencies.rub,
        value: usdRub,
        source: Sources.cbr,
        timestamp: DateTime.now(),
      ));
      await db.insertRate(Rate(
        base: Currencies.vnd,
        quote: Currencies.rub,
        value: vndRub,
        source: Sources.cbr,
        timestamp: DateTime.now(),
      ));

      // Сохраняем дату обновления
      await _saveUpdateDate();

      print('Курсы ЦБ сохранены. USD/RUB = $usdRub, VND/RUB = $vndRub');
      return true;
    } catch (e) {
      throw Exception('Ошибка получения курсов ЦБ: $e');
    }
  }
}