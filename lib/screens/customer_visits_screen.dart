import 'dart:async';

import 'package:flutter/material.dart';

import '../models/product_catalog.dart';
import '../models/sale_data.dart';
import '../services/customer_service.dart';
import '../services/visit_service.dart';
import 'pos_shell.dart';
import 'wholesale_receipt_screen.dart';

/// The rep's customer list for a day, worked through like a to-do list: each
/// customer gets one result (sale, collection only, or an order) and a note.
class CustomerVisitsScreen extends StatefulWidget {
  const CustomerVisitsScreen({
    super.key,
    required this.user,
    this.service,
    this.customerService,
  });

  final Map<String, dynamic> user;
  final VisitService? service;
  final CustomerService? customerService;

  @override
  State<CustomerVisitsScreen> createState() => _CustomerVisitsScreenState();
}

class _CustomerVisitsScreenState extends State<CustomerVisitsScreen> {
  late final VisitService _service = widget.service ?? VisitService();
  late final CustomerService _customers =
      widget.customerService ?? CustomerService();
  List<Map<String, dynamic>> _visits = [];
  DateTime _date = DateTime.now();
  bool _busy = true;
  String? _error;

  int get _done => _visits.where((visit) => visit['outcome'] != null).length;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final visits = await _service.fetch(_date);
      if (mounted) setState(() => _visits = visits);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(Object message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$message')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    await _load();
  }

  Future<void> _addCustomers() async {
    List<dynamic> parties;
    try {
      parties = (await _customers.fetchWholesaleParties())
          .where((row) => row is Map && row['type'] != 'supplier')
          .toList();
    } catch (e) {
      _message(e);
      return;
    }
    if (!mounted) return;
    final onList = _visits
        .map((visit) => SaleData.id((visit['customer'] as Map?)?['id']))
        .whereType<int>()
        .toSet();
    final chosen = await showDialog<List<int>>(
      context: context,
      builder: (_) => _CustomerChecklist(
        customers: parties
            .where((row) => !onList.contains(SaleData.id(row['id'])))
            .toList(),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    try {
      final visits = await _service.add(_date, chosen);
      if (mounted) setState(() => _visits = visits);
    } catch (e) {
      _message(e);
    }
  }

  Future<void> _record(
    Map<String, dynamic> visit, {
    required String? outcome,
    String? notes,
  }) async {
    try {
      final saved = await _service.update(
        SaleData.id(visit['id'])!,
        outcome: outcome,
        notes: notes ?? '${visit['notes'] ?? ''}',
      );
      if (!mounted) return;
      setState(() {
        final index = _visits.indexWhere((row) => row['id'] == visit['id']);
        if (index >= 0) _visits[index] = saved;
      });
    } catch (e) {
      _message(e);
    }
  }

  Future<void> _editNote(Map<String, dynamic> visit) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        customerName: '${(visit['customer'] as Map?)?['name'] ?? ''}',
        initialNote: '${visit['notes'] ?? ''}',
      ),
    );
    if (note == null) return;
    await _record(visit, outcome: visit['outcome'] as String?, notes: note);
  }

  Future<void> _remove(Map<String, dynamic> visit) async {
    try {
      await _service.remove(SaleData.id(visit['id'])!);
      if (mounted) {
        setState(() => _visits.removeWhere((row) => row['id'] == visit['id']));
      }
    } catch (e) {
      _message(e);
    }
  }

  void _openReceipt(Map<String, dynamic> visit) {
    final customer = Map<String, dynamic>.from(visit['customer'] as Map);
    unawaited(
      PosShell.open(
        context,
        'سند قبض مستقل',
        WholesaleReceiptScreen(
          user: widget.user,
          customers: [customer],
          initialCustomerId: SaleData.id(customer['id']),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الزيارات'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(VisitService.dateKey(_date)),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addCustomers,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة زبائن'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  _Progress(done: _done, total: _visits.length),
                  const SizedBox(height: 8),
                  if (_visits.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'لا يوجد زبائن في قائمة هذا اليوم. اضغط «إضافة زبائن».',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final visit in _visits)
                    _VisitCard(
                      key: ValueKey('visit-${visit['id']}'),
                      visit: visit,
                      onOutcome: (outcome) => _record(
                        visit,
                        // Tapping the chosen result again clears it.
                        outcome: visit['outcome'] == outcome ? null : outcome,
                      ),
                      onNote: () => _editNote(visit),
                      onRemove: visit['outcome'] == null
                          ? () => _remove(visit)
                          : null,
                      onReceipt: () => _openReceipt(visit),
                    ),
                ],
              ),
            ),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تمت زيارة $done من $total',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: total == 0 ? 0 : done / total),
        ],
      ),
    ),
  );
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    super.key,
    required this.visit,
    required this.onOutcome,
    required this.onNote,
    required this.onRemove,
    required this.onReceipt,
  });

  final Map<String, dynamic> visit;
  final ValueChanged<String> onOutcome;
  final VoidCallback onNote, onReceipt;
  final VoidCallback? onRemove;

  static const _colors = {
    'sale': Colors.green,
    'collection': Colors.blue,
    'order': Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final customer = Map<String, dynamic>.from(visit['customer'] as Map? ?? {});
    final outcome = visit['outcome'] as String?;
    final notes = '${visit['notes'] ?? ''}'.trim();
    final balance = SaleData.number(customer['current_balance']) ?? 0;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: outcome == null
              ? Colors.grey.shade300
              : _colors[outcome]!.shade300,
          width: outcome == null ? 1 : 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  outcome == null
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                  color: outcome == null ? Colors.grey : _colors[outcome],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer['name'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        [
                          if ('${customer['phone'] ?? ''}'.isNotEmpty)
                            '${customer['phone']}',
                          'الرصيد: ${balance.toStringAsFixed(2)}',
                        ].join(' · '),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => switch (value) {
                    'note' => onNote(),
                    'receipt' => onReceipt(),
                    'remove' => onRemove?.call(),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'note', child: Text('ملاحظة')),
                    const PopupMenuItem(
                      value: 'receipt',
                      child: Text('سند قبض لهذا الزبون'),
                    ),
                    if (onRemove != null)
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('حذف من القائمة'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in VisitService.outcomes.entries)
                  ChoiceChip(
                    key: ValueKey('outcome-${visit['id']}-${entry.key}'),
                    label: Text(entry.value),
                    selected: outcome == entry.key,
                    selectedColor: _colors[entry.key]!.shade100,
                    onSelected: (_) => onOutcome(entry.key),
                  ),
              ],
            ),
            InkWell(
              onTap: onNote,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  notes.isEmpty ? '+ إضافة ملاحظة' : notes,
                  style: TextStyle(
                    color: notes.isEmpty
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its text controller so it lives as long as the dialog, closing animation included.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.customerName, required this.initialNote});
  final String customerName, initialNote;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('ملاحظة: ${widget.customerName}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: 3,
      maxLength: 1000,
      decoration: const InputDecoration(
        hintText: 'مثال: يريد 10 كراتين يوم الأحد',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('حفظ'),
      ),
    ],
  );
}

