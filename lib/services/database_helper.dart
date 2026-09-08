import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import '../models/rate.dart';

class DatabaseHelper {
  // Singleton: один экземпляр на всё приложение
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  // Геттер для получения базы данных (если не открыта, открывает)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Инициализация базы
  Future<Database> _initDatabase() async {
    // Получаем путь к директории приложения
    final directory = await getApplicationDocumentsDirectory();
    // Создаём полный путь к файлу базы данных
    final path = join(directory.path, 'currency_tracker.db');

    // Открываем базу (если файла нет, он создастся автоматически)
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate, // вызывается при первом создании БД
    );
  }

  // Метод создания таблицы
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
    // Можно добавить индексы для ускорения запросов, пока не нужно
  }

  // ---- CRUD операции ----

  // Вставка нового курса
  Future<void> insertRate(Rate rate) async {
    final db = await database;
    await db.insert(
      'rates',
      rate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // если такой id есть, заменить
    );
  }

  // Получение последнего курса по источнику
  /// Получить последний курс для заданной пары и источника
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

  // Получение всех курсов за последний час (можно использовать для кэша)
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