import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/services/offline_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final uri = Uri.parse('https://example.test/api/pos/products?branch_id=1');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wasla_cache_test');
  });
  tearDown(() async {
    OfflineStore.cacheDirectory = null;
    await directory.delete(recursive: true);
  });

  test('snapshots live in files, outside secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await OfflineStore.useFileCache(directory.path);
    final store = OfflineStore('scope');
    expect(await store.hasCached(uri), isFalse);

    await store.cache(uri, '{"categories":[1,2]}');
    // A non-object response never replaces a usable snapshot.
    await store.cache(uri, '[1]');

    final saved = await store.cached(uri);
    expect(saved!['body'], '{"categories":[1,2]}');
    expect(DateTime.tryParse(saved['saved_at'] as String), isNotNull);
    expect(await store.hasCached(uri), isTrue);
    final secure = await const FlutterSecureStorage().readAll();
    expect(
      secure.keys.where((key) => key.startsWith('wasla_offline_v1_')),
      isEmpty,
    );

    await store.forget(uri);
    expect(await store.cached(uri), isNull);
    expect(await store.hasCached(uri), isFalse);
  });

  test('older secure-storage snapshots move to files once', () async {
    final legacyKey =
        'wasla_offline_v1_${Uri.encodeComponent('scope')}_cache_'
        '${Uri.encodeComponent(uri.toString())}';
    FlutterSecureStorage.setMockInitialValues({
      legacyKey: jsonEncode({
        'body': '{"categories":[]}',
        'saved_at': '2026-01-01T00:00:00.000Z',
      }),
      'wasla_offline_v1_scope_draft_1': '{"items":[]}',
    });
    await OfflineStore.useFileCache(directory.path);
    final store = OfflineStore('scope');

    final saved = await store.cached(uri);
    expect(saved, {
      'body': '{"categories":[]}',
      'saved_at': '2026-01-01T00:00:00.000Z',
    });
    final secure = await const FlutterSecureStorage().readAll();
    expect(secure.containsKey(legacyKey), isFalse);
    expect(secure['wasla_offline_v1_scope_draft_1'], '{"items":[]}');
  });
}
