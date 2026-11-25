part of 'pos_workspace.dart';

/// The recipient and delivery company of a delivery sale, as the web POS saves them.
class DeliveryDetails {
  const DeliveryDetails({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.companyId,
    this.companyName = '',
  });

  final String name;
  final String phone;
  final String address;
  final String notes;
  final int? companyId;
  final String companyName;

  bool get isComplete =>
      name.trim().isNotEmpty &&
      phone.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      companyId != null;

  /// The fields `/pos/orders` takes for a delivery sale.
  Map<String, dynamic> toPayload() => {
    'delivery_customer_name': name.trim(),
    'delivery_customer_phone': phone.trim(),
    'delivery_customer_address': address.trim(),
    if (notes.trim().isNotEmpty) 'delivery_notes': notes.trim(),
    'delivery_party_id': companyId,
  };
}

/// What the cashier chose in the delivery window: the details and whether to print after saving.
class DeliveryDecision {
  const DeliveryDecision(this.details, {required this.print});
  final DeliveryDetails details;
  final bool print;
}

/// The web POS «بيانات التوصيل» window: recipient name, phone, address, delivery note and the
/// delivery company (any active customer or supplier account), then «حفظ» or «حفظ وطباعة».
Future<DeliveryDecision?> showDeliveryDetailsDialog(
  BuildContext context, {
  required DeliveryDetails initial,
  required List<dynamic> parties,
}) => showDialog<DeliveryDecision>(
  context: context,
  barrierColor: const Color(0x99020617),
  builder: (_) => _DeliveryDetailsDialog(initial: initial, parties: parties),
);

class _DeliveryDetailsDialog extends StatefulWidget {
  const _DeliveryDetailsDialog({required this.initial, required this.parties});
  final DeliveryDetails initial;
  final List<dynamic> parties;

  @override
  State<_DeliveryDetailsDialog> createState() => _DeliveryDetailsDialogState();
}

