import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';
import '../theme/theme_provider.dart';
import 'add_transaction_screen.dart';
import 'welcome_and_logs_screen.dart';

class _DriveAuthSession {
  final String email;
  final Map<String, String> headers;
  const _DriveAuthSession({required this.email, required this.headers});
}

// ===========================================================================
// MODULAR CLOUD SYNC, SMART 8-BOOK MERGE & MONTHLY INSIGHTS HELPER
// ===========================================================================
class FinTraxCloudAndInsightsHelper {
  static const MethodChannel _nativeBridge = MethodChannel('com.chandankumar.fintrack/sms');
  static const String _driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const String _backupFileName = 'fintrax_cloud_backup.json';
  static const String _webServerClientId =
      '174741660325-qh2rr5oid0pd90nhp8ugn6qfqffuvonj.apps.googleusercontent.com';

  static final GoogleSignIn googleAuthPrimary = GoogleSignIn(
    scopes: <String>[_driveAppDataScope],
    serverClientId: _webServerClientId,
  );

  static final GoogleSignIn _googleAuthFallback = GoogleSignIn(
    scopes: <String>[],
  );

  static const List<String> monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static String todayStamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // SMS DEDUPLICATION AGAINST RESTORED / EXISTING TRANSACTIONS
  // ===========================================================================
  /// Marks any phone SMS that matches an already-saved transaction in any book as 'added'
  /// so restored books never show duplicate pending SMS suggestions.
  static Future<void> syncRestoredTransactionsWithSmsInbox() async {
    try {
      final permitted = await _nativeBridge
              .invokeMethod<bool>('checkSmsPermission')
              .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
          false;
      if (!permitted) return;

      final db = await DatabaseHelper.instance.database;
      final txRows = await db.query('transactions');
      if (txRows.isEmpty) return;

      final savedSmsBodies = <String>{};
      final savedTxFingerprints = <Map<String, dynamic>>[];

      for (final r in txRows) {
        final smsBody = (r['smsBody']?.toString() ?? '').trim();
        if (smsBody.isNotEmpty) {
          savedSmsBodies.add(_normalizeSmsText(smsBody));
        }
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final dt = DateTime.tryParse(r['date']?.toString() ?? '');
        if (amt > 0 && dt != null) {
          savedTxFingerprints.add({'amount': amt, 'date': dt});
        }
      }

      final rawList = await _nativeBridge
              .invokeMethod<List<dynamic>>('getBankSms')
              .timeout(const Duration(seconds: 4), onTimeout: () => <dynamic>[]) ??
          [];

      final matchedIds = <String>[];
      for (final item in rawList) {
        if (item is Map) {
          final parsed = ParsedSmsTransaction.tryParse(item);
          if (parsed != null) {
            final normBody = _normalizeSmsText(parsed.body);
            bool alreadyInBook = savedSmsBodies.contains(normBody);

            if (!alreadyInBook) {
              for (final fp in savedTxFingerprints) {
                final double txAmt = fp['amount'] as double;
                final DateTime txDate = fp['date'] as DateTime;
                if ((txAmt - parsed.amount).abs() < 0.01 &&
                    txDate.difference(parsed.date).inMinutes.abs() <= 10) {
                  alreadyInBook = true;
                  break;
                }
              }
            }

            if (alreadyInBook) {
              matchedIds.add(parsed.smsId);
            }
          }
        }
      }

      if (matchedIds.isNotEmpty) {
        await DatabaseHelper.instance.markMultipleSmsHandled(matchedIds, 'added');
        AppLogger.instance.log(
          'Auto-marked ${matchedIds.length} SMS messages as already added from restored books.',
          tag: 'SMS_SYNC',
        );
      }
    } catch (e) {
      AppLogger.instance.log('syncRestoredTransactionsWithSmsInbox notice: $e', tag: 'WARN');
    }
  }

