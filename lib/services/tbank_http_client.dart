import 'package:http/http.dart' as http;

import 'tbank_transport_stub.dart'
    if (dart.library.io) 'tbank_transport_io.dart';

/// Keeps the additional CA scoped to HTTPS requests to the bank's API host.
class TbankHttpClient extends http.BaseClient {
  TbankHttpClient(this._inner);

  factory TbankHttpClient.withTrustedRoot(List<int> certificate) {
    return TbankHttpClient(createTbankTransport(certificate));
  }

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.scheme != 'https' ||
        request.url.host != 'www.tbank.ru' ||
        request.url.port != 443) {
      throw http.ClientException(
        'Этот клиент предназначен только для HTTPS API Т-Банка',
        request.url,
      );
    }
    // Do not carry this client's extra trust to a redirect destination.
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
