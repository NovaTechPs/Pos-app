import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waslapos_app/services/local_database.dart';
import 'package:waslapos_app/services/offline_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late LocalDatabase database;
  late OfflineStore store;
  final uri = Uri.parse('https://waslapos.app/api/pos/products?branch_id=1');

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineStore.cacheDirectory = null;
    database = LocalDatabase.inMemory(factory: databaseFactoryFfiNoIsolate);
    await database.initialize();
    store = OfflineStore('tenant-1-user-7', database: database);
  });

  tearDown(() => database.close());

  test('uses SQLite when the legacy snapshot is no longer available', () async {
    await store.cache(uri, '{"categories":[]}');
    await const FlutterSecureStorage().deleteAll();

    final snapshot = await store.cached(uri);
    expect(snapshot?['body'], '{"categories":[]}');
    expect(snapshot?['saved_at'], isA<String>());
    expect(await store.hasCached(uri), isTrue);

    await store.forget(uri);
    expect(await store.cached(uri), isNull);
  });

  test(
    'keeps queued operations in SQLite when encrypted backup is unavailable',
    () async {
      final record = {
        'status': 'queued',
        'created_at': '2026-11-18T12:00:00.000Z',
        'payload': {'operation_uuid': 'operation-1', 'total_amount': 75},
      };

      await store.saveOperation(record);
      await const FlutterSecureStorage().deleteAll();

      final operations = await store.pendingOperations();
      expect(operations, hasLength(1));
      expect(operations.single['payload']['operation_uuid'], 'operation-1');
    },
  );

  test('imports existing encrypted operations into SQLite once', () async {
    const scope = 'tenant-1-user-9';
    const uuid = 'legacy-operation';
    final prefix = 'wasla_offline_v1_${Uri.encodeComponent(scope)}_';
    final record = {
      'status': 'queued',
      'created_at': '2026-11-18T12:00:00.000Z',
      'payload': {'operation_uuid': uuid, 'total_amount': 30},
    };
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}operation_index': '["$uuid"]',
      '${prefix}operation_$uuid': jsonEncode(record),
    });
    final legacyStore = OfflineStore(scope, database: database);

    expect(
      (await legacyStore.operations()).single['payload']['operation_uuid'],
      uuid,
    );
    await const FlutterSecureStorage().deleteAll();
    expect(
      (await legacyStore.operations()).single['payload']['operation_uuid'],
      uuid,
    );
  });

  test(
    'keeps drafts and held invoices after secure-storage recovery',
    () async {
      await store.saveDraft(1, {
        'notes': 'مسودة محلية',
        'items': <Map<String, dynamic>>[],
      });
      await store.saveLocalHeld(1, 'held-1', {
        'id': 'held-1',
        'invoice_number': 'HOLD-1',
        'total': 50,
      });
      await const FlutterSecureStorage().deleteAll();

      expect((await store.draft(1))?['notes'], 'مسودة محلية');
      expect((await store.localHeld(1)).single['invoice_number'], 'HOLD-1');
    },
  );
}