/// Lets the rep tick several customers at once to add them to the day's list.
class _CustomerChecklist extends StatefulWidget {
  const _CustomerChecklist({required this.customers});
  final List<dynamic> customers;

  @override
  State<_CustomerChecklist> createState() => _CustomerChecklistState();
}

class _CustomerChecklistState extends State<_CustomerChecklist> {
  final _selected = <int>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = ProductCatalog.normalizeSearch(_query);
    final matches = query.isEmpty
        ? widget.customers
        : widget.customers
              .where(
                (customer) => ProductCatalog.normalizeSearch(
                  '${customer['name']} ${customer['code'] ?? ''} ${customer['phone'] ?? ''}',
                ).contains(query),
              )
              .toList(growable: false);
    return AlertDialog(
      title: const Text('إضافة زبائن لقائمة اليوم'),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'بحث بالاسم أو الرمز أو الهاتف',
              ),
              onChanged: (text) => setState(() => _query = text),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final customer = matches[index];
                  final id = SaleData.id(customer['id']);
                  return CheckboxListTile(
                    value: _selected.contains(id),
                    title: Text('${customer['name']}'),
                    subtitle: Text('${customer['phone'] ?? ''}'),
                    onChanged: id == null
                        ? null
                        : (checked) => setState(
                            () => checked == true
                                ? _selected.add(id)
                                : _selected.remove(id),
                          ),
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
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: Text('إضافة (${_selected.length})'),
        ),
      ],
    );
  }
}
