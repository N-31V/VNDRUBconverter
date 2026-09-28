import 'package:http/http.dart' as http;

// Browsers manage their own trust store; native builds use the IO transport.
http.Client createTbankTransport(List<int> certificate) => http.Client();
