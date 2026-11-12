import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/sync_service.dart';
import 'package:waslapos_app/widgets/sync_status_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
    await ApiClient.saveSession(
      token: 'token',
      session: {
        'user': {'id': 1, 'tenant_id': 1, 'branch_id': 1},
      },
    );
  });
  testWidgets(
    'ordinary UI rebuilds do not reread the ledger; ledger and branch changes do',
    (tester) async {
      var reads = 0;
      Future<List<Map<String, dynamic>>> load() async {
        reads++;
        return [
          {'status': 'queued'},
        ];
      }

      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) {
                rebuild = update;
                return SyncStatusButton(onPressed: () {}, loadRecords: load);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 100; i++) {
        rebuild(() {});
        await tester.pump();
      }
      expect(reads, 1);
      ApiClient.offline.value = true;
      SyncService.lastError.value = 'temporary error';
      await tester.pumpAndSettle();
      expect(reads, 1);
      SyncService.lastError.value = null;
      SyncService.revision.value++;
      await tester.pumpAndSettle();
      expect(reads, 2);
      await ApiClient.saveSession(
        token: 'token',
        session: {
          'user': {'id': 1, 'tenant_id': 1, 'branch_id': 2},
        },
      );
      rebuild(() {});
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
