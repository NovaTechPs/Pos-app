import 'package:flutter/material.dart';

import '../models/sale_data.dart';

class ProductSelection {
  const ProductSelection(this.price, this.quantity);
  final double price, quantity;
}

String productUnit(Map product) {
  final unit = product['unit'];
  return unit is Map ? '${unit['name'] ?? 'قطعة'}' : '${unit ?? 'قطعة'}';
}

class MobileProductRow extends StatelessWidget {
  const MobileProductRow({
    super.key,
    required this.product,
    required this.price,
    this.onTap,
  });
  final Map product;
  final double? price;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    onTap: onTap,
    title: Text(
      '${product['name']}',
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
    ),
    subtitle: Text(
      '${product['product_number'] ?? product['id']} · ${productUnit(product)}',
      style: const TextStyle(color: Color(0xFF64748B)),
    ),
    // Side by side: ListTile limits trailing height to 48px.
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          price == null ? 'غير مسعّر' : '₪ ${price!.toStringAsFixed(2)}',
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.add_circle_outline,
          color: onTap == null ? Colors.grey : const Color(0xFF10883D),
          size: 22,
        ),
      ],
    ),
  );
}

class ProductAddDialog extends StatefulWidget {
  const ProductAddDialog({
    super.key,
    required this.product,
    required this.price,
    required this.loadHistory,
    this.customerName,
    this.minimum = 1,
    this.available,
  });
  final Map<String, dynamic> product;
  final double price, minimum;
  final double? available;
  final String? customerName;
  final Future<List<dynamic>> Function()? loadHistory;
  @override
  State<ProductAddDialog> createState() => _ProductAddDialogState();
}

