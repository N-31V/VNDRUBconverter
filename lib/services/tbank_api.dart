import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/rate.dart';
import '../services/database_helper.dart';
import '../constants.dart';

class TbankApiClient {
  static const String _url = 'https://www.tbank.ru/api/common/v1/currency_rates?from=RUB&to=VND';

  static Future<void> fetchAndSaveTbankRates() async {
    try {
      final response = await http.get(Uri.parse(_url));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data['resultCode'] != 'OK') {
        throw Exception('API ошибка: ${data['resultCode']}');
      }

      final rates = data['payload']['rates'] as List;

      final transferRateObj = rates.firstWhere(
            (r) => r['category'] == 'DebitCardsTransfers',
        orElse: () => throw Exception('Категория DebitCardsTransfers не найдена'),
      );

      final transferSell = (transferRateObj['buy'] as num).toDouble();

      final db = DatabaseHelper();
      await db.insertRateIfChanged(Rate(
        base: Currencies.rub,
        quote: Currencies.vnd,
        value: transferSell,
        source: Sources.tbankTransfer,
        timestamp: DateTime.now(),
      ));

      print('Курс Т-Банка (перевод) сохранён: $transferSell VND/RUB');
    } catch (e) {
      throw Exception('Ошибка получения курса Т-Банка: $e');
    }
  }
}