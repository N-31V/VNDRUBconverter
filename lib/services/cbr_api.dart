import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/rate.dart';
import '../services/database_helper.dart';
import '../constants.dart';

class CbrApiClient {
  static const String _url = 'https://www.cbr.ru/scripts/XML_daily.asp';

  static Future<void> fetchAndSaveRates() async {
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

      final db = DatabaseHelper();
      await db.insertRateIfChanged(Rate(
        base: Currencies.usd,
        quote: Currencies.rub,
        value: usdRub,
        source: Sources.cbr,
        timestamp: DateTime.now(),
      ));
      await db.insertRateIfChanged(Rate(
        base: Currencies.vnd,
        quote: Currencies.rub,
        value: vndRub,
        source: Sources.cbr,
        timestamp: DateTime.now(),
      ));

      print('Курсы ЦБ сохранены: USD/RUB = $usdRub, VND/RUB = $vndRub');
    } catch (e) {
      throw Exception('Ошибка получения курсов ЦБ: $e');
    }
  }
}