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

      final qrRateObj = rates.firstWhere(
            (r) => r['category'] == 'DebitCardsOperations',
        orElse: () => throw Exception('Категория DebitCardsOperations не найдена'),
      );
      final transferRateObj = rates.firstWhere(
            (r) => r['category'] == 'DebitCardsTransfers',
        orElse: () => throw Exception('Категория DebitCardsTransfers не найдена'),
      );

      final qrSell = (qrRateObj['buy'] as num).toDouble(); // VND за 1 RUB
      final transferSell = (transferRateObj['buy'] as num).toDouble();

      final db = DatabaseHelper();
      await db.insertRateIfChanged(Rate(
        base: Currencies.rub,
        quote: Currencies.vnd,
        value: qrSell,
        source: Sources.tbankQr,
        timestamp: DateTime.now(),
      ));
      await db.insertRateIfChanged(Rate(
        base: Currencies.rub,
        quote: Currencies.vnd,
        value: transferSell,
        source: Sources.tbankTransfer,
        timestamp: DateTime.now(),
      ));

      print('Курсы Т-Банка сохранены: QR = $qrSell VND/RUB, Transfer = $transferSell VND/RUB');
    } catch (e) {
      throw Exception('Ошибка получения курсов Т-Банка: $e');
    }
  }
}