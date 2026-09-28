import 'dart:async';
import 'dart:convert';

import 'package:currency_tracker/constants.dart';
import 'package:currency_tracker/models/rate.dart';
import 'package:currency_tracker/services/cbr_api.dart';
import 'package:currency_tracker/services/rate_fetch_exception.dart';
import 'package:currency_tracker/services/tbank_api.dart';
import 'package:currency_tracker/services/tbank_http_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> bankRate({
  String category = 'DebitCardsTransfers',
  String from = 'RUB',
  String to = 'VND',
  num buy = 280,
}) => {
  'category': category,
  'fromCurrency': {'name': from},
  'toCurrency': {'name': to},
  'buy': buy,
  'sell': 330,
};

String bankResponse(List<Map<String, Object>> rates) => jsonEncode({
  'resultCode': 'OK',
  'payload': {'rates': rates},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'T-Bank only saves the requested transfer pair, never the QR rate',
    () async {
      final saved = <Rate>[];
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.queryParameters, {'from': 'RUB', 'to': 'VND'});
        return http.Response(
          bankResponse([
            bankRate(category: 'DebitCardsOperations', buy: 310),
            bankRate(to: 'USD', buy: 0.01),
            bankRate(buy: 285.5),
          ]),
          200,
        );
      });
      await TbankApiClient.fetchAndSaveTbankRates(
        client: client,
        saveRate: (rate) async => saved.add(rate),
      );
      expect(saved, hasLength(1));
      expect(saved.single.source, Sources.tbankTransfer);
      expect(saved.single.value, 285.5);
      expect(saved.single.base, Currencies.rub);
      expect(saved.single.quote, Currencies.vnd);
    },
  );

  test('T-Bank bad responses do not overwrite saved values', () async {
    for (final response in [
      http.Response('unavailable', 503),
      http.Response('{', 200),
      http.Response('{"resultCode":"ERROR"}', 200),
      http.Response('{"resultCode":"OK","payload":{}}', 200),
      http.Response(bankResponse([bankRate(to: 'USD')]), 200),
      http.Response(bankResponse([bankRate(buy: 0)]), 200),
      http.Response(bankResponse([bankRate(buy: -2)]), 200),
    ]) {
      final saved = <Rate>[];
      await expectLater(
        TbankApiClient.fetchAndSaveTbankRates(
          client: MockClient((_) async => response),
          saveRate: (rate) async => saved.add(rate),
        ),
        throwsA(isA<RateFetchException>()),
      );
      expect(saved, isEmpty);
    }
  });

  test(
    'timeout releases caller and late response cannot save stale data',
    () async {
      final pending = Completer<http.Response>();
      final saved = <Rate>[];
      await expectLater(
        TbankApiClient.fetchAndSaveTbankRates(
          client: MockClient((_) => pending.future),
          saveRate: (rate) async => saved.add(rate),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<RateFetchException>().having(
            (e) => e.message,
            'message',
            contains('вовремя'),
          ),
        ),
      );
      pending.complete(http.Response(bankResponse([bankRate()]), 200));
      await Future<void>.delayed(Duration.zero);
      expect(saved, isEmpty);
    },
  );

  test(
    'certificate failures have an actionable message and do not save',
    () async {
      var saved = false;
      await expectLater(
        TbankApiClient.fetchAndSaveTbankRates(
          client: MockClient(
            (_) async => throw http.ClientException(
              'CERTIFICATE_VERIFY_FAILED: self signed certificate in certificate chain',
            ),
          ),
          saveRate: (_) async {
            saved = true;
          },
        ),
        throwsA(
          isA<RateFetchException>().having(
            (e) => e.message,
            'message',
            contains('сертификат'),
          ),
        ),
      );
      expect(saved, isFalse);
    },
  );

  const xml = '''<ValCurs>
    <Valute><CharCode>USD</CharCode><Nominal>1</Nominal><Value>80,50</Value></Valute>
    <Valute><CharCode>VND</CharCode><Nominal>10000</Nominal><Value>30,50</Value></Valute>
  </ValCurs>''';

  test(
    'CBR uses HTTPS and normalizes XML nominal to one currency unit',
    () async {
      final saved = <Rate>[];
      await CbrApiClient.fetchAndSaveRates(
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          return http.Response(xml, 200);
        }),
        saveRate: (rate) async => saved.add(rate),
      );
      expect(saved.map((rate) => rate.value), [80.5, 0.00305]);
      expect(saved.map((rate) => rate.base), ['USD', 'VND']);
    },
  );

  test('invalid second CBR currency prevents any partial save', () async {
    final saved = <Rate>[];
    await expectLater(
      CbrApiClient.fetchAndSaveRates(
        client: MockClient(
          (_) async => http.Response(
            xml.replaceFirst(
              '<Nominal>10000</Nominal>',
              '<Nominal>0</Nominal>',
            ),
            200,
          ),
        ),
        saveRate: (rate) async => saved.add(rate),
      ),
      throwsA(isA<RateFetchException>()),
    );
    expect(saved, isEmpty);
  });

  test(
    'T-Bank custom trust cannot be used for other hosts, HTTP or ports',
    () async {
      var requests = 0;
      final client = TbankHttpClient(
        MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      for (final url in [
        'http://www.tbank.ru/',
        'https://example.com/',
        'https://www.tbank.ru.evil.example/',
        'https://www.tbank.ru:8443/',
      ]) {
        await expectLater(
          client.get(Uri.parse(url)),
          throwsA(isA<http.ClientException>()),
        );
      }
      expect(requests, 0);
      client.close();
    },
  );

  test('T-Bank client disables redirects to keep extra trust scoped', () async {
    final client = TbankHttpClient(
      MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://example.com/'},
        );
      }),
    );
    expect(
      (await client.get(Uri.parse('https://www.tbank.ru/'))).statusCode,
      302,
    );
    client.close();
  });

  test(
    'bundled root certificate can be loaded and parsed by native TLS',
    () async {
      final bytes = await rootBundle.load(
        'assets/certificates/russian_trusted_root_ca.pem',
      );
      final client = TbankHttpClient.withTrustedRoot(
        bytes.buffer.asUint8List(),
      );
      client.close();
    },
  );
}
