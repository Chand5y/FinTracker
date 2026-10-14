import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'book_model.dart';
import 'transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fintrack_v4.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      isPinned INTEGER DEFAULT 0
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL,
      type TEXT,
      amount REAL,
      name TEXT,
      category TEXT,
      notes TEXT,
      imagePath TEXT,
      date TEXT,
      currency TEXT,
      paymentMode TEXT,
      FOREIGN KEY (bookId) REFERENCES books (id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS handled_sms (
      smsId TEXT PRIMARY KEY,
      status TEXT
    )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS handled_sms (
      smsId TEXT PRIMARY KEY,
      status TEXT
    )
    ''');
  }

  // --- BOOK METHODS ---
  Future<int> insertBook(BookModel book) async {
    final db = await instance.database;
    try {
      return await db.insert('books', book.toMap());
    } catch (e) {
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getBooksWithBalances() async {
    final db = await instance.database;
    final rawResult = await db.rawQuery('''
      SELECT b.id, b.name, b.createdAt, b.updatedAt, b.isPinned,
             COALESCE(SUM(CASE WHEN t.type = 'Income' THEN t.amount ELSE 0 END), 0) as totalIn,
             COALESCE(SUM(CASE WHEN t.type = 'Expense' THEN t.amount ELSE 0 END), 0) as totalOut
      FROM books b
      LEFT JOIN transactions t ON b.id = t.bookId
      GROUP BY b.id
    ''');
    // Crucial fix: Clone into a modifiable list so .sort() never crashes!
    return List<Map<String, dynamic>>.from(rawResult);
  }

  Future<int> togglePinBook(int id, bool isPinned) async {
    final db = await instance.database;
    return await db.update('books', {'isPinned': isPinned ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateBookName(int id, String newName) async {
    final db = await instance.database;
    try {
      return await db.update('books', {'name': newName, 'updatedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      return -1;
    }
  }

  Future<int> deleteBook(int id) async {
    final db = await instance.database;
    return await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  // --- TRANSACTION METHODS ---
  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await instance.database;
    await db.update('books', {'updatedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [transaction.bookId]);
    return await db.insert('transactions', transaction.toMap());
  }
  
  Future<int> updateTransaction(TransactionModel transaction) async {
    final db = await instance.database;
    await db.update('books', {'updatedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [transaction.bookId]);
    return await db.update('transactions', transaction.toMap(), where: 'id = ?', whereArgs: [transaction.id]);
  }

  Future<List<TransactionModel>> readTransactionsForBook(int bookId) async {
    final db = await instance.database;
    final result = await db.query('transactions', where: 'bookId = ?', whereArgs: [bookId], orderBy: 'date DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> deleteTransaction(int id, int bookId) async {
    final db = await instance.database;
    await db.update('books', {'updatedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [bookId]);
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- SMS TRACKING METHODS ---
  Future<Set<String>> getHandledSmsIds() async {
    final db = await instance.database;
    try {
      final rows = await db.query('handled_sms');
      return rows.map((r) => r['smsId'].toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> markSmsHandled(String smsId, String status) async {
    final db = await instance.database;
    await db.insert('handled_sms', {'smsId': smsId, 'status': status}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
