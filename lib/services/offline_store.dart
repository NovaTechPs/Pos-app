import 'dart:convert';
import 'dart:io';
import 'background_json.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped durable snapshots. A failed write must never count as a sale.
class OfflineStore {
  OfflineStore(this.scope, {this.storage = const FlutterSecureStorage()});

  final String scope;
  final FlutterSecureStorage storage;

  /// App-private directory for bulky read-only snapshots (catalogs, customers).
  ///
  /// On Android every secure-storage value lives in one SharedPreferences file
  /// that is rewritten on each write, so multi-megabyte catalogs there made every
  /// draft save slow. When set, snapshots go to individual files instead;
  /// sales, drafts and held orders stay in secure storage.
  static String? cacheDirectory;
  static Future<void>? _cacheMigration;
  static const _migrationMarker = 'wasla_offline_cache_files_v1';

  static Future<void> useFileCache(String directory) async {
    await Directory(directory).create(recursive: true);
    cacheDirectory = directory;
    _cacheMigration = null;
  }

  File? _cacheFile(String key) {
    final directory = cacheDirectory;
    if (directory == null) return null;
    final name = sha256.convert(utf8.encode(key)).toString();
    return File('$directory${Platform.pathSeparator}$name.json');
  }

  /// Moves snapshots saved by older versions out of secure storage once.
  Future<void> _migrateCache() => _cacheMigration ??= () async {
    try {
      await _moveLegacyCache();
    } catch (_) {
      // Snapshots are re-downloadable; never block selling on this cleanup.
    }
  }();

  Future<void> _moveLegacyCache() async {
    if (await storage.read(key: _migrationMarker) != null) return;
    final stored = await storage.readAll();
    for (final entry in stored.entries) {
      if (!entry.key.startsWith('wasla_offline_v1_') ||
          !entry.key.contains('_cache_')) {
        continue;
      }
      try {
        final data = jsonDecode(entry.value);
        if (data is Map && data['body'] is String) {
          await _writeCacheFile(
            _cacheFile(entry.key)!,
            data['body'] as String,
            '${data['saved_at'] ?? ''}',
          );
        }
      } catch (_) {
        /* An unreadable snapshot is simply downloaded again. */
      }
      await storage.delete(key: entry.key);
    }
    await storage.write(key: _migrationMarker, value: '1');
  }

  static Future<void> _writeCacheFile(
    File file,
    String body,
    String savedAt,
  ) async {
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString('$savedAt\n$body', flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    }
  }

  // Large catalogs are validated off the UI thread to avoid frame drops.
  static Future<bool> _isJsonObject(String body) async =>
      await BackgroundJson.decode(body) is Map;
  static Future<void>? _invoiceAllocation;
  static Future<void>? _operationAccess;
  String get _prefix => 'wasla_offline_v1_${Uri.encodeComponent(scope)}_';

  /// A receipt reference on this device; operation_uuid remains the sync key.
  Future<String> nextOfflineInvoiceNumber() {
    Future<String> reserve() async {
      final key = '${_prefix}invoice_sequence';
      final saved = await storage.read(key: key);
      final previous = saved == null ? 0 : int.parse(saved);
      if (previous < 0 || previous >= 999999) {
        throw StateError(
          'تعذر تخصيص رقم فاتورة محلي قصير؛ راجع إعدادات الجهاز.',
        );
      }
      final next = previous + 1;
      await storage.write(key: key, value: '$next');
      return 'OFF${next.toString().padLeft(6, '0')}';
    }

    final pending = _invoiceAllocation;
    final allocation = pending == null
        ? reserve()
        : pending.then((_) => reserve());
    late final Future<void> marker;
    void release() {
      if (identical(_invoiceAllocation, marker)) _invoiceAllocation = null;
    }

    marker = allocation.then<void>(
      (_) => release(),
      onError: (Object error, StackTrace stack) => release(),
    );
    _invoiceAllocation = marker;
    return allocation;
  }

