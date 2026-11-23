import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/checkout_service.dart';
import 'package:waslapos_app/services/offline_store.dart';
import 'package:waslapos_app/services/pos_service.dart';
import 'package:waslapos_app/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> login({int user = 1, int tenant = 1, int branch = 1}) =>
      ApiClient.saveSession(
        token: 'token-$user',
        session: {
          'user': {'id': user, 'tenant_id': tenant, 'branch_id': branch},
        },
      );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
    await login();
    await ApiClient.offlineStore!.cache(
      Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=1'),
      '{"categories":[],"offline_contract_version":1}',
    );
  });
  tearDown(() => ApiClient.client.close());
  http.Response response(Object data, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final catalog = Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=1');
  final payload = <String, dynamic>{
    'branch_id': 1,
    'total_amount': 20,
    'items': [
      {'product_id': 2, 'quantity': 2, 'price': 10},
    ],
  };
  CheckoutService service() =>
      CheckoutService(scope: 'sale-1', offlineEndpoint: 'pos/orders');
  Future<Map<String, dynamic>> sell(CheckoutService checkout) =>
      checkout.checkout(
        payload: payload,
        receiptItems: [
          {'name': 'قهوة', 'product_id': 2, 'quantity': 2, 'price': 10},
        ],
        cashierName: 'كاشير',
        offlineShiftId: 7,
      );
  void online({
    Future<http.Response> Function(http.Request)? sale,
    int shift = 7,
  }) {
    ApiClient.client = MockClient((request) async {
      if (request.url.path.endsWith('/shifts/active')) {
        return response({
          'active_shift': {'id': shift},
          'offline_contract_version': 1,
        });
      }
      if (request.url.path.endsWith('/theme')) {
        return response({'theme': 'blue'});
      }
      if (request.method == 'POST' && sale != null) return sale(request);
      return response({'status': 'missing'}, 404);
    });
  }

  test('rapid online saves reuse reachability checks but offline and branch changes invalidate them', () async {
    var probes = 0;
    var posts = 0;
    ApiClient.client = MockClient((request) async {
      if (request.method == 'GET') {
        probes++;
        return response({
          'active_shift': {'id': 7},
        });
      }
      posts++;
      return response({
        'order': {'id': posts, 'invoice_number': 'INV-$posts'},
      }, 201);
    });
    final checkout = service();
    expect((await sell(checkout))['success'], true);
    expect((await sell(checkout))['success'], true);
    expect(probes, 1);
    expect(posts, 2);
    ApiClient.offline.value = true;
    final queued = await sell(checkout);
    expect(queued['queued'], true);
    expect(posts, 2);
    expect(probes, 1);
    final restored = await checkout.checkout(
      payload: payload,
      receiptItems: [],
      cashierName: 'كاشير',
      offlineShiftId: 7,
      probeWhenOffline: true,
    );
    expect(restored['success'], true);
    expect(probes, 2);
    expect(posts, 3);
    expect(
      (await checkout.checkout(
        payload: {...payload, 'branch_id': 2},
        receiptItems: [],
        cashierName: 'كاشير',
        offlineShiftId: 7,
      ))['success'],
      true,
    );
    expect(probes, 3);
  });

  test('a server-confirmed sale lets the next checkout skip a redundant connection request', () async {
    var probes = 0;
    var posts = 0;
    ApiClient.client = MockClient((request) async {
      if (request.method == 'GET') {
        probes++;
        return response({
          'active_shift': {'id': 7},
        });
      }
      posts++;
      return response({
        'order': {'id': posts, 'invoice_number': 'INV-$posts'},
      }, 201);
    });
    final first = CheckoutService(scope: 'online-only-sale');
    expect((await sell(first))['success'], true);
    expect(probes, 0);
    expect((await sell(service()))['success'], true);
    expect(posts, 2);
    expect(probes, 0);
  });

  test('short local numbers are serialized and survive restart without changing sync IDs', () async {
    final numbers = await Future.wait(
      List.generate(
        12,
        (_) => ApiClient.offlineStore!.nextOfflineInvoiceNumber(),
      ),
    );
    expect(numbers.toSet().length, 12);
    expect(numbers.first, 'OFF000001');
    expect(numbers.last, 'OFF000012');
    await ApiClient.initialize();
    expect(
      await ApiClient.offlineStore!.nextOfflineInvoiceNumber(),
      'OFF000013',
    );
    ApiClient.offline.value = true;
    final result = await sell(service());
    expect(result['order']['invoice_number'], 'OFF000014');
    final queued = (await SyncService.records()).single;
    expect(queued['payload']['operation_uuid'], isNot(startsWith('OFF')));
    online(
      sale: (_) async => response({
        'order': {'id': 81, 'invoice_number': 'INV-81'},
      }, 201),
    );
    await SyncService.synchronize();
    expect((await service().read())!['order']['invoice_number'], 'INV-81');
  });

  test('a restored API connection uses its invoice number despite an old offline flag', () async {
    ApiClient.offline.value = true;
    var writes = 0;
    online(
      sale: (_) async {
        writes++;
        return response({
          'order': {'id': 82, 'invoice_number': 'INV-SERVER-82'},
        }, 201);
      },
    );
    final result = await service().checkout(
      payload: payload,
      receiptItems: [],
      cashierName: 'كاشير',
      offlineShiftId: 7,
      probeWhenOffline: true,
    );
    expect(result['success'], true);
    expect(result['queued'], isNot(true));
    expect(result['order']['invoice_number'], 'INV-SERVER-82');
    expect(writes, 1);
    expect(ApiClient.offline.value, false);
  });

  test('drafts and local held invoices survive restart and stay isolated by account', () async {
    final store = ApiClient.offlineStore!;
    await store.saveDraft(1, {
      'items': [
        {'product_id': 2},
      ],
      'notes': 'مسودة',
    });
    await store.saveLocalHeld(1, 'held-1', {'id': 'local:held-1', 'total': 20});
    await ApiClient.initialize();
    expect((await ApiClient.offlineStore!.draft(1))!['notes'], 'مسودة');
    expect((await ApiClient.offlineStore!.localHeld(1)).single['total'], 20);
    await login(user: 2);
    expect(await ApiClient.offlineStore!.draft(1), isNull);
    expect(await ApiClient.offlineStore!.localHeld(1), isEmpty);
    await login();
    await ApiClient.offlineStore!.deleteLocalHeld(1, 'held-1');
    expect(await ApiClient.offlineStore!.localHeld(1), isEmpty);
  });

  test('offline customers use their prepared pricing branch without borrowing another branch price', () async {
    var downloads = 0;
    ApiClient.client = MockClient((request) async {
      downloads++;
      final customerBranch = request.url.queryParameters['customer_id'] == '6'
          ? 2
          : 1;
      return response({
        'categories': [
          {
            'id': 1,
            'products': [
              {
                'id': 2,
                'name': 'قهوة',
                'pricing_branch_id': customerBranch,
                'retail_price': customerBranch == 1 ? 10 : 12,
              },
            ],
          },
        ],
        'offline_contract_version': 1,
        'pos_line_contract_version': 2,
      });
    });
    await PosService().prepareOfflineCustomerPricing(1, [
      {'id': 5, 'branch_id': 1},
      {'id': 6, 'branch_id': 2},
      {'id': 7, 'branch_id': 2},
    ]);
    expect(downloads, 2);
    ApiClient.offline.value = true;
    ApiClient.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    final service = PosService();
    final first = await service.fetchCategories(
      1,
      customerId: 5,
      pricingBranchId: 1,
      preferCache: true,
    );
    final second = await service.fetchCategories(
      1,
      customerId: 7,
      pricingBranchId: 2,
      preferCache: true,
    );
    expect(first.first['products'][0]['retail_price'], 10);
    expect(second.first['products'][0]['retail_price'], 12);
    expect(service.supportsGiftLines, true);
    expect(service.lastFetchOffline, true);
    expect(
      () => service.fetchCategories(
        1,
        customerId: 9,
        pricingBranchId: 3,
        preferCache: true,
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('cached catalog survives restart and transport failure', () async {
    final savedToken = ApiClient.token;
    final savedUser = ApiClient.user;
    ApiClient.client = MockClient(
      (_) async => response({
        'categories': [
          {'name': 'قهوة'},
        ],
      }),
    );
    await ApiClient.get(catalog, cacheForOffline: true);
    await ApiClient.initialize();
    ApiClient.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    final cached = await ApiClient.get(catalog, cacheForOffline: true);
    expect(jsonDecode(cached.body)['categories'][0]['name'], 'قهوة');
    expect(cached.headers['x-wasla-offline'], 'true');
    expect(ApiClient.offline.value, true);
    expect(ApiClient.token, savedToken);
    expect(ApiClient.user, savedUser);
  });
  test('older unresolved operations can be manually reviewed without retransmission', () async {
    ApiClient.offline.value = true;
    await sell(service());
    await sell(service());
    final record = (await SyncService.records()).first;
    final uuid = record['payload']['operation_uuid'] as String;
    await ApiClient.offlineStore!.saveOperation({
      ...record,
      'status': 'uncertain',
    });
    await SyncService.resolveAfterVerification(uuid, wasSaved: false);
    expect(
      (await ApiClient.offlineStore!.operation(uuid))!['status'],
      'rejected',
    );
    expect(
      (await SyncService.records()).where(
        (entry) => entry['status'] == 'queued',
      ),
      hasLength(1),
    );
  });
  test('manual review cannot silently confirm an unsent queued sale', () async {
    ApiClient.offline.value = true;
    await sell(service());
    final record = (await SyncService.records()).single;
    await SyncService.resolveAfterVerification(
      record['payload']['operation_uuid'],
      wasSaved: true,
    );
    expect((await SyncService.records()).single['status'], 'queued');
  });
  test(
    'checkout reconciliation updates the outbox as well as the last receipt',
    () async {
      ApiClient.offline.value = true;
      await sell(service());
      online(sale: (_) async => throw TimeoutException('lost'));
      await expectLater(
        SyncService.synchronize(),
        throwsA(isA<TimeoutException>()),
      );
      ApiClient.client = MockClient(
        (_) async => response({
          'status': 'confirmed',
          'result': {
            'order': {'id': 70, 'invoice_number': 'INV-70'},
          },
        }),
      );
      expect(await service().reconcile(), true);
      expect((await SyncService.records()).single['status'], 'confirmed');
      expect((await service().read())!['order']['id'], 70);
    },
  );
  test(
    'manual verification cannot leave a stale sending record in the outbox',
    () async {
      ApiClient.offline.value = true;
      await sell(service());
      online(sale: (_) async => throw TimeoutException('lost'));
      await expectLater(
        SyncService.synchronize(),
        throwsA(isA<TimeoutException>()),
      );
      await service().resolveAfterVerification(wasSaved: false);
      expect((await SyncService.records()).single['status'], 'rejected');
      expect((await service().read())!['status'], 'rejected');
    },
  );
  test(
    'offline checkout queues locally without a server contract flag',
    () async {
      await ApiClient.offlineStore!.cache(catalog, '{"categories":[]}');
      ApiClient.offline.value = true;
      var calls = 0;
      ApiClient.client = MockClient((_) async {
        calls++;
        return response({});
      });
      final result = await sell(service());
      expect(result['success'], true);
      expect(result['queued'], true);
      expect((await SyncService.records()).single['status'], 'queued');
      expect(calls, 0);
    },
  );
  test('an offline invoice can be saved from the loaded cart without a catalog snapshot', () async {
    await ApiClient.offlineStore!.forget(catalog);
    ApiClient.offline.value = true;
    ApiClient.client = MockClient(
      (_) async => throw StateError('must not send'),
    );
    expect((await sell(service()))['queued'], true);
    expect((await SyncService.records()).single['status'], 'queued');
  });

  test(
    'a newly dropped connection queues before sending any financial request',
    () async {
      ApiClient.offline.value = false;
      var writes = 0;
      ApiClient.client = MockClient((request) async {
        if (request.method == 'POST') writes++;
        throw http.ClientException('no internet');
      });
      final result = await sell(service());
      expect(result['queued'], true);
      expect(writes, 0);
      expect(ApiClient.offline.value, true);
    },
  );

  test(
    'legacy API without a contract flag accepts a queued invoice exactly once',
    () async {
      ApiClient.offline.value = true;
      await sell(service());
      var writes = 0;
      ApiClient.client = MockClient((request) async {
        if (request.url.path.endsWith('/shifts/active')) {
          return response({
            'active_shift': {'id': 7},
          });
        }
        if (request.method == 'POST') {
          writes++;
          return response({
            'order': {'id': 81, 'invoice_number': 'INV-81'},
          }, 200);
        }
        return response({'theme': 'blue'});
      });
      await SyncService.synchronize();
      await SyncService.synchronize();
      expect(writes, 1);
      expect((await SyncService.records()).single['status'], 'confirmed');
    },
  );

  test('operations without an offline implementation are not transmitted or queued', () async {
    ApiClient.offline.value = true;
    var calls = 0;
    final result = await sell(
      CheckoutService(
        scope: 'unsupported',
        send: (_) async {
          calls++;
          return response({});
        },
      ),
    );
    expect(result['success'], false);
    expect(calls, 0);
    expect(await SyncService.records(), isEmpty);
  });
  test('sync and checkout cannot run financial writes concurrently', () async {
    final remote = Completer<http.Response>();
    ApiClient.client = MockClient((_) => remote.future);
    final sync = SyncService.synchronize();
    expect((await sell(service()))['success'], false);
    remote.complete(response({'theme': 'blue'}));
    await sync;
    expect(SyncService.beginCheckout(), true);
    try {
      await expectLater(SyncService.synchronize(), throwsStateError);
    } finally {
      SyncService.endCheckout();
    }
  });
  test(
    'cache is isolated by tenant user branch and full customer query',
    () async {
      await ApiClient.offlineStore!.cache(catalog, '{"categories":[]}');
      final owner = ApiClient.offlineStore!;
      for (final identity in [(2, 1, 1), (1, 2, 1), (1, 1, 2)]) {
        await login(
          user: identity.$1,
          tenant: identity.$2,
          branch: identity.$3,
        );
        expect(await ApiClient.offlineStore!.cached(catalog), isNull);
      }
      expect(
        await owner.cached(
          catalog.replace(
            queryParameters: {'branch_id': '1', 'customer_id': '8'},
          ),
        ),
        isNull,
      );
    },
  );
  for (final code in [401, 403, 422, 503]) {
    test('HTTP $code is never disguised as cached success', () async {
      await ApiClient.offlineStore!.cache(catalog, '{"categories":[]}');
      ApiClient.client = MockClient(
        (_) async => response({'message': 'failed'}, code),
      );
      expect(
        (await ApiClient.get(catalog, cacheForOffline: true)).statusCode,
        code,
      );
      expect(ApiClient.offline.value, false);
    });
  }
  test('reconciliation never uses an offline snapshot', () async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/sale-operations/test');
    await ApiClient.offlineStore!.cache(uri, '{"status":"confirmed"}');
    ApiClient.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    await expectLater(ApiClient.get(uri), throwsA(isA<http.ClientException>()));
  });
  test(
    'offline sales persist separately with stable UUIDs and no HTTP writes',
    () async {
      var writes = 0;
      ApiClient.offline.value = true;
      ApiClient.client = MockClient((_) async {
        writes++;
        throw StateError('must not send');
      });
      final first = await sell(service());
      final second = await sell(service());
      expect(first['success'], true);
      expect(first['queued'], true);
      expect(first['order']['offline_pending'], true);
      expect(
        first['order']['invoice_number'],
        isNot(second['order']['invoice_number']),
      );
      await ApiClient.initialize();
      expect(await SyncService.records(), hasLength(2));
      expect((await service().read())!['status'], 'queued');
      expect(writes, 0);
    },
  );
  test(
    'sync preserves UUID, checks original shift and confirms only once',
    () async {
      ApiClient.offline.value = true;
      await sell(service());
      final uuid =
          (await SyncService.records()).single['payload']['operation_uuid'];
      var writes = 0;
      online(
        sale: (request) async {
          writes++;
          expect(jsonDecode(request.body)['operation_uuid'], uuid);
          return response({
            'order': {'id': 50, 'invoice_number': 'INV-50'},
          }, 201);
        },
      );
      await SyncService.synchronize();
      await SyncService.synchronize();
      expect(writes, 1);
      expect((await service().read())!['order']['id'], 50);
      expect(ApiClient.offline.value, false);
    },
  );
  test('automatic sync exposes a blocking reason and succeeds on a later automatic attempt', () async {
    ApiClient.offline.value = true;
    await sell(service());
    online(shift: 8);
    await SyncService.synchronizeAutomatically();
    expect(SyncService.currentError, contains('الوردية الأصلية'));
    expect((await SyncService.records()).single['status'], 'queued');
    online(
      sale: (_) async => response({
        'order': {'id': 91},
      }, 201),
    );
    await SyncService.synchronizeAutomatically();
    expect(SyncService.currentError, isNull);
    expect((await SyncService.records()).single['status'], 'confirmed');
  });

  test('an uncertain invoice the server cannot answer for is not resent and does not block a later unsent invoice', () async {
    ApiClient.offline.value = true;
    await sell(service());
    await sell(service());
    final records = await SyncService.records();
    await ApiClient.offlineStore!.saveOperation({
      ...records.first,
      'status': 'uncertain',
    });
    final pendingUuid = records.last['payload']['operation_uuid'];
    var writes = 0;
    ApiClient.client = MockClient((request) async {
      if (request.url.path.contains('/sale-operations/')) {
        return http.Response('<html>waking up</html>', 503);
      }
      if (request.url.path.endsWith('/shifts/active')) {
        return response({
          'active_shift': {'id': 7},
        });
      }
      writes++;
      expect(jsonDecode(request.body)['operation_uuid'], pendingUuid);
      return response({
        'order': {'id': 92},
      }, 201);
    });
    await SyncService.synchronizeAutomatically();
    expect(writes, 1);
    final updated = await SyncService.records();
    expect(updated.first['status'], 'uncertain');
    expect(updated.last['status'], 'confirmed');
    expect(SyncService.currentError, contains('لم يتأكد حفظها'));
  });

  test('an invoice stuck by a waking server is sent once the server confirms it never saved it', () async {
    ApiClient.offline.value = true;
    await sell(service());
    final uuid =
        (await SyncService.records()).single['payload']['operation_uuid'];

    // The server is waking: the first send gets an HTML 503 page.
    online(sale: (_) async => http.Response('<html>waking up</html>', 503));
    await SyncService.synchronizeAutomatically();
    expect((await SyncService.records()).single['status'], 'uncertain');

    // Awake: no result is stored for that ID, so the same invoice is sent again.
    final sent = <String>[];
    online(
      sale: (request) async {
        sent.add(jsonDecode(request.body)['operation_uuid']);
        return response({
          'order': {'id': 93},
        }, 201);
      },
    );
    await SyncService.synchronizeAutomatically();
    expect(sent, [uuid]);
    final record = (await SyncService.records()).single;
    expect(record['status'], 'confirmed');
    expect(record['order']['id'], 93);
  });

  test('changed shift prevents any financial write', () async {
    ApiClient.offline.value = true;
    await sell(service());
    var writes = 0;
    online(
      shift: 8,
      sale: (_) async {
        writes++;
        return response({});
      },
    );
    await expectLater(SyncService.synchronize(), throwsStateError);
    expect(writes, 0);
    expect((await SyncService.records()).single['status'], 'queued');
  });
  test('lost sync reply survives restart and is confirmed from the server without resubmitting', () async {
    ApiClient.offline.value = true;
    await sell(service());
    var writes = 0;
    online(
      sale: (_) async {
        writes++;
        throw TimeoutException('lost response');
      },
    );
    await expectLater(
      SyncService.synchronize(),
      throwsA(isA<TimeoutException>()),
    );
    await ApiClient.initialize();
    expect((await SyncService.records()).single['status'], 'sending');
    // The server saved it before the reply was lost: it answers for the ID.
    ApiClient.client = MockClient((request) async {
      if (request.url.path.contains('/sale-operations/')) {
        return response({
          'status': 'confirmed',
          'result': {
            'order': {'id': 94},
          },
        });
      }
      if (request.method == 'POST') writes++;
      return response({'theme': 'blue'});
    });
    await SyncService.synchronize();
    expect(writes, 1);
    final record = (await SyncService.records()).single;
    expect(record['status'], 'confirmed');
    expect(record['order']['id'], 94);
  });
  test(
    'server rejection stays in the local ledger and is never retried',
    () async {
      ApiClient.offline.value = true;
      await sell(service());
      var writes = 0;
      online(
        sale: (_) async {
          writes++;
          return response({'message': 'stock changed'}, 422);
        },
      );
      await SyncService.synchronize();
      await SyncService.synchronize();
      expect(writes, 1);
      expect((await SyncService.records()).single['status'], 'rejected');
      expect((await SyncService.records()).single['message'], 'stock changed');
    },
  );
  test('damaged financial ledger is surfaced rather than silently discarded', () async {
    final prefix =
        'wasla_offline_v1_${Uri.encodeComponent(ApiClient.offlineStore!.scope)}_operation_bad';
    await const FlutterSecureStorage().write(key: prefix, value: '{bad');
    await expectLater(SyncService.records(), throwsFormatException);
  });
  test('separate storage instances share persisted records only within their scope', () async {
    final a = OfflineStore('A');
    await a.saveOperation({
      'payload': {'operation_uuid': 'stable-id'},
      'created_at': '2026-10-28',
      'status': 'queued',
    });
    expect(await OfflineStore('A').operations(), hasLength(1));
    expect(await OfflineStore('B').operations(), isEmpty);
  });
}
