import 'dart:convert';
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

  Future<void> markMultipleSmsHandled(List<String> smsIds, String status) async {
    if (smsIds.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final id in smsIds) {
      batch.insert('handled_sms', {'smsId': id, 'status': status}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // --- GOOGLE DRIVE BACKUP & RESTORE SERIALIZATION ---
  Future<String> exportDatabaseJson() async {
    final db = await instance.database;
    final books = await db.query('books');
    final transactions = await db.query('transactions');
    final handledSms = await db.query('handled_sms');

    final payload = {
      'app': 'FinTrax',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': books,
      'transactions': transactions,
      'handled_sms': handledSms,
    };
    return jsonEncode(payload);
  }

  Future<int> importDatabaseJson(String jsonString) async {
    final db = await instance.database;
    final Map<String, dynamic> data = jsonDecode(jsonString) as Map<String, dynamic>;
    final List<dynamic> booksList = (data['books'] as List<dynamic>?) ?? [];
    final List<dynamic> txList = (data['transactions'] as List<dynamic>?) ?? [];
    final List<dynamic> smsList = (data['handled_sms'] as List<dynamic>?) ?? [];

    final Map<int, int> oldBookIdToNewId = {};
    int restoredBooksCount = 0;

    await db.transaction((txn) async {
      for (final item in booksList) {
        if (item is Map) {
          final int oldId = (item['id'] as num).toInt();
          final String name = item['name'].toString();
          final String createdAt = item['createdAt']?.toString() ?? DateTime.now().toIso8601String();
          final String updatedAt = item['updatedAt']?.toString() ?? createdAt;
          final int isPinned = (item['isPinned'] as num?)?.toInt() ?? 0;

          final existing = await txn.query('books', where: 'name = ?', whereArgs: [name]);
          if (existing.isNotEmpty) {
            final int existingId = (existing.first['id'] as num).toInt();
            oldBookIdToNewId[oldId] = existingId;
          } else {
            final int newId = await txn.insert('books', {
              'name': name,
              'createdAt': createdAt,
              'updatedAt': updatedAt,
              'isPinned': isPinned,
            });
            oldBookIdToNewId[oldId] = newId;
            restoredBooksCount++;
          }
        }
      }

      for (final item in txList) {
        if (item is Map) {
          final int oldBookId = (item['bookId'] as num).toInt();
          final int? targetBookId = oldBookIdToNewId[oldBookId];
          if (targetBookId != null) {
            final String dateStr = item['date']?.toString() ?? '';
            final double amount = (item['amount'] as num).toDouble();
            final String name = item['name']?.toString() ?? '';

            final dup = await txn.query(
              'transactions',
              where: 'bookId = ? AND date = ? AND amount = ? AND name = ?',
              whereArgs: [targetBookId, dateStr, amount, name],
            );
            if (dup.isEmpty) {
              await txn.insert('transactions', {
                'bookId': targetBookId,
                'type': item['type']?.toString() ?? 'Expense',
                'amount': amount,
                'name': name,
                'category': item['category']?.toString() ?? '',
                'notes': item['notes']?.toString() ?? '',
                'imagePath': item['imagePath']?.toString() ?? '',
                'date': dateStr,
                'currency': item['currency']?.toString() ?? '₹',
                'paymentMode': item['paymentMode']?.toString() ?? 'Cash',
              });
            }
          }
        }
      }

      for (final item in smsList) {
        if (item is Map && item['smsId'] != null) {
          await txn.insert(
            'handled_sms',
            {'smsId': item['smsId'].toString(), 'status': item['status']?.toString() ?? 'added'},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });

    return booksList.isEmpty ? 0 : (restoredBooksCount > 0 ? restoredBooksCount : booksList.length);
  }
}
