import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/services/offline_store.dart';

class CountingStorage extends FlutterSecureStorage {
  int scans = 0;
  final readKeys = <String>[];
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    readKeys.add(key);
    return super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    scans++;
    return super.readAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefix = 'wasla_offline_v1_test_';
  Map<String, dynamic> record(String uuid) => {
    'payload': {'operation_uuid': uuid},
    'status': 'queued',
    'created_at': uuid,
  };
  test('pending checks skip settled history and retain rejected invoices for review', () async {
    final settled = List.generate(500, (i) => 'settled-$i');
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}operation_index': jsonEncode([
        ...settled,
        'queued',
        'rejected',
      ]),
      for (final id in settled)
        '${prefix}operation_$id': jsonEncode({
          ...record(id),
          'status': 'confirmed',
        }),
      '${prefix}operation_queued': jsonEncode(record('queued')),
      '${prefix}operation_rejected': jsonEncode({
        ...record('rejected'),
        'status': 'rejected',
      }),
    });
    final storage = CountingStorage();
    final store = OfflineStore('test', storage: storage);
    expect(await store.pendingOperations(), hasLength(2));
    storage.readKeys.clear();
    expect(
      await OfflineStore('test', storage: storage).pendingOperations(),
      hasLength(2),
    );
    expect(
      storage.readKeys.where((key) => key.contains('operation_settled')),
      isEmpty,
    );
    expect(storage.readKeys, hasLength(4));
    expect(storage.scans, 0);
    await store.saveOperation({...record('queued'), 'status': 'confirmed'});
    expect((await store.pendingOperations()).single['status'], 'rejected');
    expect(await store.operations(), hasLength(502));
    // A previous app version can append an invoice without updating the new index.
    await storage.write(
      key: '${prefix}operation_index',
      value: jsonEncode([...settled, 'queued', 'rejected', 'older-app']),
    );
    await storage.write(
      key: '${prefix}operation_older-app',
      value: jsonEncode(record('older-app')),
    );
    expect(
      (await store.pendingOperations()).map(
        (r) => r['payload']['operation_uuid'],
      ),
      contains('older-app'),
    );
  });
  test('attention reservations recover safely after interruption and concurrent saves', () async {
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}operation_index': jsonEncode(['reserved']),
      '${prefix}pending_index_v1': jsonEncode({
        'indexed_count': 1,
        'ids': ['reserved'],
      }),
    });
    final store = OfflineStore('test');
    expect(await store.pendingOperations(), isEmpty);
    await Future.wait(
      List.generate(10, (i) => store.saveOperation(record('new-$i'))),
    );
    await store.saveOperation(record('reserved'));
    expect(await store.pendingOperations(), hasLength(11));
    await store.storage.write(key: '${prefix}pending_index_v1', value: '{}');
    await expectLater(store.pendingOperations(), throwsFormatException);
  });
  test(
    'legacy invoices migrate once and later polls do not scan catalog storage',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        '${prefix}operation_old': jsonEncode(record('old')),
        '${prefix}cache_products': 'large catalog data',
        'wasla_offline_v1_other_operation_elsewhere': jsonEncode(
          record('elsewhere'),
        ),
      });
      final storage = CountingStorage();
      final store = OfflineStore('test', storage: storage);
      expect(
        (await store.operations()).single['payload']['operation_uuid'],
        'old',
      );
      expect(storage.scans, 1);
      await Future.wait(
        List.generate(20, (i) => store.saveOperation(record('new-$i'))),
      );
      final restored = OfflineStore('test', storage: storage);
      expect(await restored.operations(), hasLength(21));
      expect(await restored.operations(), hasLength(21));
      expect(storage.scans, 1);
    },
  );
  test('an empty reservation survives interruption and damaged invoices remain errors', () async {
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}operation_index': jsonEncode(['reserved', 'saved']),
      '${prefix}operation_saved': jsonEncode(record('saved')),
    });
    final store = OfflineStore('test');
    expect(await store.operations(), hasLength(1));
    await store.saveOperation(record('reserved'));
    expect(await store.operations(), hasLength(2));
    await store.storage.write(key: '${prefix}operation_saved', value: 'broken');
    await expectLater(store.operations(), throwsFormatException);
  });
  test('a damaged index never silently hides financial records', () async {
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}operation_index': '{}',
    });
    await expectLater(OfflineStore('test').operations(), throwsFormatException);
  });
}
