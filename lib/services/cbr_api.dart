import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../constants.dart';
import '../models/rate.dart';
import 'database_helper.dart';
import 'rate_fetch_exception.dart';

class CbrApiClient {
  static final _url = Uri.https('www.cbr-xml-daily.ru', '/daily_utf8.xml');

  static Future<void> fetchAndSaveRates({
    http.Client? client,
    Future<void> Function(Rate)? saveRate,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final activeClient = client ?? http.Client();
    try {
      final response = await activeClient.get(_url).timeout(timeout);
      if (response.statusCode != 200) {
        throw RateFetchException('Сервер вернул HTTP ${response.statusCode}');
      }
      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final now = DateTime.now();
      // Validate both values before saving either of them.
      final rates = [Currencies.usd, Currencies.vnd].map((currency) {
        final node = document
            .findAllElements('Valute')
            .where((node) => node.getElement('CharCode')?.innerText == currency)
            .firstOrNull;
        final value = double.tryParse(
          (node?.getElement('Value')?.innerText ?? '').replaceAll(',', '.'),
        );
        final nominal = int.tryParse(
          node?.getElement('Nominal')?.innerText ?? '',
        );
        if (value == null ||
            !value.isFinite ||
            value <= 0 ||
            nominal == null ||
            nominal <= 0) {
          throw const FormatException('Invalid CBR rate');
        }
        return Rate(
          base: currency,
          quote: Currencies.rub,
          value: value / nominal,
          source: Sources.cbr,
          timestamp: now,
        );
      }).toList();
      for (final rate in rates) {
        await (saveRate ?? DatabaseHelper().insertRateIfChanged)(rate);
      }
    } catch (error) {
      throw RateFetchException.from(error);
    } finally {
      if (client == null) activeClient.close();
    }
  }
}
