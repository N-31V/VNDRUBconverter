import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/rate.dart';
import 'database_helper.dart';
import 'rate_fetch_exception.dart';
import 'tbank_http_client.dart';

class TbankApiClient {
  static final _url = Uri.https(
    'www.tbank.ru',
    '/api/common/v1/currency_rates',
    {'from': 'RUB', 'to': 'VND'},
  );

  static Future<void> fetchAndSaveTbankRates({
    http.Client? client,
    Future<void> Function(Rate)? saveRate,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    http.Client? ownedClient;
    try {
      if (client == null) {
        final certificate = await rootBundle.load(
          'assets/certificates/russian_trusted_root_ca.pem',
        );
        ownedClient = TbankHttpClient.withTrustedRoot(
          certificate.buffer.asUint8List(
            certificate.offsetInBytes,
            certificate.lengthInBytes,
          ),
        );
      }
      final response = await (client ?? ownedClient!)
          .get(_url)
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw RateFetchException('Сервер вернул HTTP ${response.statusCode}');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> || data['resultCode'] != 'OK') {
        throw const RateFetchException('API Т-Банка не вернул курсы');
      }
      final payload = data['payload'];
      if (payload is! Map<String, dynamic> || payload['rates'] is! List) {
        throw const FormatException('Missing rates');
      }
      final rates = (payload['rates'] as List)
          .whereType<Map<String, dynamic>>();
      final transfer = rates.where((rate) {
        final from = rate['fromCurrency'];
        final to = rate['toCurrency'];
        return rate['category'] == 'DebitCardsTransfers' &&
            from is Map &&
            from['name'] == Currencies.rub &&
            to is Map &&
            to['name'] == Currencies.vnd;
      }).firstOrNull;
      if (transfer == null) {
        throw const RateFetchException(
          'Курс переводов RUB/VND отсутствует в ответе',
        );
      }
      // For RUB -> VND, buy is the number of VND received per RUB.
      final value = transfer['buy'];
      if (value is! num || !value.isFinite || value <= 0) {
        throw const FormatException('Invalid transfer rate');
      }
      await (saveRate ?? DatabaseHelper().insertRateIfChanged)(
        Rate(
          base: Currencies.rub,
          quote: Currencies.vnd,
          value: value.toDouble(),
          source: Sources.tbankTransfer,
          timestamp: DateTime.now(),
        ),
      );
    } catch (error) {
      throw RateFetchException.from(error);
    } finally {
      ownedClient?.close();
    }
  }
}
