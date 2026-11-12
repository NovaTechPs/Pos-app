import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/printer_routing_service.dart';
import 'printer_test_screen.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key, this.service});
  final PrinterRoutingService? service;
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterRoutingService get _service =>
      widget.service ?? PrinterRoutingService.instance;
  List<Printer> _printers = [];
  final Map<PrintRole, Printer?> _selected = {};
  final Map<PrintRole, int> _widths = {};
  bool _loading = true, _saving = false, _direct = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _service.settingsCapabilities();
      final printers = info.canListPrinters
          ? await _service.settingsPrinters()
          : <Printer>[];
      final selected = <PrintRole, Printer?>{};
      for (final role in PrintRole.values) {
        selected[role] = await _service.selected(role);
        _widths[role] = await _service.paperWidth(role);
      }
      if (mounted) {
        setState(() {
          _printers = printers;
          _selected.addAll(selected);
          _direct = info.directPrint;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(PrintRole role, String? url) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final printer = url == null || url.isEmpty
          ? null
          : _printers.firstWhere((p) => p.url == url);
      await _service.select(role, printer);
      if (mounted) setState(() => _selected[role] = printer);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ الطابعة: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('إعدادات الطابعات'),
      actions: [
        IconButton(
          onPressed: _loading || _saving ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث الطابعات',
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PrinterTestScreen(service: _service),
                        ),
                      ),
                icon: const Icon(Icons.print),
                label: const Text('فتح صفحة اختبار الطابعة'),
              ),
              const SizedBox(height: 12),
              Text(
                _service.androidBluetooth
                    ? 'اختر طابعة Q6 Pro المدمجة إذا ظهرت، أو اقرن طابعة بلوتوث من إعدادات الجهاز ثم اخترها هنا مرة واحدة. ستُطبع الفواتير مباشرة دون نافذة النظام. الطابعات الخارجية يجب أن تدعم ESC/POS Bluetooth Classic.'
                    : _direct
                    ? 'اختر طابعة لكل نوع مرة واحدة على هذا الجهاز. ستُرسل المهام مباشرة دون نافذة اختيار الطابعة.'
                    : 'هذه المنصة تستخدم نافذة الطباعة الخاصة بالنظام. حفظ طابعة والطباعة المباشرة متاحان على Windows والمنصات الداعمة.',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final role in PrintRole.values)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          role.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey('${role.name}-${_selected[role]?.url}'),
                          initialValue: _selected[role]?.url ?? '',
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('اختر الطابعة'),
                            ),
                            for (final printer in _printers)
                              DropdownMenuItem(
                                value: printer.url,
                                child: Text(
                                  printer.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_selected[role] != null &&
                                !_printers.any(
                                  (p) => p.url == _selected[role]!.url,
                                ))
                              DropdownMenuItem(
                                value: _selected[role]!.url,
                                enabled: false,
                                child: Text(
                                  '${_selected[role]!.name} (غير متاحة)',
                                ),
                              ),
                          ],
                          onChanged: !_direct || _saving
                              ? null
                              : (url) => _save(role, url),
                        ),
                        if (_service.androidBluetooth) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _widths[role] ?? 384,
                            decoration: const InputDecoration(
                              labelText: 'عرض الطباعة',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 384,
                                child: Text('58 مم — 384 نقطة'),
                              ),
                              DropdownMenuItem(
                                value: 576,
                                child: Text('80 مم — 576 نقطة'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (width) async {
                                    if (width == null) return;
                                    setState(() => _saving = true);
                                    try {
                                      await _service.setPaperWidth(role, width);
                                      if (mounted) {
                                        setState(() => _widths[role] = width);
                                      }
                                    } catch (error) {
                                      if (mounted) {
                                        setState(() => _error = '$error');
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _saving = false);
                                      }
                                    }
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _service.androidBluetooth
                    ? 'تُحفظ الخيارات على هذا الجهاز. طابعة Q6 المدمجة تستخدم عرض 58 مم تلقائياً. البلوتوث لا يحتاج إنترنت، وقد يطلب النظام إذن الأجهزة القريبة مرة واحدة.'
                    : 'تُحفظ هذه الخيارات محلياً لكل جهاز. اضبط مقاس ورق الطابعة الحرارية والتقارير مرة واحدة من خصائص الطابعة في Windows.',
              ),
            ],
          ),
  );
}
