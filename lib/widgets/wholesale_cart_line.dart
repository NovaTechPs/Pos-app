import 'package:flutter/material.dart';

class WholesaleCartLine extends StatefulWidget {
  const WholesaleCartLine({
    super.key,
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.minimum,
    required this.available,
    required this.allowNegative,
    required this.enabled,
    required this.onChanged,
    required this.onValidity,
    required this.onRemove,
    required this.onHistory,
  });
  final int id;
  final String name;
  final double price, quantity, minimum, available;
  final bool allowNegative, enabled;
  final void Function(double price, double quantity) onChanged;
  final ValueChanged<bool> onValidity;
  final VoidCallback onRemove, onHistory;
  @override
  State<WholesaleCartLine> createState() => _WholesaleCartLineState();
}

class _WholesaleCartLineState extends State<WholesaleCartLine> {
  late final _price = TextEditingController(
    text: widget.price.toStringAsFixed(2),
  );
  late final _quantity = TextEditingController(text: _format(widget.quantity));
  String _format(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  double? _number(String value) {
    value = value.trim().replaceAll(',', '.').replaceAll('٫', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  String? get _priceError {
    final price = _number(_price.text);
    return price == null || price < 0 ? 'أدخل سعراً صحيحاً' : null;
  }

  String? get _quantityError {
    final quantity = _number(_quantity.text);
    if (quantity == null || quantity <= 0) return 'أدخل كمية صحيحة';
    if (quantity < widget.minimum) {
      return 'الحد الأدنى ${_format(widget.minimum)}';
    }
    if (!widget.allowNegative && quantity > widget.available) {
      return 'المتوفر ${_format(widget.available)}';
    }
    return null;
  }

  void _change() {
    final valid = _priceError == null && _quantityError == null;
    widget.onValidity(valid);
    setState(() {});
    if (valid) {
      widget.onChanged(_number(_price.text)!, _number(_quantity.text)!);
    }
  }

  void _sync(TextEditingController controller, double value, String text) {
    if (_number(controller.text) == value) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void didUpdateWidget(covariant WholesaleCartLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _sync(_price, widget.price, widget.price.toStringAsFixed(2));
    }
    if (oldWidget.quantity != widget.quantity) {
      _sync(_quantity, widget.quantity, _format(widget.quantity));
    }
    widget.onValidity(_priceError == null && _quantityError == null);
  }

  void _step(int delta) {
    final quantity = widget.quantity + delta;
    if (quantity < widget.minimum) {
      widget.onRemove();
      return;
    }
    _quantity.text = _format(quantity);
    _change();
  }

  @override
  void dispose() {
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'آخر سعر للعميل',
              onPressed: widget.onHistory,
              icon: const Icon(Icons.history, size: 19),
            ),
            IconButton(
              tooltip: 'حذف الصنف',
              onPressed: widget.enabled ? widget.onRemove : null,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 156,
              child: Column(
                children: [
                  TextField(
                    key: ValueKey('wholesale-price-${widget.id}'),
                    controller: _price,
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onTap: () {
                      _price.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _price.text.length,
                      );
                    },
                    decoration: InputDecoration(
                      labelText: 'السعر',
                      errorText: widget.enabled ? _priceError : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _change(),
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'زيادة الكمية',
                          onPressed: widget.enabled ? () => _step(1) : null,
                          icon: const Icon(Icons.add, size: 19),
                        ),
                        Expanded(
                          child: TextField(
                            key: ValueKey('wholesale-quantity-${widget.id}'),
                            controller: _quantity,
                            enabled: widget.enabled,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onChanged: (_) => _change(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تقليل الكمية',
                          onPressed: widget.enabled ? () => _step(-1) : null,
                          icon: const Icon(Icons.remove, size: 19),
                        ),
                      ],
                    ),
                  ),
                  if (widget.enabled && _quantityError != null)
                    Text(
                      _quantityError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_format(widget.quantity)} × ${widget.price.toStringAsFixed(2)}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    (widget.quantity * widget.price).toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
