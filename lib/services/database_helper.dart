import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import '../models/rate.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const double _epsilon = 1e-6;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'currency_tracker.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base TEXT NOT NULL,
        quote TEXT NOT NULL,
        value REAL NOT NULL,
        source TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  // Безусловная вставка (используется редко, например, при миграциях)
  Future<void> insertRate(Rate rate) async {
    final db = await database;
    await db.insert('rates', rate.toMap());
  }

  // Умная вставка: учитывает дату и значение
  Future<void> insertRateIfChanged(Rate newRate) async {
    final db = await database;
    // Определяем дату новой записи (начало дня)
    final date = DateTime(newRate.timestamp.year, newRate.timestamp.month, newRate.timestamp.day);
    final dateStr = date.toIso8601String();

    // Ищем запись за этот день с таким же source, base, quote
    final List<Map<String, dynamic>> existing = await db.query(
      'rates',
      where: 'source = ? AND base = ? AND quote = ? AND date(timestamp) = ?',
      whereArgs: [newRate.source, newRate.base, newRate.quote, dateStr],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Есть запись за сегодня
      final existingRate = Rate.fromMap(existing.first);
      if ((existingRate.value - newRate.value).abs() < _epsilon) {
        // Значение не изменилось – ничего не делаем
        print('Курс ${newRate.source} ${newRate.base}/${newRate.quote} за сегодня не изменился, пропускаем вставку');
        return;
      }
      // Значение изменилось – обновляем запись
      await db.update(
        'rates',
        newRate.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      print('Курс ${newRate.source} ${newRate.base}/${newRate.quote} за сегодня обновлён');
    } else {
      // Нет записи за сегодня – вставляем новую
      await db.insert('rates', newRate.toMap());
      print('Курс ${newRate.source} ${newRate.base}/${newRate.quote} сохранён за новый день');
    }
  }

  // Получение последней записи для источника и пары (по времени)
  Future<Rate?> getLatestRate(String source, String base, String quote) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'rates',
      where: 'source = ? AND base = ? AND quote = ?',
      whereArgs: [source, base, quote],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Rate.fromMap(maps.first);
    }
    return null;
  }

  // Получение всех записей за период (для графиков)
  Future<List<Rate>> getRatesForPeriod(String source, String base, String quote, DateTime from, DateTime to) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'rates',
      where: 'source = ? AND base = ? AND quote = ? AND timestamp BETWEEN ? AND ?',
      whereArgs: [source, base, quote, from.toIso8601String(), to.toIso8601String()],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => Rate.fromMap(map)).toList();
  }

// (Остальные методы, если есть, остаются без изменений)
}