class _DeliveryDetailsDialogState extends State<_DeliveryDetailsDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _address = TextEditingController(text: widget.initial.address);
  late final _notes = TextEditingController(text: widget.initial.notes);
  late final _company = TextEditingController(text: widget.initial.companyName);
  late int? _companyId = widget.initial.companyId;
  int _activeResult = -1;
  bool _resultsOpen = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _notes, _company]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Active customer and supplier accounts whose name or phone contains the search, as on the web.
  List<Map> get _results {
    final search = _company.text.trim();
    if (search.isEmpty) return const [];
    return widget.parties
        .whereType<Map>()
        .where(
          (party) =>
              party['is_active'] != false &&
              party['is_active'] != 0 &&
              ('${party['name'] ?? ''}'.contains(search) ||
                  '${party['phone'] ?? ''}'.contains(search)),
        )
        .take(30)
        .toList();
  }

  void _pick(Map party) => setState(() {
    _companyId = SaleData.id(party['id']);
    _company.text = '${party['name'] ?? ''}';
    _resultsOpen = false;
    _activeResult = -1;
    _errors.remove('company');
  });

  void _submit({required bool print}) {
    final details = DeliveryDetails(
      name: _name.text,
      phone: _phone.text,
      address: _address.text,
      notes: _notes.text,
      companyId: _companyId,
      companyName: _company.text.trim(),
    );
    setState(() {
      _errors
        ..clear()
        ..addAll({
          if (details.name.trim().isEmpty) 'name': 'حقل الاسم مطلوب.',
          if (details.phone.trim().isEmpty) 'phone': 'حقل رقم الهاتف مطلوب.',
          if (details.address.trim().isEmpty)
            'address': 'حقل المكان / العنوان مطلوب.',
          if (details.companyId == null) 'company': 'اختر شركة التوصيل.',
        });
    });
    if (_errors.isEmpty) {
      Navigator.of(context).pop(DeliveryDecision(details, print: print));
    }
  }

  Widget _label(String text, Widget field, {String? error}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        text,
        style: _Web.text(12, weight: FontWeight.w900, color: _Web.slate700),
      ),
      const SizedBox(height: 4),
      field,
      if (error != null) ...[
        const SizedBox(height: 4),
        Text(error, style: _Web.text(12, color: _Web.rose600)),
      ],
    ],
  );

  Widget _input(
    TextEditingController controller, {
    Key? key,
    int lines = 1,
    bool autofocus = false,
    TextInputType? keyboard,
    String? hint,
    TextStyle? style,
    ValueChanged<String>? onChanged,
  }) => TextField(
    key: key,
    controller: controller,
    autofocus: autofocus,
    minLines: lines,
    maxLines: lines,
    keyboardType: keyboard,
    style:
        style ?? _Web.text(14, weight: FontWeight.w400, color: _Web.slate900),
    decoration: _Web.field(
      hint: hint,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    onChanged: onChanged,
  );

  KeyEventResult _companyKeys(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_resultsOpen) return KeyEventResult.ignored;
    final results = _results;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _activeResult = math.min(_activeResult + 1, results.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _activeResult = math.max(_activeResult - 1, 0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _activeResult >= 0 &&
        _activeResult < results.length) {
      _pick(results[_activeResult]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _resultsOpen = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        key: const Key('pos-delivery-dialog'),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 512),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'بيانات التوصيل',
                            style: _Web.text(
                              16,
                              weight: FontWeight.w900,
                              color: _Web.slate900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'هذه البيانات ستظهر وتحفظ مع الفاتورة.',
                            style: _Web.text(
                              12,
                              weight: FontWeight.w400,
                              color: _Web.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Material(
                        color: _Web.slate100,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.of(context).pop(),
                          child: Center(
                            child: Text(
                              '✕',
                              style: _Web.text(14, color: _Web.slate600),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _label(
                        'الاسم',
                        _input(
                          _name,
                          key: const Key('pos-delivery-name'),
                          autofocus: true,
                        ),
                        error: _errors['name'],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _label(
                        'رقم الهاتف',
                        _input(
                          _phone,
                          key: const Key('pos-delivery-phone'),
                          keyboard: TextInputType.phone,
                        ),
                        error: _errors['phone'],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _label(
                  'المكان / العنوان',
                  _input(
                    _address,
                    key: const Key('pos-delivery-address'),
                    lines: 2,
                  ),
                  error: _errors['address'],
                ),
                const SizedBox(height: 12),
                _label(
                  'ملاحظة التوصيل',
                  _input(
                    _notes,
                    key: const Key('pos-delivery-notes'),
                    lines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _label(
                  'شركة التوصيل',
                  Focus(
                    onKeyEvent: _companyKeys,
                    child: _input(
                      _company,
                      key: const Key('pos-delivery-company'),
                      hint: 'ابحث بالاسم أو الهاتف',
                      style: _companyId == null
                          ? null
                          : _Web.text(
                              14,
                              weight: FontWeight.w900,
                              color: _Web.blue700,
                            ),
                      onChanged: (value) => setState(() {
                        _companyId = null;
                        _activeResult = -1;
                        _resultsOpen = value.trim().isNotEmpty;
                      }),
                    ),
                  ),
                  error: _errors['company'],
                ),
                if (_resultsOpen && _company.text.trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _Web.slate200),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F0F172A),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              'لا توجد نتائج مطابقة.',
                              style: _Web.text(
                                12,
                                weight: FontWeight.w400,
                                color: _Web.slate500,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (_, index) {
                              final party = results[index];
                              final chosen =
                                  SaleData.id(party['id']) == _companyId;
                              final active = index == _activeResult;
                              return Material(
                                color: active
                                    ? _Web.blue700
                                    : chosen
                                    ? _Web.blue50
                                    : Colors.white,
                                child: InkWell(
                                  key: Key(
                                    'pos-delivery-company-${party['id']}',
                                  ),
                                  onTap: () => _pick(party),
                                  onHover: (hovering) {
                                    if (hovering) {
                                      setState(() => _activeResult = index);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${party['name'] ?? ''}',
                                            style: _Web.text(
                                              14,
                                              weight: chosen
                                                  ? FontWeight.w900
                                                  : FontWeight.w400,
                                              color: active
                                                  ? Colors.white
                                                  : (chosen
                                                        ? _Web.blue700
                                                        : _Web.slate900),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${party['phone'] ?? ''}',
                                          textDirection: TextDirection.ltr,
                                          style: _Web.text(
                                            14,
                                            weight: FontWeight.w400,
                                            color: active
                                                ? Colors.white
                                                : _Web.slate500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          key: const Key('pos-delivery-save'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _Web.indigo700,
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _submit(print: false),
                          child: Text(
                            '💾 حفظ',
                            style: _Web.text(
                              14,
                              weight: FontWeight.w900,
                              color: _Web.indigo700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          key: const Key('pos-delivery-save-print'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _submit(print: true),
                          child: Text(
                            '🖨️ حفظ وطباعة',
                            style: _Web.text(
                              14,
                              weight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