  Future<Map<String, dynamic>?> draft(int branchId) async {
    final raw = await storage.read(key: '${_prefix}draft_$branchId');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> saveDraft(int branchId, Map<String, dynamic> draft) =>
      storage.write(key: '${_prefix}draft_$branchId', value: jsonEncode(draft));

  Future<List<Map<String, dynamic>>> localHeld(int branchId) async {
    final stored = await storage.readAll();
    return stored.entries
        .where((entry) => entry.key.startsWith('${_prefix}held_${branchId}_'))
        .map((entry) => Map<String, dynamic>.from(jsonDecode(entry.value)))
        .toList();
  }

  Future<void> saveLocalHeld(
    int branchId,
    String id,
    Map<String, dynamic> order,
  ) => storage.write(
    key: '${_prefix}held_${branchId}_$id',
    value: jsonEncode(order),
  );

  Future<void> deleteLocalHeld(int branchId, String id) =>
      storage.delete(key: '${_prefix}held_${branchId}_$id');

  String _cacheKey(Uri uri) =>
      '${_prefix}cache_${Uri.encodeComponent(uri.toString())}';

  Future<void> cache(Uri uri, String body) async {
    // Validate before replacing a usable snapshot with a gateway error page.
    if (!await _isJsonObject(body)) return;
    final savedAt = DateTime.now().toUtc().toIso8601String();
    final file = _cacheFile(_cacheKey(uri));
    if (file != null) {
      await _migrateCache();
      await _writeCacheFile(file, body, savedAt);
      return;
    }
    await storage.write(
      key: _cacheKey(uri),
      value: jsonEncode({'body': body, 'saved_at': savedAt}),
    );
  }

  Future<Map<String, dynamic>?> cached(Uri uri) async {
    final file = _cacheFile(_cacheKey(uri));
    if (file != null) {
      await _migrateCache();
      final String raw;
      try {
        raw = await file.readAsString();
      } on FileSystemException {
        return null;
      }
      final split = raw.indexOf('\n');
      if (split < 0) return null;
      final savedAt = raw.substring(0, split);
      return {
        'body': raw.substring(split + 1),
        'saved_at': savedAt.isEmpty ? null : savedAt,
      };
    }
    final raw = await storage.read(key: _cacheKey(uri));
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  /// Cheap existence check that does not read or decrypt the snapshot.
  Future<bool> hasCached(Uri uri) async {
    final file = _cacheFile(_cacheKey(uri));
    if (file != null) {
      await _migrateCache();
      return file.exists();
    }
    return await storage.containsKey(key: _cacheKey(uri));
  }

  Future<void> forget(Uri uri) async {
    final file = _cacheFile(_cacheKey(uri));
    if (file != null) {
      await _migrateCache();
      try {
        await file.delete();
      } on FileSystemException {
        /* Already absent. */
      }
      return;
    }
    await storage.delete(key: _cacheKey(uri));
  }

  String _operationKey(String uuid) => '${_prefix}operation_$uuid';

  Future<Map<String, dynamic>?> operation(String uuid) async {
    final raw = await storage.read(key: _operationKey(uuid));
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  // Serialize index changes and reads so two queued sales cannot lose an entry.
  static Future<T> _withOperations<T>(Future<T> Function() action) {
    final pending = _operationAccess;
    final result = pending == null ? action() : pending.then((_) => action());
    late final Future<void> marker;
    void release() {
      if (identical(_operationAccess, marker)) _operationAccess = null;
    }

    marker = result.then<void>(
      (_) => release(),
      onError: (Object error, StackTrace stack) => release(),
    );
    _operationAccess = marker;
    return result;
  }

  Future<List<String>> _operationIds() async {
    final key = '${_prefix}operation_index';
    final raw = await storage.read(key: key);
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is! List ||
          decoded.any((id) => id is! String || id.isEmpty)) {
        throw const FormatException('سجل الفواتير المحلية غير صالح');
      }
      return List<String>.from(decoded);
    }
    // One-time migration: subsequent sync checks never decrypt the large catalogs.
    final stored = await storage.readAll();
    final prefix = '${_prefix}operation_';
    final ids = stored.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toList();
    await storage.write(key: key, value: jsonEncode(ids));
    return ids;
  }

  Future<void> saveOperation(
    Map<String, dynamic> record,
  ) => _withOperations(() async {
    final uuid = record['payload']?['operation_uuid'];
    if (uuid is! String || uuid.isEmpty) {
      throw const FormatException('معرف العملية المحلية مفقود');
    }
    final ids = await _operationIds();
    final attention = await _attentionIds(ids);
    if (!ids.contains(uuid)) {
      // Reserve the index entry first: a crash may leave an empty reservation,
      // but can never leave a successfully saved invoice undiscoverable.
      await storage.write(
        key: '${_prefix}operation_index',
        value: jsonEncode([...ids, uuid]),
      );
      ids.add(uuid);
    }
    // Reserve attention before writing: interruption cannot hide a queued sale.
    if (!attention.contains(uuid)) {
      attention.add(uuid);
      await _writeAttention(attention, ids.length);
    }
    await storage.write(key: _operationKey(uuid), value: jsonEncode(record));
    if (!_needsAttention(record)) {
      attention.remove(uuid);
      await _writeAttention(attention, ids.length);
    }
  });

  static bool _needsAttention(Map<String, dynamic> record) =>
      !const {'confirmed', 'verified_saved'}.contains(record['status']);

  Future<void> _writeAttention(List<String> ids, int count) => storage.write(
    key: '${_prefix}pending_index_v1',
    value: jsonEncode({'indexed_count': count, 'ids': ids}),
  );

  Future<List<String>> _attentionIds(List<String> allIds) async {
    final raw = await storage.read(key: '${_prefix}pending_index_v1');
    if (raw != null) {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['indexed_count'] is! int ||
          data['ids'] is! List ||
          (data['ids'] as List).any((id) => id is! String || id.isEmpty)) {
        throw const FormatException('فهرس متابعة الفواتير غير صالح');
      }
      // Older app versions may append invoices without knowing this index.
      if (data['indexed_count'] == allIds.length) {
        final ids = List<String>.from(data['ids']);
        final known = allIds.toSet();
        if (ids.any((id) => !known.contains(id))) {
          throw const FormatException('فهرس متابعة الفواتير غير متطابق');
        }
        return ids;
      }
    }
    final ids = <String>[];
    for (final id in allIds) {
      final record = await operation(id);
      if (record != null && _needsAttention(record)) ids.add(id);
    }
    await _writeAttention(ids, allIds.length);
    return ids;
  }

  Future<List<Map<String, dynamic>>> pendingOperations() =>
      _withOperations(() async {
        final ids = await _attentionIds(await _operationIds());
        final records = <Map<String, dynamic>>[];
        for (final id in ids) {
          final record = await operation(id);
          if (record != null && _needsAttention(record)) records.add(record);
        }
        records.sort(
          (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'),
        );
        return records;
      });

  Future<List<Map<String, dynamic>>> operations() => _withOperations(() async {
    final ids = await _operationIds();
    final records = <Map<String, dynamic>>[];
    for (final id in ids) {
      final record = await operation(id);
      if (record != null) records.add(record);
    }
    records.sort(
      (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'),
    );
    return records;
  });
}
