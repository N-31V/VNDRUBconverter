import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

import '../models/rate.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// Uses an already opened database, for alternate storage and tests.
  DatabaseHelper.withDatabase(Database database)
    : _databaseFuture = Future.value(database);

  Future<Database>? _databaseFuture;
  static const double _epsilon = 1e-6;

  Future<Database> get database {
    return _databaseFuture ??= _initDatabase().catchError((
      Object error,
      StackTrace stack,
    ) {
      // A temporary storage failure should remain retryable on the next load.
      _databaseFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'currency_tracker.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
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

  // История изменений: одинаковое значение не добавляем, старые записи не меняем.
  Future<void> insertRateIfChanged(Rate newRate) async {
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'rates',
        where: 'source = ? AND base = ? AND quote = ?',
        whereArgs: [newRate.source, newRate.base, newRate.quote],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final previous = Rate.fromMap(existing.first);
        if ((previous.value - newRate.value).abs() < _epsilon) return;
      }
      await transaction.insert('rates', newRate.toMap()..remove('id'));
    });
  }

  // Получение последней записи для источника и пары (по времени)
  Future<Rate?> getLatestRate(String source, String base, String quote) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'rates',
      where: 'source = ? AND base = ? AND quote = ?',
      whereArgs: [source, base, quote],
      orderBy: 'timestamp DESC, id DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Rate.fromMap(maps.first);
    }
    return null;
  }

  /// Returns the last observation before [from], then changes within the window.
  /// The anchor keeps its original timestamp; only chart points are clipped.
  Future<List<Rate>> getRatesForPeriod(
    String source,
    String base,
    String quote,
    DateTime from,
    DateTime to,
  ) async {
    if (from.isAfter(to)) return [];
    final db = await database;
    return db.transaction((transaction) async {
      final anchor = await transaction.query(
        'rates',
        where: 'source = ? AND base = ? AND quote = ? AND timestamp < ?',
        whereArgs: [source, base, quote, from.toIso8601String()],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      final changes = await transaction.query(
        'rates',
        where: 'source = ? AND base = ? AND quote = ? AND timestamp BETWEEN ? AND ?',
        whereArgs: [
          source,
          base,
          quote,
          from.toIso8601String(),
          to.toIso8601String(),
        ],
        orderBy: 'timestamp ASC, id ASC',
      );
      return [...anchor, ...changes].map(Rate.fromMap).toList();
    });
  }
}
