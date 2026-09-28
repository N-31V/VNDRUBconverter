import 'dart:convert';
import 'dart:io';

import 'package:currency_tracker/services/tbank_http_client.dart';

// Optional live check; does not touch the app database or system trust store.
Future<void> main() async {
  final certificate = File('assets/certificates/russian_trusted_root_ca.pem');
  final client = TbankHttpClient.withTrustedRoot(
    await certificate.readAsBytes(),
  );
  try {
    final response = await client
        .get(
          Uri.https('www.tbank.ru', '/api/common/v1/currency_rates', {
            'from': 'RUB',
            'to': 'VND',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['resultCode'] != 'OK') throw StateError('API result is not OK');
    final rates = (body['payload']['rates'] as List).where(
      (rate) =>
          rate['category'] == 'DebitCardsTransfers' &&
          rate['fromCurrency']['name'] == 'RUB' &&
          rate['toCurrency']['name'] == 'VND',
    );
    if (rates.isEmpty) throw StateError('Missing RUB/VND transfer rate');
    stdout.writeln('TLS verified; T-Bank API returned RUB/VND transfer rate.');
  } finally {
    client.close();
  }
}
