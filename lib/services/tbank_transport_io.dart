import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createTbankTransport(List<int> certificate) {
  final context = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(certificate);
  return IOClient(
    HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 15),
  );
}
