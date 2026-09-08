/// Модель курса валюты
class Rate {
  final int? id;          // первичный ключ в БД (автоматический)
  final String base;      // базовая валюта (например, 'USD')
  final String quote;     // котируемая валюта (например, 'RUB')
  final double value;     // сколько quote за 1 base
  final String source;    // источник: 'cbr', 'bybit', 'tbank_qr', 'tbank_transfer'
  final DateTime timestamp; // когда получен курс

  Rate({
    this.id,
    required this.base,
    required this.quote,
    required this.value,
    required this.source,
    required this.timestamp,
  });

  /// Преобразование в Map для вставки в БД
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'base': base,
      'quote': quote,
      'value': value,
      'source': source,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Создание объекта из Map (из БД)
  factory Rate.fromMap(Map<String, dynamic> map) {
    return Rate(
      id: map['id'],
      base: map['base'],
      quote: map['quote'],
      value: map['value'],
      source: map['source'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}