class _ProductAddDialogState extends State<ProductAddDialog> {
  late final _price = TextEditingController(
    text: widget.price.toStringAsFixed(2),
  );
  late final _quantity = TextEditingController(text: _format(widget.minimum));
  final _form = GlobalKey<FormState>();
  String _format(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  double? get price => SaleData.number(_price.text);
  double? get quantity => SaleData.number(_quantity.text);
  void _selectAll(TextEditingController controller) {
    void select() => controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    select();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) select();
    });
  }

  @override
  void dispose() {
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _history() async {
    final future = widget.loadHistory?.call();
    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'آخر سعر بيع${widget.customerName == null ? '' : ' — ${widget.customerName}'}',
        ),
        content: SizedBox(
          width: 360,
          child: future == null
              ? const Text('اختر الزبون أولاً لعرض آخر سعر بيع له')
              : FutureBuilder<List<dynamic>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          heightFactor: 1,
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Text(
                        'تعذر تحميل آخر سعر بيع. تحقق من الاتصال وحاول مجدداً.',
                      );
                    }
                    final rows = (snapshot.data ?? []).whereType<Map>().toList()
                      ..sort(
                        (a, b) => '${b['created_at'] ?? ''}'.compareTo(
                          '${a['created_at'] ?? ''}',
                        ),
                      );
                    if (rows.isEmpty) {
                      return const Text(
                        'لا توجد مبيعات سابقة لهذا الصنف لهذا الزبون',
                      );
                    }
                    final row = rows.first;
                    final last = SaleData.number(row['unit_price']);
                    if (last == null || last < 0) {
                      return const Text('سعر البيع السابق غير صالح');
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${widget.product['name']}'),
                        Text(
                          '₪ ${last.toStringAsFixed(2)}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('التاريخ: ${row['created_at'] ?? '—'}'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, last),
                          child: const Text('استخدام هذا السعر'),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (mounted && selected != null) {
      setState(() => _price.text = selected.toStringAsFixed(2));
    }
  }

  void _stepQuantity(int delta) {
    var next = ((quantity ?? widget.minimum) + delta)
        .clamp(widget.minimum, double.infinity)
        .toDouble();
    if (widget.available != null && widget.available! >= widget.minimum) {
      next = next.clamp(widget.minimum, widget.available!).toDouble();
    }
    setState(() => _quantity.text = _format(next));
  }

  Future<void> _showProductDetails() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${widget.product['name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'كود الصنف: ${widget.product['product_number'] ?? widget.product['id']}',
          ),
          const SizedBox(height: 8),
          Text('الوحدة: ${productUnit(widget.product)}'),
          if (widget.available != null) ...[
            const SizedBox(height: 8),
            Text('المتوفر: ${_format(widget.available!)}'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10883D);
    const ink = Color(0xFF171B22);
    const muted = Color(0xFF68717C);
    final total = (price ?? 0) * (quantity ?? 0);
    final image = widget.product['image_url'];
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'إضافة إلى الفاتورة',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF0F2F5),
                        minimumSize: const Size(52, 52),
                      ),
                      icon: const Icon(Icons.close, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFDCE1E7),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Row(
                          children: [
                            _productImage(image),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${widget.product['name']}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'كود: ${widget.product['product_number'] ?? widget.product['id']}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'الوحدة: ${productUnit(widget.product)}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 1.5,
                              height: 64,
                              color: const Color(0xFFDCE1E7),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFD4DAE2),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: IconButton(
                                tooltip: 'تفاصيل الصنف',
                                onPressed: _showProductDetails,
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 32,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('add-product-price'),
                  controller: _price,
                  selectAllOnFocus: true,
                  onTap: () => _selectAll(_price),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 24, color: ink),
                  decoration: const InputDecoration(
                    labelText: 'السعر',
                    prefixText: '₪',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (_) =>
                      price == null || price! < 0 ? 'أدخل سعراً صحيحاً' : null,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _history,
                    icon: const Icon(Icons.history),
                    label: const Text('آخر سعر بيع لهذا الزبون'),
                  ),
                ),
                const SizedBox(height: 8),
                _quantityControls(green, total),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(color: muted, fontSize: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          total.isFinite
                              ? '₪ ${total.toStringAsFixed(2)}'
                              : '—',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: green,
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () {
                            if (_form.currentState!.validate()) {
                              Navigator.pop(
                                context,
                                ProductSelection(price!, quantity!),
                              );
                            }
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text(
                            'حفظ',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            side: const BorderSide(
                              color: Color(0xFF9AA3AE),
                              width: 1.5,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _productImage(Object? image) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: image is String && image.isNotEmpty
        ? Container(
            width: 96,
            height: 104,
            color: const Color(0xFFF0F2F8),
            padding: const EdgeInsets.all(8),
            child: Image.network(
              image,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _imagePlaceholder(),
            ),
          )
        : _imagePlaceholder(),
  );

  Widget _imagePlaceholder() => Container(
    width: 96,
    height: 104,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2F8),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.inventory_2_outlined,
      size: 50,
      color: Color(0xFF68717C),
    ),
  );

  Widget _quantityControls(Color green, double total) => Container(
    height: 112,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFCAD0D8), width: 1.5),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          _stepButton(
            Icons.remove,
            'تقليل الكمية',
            green,
            () => _stepQuantity(-1),
          ),
          Expanded(
            child: TextFormField(
              key: const Key('add-product-quantity'),
              controller: _quantity,
              autofocus: false,
              selectAllOnFocus: true,
              onTap: () => _selectAll(_quantity),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 25),
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                hintText: 'الكمية',
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
              onChanged: (_) => setState(() {}),
              validator: (_) {
                if (quantity == null ||
                    quantity! < widget.minimum ||
                    quantity! <= 0) {
                  return 'أقل كمية ${_format(widget.minimum)}';
                }
                if (widget.available != null && quantity! > widget.available!) {
                  return 'المتوفر ${_format(widget.available!)}';
                }
                if (!total.isFinite) return 'الكمية أو السعر أكبر من المسموح';
                return null;
              },
            ),
          ),
          _stepButton(Icons.add, 'زيادة الكمية', green, () => _stepQuantity(1)),
        ],
      ),
    ),
  );

  Widget _stepButton(
    IconData icon,
    String tooltip,
    Color green,
    VoidCallback onPressed,
  ) => IconButton.filledTonal(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xFFE4F6E8),
      foregroundColor: green,
      minimumSize: const Size(76, 84),
    ),
    icon: Icon(icon, size: 34),
  );
}
