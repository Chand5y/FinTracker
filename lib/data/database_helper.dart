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
    _database = await _initDB('fintrack_books.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isPinned INTEGER NOT NULL DEFAULT 0,
        bookType TEXT NOT NULL DEFAULT 'standard'
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        notes TEXT NOT NULL,
        smsBody TEXT NOT NULL DEFAULT '',
        imagePath TEXT NOT NULL,
        date TEXT NOT NULL,
        currency TEXT NOT NULL,
        paymentMode TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE handled_sms (
        smsId TEXT PRIMARY KEY,
        status TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE books ADD COLUMN createdAt TEXT');
        await db.execute('UPDATE books SET createdAt = updatedAt WHERE createdAt IS NULL');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE books ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS handled_sms (
          smsId TEXT PRIMARY KEY,
          status TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE transactions ADD COLUMN smsBody TEXT NOT NULL DEFAULT ''");
        await db.execute("UPDATE transactions SET smsBody = notes WHERE smsBody = '' AND notes != ''");
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute("ALTER TABLE books ADD COLUMN bookType TEXT NOT NULL DEFAULT 'standard'");
      } catch (_) {}
    }
  }

  Future<int> insertBook(BookModel book) async {
    final db = await instance.database;
    final existing = await db.query(
      'books',
      where: 'LOWER(name) = ?',
      whereArgs: [book.name.trim().toLowerCase()],
    );
    if (existing.isNotEmpty) return -1;
    return await db.insert('books', book.toMap());
  }

  Future<List<Map<String, dynamic>>> getBooksWithBalances() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> rawBooks = await db.rawQuery('''
      SELECT b.id, b.name, b.createdAt, b.updatedAt, b.isPinned, b.bookType,
        COALESCE(SUM(CASE WHEN t.type = 'Income' THEN t.amount ELSE 0 END), 0) as totalIn,
        COALESCE(SUM(CASE WHEN t.type = 'Expense' THEN t.amount ELSE 0 END), 0) as totalOut
      FROM books b
      LEFT JOIN transactions t ON b.id = t.bookId
      GROUP BY b.id
    ''');
    return rawBooks.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<int> updateBookName(int id, String newName, {String? bookType}) async {
    final db = await instance.database;
    final existing = await db.query(
      'books',
      where: 'LOWER(name) = ? AND id != ?',
      whereArgs: [newName.trim().toLowerCase(), id],
    );
    if (existing.isNotEmpty) return -1;

    final values = <String, dynamic>{
      'name': newName.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (bookType != null) {
      values['bookType'] = bookType;
    }
    return await db.update('books', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> togglePinBook(int id, bool isPinned) async {
    final db = await instance.database;
    await db.update('books', {'isPinned': isPinned ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteBook(int id) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'bookId = ?', whereArgs: [id]);
    return await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await instance.database;
    await db.update(
      'books',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [transaction.bookId],
    );
    return await db.insert('transactions', transaction.toMap());
  }

  Future<void> insertTransactionToMultipleBooks(TransactionModel baseTx, List<int> bookIds) async {
    final uniqueIds = bookIds.toSet().toList();
    for (final bId in uniqueIds) {
      final copy = baseTx.copyWith(clearId: true, bookId: bId);
      await insertTransaction(copy);
    }
  }

  Future<int> copyTransactionToBooks(TransactionModel tx, List<int> targetBookIds) async {
    int count = 0;
    for (final bId in targetBookIds.toSet()) {
      if (bId == tx.bookId) continue;
      final copy = tx.copyWith(clearId: true, bookId: bId);
      await insertTransaction(copy);
      count++;
    }
    return count;
  }

  Future<void> moveTransactionToBook(TransactionModel tx, int targetBookId) async {
    if (tx.id == null || tx.bookId == targetBookId) return;
    final db = await instance.database;
    final nowIso = DateTime.now().toIso8601String();
    await db.update(
      'transactions',
      {'bookId': targetBookId},
      where: 'id = ?',
      whereArgs: [tx.id],
    );
    await db.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [tx.bookId]);
    await db.update('books', {'updatedAt': nowIso}, where: 'id = ?', whereArgs: [targetBookId]);
  }

  Future<List<TransactionModel>> readTransactionsForBook(int bookId) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'date DESC',
    );
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> updateTransaction(TransactionModel transaction) async {
    final db = await instance.database;
    await db.update(
      'books',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [transaction.bookId],
    );
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> deleteTransaction(int id, int bookId) async {
    final db = await instance.database;
    await db.update(
      'books',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [bookId],
    );
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<String>> getHandledSmsIds() async {
    final db = await instance.database;
    final rows = await db.query('handled_sms', columns: ['smsId']);
    return rows.map((r) => r['smsId'].toString()).toSet();
  }

  Future<void> markSmsHandled(String smsId, String status) async {
    final db = await instance.database;
    await db.insert(
      'handled_sms',
      {'smsId': smsId, 'status': status},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markMultipleSmsHandled(List<String> smsIds, String status) async {
    if (smsIds.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final id in smsIds) {
      batch.insert(
        'handled_sms',
        {'smsId': id, 'status': status},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ===========================================================================
  // MONTHLY INSIGHTS AGGREGATOR (WITH MULTI-BOOK DEDUPLICATION)
  // ===========================================================================
  /// Builds a signature key so the same transaction copied across multiple books
  /// is counted only ONCE in overall monthly totals and category breakdowns.
  String _buildDedupeSignature(Map<String, dynamic> row) {
    final String type = row['type']?.toString() ?? 'Expense';
    final double amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final String amtKey = amount.toStringAsFixed(2);
    final String sms = (row['smsBody']?.toString() ?? '').trim();
    final String dateStr = row['date']?.toString() ?? '';
    final String dayKey = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
    final String nameKey = (row['name']?.toString() ?? '').trim().toLowerCase();

    if (sms.isNotEmpty) {
      return 'SMS|$type|$amtKey|$dayKey|$sms';
    }
    // Entries created/copied together share the exact ISO timestamp or same day + title + amount
    return 'TX|$type|$amtKey|$dayKey|$nameKey';
  }

  Future<Map<String, dynamic>> getMonthlyInsights(int year, int month) async {
    final db = await instance.database;
    final startIso = DateTime(year, month, 1).toIso8601String();
    final endIso = DateTime(year, month + 1, 1).toIso8601String();

    final rows = await db.rawQuery('''
      SELECT t.*, b.name as bookName, b.bookType as bookType
      FROM transactions t
      INNER JOIN books b ON t.bookId = b.id
      WHERE t.date >= ? AND t.date < ?
      ORDER BY t.date DESC
    ''', [startIso, endIso]);

    double totalIncome = 0;
    double totalExpense = 0;
    double shoppingSpend = 0;
    double grocerySpend = 0;
    double foodSpend = 0;
    double lendingGiven = 0;
    double lendingReturned = 0;
    int txCount = 0;

    final Map<String, double> categoryTotals = {};
    final Map<String, double> bookTotals = {};

    // Track seen (signature -> Set of bookIds) so two genuinely separate entries in the SAME book
    // are both counted, while copies of the same entry across DIFFERENT books are counted once.
    final Map<String, Set<int>> seenStandardTxBooks = {};
    final Map<String, Set<String>> seenSignatureCategories = {};

    for (final r in rows) {
      final int bookId = (r['bookId'] as num?)?.toInt() ?? 0;
      final String bType = r['bookType']?.toString() ?? 'standard';
      final String bName = r['bookName']?.toString() ?? 'Book';
      final String txType = r['type']?.toString() ?? 'Expense';
      final double amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final String rawCat = (r['category']?.toString() ?? '').trim();
      final String cat = rawCat.isEmpty ? 'Uncategorized' : rawCat;
      final String nameLower = (r['name']?.toString() ?? '').toLowerCase();
      final String catLower = cat.toLowerCase();

      if (bType == 'lending') {
        if (txType == 'Expense') {
          lendingGiven += amt;
        } else {
          lendingReturned += amt;
        }
        continue;
      }

      // 1. Per-book spending breakdown always reflects what is inside each individual book
      if (txType == 'Expense') {
        bookTotals[bName] = (bookTotals[bName] ?? 0) + amt;
      }

      // 2. Deduplicate across multiple books for overall totals & categories
      final String sig = _buildDedupeSignature(r);
      final Set<int> booksForSig = seenStandardTxBooks.putIfAbsent(sig, () => <int>{});
      final bool isDuplicateAcrossBooks = booksForSig.isNotEmpty && !booksForSig.contains(bookId);
      booksForSig.add(bookId);

      if (!isDuplicateAcrossBooks) {
        txCount++;
        if (txType == 'Income') {
          totalIncome += amt;
        } else {
          totalExpense += amt;
        }
      }

      if (txType == 'Expense') {
        final Set<String> catsForSig = seenSignatureCategories.putIfAbsent(sig, () => <String>{});
        // If the first book had 'Uncategorized' and another book has a specific category, upgrade it!
        if (catsForSig.contains('Uncategorized') && cat != 'Uncategorized') {
          catsForSig.remove('Uncategorized');
          final prevUncat = (categoryTotals['Uncategorized'] ?? 0) - amt;
          if (prevUncat <= 0.001) {
            categoryTotals.remove('Uncategorized');
          } else {
            categoryTotals['Uncategorized'] = prevUncat;
          }
        }

        // Count each unique transaction once per category
        if (!catsForSig.contains(cat)) {
          if (cat == 'Uncategorized' && catsForSig.isNotEmpty) {
            // Already categorized under a real category in another book; skip Uncategorized
          } else {
            catsForSig.add(cat);
            categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amt;

            if (catLower.contains('shop') || nameLower.contains('shop') || nameLower.contains('amazon') || nameLower.contains('flipkart') || nameLower.contains('myntra') || nameLower.contains('meesho')) {
              shoppingSpend += amt;
            }
            if (catLower.contains('grocer') || nameLower.contains('grocer') || nameLower.contains('milk') || nameLower.contains('vegetable') || nameLower.contains('kirana') || nameLower.contains('blinkit') || nameLower.contains('zepto') || nameLower.contains('instamart')) {
              grocerySpend += amt;
            }
            if (catLower.contains('food') || catLower.contains('dining') || nameLower.contains('zomato') || nameLower.contains('swiggy') || nameLower.contains('restaurant') || nameLower.contains('dominos')) {
              foodSpend += amt;
            }
          }
        }
      }
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedBooks = bookTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'netFlow': totalIncome - totalExpense,
      'shoppingSpend': shoppingSpend,
      'grocerySpend': grocerySpend,
      'foodSpend': foodSpend,
      'lendingGiven': lendingGiven,
      'lendingReturned': lendingReturned,
      'txCount': txCount,
      'categoryBreakdown': sortedCategories.map((e) => {'name': e.key, 'amount': e.value}).toList(),
      'bookBreakdown': sortedBooks.map((e) => {'name': e.key, 'amount': e.value}).toList(),
    };
  }

  Future<String> exportDatabaseJson() async {
    final db = await instance.database;
    final books = await db.query('books');
    final transactions = await db.query('transactions');
    final handledSms = await db.query('handled_sms');

    final payload = {
      'version': 5,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': books,
      'transactions': transactions,
      'handled_sms': handledSms,
    };
    return jsonEncode(payload);
  }

  Future<int> importDatabaseJson(String jsonString) async {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final books = (decoded['books'] as List<dynamic>?) ?? [];
    final transactions = (decoded['transactions'] as List<dynamic>?) ?? [];
    final handledSms = (decoded['handled_sms'] as List<dynamic>?) ?? [];

    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('books');
      await txn.delete('handled_sms');

      for (final b in books) {
        final map = Map<String, dynamic>.from(b as Map);
        map['bookType'] ??= 'standard';
        await txn.insert('books', map);
      }
      for (final t in transactions) {
        final map = Map<String, dynamic>.from(t as Map);
        map['smsBody'] ??= map['notes'] ?? '';
        await txn.insert('transactions', map);
      }
      for (final s in handledSms) {
        await txn.insert(
          'handled_sms',
          Map<String, dynamic>.from(s as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return books.length;
  }
}
