import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';

// ===========================================================================
// SHARED BANK ICON, MERCHANT ICON, CLOUD IMAGE BACKUP & UI HELPER
// ===========================================================================
class FinTraxBrandHelper {
  static final ValueNotifier<int> dataRefreshNotifier = ValueNotifier<int>(0);
  static Timer? _undoTimer;
  static Timer? _toastTimer;

  static const String vicesCategoryName = 'Vices & Addictions';

  /// Modern rounded floating status notification (replaces the old rectangular green bar)
  static void showModernSnackBar({
    required BuildContext context,
    required String message,
    IconData icon = Icons.check_circle_rounded,
    Color color = AppConstants.incomeGreen,
    Duration duration = const Duration(seconds: 2),
  }) {
    _toastTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: EdgeInsets.zero,
        duration: duration,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF121A2B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withOpacity(0.55),
              width: 1.15,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _toastTimer = Timer(duration, () {
      try {
        messenger.removeCurrentSnackBar();
      } catch (_) {}
    });
  }

  /// Modern rounded floating 2-second Undo bar (guaranteed to auto-dismiss on HyperOS/Android)
  static void showModernUndoBar({
    required ScaffoldMessengerState messenger,
    required String message,
    required VoidCallback onUndo,
  }) {
    _undoTimer?.cancel();
    messenger.clearSnackBars();

    bool undone = false;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 2),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF121A2B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppConstants.goldAccent.withOpacity(0.45),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppConstants.expenseRed.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppConstants.expenseRed,
                  size: 17,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: AppConstants.goldAccent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (undone) return;
                    undone = true;
                    _undoTimer?.cancel();
                    HapticFeedback.lightImpact();
                    messenger.removeCurrentSnackBar();
                    onUndo();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.undo_rounded, size: 14, color: Color(0xFF0E1726)),
                        SizedBox(width: 4),
                        Text(
                          'Undo',
                          style: TextStyle(
                            color: Color(0xFF0E1726),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _undoTimer = Timer(const Duration(seconds: 2), () {
      try {
        messenger.removeCurrentSnackBar();
      } catch (_) {}
    });
  }

  /// Copies picked images into permanent app storage so Android cache cleanup never deletes them
  static Future<String> persistPickedImageFile(String sourcePath) async {
    try {
      final srcFile = File(sourcePath);
      if (!srcFile.existsSync()) return sourcePath;
      final docDir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${docDir.path}/fintrax_attachments');
      if (!attachDir.existsSync()) {
        await attachDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
      final fileName = 'img_${DateTime.now().microsecondsSinceEpoch}$ext';
      final targetPath = '${attachDir.path}/$fileName';
      final copied = await srcFile.copy(targetPath);
      return copied.path;
    } catch (_) {
      return sourcePath;
    }
  }

  /// Embeds all attached receipt images & Lending book contacts into the Google Drive backup JSON
  static Future<String> enrichBackupJsonWithImagesAndContacts(String rawDbJson) async {
    try {
      final decoded = jsonDecode(rawDbJson) as Map<String, dynamic>;

      await _ensureContactsTable();
      final db = await DatabaseHelper.instance.database;
      final contactRows = await db.query('book_contacts');
      decoded['book_contacts'] = contactRows;

      final imageMap = <String, String>{};
      final txs = (decoded['transactions'] as List<dynamic>?) ?? [];
      for (final item in txs) {
        if (item is Map) {
          final rawPath = item['imagePath']?.toString() ?? '';
          final paths = parseImagePaths(rawPath);
          for (final p in paths) {
            if (!imageMap.containsKey(p)) {
              final f = File(p);
              if (f.existsSync()) {
                try {
                  final bytes = await f.readAsBytes();
                  if (bytes.isNotEmpty) {
                    imageMap[p] = base64Encode(bytes);
                  }
                } catch (_) {}
              }
            }
          }
        }
      }
      decoded['attached_images_base64'] = imageMap;
      return jsonEncode(decoded);
    } catch (_) {
      return rawDbJson;
    }
  }

  /// Restores Lending book contacts and recreates attached receipt image files from Google Drive JSON
  static Future<void> restoreImagesAndContactsFromBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final db = await DatabaseHelper.instance.database;

      await _ensureContactsTable();
      final contactsList = (decoded['book_contacts'] as List<dynamic>?) ?? [];
      for (final c in contactsList) {
        if (c is Map) {
          final bookId = c['bookId'];
          final phone = c['phone']?.toString() ?? '';
          final photoBase64 = c['photoBase64']?.toString() ?? '';
          if (bookId != null) {
            await db.rawInsert(
              'INSERT OR REPLACE INTO book_contacts (bookId, phone, photoBase64) VALUES (?, ?, ?)',
              [bookId, phone, photoBase64],
            );
          }
        }
      }

      final imageMapRaw = decoded['attached_images_base64'];
      if (imageMapRaw is Map && imageMapRaw.isNotEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        final attachDir = Directory('${docDir.path}/fintrax_attachments');
        if (!attachDir.existsSync()) {
          await attachDir.create(recursive: true);
        }

        final pathRemap = <String, String>{};
        int counter = 0;
        for (final entry in imageMapRaw.entries) {
          final oldPath = entry.key.toString();
          final b64 = entry.value?.toString() ?? '';
          if (b64.isEmpty) continue;
          try {
            final bytes = base64Decode(b64);
            if (bytes.isNotEmpty) {
              counter++;
              final newPath = '${attachDir.path}/restored_${DateTime.now().millisecondsSinceEpoch}_$counter.jpg';
              final outFile = File(newPath);
              await outFile.writeAsBytes(bytes, flush: true);
              pathRemap[oldPath] = newPath;
            }
          } catch (_) {}
        }

        if (pathRemap.isNotEmpty) {
          final txRows = await db.query('transactions');
          for (final row in txRows) {
            final txId = row['id'] as int?;
            final rawImg = row['imagePath']?.toString() ?? '';
            if (txId == null || rawImg.isEmpty) continue;
            final oldPaths = parseImagePaths(rawImg);
            bool changed = false;
            final updatedPaths = <String>[];
            for (final p in oldPaths) {
              if (pathRemap.containsKey(p)) {
                updatedPaths.add(pathRemap[p]!);
                changed = true;
              } else if (File(p).existsSync()) {
                updatedPaths.add(p);
              } else {
                changed = true;
              }
            }
            if (changed) {
              await db.update(
                'transactions',
                {'imagePath': joinImagePaths(updatedPaths)},
                where: 'id = ?',
                whereArgs: [txId],
              );
            }
          }
        }
      } else {
        // Clean out broken file paths from older backups that did not embed image bytes
        final txRows = await db.query('transactions');
        for (final row in txRows) {
          final txId = row['id'] as int?;
          final rawImg = row['imagePath']?.toString() ?? '';
          if (txId == null || rawImg.isEmpty) continue;
          final oldPaths = parseImagePaths(rawImg);
          final validPaths = oldPaths.where((p) => File(p).existsSync()).toList();
          if (validPaths.length != oldPaths.length) {
            await db.update(
              'transactions',
              {'imagePath': joinImagePaths(validPaths)},
              where: 'id = ?',
              whereArgs: [txId],
            );
          }
        }
      }
    } catch (_) {}
  }

  static const List<Map<String, String>> paymentMethods = [
    {'name': 'Cash', 'emoji': '💵', 'asset': ''},
    {'name': 'UPI', 'emoji': '📱', 'asset': 'assets/icons/upi.png'},
    {'name': 'Airtel', 'emoji': '🏦', 'asset': 'assets/icons/airtel.png'},
    {'name': 'Utkarsh SFBL', 'emoji': '💳', 'asset': 'assets/icons/Utkarsh.png'},
    {'name': 'Kotak Bank', 'emoji': '🏦', 'asset': 'assets/icons/kotak.png'},
    {'name': 'SBI', 'emoji': '🏦', 'asset': 'assets/icons/sbi.png'},
    {'name': 'ICICI Bank', 'emoji': '🏦', 'asset': 'assets/icons/icici.png'},
    {'name': 'Bank of Baroda', 'emoji': '🏦', 'asset': 'assets/icons/Baroda.png'},
    {'name': 'IPPB', 'emoji': '🏦', 'asset': 'assets/icons/ippb.png'},
    {'name': 'Google Pay', 'emoji': '📱', 'asset': 'assets/icons/Gpay.png'},
    {'name': 'PhonePe', 'emoji': '📱', 'asset': 'assets/icons/PhonePe.png'},
    {'name': 'Paytm', 'emoji': '📱', 'asset': 'assets/icons/paytm.png'},
    {'name': 'SuperMoney', 'emoji': '⚡', 'asset': 'assets/icons/SuperMoney.png'},
    {'name': 'Slice', 'emoji': '💳', 'asset': 'assets/icons/slice.png'},
    {'name': 'Navi', 'emoji': '📱', 'asset': 'assets/icons/navi.png'},
    {'name': 'PayPal', 'emoji': '🌐', 'asset': 'assets/icons/paypal.png'},
    {'name': 'JioPay', 'emoji': '📱', 'asset': 'assets/icons/jio.png'},
    {'name': 'Card', 'emoji': '💳', 'asset': ''},
    {'name': 'Bank Transfer', 'emoji': '🏦', 'asset': ''},
    {'name': 'Online', 'emoji': '🌐', 'asset': 'assets/icons/upi.png'},
  ];

  static List<Map<String, String>> get allCategories {
    final base = List<Map<String, String>>.from(AppConstants.categories)
        .where((c) => (c['name'] ?? '').toLowerCase() != 'food')
        .toList();

    final result = <Map<String, String>>[
      {'name': vicesCategoryName, 'emoji': '🚭'},
      ...base,
    ];

    if (!result.any((c) => (c['name'] ?? '').toLowerCase() == 'investment')) {
      result.add({'name': 'Investment', 'emoji': '📈'});
    }
    if (!result.any((c) => (c['name'] ?? '').toLowerCase() == 'emi')) {
      result.add({'name': 'EMI', 'emoji': '🏦'});
    }
    return result;
  }

  static String getCategoryEmoji(String? catName) {
    if (catName == null || catName.trim().isEmpty) return '🏷️';
    final lower = catName.trim().toLowerCase();
    if (lower == 'food') return '🍔';
    for (final c in allCategories) {
      if ((c['name'] ?? '').toLowerCase() == lower) {
        return c['emoji'] ?? '🏷️';
      }
    }
    return '🏷️';
  }

  static String resolveMerchantTitle(String currentName, String smsBody) {
    final trimmed = currentName.trim();
    final lowerName = trimmed.toLowerCase();
    final lowerSms = smsBody.toLowerCase();

    final bool isRawSenderCode = trimmed.isEmpty ||
        lowerName.contains('utkspr') ||
        lowerName.contains('airbnk') ||
        lowerName.contains('kbankt') ||
        lowerName.contains('sbipsg') ||
        lowerName.contains('hdfcbk') ||
        lowerName.contains('icicib') ||
        lowerName.contains('axisbk') ||
        lowerName.contains('bobtxn') ||
        RegExp(r'^[a-z]{2}-[a-z0-9-]+$', caseSensitive: false).hasMatch(trimmed) ||
        RegExp(r'^[a-z0-9]{5,8}-[sptg]$', caseSensitive: false).hasMatch(trimmed);

    if (!isRawSenderCode) {
      return trimmed;
    }

    if (lowerSms.contains('flipkart')) return 'Flipkart';
    if (lowerSms.contains('instamart')) return 'Swiggy Instamart';
    if (lowerSms.contains('swiggy')) return 'Swiggy';
    if (lowerSms.contains('zomato')) return 'Zomato';
    if (lowerSms.contains('blinkit')) return 'Blinkit';
    if (lowerSms.contains('amazon') || lowerSms.contains('amzn')) return 'Amazon';
    if (lowerSms.contains('myntra')) return 'Myntra';
    if (lowerSms.contains('meesho')) return 'Meesho';
    if (lowerSms.contains('dominos') || lowerSms.contains("domino's")) return 'Dominos';
    if (lowerSms.contains('zerodha')) return 'Zerodha';
    if (lowerSms.contains('groww')) return 'Groww';
    if (lowerSms.contains('upstox')) return 'Upstox';
    if (lowerSms.contains('angel one') || lowerSms.contains('angelbroking')) return 'Angel One';
    if (lowerSms.contains('indmoney')) return 'INDmoney';
    if (lowerSms.contains('kuvera')) return 'Kuvera';
    if (lowerSms.contains('jio')) return 'Jio';

    final atMatch = RegExp(
      r'(?:supercard\s+at|spent\s+at|paid\s+to|sent\s+to|trf\s+to)\s+([A-Za-z0-9][A-Za-z0-9 &._-]{1,30}?)(?:\s+internet\s+priva|\s+pvt|\s+private|\s+on\b|\s+available\b|\.|\s*$)',
      caseSensitive: false,
    ).firstMatch(smsBody);
    if (atMatch != null) {
      final extracted = atMatch.group(1)?.trim() ?? '';
      if (extracted.isNotEmpty) {
        return _toTitleCase(extracted);
      }
    }

    if (lowerSms.contains('received payment') && lowerSms.contains('supercard')) {
      return 'SuperCard Bill Payment';
    }

    return trimmed.isEmpty ? 'Bank Transaction' : trimmed;
  }

  static String _toTitleCase(String input) {
    return input
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  static String detectPaymentMethod({
    String currentMode = '',
    String smsBody = '',
    String sender = '',
  }) {
    final combined = '$sender $smsBody $currentMode'.toLowerCase();

    if (combined.contains('airbnk') || combined.contains('airtel payments bank') || combined.contains('airtel')) {
      return 'Airtel';
    }
    if (combined.contains('utkspr') || combined.contains('utkarsh') || combined.contains('supercard')) {
      return 'Utkarsh SFBL';
    }
    if (combined.contains('kotak') || combined.contains('kbankt')) {
      return 'Kotak Bank';
    }
    if (combined.contains('state bank') || RegExp(r'\bsbi\b').hasMatch(combined) || combined.contains('sbipsg')) {
      return 'SBI';
    }
    if (combined.contains('icici')) {
      return 'ICICI Bank';
    }
    if (combined.contains('baroda') || RegExp(r'\bbob\b').hasMatch(combined)) {
      return 'Bank of Baroda';
    }
    if (combined.contains('ippb') || combined.contains('india post')) {
      return 'IPPB';
    }
    if (combined.contains('supermoney') || combined.contains('super.money')) {
      return 'SuperMoney';
    }
    if (combined.contains('slice')) {
      return 'Slice';
    }
    if (combined.contains('navi')) {
      return 'Navi';
    }
    if (combined.contains('phonepe')) {
      return 'PhonePe';
    }
    if (combined.contains('gpay') || combined.contains('google pay')) {
      return 'Google Pay';
    }
    if (combined.contains('paytm')) {
      return 'Paytm';
    }
    if (combined.contains('paypal')) {
      return 'PayPal';
    }
    if (combined.contains('jiopay')) {
      return 'JioPay';
    }
    if (combined.contains('upi')) {
      return 'UPI';
    }

    if (currentMode.trim().isNotEmpty) {
      return currentMode.trim();
    }
    return 'Cash';
  }

  static String? getPaymentIconAsset(String paymentMode, {String smsBody = '', String sender = ''}) {
    final resolved = detectPaymentMethod(currentMode: paymentMode, smsBody: smsBody, sender: sender);
    for (final item in paymentMethods) {
      if (item['name']!.toLowerCase() == resolved.toLowerCase()) {
        final asset = item['asset'] ?? '';
        return asset.isNotEmpty ? asset : null;
      }
    }
    return null;
  }

  static String getPaymentEmoji(String paymentMode) {
    for (final item in paymentMethods) {
      if (item['name']!.toLowerCase() == paymentMode.toLowerCase()) {
        return item['emoji'] ?? '💳';
      }
    }
    return AppConstants.paymentModeEmojis[paymentMode] ?? '💳';
  }

  static String? getMerchantIconAsset(String name, {String smsBody = ''}) {
    final text = '$name $smsBody'.toLowerCase();
    if (text.contains('flipkart')) return 'assets/icons/Flipkart.png';
    if (text.contains('amazon') || text.contains('amzn')) return 'assets/icons/amazon.png';
    if (text.contains('myntra')) return 'assets/icons/Myntra.png';
    if (text.contains('meesho')) return 'assets/icons/meesho.png';
    if (text.contains('swiggy') || text.contains('instamart')) return 'assets/icons/swiggy.png';
    if (text.contains('zomato') || text.contains('blinkit')) return 'assets/icons/zomato.png';
    if (text.contains('jio')) return 'assets/icons/jio.png';
    return null;
  }

  static Future<void> _ensureContactsTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_contacts (
        bookId INTEGER PRIMARY KEY,
        phone TEXT,
        photoBase64 TEXT
      )
    ''');
  }

  static Future<void> saveBookContact(int bookId, String phone, String photoBase64) async {
    await _ensureContactsTable();
    final db = await DatabaseHelper.instance.database;
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty && photoBase64.isEmpty) {
      await db.delete('book_contacts', where: 'bookId = ?', whereArgs: [bookId]);
      return;
    }
    await db.rawInsert(
      'INSERT OR REPLACE INTO book_contacts (bookId, phone, photoBase64) VALUES (?, ?, ?)',
      [bookId, cleanPhone, photoBase64],
    );
  }

  static Future<Map<String, String>> getBookContact(int bookId) async {
    await _ensureContactsTable();
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('book_contacts', where: 'bookId = ?', whereArgs: [bookId]);
    if (rows.isEmpty) return {'phone': '', 'photoBase64': ''};
    return {
      'phone': rows.first['phone']?.toString() ?? '',
      'photoBase64': rows.first['photoBase64']?.toString() ?? '',
    };
  }

  static Future<Map<int, Map<String, String>>> getAllBookContacts() async {
    await _ensureContactsTable();
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('book_contacts');
    final map = <int, Map<String, String>>{};
    for (final r in rows) {
      final id = r['bookId'] as int?;
      if (id != null) {
        map[id] = {
          'phone': r['phone']?.toString() ?? '',
          'photoBase64': r['photoBase64']?.toString() ?? '',
        };
      }
    }
    return map;
  }

  static String? detectCategory(String name, {String smsBody = '', String currentCategory = ''}) {
    if (currentCategory.trim().isNotEmpty) {
      if (currentCategory.trim().toLowerCase() == 'food') return 'Food & Dining';
      return currentCategory.trim();
    }
    final text = '$name $smsBody'.toLowerCase();

    if (RegExp(r'\bsip\b').hasMatch(text) ||
        text.contains('mutual fund') ||
        RegExp(r'\bmf\b').hasMatch(text) ||
        text.contains('folio') ||
        text.contains('units allotted') ||
        RegExp(r'\bnav\b').hasMatch(text) ||
        text.contains('zerodha') ||
        text.contains('groww') ||
        text.contains('upstox') ||
        text.contains('angel one') ||
        text.contains('angelbroking') ||
        text.contains('indmoney') ||
        text.contains('kuvera') ||
        text.contains('etmoney') ||
        text.contains('smallcase') ||
        text.contains('stock') ||
        text.contains('equity') ||
        text.contains('demat') ||
        text.contains('cdsl') ||
        text.contains('nsdl') ||
        RegExp(r'\bnse\b').hasMatch(text) ||
        RegExp(r'\bbse\b').hasMatch(text)) {
      return 'Investment';
    }

    if (text.contains('cigarette') ||
        text.contains('smoke') ||
        text.contains('tobacco') ||
        text.contains('vape') ||
        text.contains('hookah') ||
        text.contains('alcohol') ||
        text.contains('liquor') ||
        text.contains('wine shop') ||
        text.contains('beer') ||
        text.contains('whisky') ||
        text.contains('vodka') ||
        text.contains('casino') ||
        text.contains('dream11') ||
        text.contains('betting')) {
      return vicesCategoryName;
    }

    if (text.contains('instamart') ||
        text.contains('flipkart') ||
        text.contains('amazon') ||
        text.contains('amzn') ||
        text.contains('meesho') ||
        text.contains('myntra') ||
        text.contains('ajio') ||
        text.contains('nykaa')) {
      return 'Shopping';
    }

    if (text.contains('zomato') ||
        text.contains('swiggy') ||
        text.contains('dominos') ||
        text.contains("domino's") ||
        text.contains('kfc') ||
        text.contains('mcdonald') ||
        text.contains('pizza hut') ||
        text.contains('burger king')) {
      return 'Food & Dining';
    }

    return null;
  }

  static List<String> parseImagePaths(String rawImagePath) {
    if (rawImagePath.trim().isEmpty) return [];
    return rawImagePath
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String joinImagePaths(List<String> paths) {
    return paths.map((s) => s.trim()).where((s) => s.isNotEmpty).join('|');
  }

  static Widget buildIconBadge({
    required String? assetPath,
    required String fallbackEmoji,
    double size = 20,
    double borderRadius = 6,
  }) {
    if (assetPath != null && assetPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(fallbackEmoji, style: TextStyle(fontSize: size * 0.78)),
        ),
      );
    }
    return Text(fallbackEmoji, style: TextStyle(fontSize: size * 0.78));
  }
}

// ===========================================================================
// ADD / EDIT TRANSACTION SCREEN
// ===========================================================================
class AddTransactionScreen extends StatefulWidget {
  final int bookId;
  final String type;
  final TransactionModel? existingTransaction;
  final bool isSmsDraft;

  const AddTransactionScreen({
    Key? key,
    required this.bookId,
    required this.type,
    this.existingTransaction,
    this.isSmsDraft = false,
  }) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  late String _selectedType;
  String? _selectedCategory;
  late String _paymentMode;
  late DateTime _selectedDate;
  List<String> _imagePaths = [];
  String _smsText = '';

  late TextEditingController _amountController;
  late TextEditingController _nameController;
  late TextEditingController _notesController;

  List<Map<String, dynamic>> _otherBooks = [];
  final Set<int> _selectedExtraBookIds = <int>{};

  bool get _isEditingExisting =>
      widget.existingTransaction != null && widget.existingTransaction?.id != null && !widget.isSmsDraft;

  List<Map<String, String>> get _allCategories => FinTraxBrandHelper.allCategories;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
    _selectedDate = widget.existingTransaction?.date ?? DateTime.now();
    _amountController = TextEditingController(
      text: widget.existingTransaction != null ? widget.existingTransaction!.amount.toStringAsFixed(0) : '',
    );

    _smsText = widget.existingTransaction?.effectiveSmsText ?? '';
    final rawName = widget.existingTransaction?.name ?? '';
    final resolvedTitle = _smsText.isNotEmpty
        ? FinTraxBrandHelper.resolveMerchantTitle(rawName, _smsText)
        : rawName;

    _nameController = TextEditingController(text: resolvedTitle);
    _notesController = TextEditingController(
      text: widget.isSmsDraft ? '' : (widget.existingTransaction?.notes ?? ''),
    );

    final existingCat = widget.existingTransaction?.category ?? '';
    _selectedCategory = FinTraxBrandHelper.detectCategory(
      _nameController.text,
      smsBody: _smsText,
      currentCategory: existingCat,
    );

    final initialMode = widget.existingTransaction?.paymentMode ?? 'Cash';
    _paymentMode = FinTraxBrandHelper.detectPaymentMethod(
      currentMode: initialMode,
      smsBody: _smsText,
      sender: rawName,
    );

    // Filter out any non-existent broken paths from older restores so new attachments work cleanly
    final rawPaths = FinTraxBrandHelper.parseImagePaths(widget.existingTransaction?.imagePath ?? '');
    _imagePaths = rawPaths;
    _nameController.addListener(_onMerchantNameChanged);
    _loadOtherBooks();
  }

  void _onMerchantNameChanged() {
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      final autoCat = FinTraxBrandHelper.detectCategory(_nameController.text, smsBody: _smsText);
      if (autoCat != null && mounted) {
        setState(() => _selectedCategory = autoCat);
      }
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onMerchantNameChanged);
    _amountController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOtherBooks() async {
    try {
      final allBooks = await DatabaseHelper.instance.getBooksWithBalances();
      final filtered = allBooks.where((b) => (b['id'] as int) != widget.bookId).toList();
      if (mounted) {
        setState(() => _otherBooks = filtered);
      }
    } catch (_) {}
  }

  Future<void> _pickTransactionDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'SELECT TRANSACTION DATE',
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDate = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  Future<void> _confirmAndDeleteImage(int idx) async {
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do you want to delete?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: const Text(
          'Remove this attached image from the entry?',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final String removedPath = _imagePaths[idx];
      setState(() => _imagePaths.removeAt(idx));
      FinTraxBrandHelper.showModernUndoBar(
        messenger: ScaffoldMessenger.of(context),
        message: 'Image removed',
        onUndo: () {
          if (mounted) {
            setState(() {
              final insertPos = idx.clamp(0, _imagePaths.length);
              _imagePaths.insert(insertPos, removedPath);
            });
          }
        },
      );
    }
  }

  Future<void> _confirmAndDeleteEntry() async {
    if (!_isEditingExisting) return;
    HapticFeedback.mediumImpact();
    final txToBackup = widget.existingTransaction!;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do you want to delete?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          'Delete "${txToBackup.name}" from this book?',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      final backupMap = txToBackup.toMap();
      await DatabaseHelper.instance.deleteTransaction(txToBackup.id!, widget.bookId);
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);

      FinTraxBrandHelper.showModernUndoBar(
        messenger: messenger,
        message: 'Deleted "${txToBackup.name}"',
        onUndo: () async {
          final db = await DatabaseHelper.instance.database;
          await db.insert('transactions', backupMap);
          FinTraxBrandHelper.dataRefreshNotifier.value++;
        },
      );
    }
  }

  Widget _buildTwoColumnGridTile({
    required bool isDark,
    required Widget leadingIcon,
    required String title,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
    bool isWarningHabit = false,
  }) {
    final Color effectiveAccent = isWarningHabit ? AppConstants.expenseRed : accentColor;
    final Color cardBg = isSelected
        ? effectiveAccent.withOpacity(isDark ? 0.20 : 0.12)
        : isWarningHabit
            ? AppConstants.expenseRed.withOpacity(isDark ? 0.08 : 0.05)
            : (isDark ? const Color(0xFF1A1C22) : const Color(0xFFF8FAFC));

    final Color borderColor = isSelected
        ? effectiveAccent
        : isWarningHabit
            ? AppConstants.expenseRed.withOpacity(0.35)
            : (isDark ? AppConstants.borderDark : AppConstants.borderLight);

    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: borderColor, width: isSelected ? 1.4 : 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withOpacity(0.35) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: leadingIcon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isWarningHabit ? AppConstants.expenseRed : null,
                    fontWeight: isSelected || isWarningHabit ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: effectiveAccent, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategoryPicker(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;
    final options = <Map<String, String?>>[
      {'name': null, 'label': 'None', 'emoji': '🚫'},
      ..._allCategories.map((c) => {'name': c['name'], 'label': c['name'], 'emoji': c['emoji']}),
    ];

    final rows = <Widget>[];
    for (int i = 0; i < options.length; i += 2) {
      final first = options[i];
      final second = (i + 1 < options.length) ? options[i + 1] : null;
      final bool firstIsVice = first['name'] == FinTraxBrandHelper.vicesCategoryName;
      final bool secondIsVice = second != null && second['name'] == FinTraxBrandHelper.vicesCategoryName;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildTwoColumnGridTile(
                  isDark: isDark,
                  leadingIcon: Text(first['emoji'] ?? '🏷️', style: const TextStyle(fontSize: 15)),
                  title: first['label'] ?? 'None',
                  isSelected: _selectedCategory == first['name'],
                  accentColor: scheme.primary,
                  isWarningHabit: firstIsVice,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = first['name']);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: second != null
                    ? _buildTwoColumnGridTile(
                        isDark: isDark,
                        leadingIcon: Text(second['emoji'] ?? '🏷️', style: const TextStyle(fontSize: 15)),
                        title: second['label'] ?? '',
                        isSelected: _selectedCategory == second['name'],
                        accentColor: scheme.primary,
                        isWarningHabit: secondIsVice,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = second['name']);
                          Navigator.pop(context);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.68),
          decoration: BoxDecoration(
            color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Category', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    children: rows,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPaymentModePicker(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;
    const methods = FinTraxBrandHelper.paymentMethods;

    final rows = <Widget>[];
    for (int i = 0; i < methods.length; i += 2) {
      final first = methods[i];
      final second = (i + 1 < methods.length) ? methods[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildTwoColumnGridTile(
                  isDark: isDark,
                  leadingIcon: FinTraxBrandHelper.buildIconBadge(
                    assetPath: first['asset'],
                    fallbackEmoji: first['emoji'] ?? '💳',
                    size: 20,
                  ),
                  title: first['name']!,
                  isSelected: _paymentMode.toLowerCase() == first['name']!.toLowerCase(),
                  accentColor: scheme.primary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _paymentMode = first['name']!);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: second != null
                    ? _buildTwoColumnGridTile(
                        isDark: isDark,
                        leadingIcon: FinTraxBrandHelper.buildIconBadge(
                          assetPath: second['asset'],
                          fallbackEmoji: second['emoji'] ?? '💳',
                          size: 20,
                        ),
                        title: second['name']!,
                        isSelected: _paymentMode.toLowerCase() == second['name']!.toLowerCase(),
                        accentColor: scheme.primary,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _paymentMode = second['name']!);
                          Navigator.pop(context);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
          decoration: BoxDecoration(
            color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Payment Method / Bank', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    children: rows,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openOtherBooksSheet(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isEditingExisting ? 'Also Copy Entry to Books' : 'Also Add to Other Books',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _otherBooks.length,
                      itemBuilder: (_, idx) {
                        final book = _otherBooks[idx];
                        final int id = book['id'] as int;
                        final String name = book['name'].toString();
                        final bool isLending = (book['bookType']?.toString() ?? 'standard') == 'lending';
                        final bool isSelected = _selectedExtraBookIds.contains(id);

                        return CheckboxListTile(
                          secondary: Icon(
                            isLending ? Icons.handshake_rounded : Icons.book_rounded,
                            color: isSelected ? scheme.primary : Colors.grey[500],
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          value: isSelected,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              if (val == true) {
                                _selectedExtraBookIds.add(id);
                              } else {
                                _selectedExtraBookIds.remove(id);
                              }
                            });
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text(
                          _selectedExtraBookIds.isEmpty
                              ? 'Done'
                              : 'Done (${_selectedExtraBookIds.length} Selected)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickImages() async {
    HapticFeedback.selectionClick();
    // Automatically clean out any missing/corrupted paths before adding new ones
    _imagePaths.removeWhere((p) => !File(p).existsSync());

    try {
      final List<XFile> pickedList = await _picker.pickMultiImage(
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 78,
      );
      if (pickedList.isNotEmpty && mounted) {
        final savedPaths = <String>[];
        for (final item in pickedList) {
          final permanentPath = await FinTraxBrandHelper.persistPickedImageFile(item.path);
          savedPaths.add(permanentPath);
        }
        if (mounted) {
          setState(() {
            for (final p in savedPaths) {
              if (!_imagePaths.contains(p)) {
                _imagePaths.add(p);
              }
            }
          });
        }
        return;
      }
    } catch (_) {
      final XFile? single = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 78,
      );
      if (single != null && mounted) {
        final permanentPath = await FinTraxBrandHelper.persistPickedImageFile(single.path);
        if (mounted) {
          setState(() {
            if (!_imagePaths.contains(permanentPath)) {
              _imagePaths.add(permanentPath);
            }
          });
        }
      }
    }
  }

  void _openImageGalleryFullScreen(int initialIndex) {
    HapticFeedback.lightImpact();
    final pageCtrl = PageController(initialPage: initialIndex);
    int currentIdx = initialIndex;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setGalleryState) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                'Attachment ${currentIdx + 1} of ${_imagePaths.length}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            body: PageView.builder(
              controller: pageCtrl,
              itemCount: _imagePaths.length,
              onPageChanged: (i) => setGalleryState(() => currentIdx = i),
              itemBuilder: (_, idx) {
                final file = File(_imagePaths[idx]);
                final exists = file.existsSync();
                return Center(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: exists
                        ? Image.file(
                            file,
                            errorBuilder: (_, __, ___) => const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                                SizedBox(height: 12),
                                Text(
                                  'Unable to load this image file',
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 64),
                              SizedBox(height: 12),
                              Text(
                                'Image Missing on Device\n(Delete this attachment & re-attach)',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    final double? parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      FinTraxBrandHelper.showModernSnackBar(
        context: context,
        message: 'Please enter a valid amount.',
        icon: Icons.error_outline_rounded,
        color: AppConstants.expenseRed,
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final validPaths = _imagePaths.where((p) => File(p).existsSync()).toList();
    final bool isNewInsert = widget.existingTransaction == null || widget.existingTransaction?.id == null;

    final transaction = TransactionModel(
      id: widget.existingTransaction?.id,
      bookId: widget.bookId,
      type: _selectedType,
      amount: parsedAmount,
      name: _nameController.text.trim().isEmpty ? 'Untitled Entry' : _nameController.text.trim(),
      category: _selectedCategory ?? '',
      notes: _notesController.text.trim(),
      smsBody: _smsText,
      date: _selectedDate,
      currency: AppConstants.defaultCurrency,
      paymentMode: _paymentMode,
      imagePath: FinTraxBrandHelper.joinImagePaths(validPaths),
    );

    if (isNewInsert) {
      final targetBooks = <int>[widget.bookId, ..._selectedExtraBookIds];
      await DatabaseHelper.instance.insertTransactionToMultipleBooks(transaction, targetBooks);
    } else {
      await DatabaseHelper.instance.updateTransaction(transaction);
      if (_selectedExtraBookIds.isNotEmpty) {
        await DatabaseHelper.instance.copyTransactionToBooks(transaction, _selectedExtraBookIds.toList());
      }
    }

    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildImagePreviewTile(bool isDark, int idx, {double? width, required double height}) {
    final path = _imagePaths[idx];
    final file = File(path);
    final exists = file.existsSync();

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181A20) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF323642) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          GestureDetector(
            onTap: () => _openImageGalleryFullScreen(idx),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: exists
                  ? Image.file(
                      file,
                      key: ValueKey(path),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: double.infinity,
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_rounded, color: Colors.grey, size: 28),
                            SizedBox(height: 4),
                            Text('Corrupted Image', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      height: double.infinity,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 28),
                          SizedBox(height: 4),
                          Text(
                            'Missing on Device • Tap X to remove',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, size: 16, color: Colors.white),
                onPressed: () => _confirmAndDeleteImage(idx),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptiveImagesSection(bool isDark) {
    if (_imagePaths.length == 1) {
      return _buildImagePreviewTile(isDark, 0, width: double.infinity, height: 165);
    }
    if (_imagePaths.length == 2) {
      return Row(
        children: [
          Expanded(child: _buildImagePreviewTile(isDark, 0, height: 145)),
          const SizedBox(width: 10),
          Expanded(child: _buildImagePreviewTile(isDark, 1, height: 145)),
        ],
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _imagePaths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, idx) => _buildImagePreviewTile(isDark, idx, width: 130, height: 130),
      ),
    );
  }

  Widget _buildCompactSelectorCard({
    required bool isDark,
    required String label,
    required String valueText,
    required Widget iconWidget,
    required VoidCallback onTap,
    Color? valueColor,
  }) {
    return Material(
      color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: iconWidget,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelectorRow(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickTransactionDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 19, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Date: ${AppConstants.formatOrdinalDate(_selectedDate)}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Change Date',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermanentSmsCard(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.cardDark : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.primary.withOpacity(isDark ? 0.35 : 0.28),
          width: 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sms_rounded, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Transaction SMS Record',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                AppConstants.formatOrdinalDateTime(_selectedDate),
                style: TextStyle(fontSize: 10.5, color: Colors.grey[500], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _smsText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMultiBookButton(bool isDark) {
    if (_otherBooks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final int count = _selectedExtraBookIds.length;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: count > 0 ? scheme.primary : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
            width: count > 0 ? 1.3 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openOtherBooksSheet(isDark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.library_add_check_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditingExisting ? 'Also Copy Entry to Other Books' : 'Also Add to Other Books',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count selected',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                  )
                else
                  Text('Select', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_right_rounded, size: 18, color: Colors.grey[500]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isIncome = _selectedType == 'Income';
    final String screenTitle = widget.isSmsDraft
        ? 'Review SMS $_selectedType'
        : (widget.existingTransaction == null ? 'Add $_selectedType' : 'Edit $_selectedType');

    final paymentIconAsset = FinTraxBrandHelper.getPaymentIconAsset(_paymentMode, smsBody: _smsText);
    final merchantAppAsset = FinTraxBrandHelper.getMerchantIconAsset(_nameController.text, smsBody: _smsText);
    final bool isVicesSelected = _selectedCategory == FinTraxBrandHelper.vicesCategoryName;

    final Color dullNoteColor = isDark ? Colors.grey[600]! : Colors.grey[400]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
        actions: [
          if (_isEditingExisting)
            IconButton(
              tooltip: 'Delete Entry',
              icon: const Icon(Icons.delete_outline_rounded, color: AppConstants.expenseRed),
              onPressed: _confirmAndDeleteEntry,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _amountController,
              autofocus: widget.existingTransaction == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: isIncome ? AppConstants.incomeGreen : AppConstants.expenseRed,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${AppConstants.defaultCurrency})',
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter an amount' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Remark / Title (e.g., Milk, Shoe, etc.)',
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildCompactSelectorCard(
                    isDark: isDark,
                    label: 'Category',
                    valueText: _selectedCategory ?? 'None',
                    valueColor: isVicesSelected ? AppConstants.expenseRed : null,
                    iconWidget: FinTraxBrandHelper.buildIconBadge(
                      assetPath: merchantAppAsset,
                      fallbackEmoji: FinTraxBrandHelper.getCategoryEmoji(_selectedCategory),
                      size: 20,
                    ),
                    onTap: () => _openCategoryPicker(isDark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildCompactSelectorCard(
                    isDark: isDark,
                    label: 'Payment Mode',
                    valueText: _paymentMode,
                    iconWidget: FinTraxBrandHelper.buildIconBadge(
                      assetPath: paymentIconAsset,
                      fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(_paymentMode),
                      size: 20,
                    ),
                    onTap: () => _openPaymentModePicker(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDateSelectorRow(isDark),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                labelStyle: TextStyle(color: dullNoteColor, fontSize: 13.5, fontWeight: FontWeight.w400),
                floatingLabelStyle: TextStyle(color: dullNoteColor, fontSize: 12, fontWeight: FontWeight.w500),
                hintText: 'Add any extra details about this payment...',
                hintStyle: TextStyle(color: dullNoteColor, fontSize: 13, fontWeight: FontWeight.w400),
                prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 20, color: dullNoteColor),
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_smsText.isNotEmpty) _buildPermanentSmsCard(isDark),
            _buildCompactMultiBookButton(isDark),
            const SizedBox(height: 14),
            Material(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickImages,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _imagePaths.isEmpty
                              ? 'Attach Receipt or Screenshot(s)'
                              : 'Add More Images (${_imagePaths.length} attached)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      Icon(Icons.add_circle_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
            if (_imagePaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildAdaptiveImagesSection(isDark),
              const SizedBox(height: 6),
              Text(
                'Tap any image to view full screen • Tap + above to attach more',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 26),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saveTransaction,
              child: Text(
                _selectedExtraBookIds.isEmpty
                    ? 'Save Entry'
                    : 'Save in ${1 + _selectedExtraBookIds.length} Books',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
