import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import '../models/rate.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const double _epsilon = 1e-6; // допуск для сравнения double

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

  // Вставка нового курса (безусловная)
  Future<void> insertRate(Rate rate) async {
    final db = await database;
    await db.insert('rates', rate.toMap());
  }

  // Вставка только если значение изменилось
  Future<void> insertRateIfChanged(Rate newRate) async {
    final existing = await getLatestRate(newRate.source, newRate.base, newRate.quote);
    if (existing != null && (existing.value - newRate.value).abs() < _epsilon) {
      // Значение не изменилось – пропускаем
      print('Курс ${newRate.source} ${newRate.base}/${newRate.quote} не изменился, пропускаем вставку');
      return;
    }
    await insertRate(newRate);
  }

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

  Future<List<Rate>> getRatesSince(DateTime since) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'rates',
      where: 'timestamp > ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => Rate.fromMap(map)).toList();
  }
}