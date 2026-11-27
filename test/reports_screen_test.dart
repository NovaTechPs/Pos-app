import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/models/report_filters.dart';
import 'package:waslapos_app/screens/reports_screen.dart';
import 'package:waslapos_app/services/report_center_service.dart';

class _FakeReports extends ReportCenterService {
  final calls = <(String, Map<String, String>, int)>[];
  final partySearches = <String>[];

  @override
  Future<Map<String, dynamic>> index() async => {
    'groups': [
      {
        'name': 'الحسابات',
        'reports': [
          {
            'key': 'statement',
            'title': 'كشف حساب زبون / مورد',
            'all_branches': true,
          },
          {'key': 'balances', 'title': 'الذمم المدينة والدائنة'},
        ],
      },
      {
        'name': 'المبيعات',
        'reports': [
          {
            'key': 'sales',
            'title': 'ملخص المبيعات يوم بيوم',
            'all_branches': false,
            'branch_ids': [2],
          },
        ],
      },
    ],
    'branches': [
      {'id': 1, 'name': 'الرئيسي'},
      {'id': 2, 'name': 'فانوس'},
    ],
    'own_branch_id': 2,
    'can_see_profit': true,
  };

  @override
  Future<Map<String, dynamic>> show(
    String report,
    Map<String, String> filters, {
    int page = 1,
  }) async {
    calls.add((report, filters, page));
    return {
      'title': report == 'sales' ? 'ملخص المبيعات يوم بيوم' : 'كشف حساب',
      'from': filters['from'],
      'to': filters['to'],
      'branch_name': filters['branch_id'] == '2' ? 'فانوس' : 'كل الفروع',
      'columns': [
        {'key': 'day', 'label': 'اليوم'},
        {'key': 'net', 'label': 'الصافي'},
      ],
      'rows': [
        ['2026-11-0$page', '150.00'],
      ],
      'summary': [
        {'label': 'صافي المبيعات', 'value': '150.00'},
      ],
      'notes': ['ملاحظة للتجربة'],
      'page': page,
      'last_page': 2,
      'total': 31,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> parties(
    String search, {
    String type = 'all',
  }) async {
    partySearches.add(search);
    return [
      {'id': 7, 'name': 'ابو رشيد', 'code': 'C-7', 'type': 'customer'},
    ];
  }
}

void main() {
  test('filters send only what each report shows, like the web', () {
    final filters = ReportFilters.forReport('sales', DateTime(2026, 11, 27))
      ..branchId = 3
      ..partyId = 9
      ..productId = 4
      ..search = 'شاي'
      ..source = 'pos'
      ..invoiceScope = 'all';

    expect(filters.query('sales'), {
      'from': '2026-11-01',
      'to': '2026-11-27',
      'branch_id': '3',
      'invoice_scope': 'all',
      'source': 'pos',
    });
    expect(filters.query('product-sales', canSeeProfit: true), {
      'from': '2026-11-01',
      'to': '2026-11-27',
      'branch_id': '3',
      'product_id': '4',
      'search': 'شاي',
      'source': 'pos',
      'product_view': 'summary',
      'cost_method': 'recorded',
    });
    expect(filters.query('product-sales').containsKey('cost_method'), isFalse);
    expect(filters.query('statement')['party_id'], '9');
    expect(
      ReportFilters.forReport('expiring', DateTime(2026, 11, 27)).to,
      DateTime(2026, 12, 27),
    );

    filters.setFrom(DateTime(2026, 12, 5));
    expect(ReportFilters.date(filters.to), '2026-12-05');
    filters.setTo(DateTime(2026, 11, 2));
    expect(ReportFilters.date(filters.from), '2026-11-02');

    final periods = ReportFilters.periods(DateTime(2026, 1, 10, 15));
    expect(periods['الشهر السابق'], (
      DateTime(2025, 12),
      DateTime(2025, 12, 31),
    ));
    expect(periods['آخر 30 يوم']!.$1, DateTime(2025, 12, 12));
  });

  testWidgets(
    'reports open by group, need an account for the statement and page through rows',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeReports();
      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            user: const {'id': 1},
            service: service,
            now: () => DateTime(2026, 11, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The statement waits for an account, as on the web.
      expect(service.calls, isEmpty);
      expect(find.text('اختر حساباً'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-show')));
      await tester.pumpAndSettle();
      expect(find.text('اختر زبوناً أو مورداً أولاً.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-party')));
      await tester.pumpAndSettle();
      expect(service.partySearches, ['']);
      await tester.tap(find.byKey(const Key('report-lookup-0')));
      await tester.pumpAndSettle();
      expect(service.calls.single.$1, 'statement');
      expect(service.calls.single.$2['party_id'], '7');
      expect(find.text('ابو رشيد'), findsOneWidget);

      // A report limited to one branch uses it, and pages through the rows.
      await tester.tap(find.byKey(const Key('report-group-المبيعات')));
      await tester.pumpAndSettle();
      expect(service.calls.last.$1, 'sales');
      expect(service.calls.last.$2['branch_id'], '2');
      expect(find.text('الفرع: فانوس'), findsOneWidget);
      expect(find.text('صافي المبيعات: 150.00'), findsOneWidget);
      expect(find.text('2026-11-01'), findsOneWidget);
      expect(find.text('صفحة 1 من 2 — 31 سطر'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(service.calls.last.$3, 2);
      expect(find.text('2026-11-02'), findsOneWidget);

      // A quick period reloads the report for it.
      await tester.tap(find.text('أمس'));
      await tester.pumpAndSettle();
      expect(service.calls.last.$2['from'], '2026-11-26');
      expect(service.calls.last.$2['to'], '2026-11-26');
      expect(service.calls.last.$3, 1);
    },
  );
}
