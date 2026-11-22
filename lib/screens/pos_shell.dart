import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/api_client.dart';
import '../widgets/logout_button.dart';
import '../widgets/sync_status_button.dart';
import '../widgets/desktop_pos_viewport.dart';
import 'dashboard_screen.dart';
import 'employee_screen.dart';
import 'pos_screen.dart';
import 'returns_screen.dart';
import 'sales_history_screen.dart';
import 'wholesale_screen.dart';
import 'customer_visits_screen.dart';
import 'wholesale_receipt_screen.dart';
import 'sync_screen.dart';
import 'printer_settings_screen.dart';
import 'barcode_labels_screen.dart';

/// Keeps each department's navigation and form state alive while switching tabs.
class PosShell extends StatefulWidget {
  const PosShell({super.key, required this.user});
  final Map<String, dynamic> user;

  static bool contains(BuildContext context) =>
      context.findAncestorStateOfType<_PosShellState>() != null;

  static bool isActive(BuildContext context) {
    final shell = context.findAncestorStateOfType<_PosShellState>();
    if (shell == null) return ModalRoute.of(context)?.isCurrent ?? false;
    return (ModalRoute.of(shell.context)?.isCurrent ?? false) &&
        shell._tabs.isNotEmpty &&
        shell._tabs[shell._selected].navigator.currentState ==
            Navigator.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? false);
  }

  static Future<void> open(
    BuildContext context,
    String title,
    Widget screen,
  ) async {
    final shell = context.findAncestorStateOfType<_PosShellState>();
    if (shell != null) {
      shell.open(title, screen);
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    }
  }

  @override
  State<PosShell> createState() => _PosShellState();
}

class _Department {
  _Department(this.title, this.screen);
  final String title;
  final Widget screen;
  final navigator = GlobalKey<NavigatorState>();
}

class _PosShellState extends State<PosShell> {
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  late final List<_Department> _tabs = [
    if (!_isAndroid) _Department('نقطة البيع', PosScreen(user: widget.user)),
  ];
  int _selected = 0;

