import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/api_client.dart';
import '../services/pos_service.dart';
import '../models/product_catalog.dart';
import '../models/sale_data.dart';

import '../services/barcode_label_service.dart';
import 'printer_settings_screen.dart';

class BarcodeLabelsScreen extends StatefulWidget {
  const BarcodeLabelsScreen({super.key});
  @override
  State<BarcodeLabelsScreen> createState() => _BarcodeLabelsScreenState();
}

class _BarcodeLabelsScreenState extends State<BarcodeLabelsScreen> {
  final _code = TextEditingController(),
      _name = TextEditingController(),
      _price = TextEditingController();
  final _copies = TextEditingController(text: '1'),
      _width = TextEditingController(text: '50'),
      _height = TextEditingController(text: '25');
  bool _busy = false;
  final _sku = TextEditingController();
  ProductCatalog? _catalog;
  List<dynamic> _products = [];
  List<String> _codes = [];
  String _query = '';
  bool _loading = true;
  bool _showName = true,
      _showBarcode = true,
      _showPrice = true,
      _showSku = false;
  Uint8List? _preview;
  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts({bool preferCache = true}) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final branch = SaleData.id(ApiClient.user?['branch_id']);
      if (branch == null) throw StateError('سجّل الدخول إلى حساب الفرع أولاً.');
      final categories = await PosService().fetchCategories(
        branch,
        preferCache: preferCache,
      );
      if (!mounted) return;
      setState(() {
        _catalog = ProductCatalog(categories);
        _products = _catalog!.search(_query, null);
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر تحميل الأصناف: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choose(Map<String, dynamic> product) {
    final codes = <String>{};
    void add(Object? value) {
      final code = value?.toString().trim() ?? '';
      if (code.isNotEmpty) codes.add(code);
    }

    add(product['barcode']);
    for (final alias in product['barcodes'] as List? ?? []) {
      add(alias is Map ? alias['barcode'] : alias);
    }
    setState(() {
      _codes = codes.toList();
      _code.text = _codes.isEmpty ? '' : _codes.first;
      _name.text = product['name']?.toString() ?? '';
      final cost = SaleData.number(product['cost_price']);
      _price.text = cost == null ? '' : cost.toStringAsFixed(2);
      _sku.text = '${product['product_number'] ?? product['id'] ?? ''}';
      _preview = null;
      _message = _codes.isEmpty
          ? 'لا يوجد باركود محفوظ للصنف. أضفه في الويب ثم حدّث البيانات؛ لا يُنشأ كود غير مسجل تلقائياً.'
          : null;
    });
  }

  Future<Uint8List> _buildPreview() => BarcodeLabelService.build(
    code: _code.text.trim(),
    name: _showName ? _name.text.trim() : '',
    price: _showPrice && _price.text.trim().isNotEmpty
        ? '${_price.text.trim()} NIS'
        : '',
    sku: _showSku ? _sku.text.trim() : '',
    showBarcode: _showBarcode,
    widthMm: double.tryParse(_width.text) ?? 0,
    heightMm: double.tryParse(_height.text) ?? 0,
  );
  Future<void> _showPreview() async {
    try {
      final bytes = await _buildPreview();
      if (mounted) setState(() => _preview = bytes);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  String? _message;
  @override
  void dispose() {
    for (final c in [_code, _name, _price, _sku, _copies, _width, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await BarcodeLabelService.printLabels(
        code: _code.text.trim(),
        name: _showName ? _name.text.trim() : '',
        price: _showPrice && _price.text.trim().isNotEmpty
            ? '${_price.text.trim()} NIS'
            : '',
        sku: _showSku ? _sku.text.trim() : '',
        showBarcode: _showBarcode,
        copies: int.tryParse(_copies.text) ?? 0,
        widthMm: double.tryParse(_width.text) ?? 0,
        heightMm: double.tryParse(_height.text) ?? 0,
      );
      if (mounted) {
        setState(() => _message = 'أُرسلت الملصقات إلى طابعة الباركود.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is StateError
              ? error.message.toString()
              : 'تعذرت الطباعة: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: ValueKey(label),
      controller: controller,
      onChanged: (_) {
        if (_preview != null) setState(() => _preview = null);
      },
      enabled: !_busy,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('طباعة الباركود'),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PrinterSettingsScreen(),
            ),
          ),
          icon: const Icon(Icons.settings),
          tooltip: 'إعدادات الطابعات',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('تُرسل الملصقات إلى طابعة الباركود المحفوظة لهذا الجهاز.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('label-product-search'),
          decoration: const InputDecoration(
            labelText: 'البحث عن الصنف بالاسم أو الرقم أو الباركود',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            _query = value;
            _products = _catalog?.search(value, null) ?? [];
          }),
        ),
        if (_loading) const LinearProgressIndicator(),
        SizedBox(
          height: 180,
          child: ListView.builder(
            itemCount: _products.length.clamp(0, 100),
            itemBuilder: (_, index) {
              final product = _products[index];
              return ListTile(
                key: ValueKey('label-product-${product['id']}'),
                dense: true,
                title: Text('${product['name']}'),
                subtitle: Text(
                  'رقم الصنف: ${product['product_number'] ?? product['id']}',
                ),
                onTap: _busy
                    ? null
                    : () => _choose(Map<String, dynamic>.from(product)),
              );
            },
          ),
        ),
        TextButton.icon(
          onPressed: _loading || _busy
              ? null
              : () => _loadProducts(preferCache: false),
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث قائمة الأصناف'),
        ),
        if (_codes.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(_codes.join('|')),
            initialValue: _codes.contains(_code.text) ? _code.text : null,
            decoration: const InputDecoration(
              labelText: 'الباركود المسجل للصنف',
            ),
            items: _codes
                .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                .toList(),
            onChanged: _busy
                ? null
                : (code) => setState(() {
                    _code.text = code ?? '';
                    _preview = null;
                  }),
          ),
        const SizedBox(height: 14),
        _field(_code, 'الباركود'),
        _field(_name, 'اسم الصنف (اختياري)'),
        _field(_price, 'السعر المطبوع (التكلفة كما في الويب)'),
        _field(_sku, 'رقم الصنف'),
        Wrap(
          children: [
            for (final entry in <(String, bool, ValueChanged<bool>)>[
              ('إظهار الاسم', _showName, (v) => _showName = v),
              ('إظهار الباركود', _showBarcode, (v) => _showBarcode = v),
              ('إظهار السعر', _showPrice, (v) => _showPrice = v),
              ('إظهار رقم الصنف', _showSku, (v) => _showSku = v),
            ])
              Padding(
                padding: const EdgeInsets.all(4),
                child: FilterChip(
                  label: Text(entry.$1),
                  selected: entry.$2,
                  onSelected: _busy
                      ? null
                      : (v) => setState(() {
                          entry.$3(v);
                          _preview = null;
                        }),
                ),
              ),
          ],
        ),
        _field(_copies, 'عدد الملصقات', number: true),
        Row(
          children: [
            Expanded(child: _field(_width, 'العرض بالملم', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_height, 'الارتفاع بالملم', number: true)),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_message!),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _showPreview,
          icon: const Icon(Icons.preview),
          label: const Text('معاينة الملصق'),
        ),
        if (_preview != null)
          SizedBox(
            height: 260,
            child: PdfPreview(
              build: (_) async => _preview!,
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
              useActions: false,
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _print,
          icon: const Icon(Icons.print),
          label: Text(_busy ? 'جارٍ الإرسال…' : 'طباعة الملصقات'),
        ),
      ],
    ),
  );
}
