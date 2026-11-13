import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/screens/customer_visits_screen.dart';
import 'package:waslapos_app/services/customer_service.dart';
import 'package:waslapos_app/services/visit_service.dart';

class _FakeVisits extends VisitService {
  final visits = <Map<String, dynamic>>[];
  final updates = <Map<String, Object?>>[];
  var nextId = 1;

  Map<String, dynamic> _visit(Map customer) => {
    'id': nextId++,
    'outcome': null,
    'notes': null,
    'manager_note': customer['id'] == 7 ? 'حصّل 500' : null,
    'customer': {...customer, 'current_balance': 25},
  };

  @override
  Future<List<Map<String, dynamic>>> fetch(DateTime date) async => [...visits];

  @override
  Future<List<Map<String, dynamic>>> add(
    DateTime date,
    List<int> customerIds,
  ) async {
    for (final id in customerIds) {
      visits.add(_visit({'id': id, 'name': 'زبون $id', 'phone': '059$id'}));
    }
    return [...visits];
  }

  @override
  Future<Map<String, dynamic>> update(
    int visitId, {
    required String? outcome,
    required String notes,
  }) async {
    updates.add({'id': visitId, 'outcome': outcome, 'notes': notes});
    final index = visits.indexWhere((visit) => visit['id'] == visitId);
    visits[index] = {...visits[index], 'outcome': outcome, 'notes': notes};
    return visits[index];
  }

  @override
  Future<void> remove(int visitId) async =>
      visits.removeWhere((visit) => visit['id'] == visitId);
}

class _FakeCustomers extends CustomerService {
  @override
  Future<List<dynamic>> fetchWholesaleParties() async => [
    {'id': 7, 'name': 'زبون 7', 'type': 'customer'},
    {'id': 8, 'name': 'زبون 8', 'type': 'both'},
    {'id': 9, 'name': 'مورد', 'type': 'supplier'},
  ];
}

void main() {
  testWidgets(
    'a rep adds customers to the day and records each result with a note',
    (tester) async {
      final visits = _FakeVisits();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerVisitsScreen(
            user: const {'id': 1, 'tenant_id': 1, 'branch_id': 1},
            service: visits,
            customerService: _FakeCustomers(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('لا يوجد زبائن'), findsOneWidget);

      await tester.tap(find.text('إضافة زبائن'));
      await tester.pumpAndSettle();
      // Suppliers are not offered for visits.
      expect(find.text('مورد'), findsNothing);
      await tester.tap(find.text('زبون 7'));
      await tester.tap(find.text('زبون 8'));
      await tester.pump();
      await tester.tap(find.text('إضافة (2)'));
      await tester.pumpAndSettle();
      expect(find.text('تمت زيارة 0 من 2'), findsOneWidget);
      // The manager's instruction shows on that customer only.
      expect(find.text('من الإدارة: حصّل 500'), findsOneWidget);
      expect(find.byKey(const ValueKey('manager-note-2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('outcome-1-order')));
      await tester.pumpAndSettle();
      expect(visits.updates.last, {'id': 1, 'outcome': 'order', 'notes': ''});
      expect(find.text('تمت زيارة 1 من 2'), findsOneWidget);

      await tester.tap(find.text('+ إضافة ملاحظة').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'يريد 10 كراتين');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(visits.updates.last, {
        'id': 1,
        'outcome': 'order',
        'notes': 'يريد 10 كراتين',
      });
      expect(find.text('يريد 10 كراتين'), findsOneWidget);

      // Tapping the chosen result again clears it.
      await tester.tap(find.byKey(const ValueKey('outcome-1-order')));
      await tester.pumpAndSettle();
      expect(visits.updates.last['outcome'], isNull);
      expect(find.text('تمت زيارة 0 من 2'), findsOneWidget);
    },
  );

  test('visit dates are sent as plain days', () {
    expect(VisitService.dateKey(DateTime(2026, 3, 7, 18, 30)), '2026-03-07');
    expect(VisitService.outcomes.values, ['بيع', 'تحصيل فقط', 'يوجد طلبية']);
  });
}
