import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'book_model.dart';
import 'transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _dbInitFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _dbInitFuture ??= _initDB('fintrack_v4.db');
    _database = await _dbInitFuture!;
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await _ensureColumnsExistSafely(db);
    return db;
  }

  Future<void> _ensureColumnsExistSafely(Database db) async {
    try {
      final bookCols = await db.rawQuery('PRAGMA table_info(books)');
      final hasBookType = bookCols.any((c) => c['name']?.toString() == 'bookType');
      if (!hasBookType) {
        await db.execute("ALTER TABLE books ADD COLUMN bookType TEXT DEFAULT 'standard'");
      }
    } catch (_) {}

    try {
      final txCols = await db.rawQuery('PRAGMA table_info(transactions)');
      final hasSmsBody = txCols.any((c) => c['name']?.toString() == 'smsBody');
      if (!hasSmsBody) {
        await db.execute("ALTER TABLE transactions ADD COLUMN smsBody TEXT DEFAULT ''");
      }
    } catch (_) {}
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      isPinned INTEGER DEFAULT 0,
      bookType TEXT DEFAULT 'standard'
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
      smsBody TEXT DEFAULT '',
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
    await _ensureColumnsExistSafely(db);
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
             COALESCE(b.bookType, 'standard') as bookType,
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

  Future<int> updateBookName(int id, String newName, {String? bookType}) async {
    final db = await instance.database;
    try {
      final map = <String, dynamic>{
        'name': newName,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (bookType != null) map['bookType'] = bookType;
      return await db.update('books', map, where: 'id = ?', whereArgs: [id]);
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

  Future<void> insertTransactionToMultipleBooks(TransactionModel baseTx, List<int> bookIds) async {
    final db = await instance.database;
    final nowIso = DateTime.now().toIso8601String();
    final uniqueBookIds = bookIds.toSet().toList();

    await db.transaction((txn) async {
      for (final targetBookId in uniqueBookIds) {
        final copy = baseTx.copyWith(clearId: true, bookId: targetBookId);
        await txn.insert('transactions', copy.toMap());
        await txn.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [targetBookId]);
      }
    });
  }

  Future<int> copyTransactionToBooks(TransactionModel tx, List<int> targetBookIds) async {
    if (targetBookIds.isEmpty) return 0;
    final db = await instance.database;
    final nowIso = DateTime.now().toIso8601String();
    int copied = 0;

    await db.transaction((txn) async {
      for (final targetId in targetBookIds.toSet()) {
        final newTx = tx.copyWith(clearId: true, bookId: targetId);
        await txn.insert('transactions', newTx.toMap());
        await txn.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [targetId]);
        copied++;
      }
    });
    return copied;
  }

  Future<void> moveTransactionToBook(TransactionModel tx, int targetBookId) async {
    if (tx.id == null || tx.bookId == targetBookId) return;
    final db = await instance.database;
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'transactions',
        {'bookId': targetBookId},
        where: 'id = ?',
        whereArgs: [tx.id],
      );
      await txn.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [tx.bookId]);
      await txn.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [targetBookId]);
    });
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

  // --- MONTHLY FINANCIAL INSIGHTS ENGINE ---
  Future<Map<String, dynamic>> getMonthlyInsights(int year, int month) async {
    final db = await instance.database;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();

    final rows = await db.rawQuery('''
      SELECT t.*, b.name as bookName, COALESCE(b.bookType, 'standard') as bookType
      FROM transactions t
      INNER JOIN books b ON t.bookId = b.id
      WHERE t.date >= ? AND t.date < ?
      ORDER BY t.date DESC
    ''', [startIso, endIso]);

    final seenSignatures = <String>{};
    double totalIncome = 0;
    double totalExpense = 0;
    double shoppingSpend = 0;
    double grocerySpend = 0;
    double foodSpend = 0;
    double lendingGiven = 0;
    double lendingRecovered = 0;
    int totalUniqueTxCount = 0;

    final Map<String, double> categoryTotals = {};
    final Map<String, double> bookExpenseTotals = {};
    String topExpenseTitle = '';
    double topExpenseAmount = 0;

    for (final r in rows) {
      final String bookType = r['bookType']?.toString() ?? 'standard';
      final String bookName = r['bookName']?.toString() ?? 'Book';
      final String type = r['type']?.toString() ?? 'Expense';
      final double amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final String name = (r['name']?.toString() ?? '').trim();
      final String category = (r['category']?.toString() ?? '').trim();
      final String dateStr = r['date']?.toString() ?? '';
      final String minuteKey = dateStr.length >= 16 ? dateStr.substring(0, 16) : dateStr;

      if (bookType == 'lending') {
        if (type == 'Expense') {
          lendingGiven += amount;
        } else {
          lendingRecovered += amount;
        }
        continue;
      }

      if (type == 'Expense') {
        bookExpenseTotals[bookName] = (bookExpenseTotals[bookName] ?? 0.0) + amount;
      }

      final sig = '$type|${amount.toStringAsFixed(2)}|${name.toLowerCase()}|$minuteKey';
      if (seenSignatures.contains(sig)) continue;
      seenSignatures.add(sig);
      totalUniqueTxCount++;

      if (type == 'Income') {
        totalIncome += amount;
      } else {
        totalExpense += amount;
        if (amount > topExpenseAmount) {
          topExpenseAmount = amount;
          topExpenseTitle = name.isEmpty ? 'Expense' : name;
        }

        final String catLabel = category.isEmpty ? 'Uncategorized' : category;
        categoryTotals[catLabel] = (categoryTotals[catLabel] ?? 0.0) + amount;

        final lowerCat = category.toLowerCase();
        final lowerName = name.toLowerCase();
        final lowerBook = bookName.toLowerCase();

        if (lowerCat.contains('shop') || lowerBook.contains('shop') || lowerName.contains('amazon') || lowerName.contains('flipkart') || lowerName.contains('myntra')) {
          shoppingSpend += amount;
        }
        if (lowerCat.contains('grocer') || lowerBook.contains('grocer') || lowerName.contains('blinkit') || lowerName.contains('zepto') || lowerName.contains('instamart') || lowerName.contains('bigbasket') || lowerName.contains('milk') || lowerName.contains('vegetable')) {
          grocerySpend += amount;
        }
        if (lowerCat.contains('food') || lowerCat.contains('dining') || lowerName.contains('zomato') || lowerName.contains('swiggy')) {
          foodSpend += amount;
        }
      }
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedBooks = bookExpenseTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'year': year,
      'month': month,
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'netFlow': totalIncome - totalExpense,
      'shoppingSpend': shoppingSpend,
      'grocerySpend': grocerySpend,
      'foodSpend': foodSpend,
      'lendingGiven': lendingGiven,
      'lendingRecovered': lendingRecovered,
      'txCount': totalUniqueTxCount,
      'topExpenseTitle': topExpenseTitle,
      'topExpenseAmount': topExpenseAmount,
      'categoryBreakdown': sortedCategories.map((e) => {'name': e.key, 'amount': e.value}).toList(),
      'bookBreakdown': sortedBooks.map((e) => {'name': e.key, 'amount': e.value}).toList(),
    };
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
      'version': 2,
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
          final String bookType = item['bookType']?.toString() ?? 'standard';

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
              'bookType': bookType,
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
              final String notesStr = item['notes']?.toString() ?? '';
              final String smsBodyStr = item['smsBody']?.toString() ?? notesStr;
              await txn.insert('transactions', {
                'bookId': targetBookId,
                'type': item['type']?.toString() ?? 'Expense',
                'amount': amount,
                'name': name,
                'category': item['category']?.toString() ?? '',
                'notes': notesStr,
                'smsBody': smsBodyStr,
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
