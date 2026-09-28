import 'dart:async';

class RateFetchException implements Exception {
  const RateFetchException(this.message);

  final String message;

  factory RateFetchException.from(Object error) {
    if (error is RateFetchException) return error;
    if (error is TimeoutException) {
      return const RateFetchException('Сервер не ответил вовремя');
    }
    final details = error.toString().toLowerCase();
    if (details.contains('certificate_verify_failed') ||
        details.contains('certificate verify failed')) {
      return const RateFetchException(
        'Не удалось проверить сертификат сервера. '
        'Проверьте дату устройства и версию приложения',
      );
    }
    if (error is FormatException) {
      return const RateFetchException('Сервер вернул некорректные данные');
    }
    return const RateFetchException('Не удалось обновить курс');
  }

  @override
  String toString() => message;
}