  static String _normalizeSmsText(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  // ===========================================================================
  // UNIVERSAL 3-TIER GOOGLE DRIVE AUTH (WORKS ON CUSTOM ROMS & MI A1)
  // ===========================================================================
  static void _showProgressModal(BuildContext context, String label) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.8)),
            const SizedBox(width: 18),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  static void _showErrorModal(BuildContext context, String heading, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppConstants.expenseRed),
            const SizedBox(width: 10),
            Expanded(child: Text(heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ],
        ),
        content: SingleChildScrollView(child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45))),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogsScreen()));
            },
            icon: const Icon(Icons.bug_report_outlined, size: 18),
            label: const Text('View Logs'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  static Future<GoogleSignInAccount?> _attemptPluginSignIn(
    GoogleSignIn client, {
    required bool forceAccountPicker,
    required String label,
  }) async {
    if (forceAccountPicker) {
      try {
        await client.signOut();
      } catch (e) {
        AppLogger.instance.log('[$label] Ignored signOut notice: $e', tag: 'WARN');
      }
    }
    GoogleSignInAccount? user = forceAccountPicker ? null : client.currentUser;
    if (user == null && !forceAccountPicker) {
      try {
        user = await client.signInSilently();
      } catch (_) {
        user = null;
      }
    }
    user ??= await client.signIn();
    return user;
  }

  static Future<_DriveAuthSession?> _authenticateForDrive(
    BuildContext context,
    ThemeProvider prefs, {
    bool switchAccount = false,
  }) async {
    final certInfo = await AppLogger.instance.logRuntimeEnvironment(googleAuthPrimary, prefs);
    final livePkg = certInfo['packageName'] ?? 'com.chandsy.fintrax';
    final liveSha1 = certInfo['sha1'] ?? 'UNKNOWN';

    // Always show the account chooser popup if user tapped Connect/Switch OR no account is connected yet
    final bool forcePicker = switchAccount || prefs.driveAccount.isEmpty;

    // TIER 1: Standard GoogleSignIn with Web Server Client ID
    try {
      final user = await _attemptPluginSignIn(
        googleAuthPrimary,
        forceAccountPicker: forcePicker,
        label: 'TIER1_PRIMARY',
      );
      if (user != null) {
        final headers = await user.authHeaders;
        await prefs.setDriveAccount(user.email);
        AppLogger.instance.log('Tier-1 Google Sign-In succeeded for ${user.email}', tag: 'AUTH');
        return _DriveAuthSession(email: user.email, headers: headers);
      } else {
        AppLogger.instance.log('User cancelled account picker.', tag: 'WARN');
        return null;
      }
    } catch (tier1Err) {
      AppLogger.instance.log('Tier-1 Sign-In failed ($tier1Err). Trying Tier-2 progressive fallback...', tag: 'WARN');
    }

    // TIER 2: Progressive Basic Sign-In -> Request Scopes After Account Selection
    try {
      final user = await _attemptPluginSignIn(
        _googleAuthFallback,
        forceAccountPicker: forcePicker,
        label: 'TIER2_PROGRESSIVE',
      );
      if (user != null) {
        final granted = await _googleAuthFallback.requestScopes(<String>[_driveAppDataScope]);
        if (granted) {
          final headers = await user.authHeaders;
          await prefs.setDriveAccount(user.email);
          AppLogger.instance.log('Tier-2 Progressive Sign-In succeeded for ${user.email}', tag: 'AUTH');
          return _DriveAuthSession(email: user.email, headers: headers);
        }
      }
    } catch (tier2Err) {
      AppLogger.instance.log('Tier-2 Sign-In failed ($tier2Err). Trying Tier-3 Native AccountManager...', tag: 'WARN');
    }

    // TIER 3: Native Android AccountManager + GoogleAuthUtil (Solves Mi A1 Custom ROM ApiException 12500)
    try {
      final nativeRes = await _nativeBridge.invokeMethod<Map<dynamic, dynamic>>('nativeDriveAuth', {
        'switchAccount': forcePicker,
        'savedEmail': prefs.driveAccount,
      });
      if (nativeRes != null) {
        final err = nativeRes['error']?.toString() ?? '';
        final email = nativeRes['email']?.toString() ?? '';
        final token = nativeRes['token']?.toString() ?? '';
        if (email.isNotEmpty && token.isNotEmpty) {
          await prefs.setDriveAccount(email);
          AppLogger.instance.log('Tier-3 Native AccountManager Sign-In succeeded for $email', tag: 'AUTH');
          return _DriveAuthSession(
            email: email,
            headers: <String, String>{'Authorization': 'Bearer $token'},
          );
        }
        if (err.isNotEmpty) {
          throw PlatformException(code: 'native_auth_error', message: err);
        }
      } else {
        AppLogger.instance.log('User cancelled native account picker.', tag: 'WARN');
        return null;
      }
    } catch (tier3Err) {
      AppLogger.instance.log('Tier-3 Native Auth error: $tier3Err', tag: 'ERROR');
      if (context.mounted) {
        _showErrorModal(
          context,
          'Google Sign-In Blocked',
          'Could not complete Google Sign-In on this device: $tier3Err\n\n'
          'Live APK Package: $livePkg\n'
          'Live APK SHA-1:\n$liveSha1',
        );
      }
    }
    return null;
  }

  static Future<void> runSilentDailyBackup(ThemeProvider prefs) async {
    if (prefs.driveAccount.isEmpty) return;
    final currentBooks = await DatabaseHelper.instance.getBooksWithBalances();
    if (currentBooks.isEmpty) return;

    final today = todayStamp();
    if (prefs.lastAutoBackupDay == today) return;

    try {
      Map<String, String>? headers;
      try {
        final account = await googleAuthPrimary.signInSilently();
        if (account != null) headers = await account.authHeaders;
      } catch (_) {}

      if (headers == null) {
        final nativeRes = await _nativeBridge.invokeMethod<Map<dynamic, dynamic>>('nativeDriveAuth', {
          'switchAccount': false,
          'savedEmail': prefs.driveAccount,
        });
        final token = nativeRes?['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          headers = <String, String>{'Authorization': 'Bearer $token'};
        }
      }

      if (headers == null) return;

      final existingCloud = await _pullBackupFromDrive(headers);
      final payload = await _buildMergedBackupPayload(existingCloud);
      final uploadedId = await _pushBackupToDrive(headers, payload);
      if (uploadedId != null && uploadedId.isNotEmpty) {
        await prefs.recordBackupSuccess(
          isoTimestamp: DateTime.now().toIso8601String(),
          dayKey: today,
        );
      }
    } catch (_) {}
  }

  static Future<String?> _locateBackupFileId(Map<String, String> headers) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$_backupFileName' and trashed = false",
      'fields': 'files(id,name,modifiedTime)',
      'pageSize': '1',
    });
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Drive list failed (${resp.statusCode}): ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['files'] as List<dynamic>?) ?? [];
    if (list.isEmpty) return null;
    return (list.first as Map<String, dynamic>)['id']?.toString();
  }

  static Future<String?> _pushBackupToDrive(Map<String, String> headers, String jsonPayload) async {
    String? fileId = await _locateBackupFileId(headers);

    if (fileId == null) {
      final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files');
      final createResp = await http.post(
        createUri,
        headers: {...headers, 'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'name': _backupFileName,
          'parents': ['appDataFolder'],
        }),
      );
      if (createResp.statusCode != 200 && createResp.statusCode != 201) {
        throw Exception('Drive create failed (${createResp.statusCode}): ${createResp.body}');
      }
      final created = jsonDecode(createResp.body) as Map<String, dynamic>;
      fileId = created['id']?.toString();
    }

    if (fileId == null || fileId.isEmpty) {
      throw Exception('Could not obtain Google Drive file ID.');
    }

    final uploadUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media');
    final uploadResp = await http.patch(
      uploadUri,
      headers: {...headers, 'Content-Type': 'application/json; charset=UTF-8'},
      body: utf8.encode(jsonPayload),
    );
    if (uploadResp.statusCode != 200) {
      throw Exception('Drive upload failed (${uploadResp.statusCode}): ${uploadResp.body}');
    }
    return fileId;
  }

  static Future<String?> _pullBackupFromDrive(Map<String, String> headers) async {
    final fileId = await _locateBackupFileId(headers);
    if (fileId == null || fileId.isEmpty) return null;

    final downloadUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final resp = await http.get(downloadUri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Drive download failed (${resp.statusCode}): ${resp.body}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  // ===========================================================================
  // SMART 8-BOOK MERGE ENGINE (LOCAL UPDATES REPLACE OLD, CLOUD-ONLY KEPT)
  // ===========================================================================
  /// Merges local books with any cloud-only books so:
  /// 1. If 5 books are on Drive and 3 new books were created locally without restoring,
  ///    all 8 books are preserved (and the 5 cloud-only books are also imported locally).
  /// 2. If a book exists both locally and in the cloud (same book name), the local
  ///    updated version replaces the old cloud book.
  static Future<String> _buildMergedBackupPayload(String? cloudJson) async {
    final rawLocal = await DatabaseHelper.instance.exportDatabaseJson();
    final enrichedLocal = await FinTraxBrandHelper.enrichBackupJsonWithImagesAndContacts(rawLocal);

    if (cloudJson == null || cloudJson.trim().isEmpty) {
      return enrichedLocal;
    }

    try {
      final localMap = jsonDecode(enrichedLocal) as Map<String, dynamic>;
      final cloudMap = jsonDecode(cloudJson) as Map<String, dynamic>;

      final localBooks = ((localMap['books'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cloudBooks = ((cloudMap['books'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (cloudBooks.isEmpty) return enrichedLocal;

      final localTxs = ((localMap['transactions'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cloudTxs = ((cloudMap['transactions'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final localContacts = ((localMap['book_contacts'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cloudContacts = ((cloudMap['book_contacts'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final localImages = Map<String, dynamic>.from((localMap['attached_images_base64'] as Map?) ?? {});
      final cloudImages = Map<String, dynamic>.from((cloudMap['attached_images_base64'] as Map?) ?? {});

      final localBookNames = <String, int>{};
      int maxBookId = 0;
      for (final b in localBooks) {
        final id = (b['id'] as num?)?.toInt() ?? 0;
        if (id > maxBookId) maxBookId = id;
        final nameKey = (b['name']?.toString() ?? '').trim().toLowerCase();
        if (nameKey.isNotEmpty) localBookNames[nameKey] = id;
      }

      int maxTxId = 0;
      for (final t in localTxs) {
        final id = (t['id'] as num?)?.toInt() ?? 0;
        if (id > maxTxId) maxTxId = id;
      }

      final mergedBooks = List<Map<String, dynamic>>.from(localBooks);
      final mergedTxs = List<Map<String, dynamic>>.from(localTxs);
      final mergedContacts = List<Map<String, dynamic>>.from(localContacts);
      final mergedImages = <String, dynamic>{...cloudImages, ...localImages};

      bool addedAnyCloudOnlyBook = false;

      for (final cb in cloudBooks) {
        final cName = (cb['name']?.toString() ?? '').trim();
        final cNameKey = cName.toLowerCase();
        if (cNameKey.isEmpty) continue;

        // If this book exists locally, the local version is the updated source of truth and replaces the old cloud version
        if (localBookNames.containsKey(cNameKey)) {
          continue;
        }

        // Cloud-only book: preserve it with a safe non-colliding bookId
        addedAnyCloudOnlyBook = true;
        final oldCloudBookId = (cb['id'] as num?)?.toInt() ?? -1;
        maxBookId++;
        final newBookId = maxBookId;

        final newBookMap = Map<String, dynamic>.from(cb);
        newBookMap['id'] = newBookId;
        mergedBooks.add(newBookMap);

        for (final ct in cloudTxs) {
          if ((ct['bookId'] as num?)?.toInt() == oldCloudBookId) {
            maxTxId++;
            final newTxMap = Map<String, dynamic>.from(ct);
            newTxMap['id'] = maxTxId;
            newTxMap['bookId'] = newBookId;
            mergedTxs.add(newTxMap);
          }
        }

        for (final cc in cloudContacts) {
          if ((cc['bookId'] as num?)?.toInt() == oldCloudBookId) {
            final newContactMap = Map<String, dynamic>.from(cc);
            newContactMap['bookId'] = newBookId;
            mergedContacts.add(newContactMap);
          }
        }
      }

      final mergedPayloadMap = <String, dynamic>{
        ...localMap,
        'exportedAt': DateTime.now().toIso8601String(),
        'books': mergedBooks,
        'transactions': mergedTxs,
        'book_contacts': mergedContacts,
        'attached_images_base64': mergedImages,
      };

      final finalJson = jsonEncode(mergedPayloadMap);

      // If there were cloud-only books, also import the merged set into local DB so the phone shows all 8 books too
      if (addedAnyCloudOnlyBook) {
        await DatabaseHelper.instance.importDatabaseJson(finalJson);
        await FinTraxBrandHelper.restoreImagesAndContactsFromBackupJson(finalJson);
        await syncRestoredTransactionsWithSmsInbox();
      }

      return finalJson;
    } catch (e) {
      AppLogger.instance.log('Merge fallback notice: $e', tag: 'WARN');
      return enrichedLocal;
    }
  }

  static Future<bool> promptRestoreFoundBackup({
    required BuildContext context,
    required String email,
    required String rawJson,
    required ThemeProvider prefs,
    required Future<void> Function() onBooksReload,
  }) async {
    String backupDateText = 'Unknown date';
    String exportedIso = '';
    int bookTotal = 0;
    int txTotal = 0;
    try {
      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
      exportedIso = parsed['exportedAt']?.toString() ?? '';
      final dt = DateTime.tryParse(exportedIso);
      if (dt != null) backupDateText = AppConstants.formatOrdinalDateTime(dt);
      bookTotal = ((parsed['books'] as List<dynamic>?) ?? []).length;
      txTotal = ((parsed['transactions'] as List<dynamic>?) ?? []).length;
    } catch (_) {}

    if (!context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Google Drive Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          'Account: $email\nLast Backup: $backupDateText\nContents: $bookTotal Book(s), $txTotal Entries\n\nRestore this cloud backup into FinTrax?',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore Now')),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      _showProgressModal(context, 'Restoring books, attachments & syncing SMS...');
      final count = await DatabaseHelper.instance.importDatabaseJson(rawJson);
      await FinTraxBrandHelper.restoreImagesAndContactsFromBackupJson(rawJson);
      await syncRestoredTransactionsWithSmsInbox();
      if (exportedIso.isNotEmpty) {
        await prefs.recordBackupSuccess(isoTimestamp: exportedIso, dayKey: todayStamp());
      }
      await onBooksReload();
      if (context.mounted) {
        Navigator.pop(context);
        FinTraxBrandHelper.showModernSnackBar(
          context: context,
          message: 'Restored $count book(s) from Google Drive!',
          icon: Icons.cloud_done_rounded,
          color: AppConstants.incomeGreen,
        );
      }
      return true;
    }
    return false;
  }

  static Future<void> onSwitchDriveAccount({
    required BuildContext context,
    required ThemeProvider prefs,
    required Future<void> Function() onBooksReload,
  }) async {
    HapticFeedback.lightImpact();
    final session = await _authenticateForDrive(context, prefs, switchAccount: true);
    if (session == null || !context.mounted) return;

    _showProgressModal(context, 'Checking Google Drive for ${session.email}...');
    try {
      final existing = await _pullBackupFromDrive(session.headers);
      if (context.mounted) Navigator.pop(context);

      if (existing != null && existing.isNotEmpty) {
        final decoded = jsonDecode(existing) as Map<String, dynamic>;
        final ts = decoded['exportedAt']?.toString() ?? '';
        final cloudBookCount = ((decoded['books'] as List<dynamic>?) ?? []).length;
        if (ts.isNotEmpty) {
          await prefs.recordBackupSuccess(isoTimestamp: ts, dayKey: prefs.lastAutoBackupDay);
        }
        if (cloudBookCount > 0 && context.mounted) {
          final restored = await promptRestoreFoundBackup(
            context: context,
            email: session.email,
            rawJson: existing,
            prefs: prefs,
            onBooksReload: onBooksReload,
          );
          if (!restored && context.mounted) {
            FinTraxBrandHelper.showModernSnackBar(
              context: context,
              message: 'Connected to ${session.email}',
              icon: Icons.check_circle_rounded,
              color: AppConstants.incomeGreen,
            );
          }
          return;
        }
      }
      if (context.mounted) {
        FinTraxBrandHelper.showModernSnackBar(
          context: context,
          message: 'Connected to ${session.email}',
          icon: Icons.check_circle_rounded,
          color: AppConstants.incomeGreen,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) _showErrorModal(context, 'Google Drive Connection Error', e.toString());
    }
  }

  static Future<void> onBackupNow({
    required BuildContext context,
    required ThemeProvider prefs,
    required Future<void> Function() onBooksReload,
  }) async {
    HapticFeedback.mediumImpact();
    final session = await _authenticateForDrive(context, prefs);
    if (session == null || !context.mounted) return;

    _showProgressModal(context, 'Checking Google Drive cloud backup...');
    String? cloudJson;
    try {
      cloudJson = await _pullBackupFromDrive(session.headers);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) Navigator.pop(context);
    }

    if (!context.mounted) return;

    final localBooks = await DatabaseHelper.instance.getBooksWithBalances();
    int cloudBooksCount = 0;
    if (cloudJson != null && cloudJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(cloudJson) as Map<String, dynamic>;
        cloudBooksCount = ((parsed['books'] as List<dynamic>?) ?? []).length;
      } catch (_) {}
    }

    // PROTECTION: If local app has 0 books, never overwrite a non-empty cloud backup!
    if (localBooks.isEmpty) {
      if (cloudBooksCount > 0 && cloudJson != null) {
        await promptRestoreFoundBackup(
          context: context,
          email: session.email,
          rawJson: cloudJson,
          prefs: prefs,
          onBooksReload: onBooksReload,
        );
      } else {
        FinTraxBrandHelper.showModernSnackBar(
          context: context,
          message: 'Create at least 1 book before backing up to Google Drive.',
          icon: Icons.info_outline_rounded,
          color: AppConstants.goldAccent,
        );
      }
      return;
    }

    _showProgressModal(context, 'Merging & uploading backup to Google Drive...');
    try {
      final mergedPayload = await _buildMergedBackupPayload(cloudJson);
      final fileId = await _pushBackupToDrive(session.headers, mergedPayload);
      await onBooksReload();
      if (context.mounted) Navigator.pop(context);

      if (fileId != null && fileId.isNotEmpty) {
        await prefs.recordBackupSuccess(
          isoTimestamp: DateTime.now().toIso8601String(),
          dayKey: todayStamp(),
        );
        if (context.mounted) {
          FinTraxBrandHelper.showModernSnackBar(
            context: context,
            message: 'Cloud Backup synced to Google Drive!',
            icon: Icons.cloud_upload_rounded,
            color: AppConstants.incomeGreen,
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) _showErrorModal(context, 'Google Drive Backup Failed', e.toString());
    }
  }

  static Future<void> onRestoreNow({
    required BuildContext context,
    required ThemeProvider prefs,
    required Future<void> Function() onBooksReload,
  }) async {
    HapticFeedback.mediumImpact();
    final session = await _authenticateForDrive(context, prefs);
    if (session == null || !context.mounted) return;

    _showProgressModal(context, 'Checking Google Drive Cloud...');
    String? rawJson;
    try {
      rawJson = await _pullBackupFromDrive(session.headers);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) _showErrorModal(context, 'Google Drive Restore Error', e.toString());
      return;
    }

    if (!context.mounted) return;

    if (rawJson == null || rawJson.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('No FinTrax backup was found on Google Drive for ${session.email}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    await promptRestoreFoundBackup(
      context: context,
      email: session.email,
      rawJson: rawJson,
      prefs: prefs,
      onBooksReload: onBooksReload,
    );
  }

  // ===========================================================================
  // MANAGE CLOUD DATA MODAL (VIEW & DELETE SPECIFIC BOOKS OR ENTIRE BACKUP)
  // ===========================================================================
  static Future<void> openManageCloudDataModal({
    required BuildContext context,
    required ThemeProvider prefs,
    required Future<void> Function() onBooksReload,
  }) async {
    HapticFeedback.lightImpact();
    final session = await _authenticateForDrive(context, prefs);
    if (session == null || !context.mounted) return;

    _showProgressModal(context, 'Loading Google Drive backup details...');
    String? rawJson;
    try {
      rawJson = await _pullBackupFromDrive(session.headers);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) _showErrorModal(context, 'Cloud Inspection Error', e.toString());
      return;
    }

    if (!context.mounted) return;

    if (rawJson == null || rawJson.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cloud Storage Empty', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('No cloud backup file exists on Google Drive for ${session.email}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    Map<String, dynamic> parsedCloud = {};
    try {
      parsedCloud = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {}

    List<Map<String, dynamic>> cloudBooks = ((parsedCloud['books'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    List<Map<String, dynamic>> cloudTxs = ((parsedCloud['transactions'] as List<dynamic>?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (cloudBooks.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cloud Backup Has 0 Books', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('Your Google Drive backup on ${session.email} currently contains 0 books.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final dt = DateTime.tryParse(parsedCloud['exportedAt']?.toString() ?? '');
          final backupDateText = dt != null ? AppConstants.formatOrdinalDateTime(dt) : 'Unknown date';

          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.80),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Manage Cloud Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    Text('Account: ${session.email}', style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Synced: $backupDateText', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(
                            'Total in Cloud: ${cloudBooks.length} Book(s) • ${cloudTxs.length} Entries',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'BOOKS IN GOOGLE DRIVE (TAP 🗑️ TO REMOVE FROM CLOUD):',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: cloudBooks.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final b = cloudBooks[i];
                          final bId = (b['id'] as num?)?.toInt() ?? -1;
                          final bName = b['name']?.toString() ?? 'Unnamed Book';
                          final entryCount = cloudTxs.where((t) => (t['bookId'] as num?)?.toInt() == bId).length;

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: Icon(Icons.book_rounded, size: 19, color: Theme.of(ctx).colorScheme.primary),
                            title: Text(bName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            subtitle: Text('$entryCount entries in cloud', style: const TextStyle(fontSize: 11.5)),
                            trailing: IconButton(
                              tooltip: 'Delete this book from Cloud Backup',
                              icon: const Icon(Icons.delete_outline_rounded, color: AppConstants.expenseRed, size: 20),
                              onPressed: () async {
                                final confirmBookDel = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dCtx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    title: const Text('Remove Book from Cloud?', style: TextStyle(fontWeight: FontWeight.w800)),
                                    content: Text('Delete "$bName" ($entryCount entries) from your Google Drive cloud backup?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(dCtx, true),
                                        child: const Text('Delete from Cloud'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmBookDel == true && ctx.mounted) {
                                  cloudBooks.removeWhere((item) => (item['id'] as num?)?.toInt() == bId);
                                  cloudTxs.removeWhere((item) => (item['bookId'] as num?)?.toInt() == bId);
                                  parsedCloud['books'] = cloudBooks;
                                  parsedCloud['transactions'] = cloudTxs;
                                  parsedCloud['exportedAt'] = DateTime.now().toIso8601String();
                                  final updatedJson = jsonEncode(parsedCloud);
                                  rawJson = updatedJson;

                                  _showProgressModal(context, 'Updating Google Drive backup...');
                                  try {
                                    await _pushBackupToDrive(session.headers, updatedJson);
                                    if (context.mounted) Navigator.pop(context);
                                    setSheetState(() {});
                                    if (cloudBooks.isEmpty && sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }
                                    if (context.mounted) {
                                      FinTraxBrandHelper.showModernSnackBar(
                                        context: context,
                                        message: 'Removed "$bName" from Google Drive.',
                                        icon: Icons.delete_sweep_rounded,
                                        color: AppConstants.incomeGreen,
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) Navigator.pop(context);
                                    if (context.mounted) _showErrorModal(context, 'Cloud Update Failed', e.toString());
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConstants.expenseRed,
                              side: const BorderSide(color: AppConstants.expenseRed),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              final confirmDel = await showDialog<bool>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Delete Entire Cloud Backup?', style: TextStyle(fontWeight: FontWeight.w800)),
                                  content: const Text(
                                    'This will permanently delete all backed-up books from Google Drive. Your local phone books will remain untouched.',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: const Text('Delete All from Drive'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmDel == true && context.mounted) {
                                _showProgressModal(context, 'Deleting cloud backup from Google Drive...');
                                try {
                                  final fileId = await _locateBackupFileId(session.headers);
                                  if (fileId != null) {
                                    await http.delete(
                                      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
                                      headers: session.headers,
                                    );
                                  }
                                  if (context.mounted) Navigator.pop(context);
                                  if (context.mounted) {
                                    FinTraxBrandHelper.showModernSnackBar(
                                      context: context,
                                      message: 'Cloud backup deleted from Google Drive.',
                                      icon: Icons.delete_sweep_rounded,
                                      color: AppConstants.incomeGreen,
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) Navigator.pop(context);
                                  if (context.mounted) _showErrorModal(context, 'Deletion Failed', e.toString());
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_forever_rounded, size: 18),
                            label: const Text('Delete All Cloud', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              if (rawJson != null) {
                                await promptRestoreFoundBackup(
                                  context: context,
                                  email: session.email,
                                  rawJson: rawJson!,
                                  prefs: prefs,
                                  onBooksReload: onBooksReload,
                                );
                              }
                            },
                            icon: const Icon(Icons.cloud_download_outlined, size: 18),
                            label: const Text('Restore Cloud', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // INTERACTIVE MONTHLY INSIGHTS & DRILL-DOWN BY CATEGORY / BOOK
  // ===========================================================================
  static void openMonthlyInsightsSheet({
    required BuildContext context,
    bool initialPreviousMonth = true,
    required Future<void> Function() onBooksReload,
  }) {
    HapticFeedback.lightImpact();
    bool showPrevMonth = initialPreviousMonth;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final scheme = Theme.of(ctx).colorScheme;
          final now = DateTime.now();
          final targetDate = showPrevMonth
              ? DateTime(now.year, now.month - 1, 1)
              : DateTime(now.year, now.month, 1);
          final monthTitle = '${monthNames[targetDate.month - 1]} ${targetDate.year}';

          return Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.insights_rounded, color: scheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$monthTitle Insights',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Tap any category, card, or book below to view entries',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(
                            'Last Month (${monthNames[DateTime(now.year, now.month - 1, 1).month - 1]})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(
                            'This Month (${monthNames[now.month - 1]})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      selected: {showPrevMonth},
                      onSelectionChanged: (sel) {
                        HapticFeedback.selectionClick();
                        setSheetState(() => showPrevMonth = sel.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  Flexible(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: DatabaseHelper.instance.getMonthlyInsights(targetDate.year, targetDate.month),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final data = snap.data!;
                        final double totalIn = (data['totalIncome'] as num?)?.toDouble() ?? 0.0;
                        final double totalOut = (data['totalExpense'] as num?)?.toDouble() ?? 0.0;
                        final double netFlow = (data['netFlow'] as num?)?.toDouble() ?? 0.0;
                        final double shoppingSpend = (data['shoppingSpend'] as num?)?.toDouble() ?? 0.0;
                        final double grocerySpend = (data['grocerySpend'] as num?)?.toDouble() ?? 0.0;
                        final double foodSpend = (data['foodSpend'] as num?)?.toDouble() ?? 0.0;
                        final double lendingGiven = (data['lendingGiven'] as num?)?.toDouble() ?? 0.0;
                        final int txCount = (data['txCount'] as int?) ?? 0;
                        final List<dynamic> cats = (data['categoryBreakdown'] as List<dynamic>?) ?? [];
                        final List<dynamic> booksBreak = (data['bookBreakdown'] as List<dynamic>?) ?? [];

                        double investmentSpend = (data['investmentSpend'] as num?)?.toDouble() ?? 0.0;
                        if (investmentSpend == 0.0) {
                          for (final c in cats) {
                            final String cName = c['name']?.toString().toLowerCase() ?? '';
                            if (cName == 'investment' || cName == 'investments') {
                              investmentSpend += (c['amount'] as num?)?.toDouble() ?? 0.0;
                            }
                          }
                        }

                        if (txCount == 0 && lendingGiven == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(36),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.insert_chart_outlined, size: 48, color: Colors.grey[500]),
                                const SizedBox(height: 12),
                                Text(
                                  'No entries logged for $monthTitle',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Keep logging your daily expenses to unlock rich monthly insights!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.all(18),
                          shrinkWrap: true,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _insightMetricCard(
                                    isDark: isDark,
                                    title: 'Total Income',
                                    amount: totalIn,
                                    color: AppConstants.incomeGreen,
                                    prefix: '+',
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Total Income',
                                      filterType: 'Income',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _insightMetricCard(
                                    isDark: isDark,
                                    title: 'Total Spent',
                                    amount: totalOut,
                                    color: AppConstants.expenseRed,
                                    prefix: '-',
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Total Spent',
                                      filterType: 'Expense',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Material(
                              color: isDark ? const Color(0xFF171A24) : const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openInsightDrillDownSheet(
                                  context: context,
                                  year: targetDate.year,
                                  month: targetDate.month,
                                  title: '$monthTitle • All Entries',
                                  onBooksReload: () async {
                                    await onBooksReload();
                                    if (ctx.mounted) setSheetState(() {});
                                  },
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Net Monthly Savings / Flow ($txCount unique ${txCount == 1 ? 'entry' : 'entries'})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${netFlow < 0 ? '-' : '+'}${AppConstants.defaultCurrency}${netFlow.abs().toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: netFlow < 0 ? AppConstants.expenseRed : AppConstants.incomeGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'KEY SPENDING & INVESTMENT HIGHLIGHTS (TAP FOR DETAILS)',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '📈',
                                    label: 'Investment',
                                    amount: investmentSpend,
                                    highlightGreen: true,
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Investment Entries',
                                      filterCategory: 'Investment',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🛍️',
                                    label: 'Shopping',
                                    amount: shoppingSpend,
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Shopping Entries',
                                      filterCategory: 'Shopping',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🛒',
                                    label: 'Groceries',
                                    amount: grocerySpend,
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Groceries Entries',
                                      filterCategory: 'Groceries',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🍽️',
                                    label: 'Food & Dining',
                                    amount: foodSpend,
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • Food & Dining Entries',
                                      filterCategory: 'Food & Dining',
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (cats.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                'CATEGORY BREAKDOWN (TAP ANY CATEGORY)',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              ...cats.map((c) {
                                final String cName = c['name'].toString();
                                final bool isInv = cName.toLowerCase() == 'investment';
                                final double cAmt = (c['amount'] as num).toDouble();
                                final double pct = totalOut > 0 ? (cAmt / totalOut).clamp(0.0, 1.0) : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _openInsightDrillDownSheet(
                                      context: context,
                                      year: targetDate.year,
                                      month: targetDate.month,
                                      title: '$monthTitle • $cName',
                                      filterCategory: cName,
                                      onBooksReload: () async {
                                        await onBooksReload();
                                        if (ctx.mounted) setSheetState(() {});
                                      },
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    isInv ? '📈 $cName' : '${FinTraxBrandHelper.getCategoryEmoji(cName)} $cName',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: isInv ? AppConstants.incomeGreen : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Icon(Icons.chevron_right_rounded, size: 15, color: Colors.grey[500]),
                                                ],
                                              ),
                                              Text(
                                                '${AppConstants.defaultCurrency}${cAmt.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(0)}%)',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: isInv ? AppConstants.incomeGreen : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: pct,
                                              minHeight: 6,
                                              backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                isInv ? AppConstants.incomeGreen : scheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                            if (booksBreak.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'SPENDING BY BOOK (TAP ANY BOOK)',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              ...booksBreak.map((b) {
                                final String bName = b['name'].toString();
                                final double bAmt = (b['amount'] as num).toDouble();
                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _openInsightDrillDownSheet(
                                    context: context,
                                    year: targetDate.year,
                                    month: targetDate.month,
                                    title: '$monthTitle • $bName',
                                    filterBookName: bName,
                                    onBooksReload: () async {
                                      await onBooksReload();
                                      if (ctx.mounted) setSheetState(() {});
                                    },
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.book_outlined, size: 15, color: scheme.primary),
                                            const SizedBox(width: 8),
                                            Text(bName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 4),
                                            Icon(Icons.chevron_right_rounded, size: 15, color: Colors.grey[500]),
                                          ],
                                        ),
                                        Text(
                                          '${AppConstants.defaultCurrency}${bAmt.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.expenseRed),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        );
                      },
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

  /// Opens the detailed list of entries for any tapped category, highlight card, or book
  /// with the Book Name prominently displayed at the top of each entry card.
  static Future<void> _openInsightDrillDownSheet({
    required BuildContext context,
    required int year,
    required int month,
    required String title,
    String? filterCategory,
    String? filterType,
    String? filterBookName,
    required Future<void> Function() onBooksReload,
  }) async {
    HapticFeedback.lightImpact();

    Future<List<Map<String, dynamic>>> fetchMatchingEntries() async {
      final db = await DatabaseHelper.instance.database;
      final startIso = DateTime(year, month, 1).toIso8601String();
      final endIso = DateTime(year, month + 1, 1).toIso8601String();

      final rows = await db.rawQuery('''
        SELECT t.*, b.name AS bookName, b.bookType AS bookType
        FROM transactions t
        INNER JOIN books b ON t.bookId = b.id
        WHERE t.date >= ? AND t.date < ?
        ORDER BY t.date DESC
      ''', [startIso, endIso]);

      final results = <Map<String, dynamic>>[];
      for (final r in rows) {
        final String bookType = r['bookType']?.toString() ?? 'standard';
        final String txType = r['type']?.toString() ?? 'Expense';
        final String rawCat = (r['category']?.toString() ?? '').trim();
        final String effectiveCat = rawCat.isEmpty ? 'Uncategorized' : rawCat;
        final String bName = r['bookName']?.toString() ?? 'Book';
        final String txTitle = (r['name']?.toString() ?? '').toLowerCase();

        if (filterBookName != null && bName.toLowerCase() != filterBookName.toLowerCase()) {
          continue;
        }
        if (filterType != null) {
          if (bookType == 'lending' || txType.toLowerCase() != filterType.toLowerCase()) continue;
        }
        if (filterCategory != null) {
          final target = filterCategory.toLowerCase();
          final catLow = effectiveCat.toLowerCase();
          bool match = false;
          if (target == 'investment') {
            match = catLow.contains('invest') ||
                txTitle.contains('sip') ||
                txTitle.contains('mutual fund') ||
                txTitle.contains('zerodha') ||
                txTitle.contains('groww') ||
                txTitle.contains('indmoney');
          } else if (target == 'shopping') {
            match = catLow.contains('shop') ||
                txTitle.contains('amazon') ||
                txTitle.contains('flipkart') ||
                txTitle.contains('myntra') ||
                txTitle.contains('meesho');
          } else if (target == 'groceries') {
            match = catLow.contains('grocer') ||
                txTitle.contains('instamart') ||
                txTitle.contains('blinkit') ||
                txTitle.contains('zepto') ||
                txTitle.contains('bigbasket');
          } else if (target == 'food & dining') {
            match = catLow.contains('food') ||
                catLow.contains('dining') ||
                txTitle.contains('zomato') ||
                txTitle.contains('swiggy');
          } else {
            match = catLow == target;
          }
          if (!match) continue;
        }
        results.add(r);
      }
      return results;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (drillCtx) => StatefulBuilder(
        builder: (ctx, setDrillState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final scheme = Theme.of(ctx).colorScheme;

          return Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.84),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(drillCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: fetchMatchingEntries(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(36),
                            child: Center(
                              child: Text(
                                'No matching entries found for this selection.',
                                style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600),
                              ),
                            ),
                          );
                        }

                        double sumTotal = 0;
                        for (final m in items) {
                          sumTotal += (m['amount'] as num?)?.toDouble() ?? 0.0;
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              color: scheme.primary.withOpacity(isDark ? 0.12 : 0.07),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${items.length} ${items.length == 1 ? 'Entry' : 'Entries'} Across Books',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'Total: ${AppConstants.defaultCurrency}${sumTotal.toStringAsFixed(0)}',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: scheme.primary),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(14),
                                shrinkWrap: true,
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final row = items[i];
                                  final tx = TransactionModel.fromMap(row);
                                  final bookName = row['bookName']?.toString() ?? 'Expense Book';
                                  final isIncome = tx.type == 'Income';
                                  final catLabel = tx.category.trim().isEmpty ? 'Uncategorized' : tx.category;
                                  final paymentIcon = FinTraxBrandHelper.getPaymentIconAsset(
                                    tx.paymentMode,
                                    smsBody: tx.effectiveSmsText,
                                    sender: tx.name,
                                  );

                                  return Material(
                                    color: isDark ? const Color(0xFF171A24) : const Color(0xFFF8FAFC),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        final changed = await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AddTransactionScreen(
                                              bookId: tx.bookId,
                                              type: tx.type,
                                              existingTransaction: tx,
                                            ),
                                          ),
                                        );
                                        if (changed == true) {
                                          await onBooksReload();
                                          if (ctx.mounted) setDrillState(() {});
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(13),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // TOP HEADER BADGE SHOWING BOOK NAME
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: scheme.primary.withOpacity(isDark ? 0.20 : 0.12),
                                                    borderRadius: BorderRadius.circular(7),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.menu_book_rounded, size: 12, color: scheme.primary),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        bookName,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: scheme.primary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  AppConstants.formatOrdinalDateTime(tx.date),
                                                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 9),
                                            // NORMAL ENTRY DETAILS ROW
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    tx.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${isIncome ? '+' : '-'}${AppConstants.defaultCurrency}${tx.amount.toStringAsFixed(0)}',
                                                  style: TextStyle(
                                                    fontSize: 15.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: isIncome ? AppConstants.incomeGreen : AppConstants.expenseRed,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Text(
                                                  '${FinTraxBrandHelper.getCategoryEmoji(catLabel)} $catLabel',
                                                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500], fontWeight: FontWeight.w600),
                                                ),
                                                const SizedBox(width: 10),
                                                FinTraxBrandHelper.buildIconBadge(
                                                  assetPath: paymentIcon,
                                                  fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(tx.paymentMode),
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  tx.paymentMode,
                                                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500], fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
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

  static Widget _insightMetricCard({
    required bool isDark,
    required String title,
    required double amount,
    required Color color,
    required String prefix,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(isDark ? 0.12 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
                  Icon(Icons.open_in_new_rounded, size: 13, color: color.withOpacity(0.8)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$prefix${AppConstants.defaultCurrency}${amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _highlightPill({
    required bool isDark,
    required String emoji,
    required String label,
    required double amount,
    bool highlightGreen = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: highlightGreen
          ? AppConstants.incomeGreen.withOpacity(isDark ? 0.14 : 0.08)
          : (isDark ? const Color(0xFF171A24) : const Color(0xFFF8FAFC)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlightGreen
              ? AppConstants.incomeGreen.withOpacity(0.55)
              : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
          width: highlightGreen ? 1.3 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: highlightGreen ? AppConstants.incomeGreen : Colors.grey[500],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppConstants.defaultCurrency}${amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: highlightGreen ? AppConstants.incomeGreen : null,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
}
