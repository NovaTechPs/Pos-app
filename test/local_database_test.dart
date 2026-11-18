import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waslapos_app/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late LocalDatabase database;

  setUp(() {
    database = LocalDatabase.inMemory(factory: databaseFactoryFfiNoIsolate);
  });

  tearDown(() => database.close());

  test('keeps API snapshots isolated by account scope', () async {
    final uri = Uri.parse('https://waslapos.app/api/pos/products?branch_id=1');

    await database.saveSnapshot(
      scope: 'tenant-1-user-7',
      uri: uri,
      body: '{"categories":[]}',
      savedAt: '2026-11-18T12:00:00.000Z',
    );

    expect(await database.snapshot(scope: 'tenant-2-user-7', uri: uri), isNull);
    expect(await database.snapshot(scope: 'tenant-1-user-7', uri: uri), {
      'body': '{"categories":[]}',
      'saved_at': '2026-11-18T12:00:00.000Z',
    });
  });

  test(
    'stores local documents independently from synchronization state',
    () async {
      await database.saveDocument(
        scope: 'tenant-1-user-7',
        collection: 'customers',
        documentId: '42',
        document: {'id': 42, 'name': 'شادي'},
        syncState: 'pending',
      );

      expect(
        await database.document(
          scope: 'tenant-1-user-7',
          collection: 'customers',
          documentId: '42',
        ),
        {'id': 42, 'name': 'شادي'},
      );
      expect(
        await database.documents(
          scope: 'tenant-1-user-7',
          collection: 'customers',
          syncState: 'pending',
        ),
        [
          {'id': 42, 'name': 'شادي'},
        ],
      );
    },
  );

  test(
    'keeps only unsettled operations in the synchronization queue',
    () async {
      const scope = 'tenant-1-user-7';
      final queued = {
        'status': 'queued',
        'created_at': '2026-11-18T12:00:00.000Z',
        'payload': {'operation_uuid': 'sale-1', 'total_amount': 25},
      };
      final confirmed = {
        'status': 'confirmed',
        'created_at': '2026-11-18T12:01:00.000Z',
        'payload': {'operation_uuid': 'sale-2', 'total_amount': 30},
      };

      await database.saveOperation(scope: scope, operation: confirmed);
      await database.saveOperation(scope: scope, operation: queued);

      expect(
        (await database.operations(
          scope: scope,
          pendingOnly: true,
        )).map((operation) => operation['payload']['operation_uuid']),
        ['sale-1'],
      );
    },
  );
}
