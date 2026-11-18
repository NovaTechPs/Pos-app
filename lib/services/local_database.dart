import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Relational, account-scoped storage for data that must remain usable offline.
///
/// Authentication tokens intentionally remain in [flutter_secure_storage]. This
/// database contains only business snapshots and operations that can be safely
/// replayed through the API when connectivity returns.
class LocalDatabase {
  LocalDatabase({this.factory, this.databasePath});

  LocalDatabase.inMemory({required DatabaseFactory factory})
    : this(factory: factory, databasePath: () async => inMemoryDatabasePath);

  static final shared = LocalDatabase();

  static const _version = 1;
  @visibleForTesting
  final DatabaseFactory? factory;
  @visibleForTesting
  final Future<String> Function()? databasePath;
  Database? _database;
  Future<Database>? _opening;

  bool get isReady => _database != null;

  /// Opens the database before the application starts. Web keeps the existing
  /// browser-safe cache until a dedicated web persistence implementation exists.
  Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    await _open();
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    _opening = null;
    await database?.close();
  }

  /// Stores a full response snapshot identified by the original API URI.
  Future<void> saveSnapshot({
    required String scope,
    required Uri uri,
    required String body,
    required String savedAt,
  }) async {
    final database = await _open();
    await database.insert('local_snapshots', {
      'scope': scope,
      'uri': uri.toString(),
      'body': body,
      'saved_at': savedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>?> snapshot({
    required String scope,
    required Uri uri,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'local_snapshots',
      columns: ['body', 'saved_at'],
      where: 'scope = ? AND uri = ?',
      whereArgs: [scope, uri.toString()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return {
      'body': rows.single['body']! as String,
      'saved_at': rows.single['saved_at']! as String,
    };
  }

  Future<bool> hasSnapshot({required String scope, required Uri uri}) async {
    final database = await _open();
    final rows = await database.query(
      'local_snapshots',
      columns: const ['uri'],
      where: 'scope = ? AND uri = ?',
      whereArgs: [scope, uri.toString()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteSnapshot({required String scope, required Uri uri}) async {
    final database = await _open();
    await database.delete(
      'local_snapshots',
      where: 'scope = ? AND uri = ?',
      whereArgs: [scope, uri.toString()],
    );
  }

  /// Saves an entity locally. Collections cover products, customers, payments,
  /// stock movements, and future modules without mixing different account data.
  Future<void> saveDocument({
    required String scope,
    required String collection,
    required String documentId,
    required Map<String, dynamic> document,
    String syncState = 'synced',
  }) async {
    final database = await _open();
    await database.insert('local_documents', {
      'scope': scope,
      'collection': collection,
      'document_id': documentId,
      'document': jsonEncode(document),
      'sync_state': syncState,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> document({
    required String scope,
    required String collection,
    required String documentId,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'local_documents',
      columns: const ['document'],
      where: 'scope = ? AND collection = ? AND document_id = ?',
      whereArgs: [scope, collection, documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(
      jsonDecode(rows.single['document']! as String) as Map,
    );
  }

  Future<List<Map<String, dynamic>>> documents({
    required String scope,
    required String collection,
    String? syncState,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'local_documents',
      columns: const ['document'],
      where: syncState == null
          ? 'scope = ? AND collection = ?'
          : 'scope = ? AND collection = ? AND sync_state = ?',
      whereArgs: syncState == null
          ? [scope, collection]
          : [scope, collection, syncState],
      orderBy: 'updated_at ASC',
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['document']! as String) as Map,
          ),
        )
        .toList();
  }

  Future<void> deleteDocument({
    required String scope,
    required String collection,
    required String documentId,
  }) async {
    final database = await _open();
    await database.delete(
      'local_documents',
      where: 'scope = ? AND collection = ? AND document_id = ?',
      whereArgs: [scope, collection, documentId],
    );
  }

  /// A write is persisted before it is sent, so retries can be idempotent.
  Future<void> saveOperation({
    required String scope,
    required Map<String, dynamic> operation,
  }) async {
    final uuid = operation['payload'] is Map
        ? operation['payload']['operation_uuid']?.toString()
        : null;
    if (uuid == null || uuid.isEmpty) {
      throw const FormatException('معرف العملية المحلية مفقود');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final database = await _open();
    await database.insert('local_operations', {
      'scope': scope,
      'operation_uuid': uuid,
      'operation': jsonEncode(operation),
      'status': operation['status']?.toString() ?? 'queued',
      'created_at': operation['created_at']?.toString() ?? now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> operation({
    required String scope,
    required String operationUuid,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'local_operations',
      columns: const ['operation'],
      where: 'scope = ? AND operation_uuid = ?',
      whereArgs: [scope, operationUuid],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(
      jsonDecode(rows.single['operation']! as String) as Map,
    );
  }

  Future<List<Map<String, dynamic>>> operations({
    required String scope,
    bool pendingOnly = false,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'local_operations',
      columns: const ['operation'],
      where: pendingOnly ? 'scope = ? AND status NOT IN (?, ?)' : 'scope = ?',
      whereArgs: pendingOnly ? [scope, 'confirmed', 'verified_saved'] : [scope],
      orderBy: 'created_at ASC',
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['operation']! as String) as Map,
          ),
        )
        .toList();
  }

  Future<Database> _open() {
    final existing = _database;
    if (existing != null) {
      return Future.value(existing);
    }

    return _opening ??= () async {
      if (kIsWeb) {
        throw UnsupportedError(
          'قاعدة البيانات المحلية غير مدعومة في الويب بعد.',
        );
      }

      final databaseFactory = factory ?? _nativeFactory();
      final path = await (databasePath ?? _defaultDatabasePath)();
      final database = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: _createSchema,
        ),
      );
      _database = database;
      return database;
    }();
  }

  DatabaseFactory _nativeFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }

    return sqflite.databaseFactory;
  }

  Future<String> _defaultDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}waslapos_local.db';
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE local_snapshots (
        scope TEXT NOT NULL,
        uri TEXT NOT NULL,
        body TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        PRIMARY KEY (scope, uri)
      )
    ''');
    await database.execute('''
      CREATE TABLE local_documents (
        scope TEXT NOT NULL,
        collection TEXT NOT NULL,
        document_id TEXT NOT NULL,
        document TEXT NOT NULL,
        sync_state TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (scope, collection, document_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX local_documents_collection_index
      ON local_documents (scope, collection, sync_state, updated_at)
    ''');
    await database.execute('''
      CREATE TABLE local_operations (
        scope TEXT NOT NULL,
        operation_uuid TEXT NOT NULL,
        operation TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (scope, operation_uuid)
      )
    ''');
    await database.execute('''
      CREATE INDEX local_operations_sync_index
      ON local_operations (scope, status, created_at)
    ''');
  }
}
