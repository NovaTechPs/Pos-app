import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product_catalog.dart';
import '../models/sale_data.dart';
import '../services/product_maintenance_service.dart';

class MissingBarcodeDialog extends StatefulWidget {
  const MissingBarcodeDialog({
    super.key,
    required this.barcode,
    required this.branchId,
    required this.categories,
    required this.products,
  });
  final String barcode;
  final int branchId;
  final List<dynamic> categories, products;
  @override
  State<MissingBarcodeDialog> createState() => _MissingBarcodeDialogState();
}

class _MissingBarcodeDialogState extends State<MissingBarcodeDialog> {
  String _stage = 'choice';
  bool _busy = false;
  String? _error;
  String _query = '';
  int? _category;
  final _form = GlobalKey<FormState>();
  final _choiceFocus = FocusNode();
  final _name = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _retail = TextEditingController();
  final _wholesale = TextEditingController(text: '0');
  final _stock = TextEditingController(text: '0');
  late final _catalog = ProductCatalog([
    {'products': widget.products},
  ]);

  @override
  void dispose() {
    _choiceFocus.dispose();
    for (final controller in [_name, _cost, _retail, _wholesale, _stock]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save({int? productId}) async {
    if (_busy || (productId == null && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final product = await ProductMaintenanceService().save(
        productId == null ? 'pos/products' : 'pos/product-barcodes',
        {
          'branch_id': widget.branchId,
          'barcode': widget.barcode,
          'product_id': ?productId,
          if (productId == null) ...{
            'name': _name.text.trim(),
            'category_id': _category,
            'cost_price': SaleData.number(_cost.text),
            'retail_price': SaleData.number(_retail.text),
            'wholesale_price': SaleData.number(_wholesale.text),
            'stock_quantity': SaleData.number(_stock.text),
          },
        },
      );
      if (mounted) Navigator.pop(context, product);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _amount(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = SaleData.number(value);
        return number == null || number < 0 || number > 999999999
            ? 'أدخل قيمة صحيحة غير سالبة'
            : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final results = _query.trim().isEmpty
        ? const <dynamic>[]
        : _catalog.search(_query, null).take(40).toList();
    return PopScope(
      canPop: !_busy,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_busy) Navigator.pop(context);
          },
        },
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFD9B45C)),
          ),
          child: Focus(
            focusNode: _choiceFocus,
            autofocus: true,
            skipTraversal: true,
            onKeyEvent: (_, event) =>
                _stage == 'choice' &&
                    _choiceFocus.hasPrimaryFocus &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter)
                ? KeyEventResult.handled
                : KeyEventResult.ignored,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '⚠ الباركود غير موجود',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SelectableText(
                      widget.barcode,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Flexible(
                      child: SingleChildScrollView(
                        child: _stage == 'choice'
                            ? const Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'رقم الباركود المدخل غير موجود في ملف الأصناف.',
                                  ),
                                  SizedBox(height: 16),
                                  Text('اضغط نعم لإضافته لصنف جديد.'),
                                  SizedBox(height: 16),
                                  Text(
                                    'اضغط لا لإضافة الباركود لصنف موجود مسبقاً.',
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'اضغط إلغاء لإنهاء العملية والرجوع لحقل الباركود في نقطة البيع.',
                                  ),
                                ],
                              )
                            : _stage == 'create'
                            ? Form(
                                key: _form,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      autofocus: true,
                                      controller: _name,
                                      decoration: const InputDecoration(
                                        labelText: 'اسم الصنف',
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'أدخل اسم الصنف'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<int>(
                                      initialValue: _category,
                                      decoration: const InputDecoration(
                                        labelText: 'التصنيف',
                                      ),
                                      items: [
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('بدون تصنيف'),
                                        ),
                                        for (final category
                                            in widget.categories)
                                          if ((SaleData.id(category['id']) ??
                                                  0) >
                                              0)
                                            DropdownMenuItem(
                                              value: SaleData.id(
                                                category['id'],
                                              ),
                                              child: Text(
                                                '${category['name']}',
                                              ),
                                            ),
                                      ],
                                      onChanged: _busy
                                          ? null
                                          : (value) => setState(
                                              () => _category = value,
                                            ),
                                    ),
                                    _amount('سعر التكلفة', _cost),
                                    _amount('سعر البيع', _retail),
                                    _amount('سعر الجملة', _wholesale),
                                    _amount(
                                      'الرصيد الافتتاحي في الفرع الحالي',
                                      _stock,
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: 'بحث عن صنف موجود',
                                      hintText: 'الاسم أو الرقم أو الباركود',
                                    ),
                                    onChanged: (value) =>
                                        setState(() => _query = value),
                                  ),
                                  const SizedBox(height: 12),
                                  if (results.isEmpty)
                                    Text(
                                      _query.trim().isEmpty
                                          ? 'ابدأ بكتابة اسم الصنف أو رقمه للبحث.'
                                          : 'لا توجد أصناف مطابقة.',
                                    ),
                                  for (final product in results)
                                    ListTile(
                                      title: Text('${product['name']}'),
                                      subtitle: Text(
                                        '${product['product_number'] ?? product['id']}',
                                      ),
                                      trailing: const Icon(Icons.link),
                                      onTap: _busy
                                          ? null
                                          : () => _save(
                                              productId: SaleData.id(
                                                product['id'],
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 24),
                    if (_stage == 'choice')
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF009968),
                              ),
                              onPressed: () =>
                                  setState(() => _stage = 'create'),
                              child: const Text('نعم'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  setState(() => _stage = 'attach'),
                              child: const Text('لا'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إلغاء'),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('إلغاء'),
                            ),
                          ),
                          if (_stage == 'create') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy ? null : () => _save(),
                                child: const Text('حفظ الصنف'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'إضافة الصنف تفتح هنا داخل نقطة البيع مع الاحتفاظ بالفاتورة الحالية.',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
