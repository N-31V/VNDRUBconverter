class Currencies {
  static const String usd = 'USD';
  static const String rub = 'RUB';
  static const String vnd = 'VND';
  static const String usdt = 'USDT';
}

class Sources {
  static const String cbr = 'cbr';
  static const String bybitQr =
      'bybit_qr'; // ручные курсы Bybit USDT/VND и USDT/RUB
  static const String tbankQr =
      'tbank_qr'; // ручной ввод курса Т-банк (оплата по QR)
  static const String tbankTransfer = 'tbank_transfer'; // API Т-Банка (перевод)
}
