import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../widgets/logout_button.dart';
import '../theme/app_theme.dart';
import 'pos_screen.dart';
import 'pos_shell.dart';
import 'wholesale_screen.dart';
import 'sales_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  bool _isLoading = true;
  Map<String, dynamic> _summary = {};
  String? _error;
  DateTimeRange? _period;
  DateTime? _updatedAt;

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<void> _selectPeriod() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _period ?? DateTimeRange(start: now, end: now),
    );
    if (selected == null || !mounted) return;
    if (selected.duration.inDays > 365) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختر فترة لا تتجاوز سنة.')));
      return;
    }
    setState(() => _period = selected);
    _loadSummary();
  }

  Future<void> _openScreen(Widget screen) async {
    if (PosShell.contains(context)) {
      final title = screen is PosScreen
          ? 'نقطة البيع'
          : screen is WholesaleScreen
          ? 'مبيعات الجملة'
          : 'سجل الفواتير';
      await PosShell.open(context, title, screen);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadSummary();
  }

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  void _loadSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final branchId =
        int.tryParse(widget.user['branch_id']?.toString() ?? '') ?? 0;
    try {
      final summary = await _dashboardService.fetchSummary(
        branchId,
        from: _period == null ? null : _date(_period!.start),
        to: _period == null ? null : _date(_period!.end),
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
        _updatedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل الإحصائيات: $error';
          _isLoading = false;
        });
      }
    }
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(icon, color: color, size: 28),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'لوحة التحكم',
          style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppTheme.ink),
        actions: [
          const LogoutButton(),
          IconButton(
            onPressed: () => _openScreen(SalesHistoryScreen(user: widget.user)),
            icon: const Icon(Icons.receipt_long),
            tooltip: 'سجل الفواتير',
          ),
          IconButton(
            onPressed: _selectPeriod,
            icon: const Icon(Icons.date_range),
            tooltip: 'الفترة الزمنية',
          ),
          IconButton(
            icon: Icon(
              Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => _openScreen(WholesaleScreen(user: widget.user)),
            tooltip: 'مبيعات الجملة',
          ),
          IconButton(
            icon: Icon(
              Icons.point_of_sale,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              _openScreen(PosScreen(user: widget.user));
            },
            tooltip: 'فتح نقطة البيع (POS)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.ink),
            onPressed: _loadSummary,
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadSummary,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 3
                      : constraints.maxWidth >= 600
                      ? 2
                      : 1;
                  final cards = [
                    _metricCard(
                      'عدد الفواتير المباعة',
                      '${_summary['total_sales_count'] ?? 0} فواتير',
                      Icons.receipt_long,
                      Colors.blueAccent,
                    ),
                    _metricCard(
                      'إجمالي المبيعات',
                      '${_summary['total_sales_revenue'] ?? 0.0} ر.س',
                      Icons.point_of_sale,
                      Colors.green.shade800,
                    ),
                    _metricCard(
                      'إجمالي المرتجعات',
                      '${_summary['total_returns_revenue'] ?? 0.0} ر.س',
                      Icons.assignment_return,
                      Colors.redAccent,
                    ),
                    _metricCard(
                      'صافي الإيرادات',
                      '${_summary['net_revenue'] ?? 0.0} ر.س',
                      Icons.trending_up,
                      Colors.teal.shade800,
                    ),
                    _metricCard(
                      'إجمالي المصروفات',
                      '${_summary['total_expenses'] ?? 0.0} ر.س',
                      Icons.money_off,
                      Colors.orangeAccent,
                    ),
                    _metricCard(
                      'الربح الإجمالي',
                      '${_summary['gross_profit'] ?? 0.0} ر.س',
                      Icons.account_balance_wallet,
                      Colors.indigo,
                    ),
                    _metricCard(
                      'الربح بعد المصروفات',
                      '${_summary['net_profit_estimate'] ?? 0} ر.س',
                      Icons.insights,
                      Colors.blue.shade800,
                    ),
                    _metricCard(
                      'متوسط الفاتورة',
                      '${_summary['average_order_value'] ?? 0} ر.س',
                      Icons.analytics_outlined,
                      Colors.purple.shade700,
                    ),
                  ];
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Chip(
                              avatar: const Icon(Icons.store, size: 18),
                              label: Text(
                                'الفرع: ${widget.user['branch']?['name'] ?? widget.user['branch_id'] ?? '—'}',
                              ),
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.date_range, size: 18),
                              onPressed: _selectPeriod,
                              label: Text(
                                '${_summary['from'] ?? _summary['date'] ?? 'اليوم'} — ${_summary['to'] ?? _summary['date'] ?? 'اليوم'}',
                              ),
                            ),
                            if (_updatedAt != null)
                              Chip(
                                label: Text(
                                  'آخر تحديث ${TimeOfDay.fromDateTime(_updatedAt!).format(context)}',
                                ),
                              ),
                          ],
                        ),
                      ),
                      GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: columns == 1 ? 2.4 : 1.6,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: cards,
                      ),
                      const SizedBox(height: 20),
                      _dataSection(
                        'الأكثر مبيعاً خلال الفترة',
                        Icons.trending_up,
                        _summary['top_products'] as List? ?? [],
                        false,
                      ),
                      const SizedBox(height: 16),
                      _dataSection(
                        'تنبيهات المخزون',
                        Icons.inventory_2_outlined,
                        _summary['stock_alerts'] as List? ?? [],
                        true,
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _dataSection(String title, IconData icon, List items, bool stock) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لا توجد بيانات'),
              ),
            ...items.map(
              (item) => ListTile(
                dense: true,
                title: Text(item['name']?.toString() ?? '—'),
                subtitle: Text(
                  stock
                      ? 'الكمية: ${item['stock_quantity'] ?? 0} • حد التنبيه: ${item['alert_quantity'] ?? 0}'
                      : 'الكمية المباعة: ${item['quantity_sold'] ?? 0}',
                ),
                trailing: stock
                    ? const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.deepOrange,
                      )
                    : Text('${item['revenue'] ?? 0} ر.س'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
