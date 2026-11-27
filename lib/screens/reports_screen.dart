import 'dart:async';

import 'package:flutter/material.dart';

import '../models/report_filters.dart';
import '../services/report_center_service.dart';

/// The web «مركز التقارير» in the app: report groups, the same filters per report,
/// quick periods, totals, notes and a paged table, loaded from the server.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.user,
    this.service = const ReportCenterService(),
    this.now,
  });

  final Map<String, dynamic> user;
  final ReportCenterService service;

  /// Today, replaceable in tests.
  final DateTime Function()? now;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  bool _loadingIndex = true;
  String? _indexError;
  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _branches = const [];
  int? _ownBranchId;
  bool _canSeeProfit = false;

  String? _group;
  String? _report;
  late ReportFilters _filters;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  int _page = 1;
  int _request = 0;

  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filters = ReportFilters.forReport('', _now);
    _loadIndex();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _reportEntry {
    for (final group in _groups) {
      for (final report in group['reports'] as List) {
        if (report['key'] == _report) return Map<String, dynamic>.from(report);
      }
    }
    return null;
  }

  /// Branches this report may show; null means «كل الفروع» is allowed too.
  List<Map<String, dynamic>> get _reportBranches {
    final ids = _reportEntry?['branch_ids'];
    if (ids is! List) return _branches;
    final allowed = ids.map((id) => int.tryParse('$id')).toSet();
    return _branches
        .where((branch) => allowed.contains(int.tryParse('${branch['id']}')))
        .toList();
  }

  bool get _allBranches => _reportEntry?['all_branches'] != false;

  /// «كل الفروع» when allowed, otherwise the user's own branch or the first allowed one.
  int? _defaultBranch() {
    if (_allBranches) return null;
    final ids = _reportBranches
        .map((branch) => int.tryParse('${branch['id']}'))
        .whereType<int>()
        .toList();
    if (_ownBranchId != null && ids.contains(_ownBranchId)) return _ownBranchId;
    return ids.isEmpty ? null : ids.first;
  }

  Future<void> _loadIndex() async {
    setState(() {
      _loadingIndex = true;
      _indexError = null;
    });
    try {
      final data = await widget.service.index();
      if (!mounted) return;
      final groups = (data['groups'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((group) => (group['reports'] as List? ?? const []).isNotEmpty)
          .toList();
      setState(() {
        _groups = groups;
        _branches = (data['branches'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _ownBranchId = int.tryParse('${data['own_branch_id']}');
        _canSeeProfit = data['can_see_profit'] == true;
        _loadingIndex = false;
      });
      if (groups.isNotEmpty) _selectGroup('${groups.first['name']}');
    } catch (error) {
      if (mounted) {
        setState(() {
          _indexError = '$error';
          _loadingIndex = false;
        });
      }
    }
  }

  void _selectGroup(String name) {
    final group = _groups.firstWhere((group) => group['name'] == name);
    _selectReport('${(group['reports'] as List).first['key']}', group: name);
  }

  void _selectReport(String key, {String? group}) {
    setState(() {
      _group = group ?? _group;
      _report = key;
      final keepDates = _result != null && key != 'expiring';
      final previous = _filters;
      _filters = ReportFilters.forReport(key, _now);
      if (keepDates) {
        _filters
          ..from = previous.from
          ..to = previous.to;
      }
      _filters.branchId = _allBranches ? previous.branchId : _defaultBranch();
      if (!_allBranches &&
          !_reportBranches.any(
            (branch) => int.tryParse('${branch['id']}') == _filters.branchId,
          )) {
        _filters.branchId = _defaultBranch();
      }
      _search.clear();
      _result = null;
      _error = null;
    });
    if (key != 'statement') _load();
  }

  Future<void> _load({int page = 1}) async {
    final report = _report;
    if (report == null) return;
    if (report == 'statement' && _filters.partyId == null) {
      setState(() {
        _error = 'اختر زبوناً أو مورداً أولاً.';
        _result = null;
      });
      return;
    }
    _filters.search = _search.text;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final result = await widget.service.show(
        report,
        _filters.query(report, canSeeProfit: _canSeeProfit),
        page: page,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _reset() {
    final report = _report;
    if (report == null) return;
    setState(() {
      _filters = ReportFilters.forReport(report, _now)
        ..branchId = _defaultBranch();
      _search.clear();
    });
    _load();
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(_now.year - 10),
      lastDate: DateTime(_now.year + 5),
      initialDate: from ? _filters.from : _filters.to,
    );
    if (picked == null || !mounted) return;
    setState(() => from ? _filters.setFrom(picked) : _filters.setTo(picked));
  }

  Future<void> _pickParty() async {
    final report = _report!;
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _LookupDialog(
        title: report == 'customer-invoice-profit'
            ? 'اختر زبوناً'
            : 'اختر زبوناً أو مورداً',
        hint: 'ابحث بالاسم أو الهاتف أو الرمز',
        searchOnOpen: true,
        load: (text) => widget.service.parties(
          text,
          type: report == 'customer-invoice-profit' ? 'customer' : 'all',
        ),
        subtitle: (party) =>
            '${party['code'] ?? ''} · ${ReportFilters.partyTypes[party['type']] ?? party['type'] ?? ''}',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filters
        ..partyId = int.tryParse('${picked['id']}')
        ..partyName = '${picked['name'] ?? ''}';
    });
    if (report == 'statement') _load();
  }

  Future<void> _pickProduct() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _LookupDialog(
        title: 'اختر صنفاً',
        hint: 'ابحث بالاسم أو رقم الصنف أو الباركود',
        load: widget.service.products,
        subtitle: (product) => '${product['product_number'] ?? product['id']}',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filters
        ..productId = int.tryParse('${picked['id']}')
        ..productName = '${picked['name'] ?? ''}';
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('مركز التقارير')),
      body: _loadingIndex
          ? const Center(child: CircularProgressIndicator())
          : _indexError != null
          ? _message(
              'تعذر تحميل التقارير: $_indexError',
              action: TextButton.icon(
                onPressed: _loadIndex,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            )
          : _groups.isEmpty
          ? _message('لا تملك صلاحية على أي تقرير.')
          : ListView(
              key: const Key('reports-body'),
              padding: const EdgeInsets.all(16),
              children: [
                _groupTabs(),
                const SizedBox(height: 8),
                _reportTabs(),
                const SizedBox(height: 12),
                _filterCard(),
                const SizedBox(height: 12),
                _resultSection(),
              ],
            ),
    ),
  );

  Widget _message(String text, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );

  Widget _groupTabs() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final group in _groups)
        ChoiceChip(
          key: Key('report-group-${group['name']}'),
          label: Text('${group['name']}'),
          selected: _group == group['name'],
          onSelected: (_) => _selectGroup('${group['name']}'),
        ),
    ],
  );

  Widget _reportTabs() {
    final group = _groups.firstWhere(
      (group) => group['name'] == _group,
      orElse: () => _groups.first,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final report in group['reports'] as List)
          ChoiceChip(
            key: Key('report-${report['key']}'),
            label: Text('${report['title']}'),
            selected: _report == report['key'],
            onSelected: (_) => _selectReport('${report['key']}'),
          ),
      ],
    );
  }

  Widget _select(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged, {
    Key? key,
  }) => SizedBox(
    width: 260,
    child: DropdownButtonFormField<String>(
      key: key,
      initialValue: options.containsKey(value) ? value : options.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final option in options.entries)
          DropdownMenuItem(
            value: option.key,
            child: Text(option.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => onChanged(value));
      },
    ),
  );

  Widget _filterCard() {
    final report = _report!;
    final periods = ReportFilters.periods(_now);
    final branches = _reportBranches;
    final choosesBranch = _allBranches || branches.length > 1;
    return Card(
      key: const Key('report-filters'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: const Key('report-from'),
                  onPressed: () => _pickDate(from: true),
                  icon: const Icon(Icons.event),
                  label: Text('من: ${ReportFilters.date(_filters.from)}'),
                ),
                OutlinedButton.icon(
                  key: const Key('report-to'),
                  onPressed: () => _pickDate(from: false),
                  icon: const Icon(Icons.event),
                  label: Text('إلى: ${ReportFilters.date(_filters.to)}'),
                ),
                if (choosesBranch)
                  _select(
                    'الفرع',
                    '${_filters.branchId ?? ''}',
                    {
                      if (_allBranches) '': 'كل الفروع',
                      for (final branch in branches)
                        '${branch['id']}': '${branch['name']}',
                    },
                    (value) => _filters.branchId = int.tryParse(value),
                    key: Key('report-branch-$report'),
                  )
                else
                  Chip(
                    label: Text(
                      'الفرع: ${branches.firstOrNull?['name'] ?? 'فرع المستخدم'}',
                    ),
                  ),
                if (ReportFilters.searchReports.contains(report))
                  SizedBox(
                    width: 260,
                    child: TextField(
                      key: const Key('report-search'),
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'بحث في التقرير',
                        hintText: 'اسم أو رقم الصنف / الطرف',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                if (ReportFilters.partyReports.contains(report))
                  _pickerButton(
                    key: const Key('report-party'),
                    label: report == 'statement'
                        ? 'الحساب'
                        : report == 'customer-invoice-profit'
                        ? 'الزبون'
                        : 'الزبون / المورد',
                    value: _filters.partyName,
                    empty: report == 'statement'
                        ? 'اختر حساباً'
                        : report == 'customer-invoice-profit'
                        ? 'كل الزبائن'
                        : 'كل الأطراف',
                    onPick: _pickParty,
                    onClear: report == 'statement'
                        ? null
                        : () => setState(
                            () => _filters
                              ..partyId = null
                              ..partyName = null,
                          ),
                  ),
                if (ReportFilters.productReports.contains(report))
                  _pickerButton(
                    key: const Key('report-product'),
                    label: 'الصنف',
                    value: _filters.productName,
                    empty: 'كل الأصناف',
                    onPick: _pickProduct,
                    onClear: () => setState(
                      () => _filters
                        ..productId = null
                        ..productName = null,
                    ),
                  ),
                if (ReportFilters.partyTypeReports.contains(report)) ...[
                  _select(
                    'نوع الطرف',
                    _filters.partyType,
                    ReportFilters.partyTypes,
                    (value) => _filters.partyType = value,
                  ),
                  _select(
                    'اتجاه الذمم',
                    _filters.balanceSide,
                    ReportFilters.balanceSides,
                    (value) => _filters.balanceSide = value,
                  ),
                ],
                if (ReportFilters.voucherTypeReports.contains(report))
                  _select(
                    'نوع الحركة',
                    _filters.voucherType,
                    ReportFilters.voucherTypes,
                    (value) => _filters.voucherType = value,
                  ),
                if (ReportFilters.paymentMethodReports.contains(report))
                  _select(
                    'طريقة الدفع',
                    _filters.paymentMethod,
                    ReportFilters.paymentMethods,
                    (value) => _filters.paymentMethod = value,
                  ),
                if (report == 'sales' || report == 'pos-invoices')
                  _select(
                    'الفواتير',
                    _filters.invoiceScope,
                    report == 'sales'
                        ? ReportFilters.salesInvoiceScopes
                        : ReportFilters.posInvoiceScopes,
                    (value) => _filters.invoiceScope = value,
                    key: Key('report-invoice-scope-$report'),
                  ),
                if (ReportFilters.sourceReports.contains(report)) ...[
                  _select(
                    'مصدر الفاتورة',
                    _filters.source,
                    ReportFilters.sources,
                    (value) => _filters.source = value,
                  ),
                  _select(
                    'نوع البيع',
                    _filters.saleKind,
                    ReportFilters.saleKinds,
                    (value) => _filters.saleKind = value,
                  ),
                ],
                if (ReportFilters.productViewReports.contains(report))
                  _select(
                    'طريقة العرض',
                    _filters.productView,
                    ReportFilters.productViews,
                    (value) => _filters.productView = value,
                  ),
                if (ReportFilters.showsCostMethod(
                  report,
                  canSeeProfit: _canSeeProfit,
                ))
                  _select(
                    'طريقة احتساب تكلفة الصنف',
                    _filters.costMethod,
                    ReportFilters.costMethods,
                    (value) => _filters.costMethod = value,
                  ),
                if (report == 'inventory')
                  _select(
                    'حالة المخزون',
                    _filters.stockFilter,
                    ReportFilters.stockFilters,
                    (value) => _filters.stockFilter = value,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('report-show'),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                  label: const Text('عرض التقرير'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة التعيين'),
                ),
                for (final period in periods.entries)
                  ChoiceChip(
                    label: Text(period.key),
                    selected:
                        ReportFilters.date(_filters.from) ==
                            ReportFilters.date(period.value.$1) &&
                        ReportFilters.date(_filters.to) ==
                            ReportFilters.date(period.value.$2),
                    onSelected: (_) {
                      setState(() {
                        _filters
                          ..from = period.value.$1
                          ..to = period.value.$2;
                      });
                      _load();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerButton({
    required Key key,
    required String label,
    required String? value,
    required String empty,
    required VoidCallback onPick,
    VoidCallback? onClear,
  }) => SizedBox(
    width: 280,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: key,
              onTap: onPick,
              child: Text(
                value ?? empty,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: value == null ? Colors.black54 : null),
              ),
            ),
          ),
          if (value != null && onClear != null)
            InkWell(onTap: onClear, child: const Icon(Icons.close, size: 18)),
          const SizedBox(width: 4),
          InkWell(onTap: onPick, child: const Icon(Icons.search, size: 18)),
        ],
      ),
    ),
  );

  Widget _resultSection() {
    if (_loading && _result == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('جارٍ تجهيز التقرير…')),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _error!,
          key: const Key('report-error'),
          style: const TextStyle(color: Color(0xFFB91C1C)),
        ),
      );
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final columns = (result['columns'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final rows = (result['rows'] as List? ?? const []).whereType<List>();
    final summary = (result['summary'] as List? ?? const []).whereType<Map>();
    final notes = (result['notes'] as List? ?? const []).map((n) => '$n');
    final page = int.tryParse('${result['page']}') ?? _page;
    final lastPage = int.tryParse('${result['last_page']}') ?? 1;
    return Column(
      key: const Key('report-result'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result['title'] ?? ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'الفترة: من ${result['from']} إلى ${result['to']} | الفرع: ${result['branch_name'] ?? 'كل الفروع'}',
          style: const TextStyle(color: Colors.black54),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in summary)
                Chip(
                  label: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${item['label']}: '),
                        TextSpan(
                          text: '${item['value']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (notes.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('ملاحظات التقرير'),
            children: [
              for (final note in notes)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(note),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'لا توجد بيانات مطابقة. اختر الفلاتر ثم اعرض التقرير.',
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('report-table'),
              headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F5F9)),
              columns: [
                for (final column in columns)
                  DataColumn(label: Text('${column['label']}')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      for (var i = 0; i < columns.length; i++)
                        DataCell(Text(i < row.length ? '${row[i]}' : '—')),
                    ],
                  ),
              ],
            ),
          ),
        if (lastPage > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                OutlinedButton(
                  key: const Key('report-previous'),
                  onPressed: page > 1 && !_loading
                      ? () => _load(page: page - 1)
                      : null,
                  child: const Text('السابق'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'صفحة $page من $lastPage — ${result['total']} سطر',
                  ),
                ),
                OutlinedButton(
                  key: const Key('report-next'),
                  onPressed: page < lastPage && !_loading
                      ? () => _load(page: page + 1)
                      : null,
                  child: const Text('التالي'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Search the server and pick one row (a customer, supplier or product).
class _LookupDialog extends StatefulWidget {
  const _LookupDialog({
    required this.title,
    required this.hint,
    required this.load,
    required this.subtitle,
    this.searchOnOpen = false,
  });

  final String title, hint;
  final Future<List<Map<String, dynamic>>> Function(String) load;
  final String Function(Map<String, dynamic>) subtitle;
  final bool searchOnOpen;

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.searchOnOpen) _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.load(_text.text);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('report-lookup-search'),
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _run);
              },
              onSubmitted: (_) {
                _debounce?.cancel();
                _run();
              },
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                  ? Center(
                      child: Text(
                        _text.text.trim().isEmpty && !widget.searchOnOpen
                            ? 'اكتب للبحث.'
                            : 'لا توجد نتائج مطابقة.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        return ListTile(
                          key: Key('report-lookup-$index'),
                          title: Text('${row['name'] ?? ''}'),
                          subtitle: Text(widget.subtitle(row)),
                          onTap: () => Navigator.pop(context, row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    ),
  );
}