  void open(String title, Widget screen) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final existing = _tabs.indexWhere((tab) => tab.title == title);
      if (existing >= 0) {
        _selected = existing;
      } else {
        _tabs.add(_Department(title, screen));
        _selected = _tabs.length - 1;
      }
    });
  }

  Future<void> _close(_Department tab) async {
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إغلاق ${tab.title}؟'),
        content: const Text('قد تفقد البيانات التي لم تحفظها في هذا القسم.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إغلاق التبويب'),
          ),
        ],
      ),
    );
    if (close != true || !mounted || !_tabs.contains(tab)) return;
    setState(() {
      final current = _tabs[_selected];
      _tabs.remove(tab);
      _selected = current == tab ? 0 : _tabs.indexOf(current);
    });
  }

  Map<String, Widget> get _departments =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? {
          'فاتورة مبيعات': WholesaleScreen(
            user: widget.user,
            salesInvoice: true,
          ),
          'سند قبض مستقل': WholesaleReceiptScreen(user: widget.user),
          // Phones pick their Bluetooth printer here; without it nothing can print.
          'إعدادات الطابعات': const PrinterSettingsScreen(),
        }
      : {
          'نقطة البيع': PosScreen(user: widget.user),
          'المزامنة والفواتير المحلية': const SyncScreen(),
          'إعدادات الطابعات': const PrinterSettingsScreen(),
          'طباعة الباركود': const BarcodeLabelsScreen(),
          'لوحة التحكم': DashboardScreen(user: widget.user),
          'مبيعات الجملة': WholesaleScreen(user: widget.user),
          'سند قبض مستقل': WholesaleReceiptScreen(user: widget.user),
          'قائمة الزيارات': CustomerVisitsScreen(user: widget.user),
          'سجل الفواتير': SalesHistoryScreen(user: widget.user),
          'مرتجعات المبيعات': ReturnsScreen(
            user: widget.user,
            branchId: int.tryParse('${widget.user['branch_id']}') ?? 0,
          ),
          if (ApiClient.employee != null)
            'شؤون الموظف': EmployeeScreen(
              user: widget.user,
              initialProfile: ApiClient.session ?? {},
            ),
        };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DesktopPosViewport(
      child: SafeArea(
        child: Column(
          children: [
            if (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.windows &&
                MediaQuery.sizeOf(context).width >= 1050)
              Container(
                height: 32,
                color: Colors.white,
                alignment: Alignment.centerLeft,
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    PopupMenuButton<String>(
                      onSelected: (value) => value == 'logout'
                          ? LogoutButton.logout(context)
                          : open(
                              'لوحة التحكم',
                              DashboardScreen(user: widget.user),
                            ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'dashboard',
                          child: Text('لوحة التحكم'),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: Text('تسجيل الخروج'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('WaslaPOS', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => open(
                        'إعدادات الطابعات',
                        const PrinterSettingsScreen(),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: const Color(0xFF0F172A),
                      ),
                      child: const Text(
                        'الطابعة',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (title) {
                        final screen = _departments[title];
                        if (screen != null) open(title, screen);
                      },
                      itemBuilder: (_) => [
                        for (final title in _departments.keys)
                          PopupMenuItem(value: title, child: Text(title)),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('عرض', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isAndroid && MediaQuery.sizeOf(context).width >= 1050)
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 36),
                color: Colors.white,
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/images/wasla-logo.svg',
                      width: 34,
                      height: 34,
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'WaslaPOS',
                      style: TextStyle(fontSize: 17, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 24),
                    const SizedBox(height: 24, child: VerticalDivider()),
                    const SizedBox(width: 16),
                    const Text(
                      'نقطة البيع',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 22),
                    const SizedBox(height: 24, child: VerticalDivider()),
                    TextButton.icon(
                      onPressed: () => open(
                        'لوحة التحكم',
                        DashboardScreen(user: widget.user),
                      ),
                      icon: const Icon(
                        Icons.home_outlined,
                        color: Color(0xFF737373),
                        size: 20,
                      ),
                      label: const Text(
                        'لوحة التحكم',
                        style: TextStyle(
                          color: Color(0xFF737373),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: (_) => LogoutButton.logout(context),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'logout',
                          child: Text('تسجيل الخروج'),
                        ),
                      ],
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E5E5),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '${widget.user['name'] ?? 'U'}'
                                  .split(' ')
                                  .where((word) => word.isNotEmpty)
                                  .take(2)
                                  .map((word) => word[0])
                                  .join()
                                  .toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${widget.user['name'] ?? 'الكاشير'}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF737373),
                            ),
                          ),
                          const SizedBox(width: 25),
                          const Icon(
                            Icons.expand_more,
                            color: Color(0xFF9CA3AF),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isAndroid && MediaQuery.sizeOf(context).width >= 1050)
                    _sidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        Material(
                          color: const Color(0xFFE8EDF5),
                          child: SizedBox(
                            height: MediaQuery.sizeOf(context).width >= 1050
                                ? 56
                                : 46,
                            child: Row(
                              children: [
                                PopupMenuButton<String>(
                                  tooltip: 'فتح قسم',
                                  onSelected: (title) {
                                    final screen = _departments[title];
                                    if (screen != null) open(title, screen);
                                  },
                                  itemBuilder: (_) => _departments.keys
                                      .map(
                                        (title) => PopupMenuItem(
                                          value: title,
                                          child: Text(title),
                                        ),
                                      )
                                      .toList(),
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      6,
                                      6,
                                      8,
                                      5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    height: 35,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(0xFFCBD5E1),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.menu, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'فتح قسم',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (var i = 0; i < _tabs.length; i++)
                                          Padding(
                                            key: ObjectKey(_tabs[i]),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                              vertical: 0,
                                            ),
                                            child: Material(
                                              color: i == _selected
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                  : const Color(0xFFF8FAFC),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                      top: Radius.circular(9),
                                                    ),
                                                side: BorderSide(
                                                  color: i == _selected
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                      : const Color(0xFFCBD5E1),
                                                ),
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                      top: Radius.circular(9),
                                                    ),
                                                onTap: () {
                                                  FocusManager
                                                      .instance
                                                      .primaryFocus
                                                      ?.unfocus();
                                                  setState(() => _selected = i);
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        _tabs[i].title,
                                                        style: TextStyle(
                                                          color: i == _selected
                                                              ? Colors.white
                                                              : const Color(
                                                                  0xFF475569,
                                                                ),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip:
                                                            'إغلاق ${_tabs[i].title}',
                                                        onPressed: () =>
                                                            _close(_tabs[i]),
                                                        icon: Icon(
                                                          Icons.close,
                                                          size: 16,
                                                          color: i == _selected
                                                              ? Colors.white
                                                              : const Color(
                                                                  0xFF64748B,
                                                                ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isAndroid ||
                                    MediaQuery.sizeOf(context).width < 1050)
                                  const LogoutButton(),
                                if (!_isAndroid)
                                  SyncStatusButton(
                                    onPressed: () => open(
                                      'المزامنة والفواتير المحلية',
                                      const SyncScreen(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: _tabs.isEmpty
                              ? _home()
                              : IndexedStack(
                                  index: _selected,
                                  children: [
                                    for (final tab in _tabs)
                                      TickerMode(
                                        key: ObjectKey(tab),
                                        enabled: tab == _tabs[_selected],
                                        child: Navigator(
                                          key: tab.navigator,
                                          onGenerateRoute: (_) =>
                                              MaterialPageRoute<void>(
                                                builder: (_) => tab.screen,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _home() => ColoredBox(
    color: Colors.white,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'WaslaPOS',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in _departments.entries)
                  OutlinedButton(
                    onPressed: () => open(entry.key, entry.value),
                    child: Text(entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  /// Desktop section sidebar: icons only while selling, labels when expanded.
  bool _sidebarExpanded = false;

  static const _sidebarGroups = <(String, List<(String, IconData)>)>[
    (
      'البيع',
      [
        ('نقطة البيع', Icons.point_of_sale_outlined),
        ('مبيعات الجملة', Icons.local_shipping_outlined),
        ('مرتجعات المبيعات', Icons.assignment_return_outlined),
        ('سند قبض مستقل', Icons.receipt_long_outlined),
        ('سجل الفواتير', Icons.history),
      ],
    ),
    (
      'الإدارة',
      [
        ('لوحة التحكم', Icons.dashboard_outlined),
        ('شؤون الموظف', Icons.badge_outlined),
        ('طباعة الباركود', Icons.qr_code_2),
      ],
    ),
    (
      'النظام',
      [
        ('المزامنة والفواتير المحلية', Icons.sync),
        ('إعدادات الطابعات', Icons.print_outlined),
      ],
    ),
  ];

  Widget _sidebar() => AnimatedContainer(
    key: const Key('desktop-sidebar'),
    duration: const Duration(milliseconds: 160),
    width: _sidebarExpanded ? 224 : 64,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: BorderDirectional(end: BorderSide(color: Color(0xFFE2E8F0))),
    ),
    // Labels appear only once the animated width has room for them.
    child: LayoutBuilder(
      builder: (_, box) => _sidebarContent(box.maxWidth >= 200),
    ),
  );

  Widget _sidebarContent(bool expanded) {
    final departments = _departments;
    final current = _tabs.isEmpty ? null : _tabs[_selected].title;
    const ink = Color(0xFF0F172A);
    const muted = Color(0xFF64748B);
    final primary = Theme.of(context).colorScheme.primary;
    Widget item(String title, IconData icon) {
      final selected = title == current;
      final tile = Material(
        color: selected ? primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('sidebar-$title'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final screen = departments[title];
            if (screen != null) open(title, screen);
          },
          child: SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (expanded) const SizedBox(width: 12),
                Icon(icon, size: 21, color: selected ? Colors.white : ink),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? Colors.white : ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: expanded ? tile : Tooltip(message: title, child: tile),
      );
    }

    return ClipRect(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Material(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('sidebar-toggle'),
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    setState(() => _sidebarExpanded = !_sidebarExpanded),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisAlignment: expanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      if (expanded) const SizedBox(width: 12),
                      Icon(
                        expanded ? Icons.menu_open : Icons.menu,
                        size: 21,
                        color: ink,
                      ),
                      if (expanded) ...[
                        const SizedBox(width: 12),
                        const Text(
                          'الأقسام',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (group, items) in _sidebarGroups)
                  if (items.any(
                    (entry) => departments.containsKey(entry.$1),
                  )) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        6,
                        14,
                        6,
                        4,
                      ),
                      child: expanded
                          ? Text(
                              group,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: muted,
                              ),
                            )
                          : const Divider(height: 1),
                    ),
                    for (final (title, icon) in items)
                      if (departments.containsKey(title)) item(title, icon),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
