import 'package:flutter/material.dart';

import '../services/employee_service.dart';
import '../widgets/logout_button.dart';
import '../theme/app_theme.dart';
import 'pos_screen.dart';
import 'pos_shell.dart';

class EmployeeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> initialProfile;

  const EmployeeScreen({
    super.key,
    required this.user,
    required this.initialProfile,
  });

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen>
    with WidgetsBindingObserver {
  final EmployeeService _employeeService = EmployeeService();
  bool _isClocking = false;
  bool _profileLoading = false;
  String? _profileError;
  String? _financeError;
  late Map<String, dynamic> _profileData;
  Map<String, dynamic> _finances = {
    'payroll': [],
    'advances': [],
    'leaves': [],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileData = widget.initialProfile;
    _loadFinances();
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile();
      _loadFinances();
    }
  }

  Future<void> _loadProfile() async {
    if (_profileLoading || _isClocking) return;
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await _employeeService.fetchProfile();
      if (mounted) setState(() => _profileData = profile);
    } catch (error) {
      if (mounted) {
        setState(() => _profileError = 'تعذر تحديث حالة الحضور: $error');
      }
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadFinances() async {
    try {
      final data = await _employeeService.fetchFinances();
      if (mounted) {
        setState(() {
          _finances = data;
          _financeError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _financeError = 'تعذر تحميل البيانات المالية: $error');
      }
    }
  }

  Future<void> _sendRequest(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final result = await _employeeService.submitRequest(endpoint, payload);
    if (!mounted) return;
    _showMessage(
      result['message']?.toString() ?? '',
      isError: result['success'] != true,
    );
    if (result['success'] == true) _loadFinances();
  }

  Future<void> _requestAdvance() async {
    final amount = TextEditingController();
    final installment = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب سلفة'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                    ? 'أدخل مبلغاً صحيحاً'
                    : null,
              ),
              TextFormField(
                controller: installment,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'القسط الشهري'),
                validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                    ? 'أدخل مبلغاً صحيحاً'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _sendRequest('advances', {
        'amount': amount.text,
        'installment_amount': installment.text,
        'start_installment_date': DateTime.now().toIso8601String().substring(
          0,
          10,
        ),
      });
    }
  }

  Future<void> _requestLeave() async {
    String type = 'annual';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('طلب إجازة ليوم واحد'),
          content: DropdownButtonFormField<String>(
            initialValue: type,
            items: const [
              DropdownMenuItem(value: 'annual', child: Text('سنوية')),
              DropdownMenuItem(value: 'sick', child: Text('مرضية')),
              DropdownMenuItem(value: 'emergency', child: Text('طارئة')),
              DropdownMenuItem(value: 'unpaid', child: Text('بدون راتب')),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => type = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      await _sendRequest('leaves', {
        'type': type,
        'start_date': date,
        'end_date': date,
      });
    }
  }

  Future<void> _scanAndClock() async {
    if (_isClocking || _profileLoading) return;
    setState(() => _isClocking = true);
    try {
      final fresh = await _employeeService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profileData = fresh;
        _profileError = null;
      });
      final attendance = fresh['today_attendance'] as Map?;
      final checkedIn = attendance?['check_in']?.toString().isNotEmpty == true;
      final checkedOut =
          attendance?['check_out']?.toString().isNotEmpty == true;
      if (checkedIn && checkedOut) {
        _showMessage('اكتمل دوام اليوم.');
        return;
      }
      final result = await _employeeService.clock(
        type: checkedIn ? 'check_out' : 'check_in',
      );
      if (!mounted) return;
      _showMessage(
        result['message']?.toString() ?? 'تعذر تسجيل الحركة.',
        isError: result['success'] != true,
      );
      if (result['success'] == true) {
        setState(
          () => _profileData = {
            ...fresh,
            'today_attendance': result['attendance'],
          },
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage('تعذر التحقق من حالة الحضور: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isClocking = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = _profileData['employee'] as Map<String, dynamic>?;
    final attendance =
        _profileData['today_attendance'] as Map<String, dynamic>?;
    final name = employee == null
        ? (widget.user['name']?.toString() ?? 'الموظف')
        : '${employee['first_name'] ?? ''} ${employee['last_name'] ?? ''}'
              .trim();
    final checkedIn = attendance?['check_in']?.toString();
    final checkedOut = attendance?['check_out']?.toString();
    final nextAction = (checkedIn == null || checkedIn.isEmpty)
        ? 'تسجيل الحضور'
        : (checkedOut == null || checkedOut.isEmpty)
        ? 'تسجيل الانصراف'
        : 'اكتمل دوام اليوم';

    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة الموظف'),
        actions: [
          const LogoutButton(),
          IconButton(
            onPressed: () {
              _loadProfile();
              _loadFinances();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث بيانات الموظف',
          ),
          IconButton(
            tooltip: 'نقطة البيع',
            icon: const Icon(Icons.point_of_sale_outlined),
            onPressed: () => PosShell.open(
              context,
              'نقطة البيع',
              PosScreen(user: widget.user),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          if (_profileLoading) const LinearProgressIndicator(),
          if (_profileError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_profileError!),
              ),
            ),
          if (_financeError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_financeError!),
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 31,
                            backgroundColor: Color(0xFFEAF0FF),
                            child: Icon(
                              Icons.person_rounded,
                              size: 34,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'الرقم الوظيفي: ${employee?['employee_code'] ?? '—'}',
                                  style: TextStyle(
                                    color: Colors.blueGrey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'حضور اليوم',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _timeTile(
                                  'وقت الحضور',
                                  checkedIn,
                                  const Color(0xFF16865B),
                                  Icons.login_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _timeTile(
                                  'وقت الانصراف',
                                  checkedOut,
                                  const Color(0xFFD04B4B),
                                  Icons.logout_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 56,
                            child: FilledButton.icon(
                              onPressed:
                                  _profileLoading ||
                                      _isClocking ||
                                      nextAction == 'اكتمل دوام اليوم'
                                  ? null
                                  : _scanAndClock,
                              icon: _isClocking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.qr_code_scanner_rounded),
                              label: Text(
                                _isClocking ? 'جارٍ التسجيل...' : nextAction,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'اضغط لتسجيل الحركة التالية بعد التحقق من حالة حضورك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.blueGrey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _financeCard(
                    'مسير الراتب',
                    _finances['payroll'] as List? ?? [],
                    (item) =>
                        'الصافي: ${item['net_salary'] ?? 0} • المدفوع: ${item['paid_amount'] ?? 0}',
                  ),
                  const SizedBox(height: 12),
                  _financeCard(
                    'السلف',
                    _finances['advances'] as List? ?? [],
                    (item) =>
                        'المبلغ: ${item['amount'] ?? 0} • الحالة: ${item['status'] ?? '—'}',
                  ),
                  OutlinedButton.icon(
                    onPressed: _requestAdvance,
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('طلب سلفة'),
                  ),
                  const SizedBox(height: 12),
                  _financeCard(
                    'الإجازات',
                    _finances['leaves'] as List? ?? [],
                    (item) =>
                        '${item['start_date'] ?? ''} – ${item['end_date'] ?? ''} • ${item['status'] ?? '—'}',
                  ),
                  OutlinedButton.icon(
                    onPressed: _requestLeave,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('طلب إجازة'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => PosShell.open(
                      context,
                      'نقطة البيع',
                      PosScreen(user: widget.user),
                    ),
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: const Text('فتح نقطة البيع'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeCard(
    String title,
    List entries,
    String Function(dynamic) subtitle,
  ) {
    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: entries.isEmpty
            ? [const ListTile(title: Text('لا توجد سجلات'))]
            : entries
                  .map(
                    (e) => ListTile(
                      title: Text(
                        '${e['payroll_period']?['name'] ?? e['type'] ?? e['start_date'] ?? 'سجل'}',
                      ),
                      subtitle: Text(subtitle(e)),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  Widget _timeTile(String label, String? time, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 3),
          Text(
            time == null || time.isEmpty ? '--:--' : time,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
