import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../widgets/pos_workspace.dart';
import '../widgets/product_add_dialog.dart';
import '../services/wholesale_service.dart';
import '../widgets/checkout_loading_overlay.dart';
import 'sales_history_screen.dart';
import 'pos_shell.dart';
import 'sync_screen.dart';
import 'dashboard_screen.dart';
import 'wholesale_screen.dart';
import 'employee_screen.dart';
import '../widgets/logout_button.dart';

import 'dart:async';
import 'dart:convert';

import '../services/customer_service.dart';
import '../services/api_exception.dart';
import '../models/sale_data.dart';
import '../models/product_catalog.dart';
import '../services/api_client.dart';
import '../widgets/amount_dialog.dart';
import '../widgets/cart_line_dialog.dart';
import '../widgets/operation_review.dart';
import '../widgets/missing_barcode_dialog.dart';
import '../services/pos_service.dart';
import '../services/sync_service.dart';
import '../services/operation_id.dart';
import '../services/network_status.dart';

import '../services/checkout_service.dart';
import '../services/api_config.dart';
import '../services/printer_service.dart';
import 'returns_screen.dart';
import '../services/shift_service.dart';
import '../services/statement_service.dart';
import 'barcode_scan_screen.dart';

class PosScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const PosScreen({super.key, required this.user, this.networkStatus});
  final NetworkStatusSource? networkStatus;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with WidgetsBindingObserver {
  final PosService _posService = PosService();
  final ShiftService _shiftService = ShiftService();
  final CustomerService _customerService = CustomerService();

  bool _isLoading = true;
  String? _loadError;
  bool _loadInFlight = false;
  Timer? _loadRetryTimer;
  int _loadFailures = 0;
  int? _loadRetrySeconds;
  bool _isRepricing = false;
  bool _missingBarcodeOpen = false;

  /// A second tap while the quantity window is opening must not add the item twice.
  bool _addDialogOpen = false;
  bool _holdPromptOpen = false;

  /// The line the cashier just added (new or merged); the invoice table
  /// scrolls to it on every add, like the web POS.
  int _addedLine = -1;
  int _addCount = 0;
  List<dynamic> _categories = [];
  int? _selectedCategoryId;
  List<dynamic>? _indexedCategories;
  ProductCatalog? _catalogIndex;
  ProductCatalog get _catalog {
    if (!identical(_indexedCategories, _categories)) {
      _indexedCategories = _categories;
      _catalogIndex = ProductCatalog(_categories);
    }
    return _catalogIndex!;
  }

  List<dynamic> _customers = [];
  int? _selectedCustomerId;

  final List<Map<String, dynamic>> _cart = [];
  bool _isCheckingOut = false;
  late final CheckoutService _checkoutService;
  late final CheckoutService _heldService;
  Map<String, dynamic>? _heldRecord;
  Map<String, dynamic>? _checkoutRecord;
  bool _isRestoringCheckout = true;
  String _searchQuery = '';
  bool _mergeSimilar = true;
  String _invoiceNotes = '';
  double _discount = 0.0;
  double _deliveryFee = 0;
  double? _discountPercent;
  bool _discountValid = true;
  bool _tenderValid = true;
  final double _taxRate = 0;
  String _paymentMethod = 'cash';
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _catalogFocusNode = FocusNode();
  Map<String, dynamic>? _activeShift;
  int? _activeHeldOrderId;
  int? _editingInvoiceId;
  String? _localHeldId;
  Map<String, dynamic>? _viewedInvoice;

  /// A saved invoice shown in the cart for viewing; «تعديل» unlocks it, like the web invoice archive.
  Map<String, dynamic>? _viewingInvoice;
  Timer? _barcodeDebounce;
  Timer? _searchDebounce;
  StreamSubscription<bool>? _networkSubscription;
  bool _networkAvailable = true;
  bool _probingConnection = false;
  bool _refreshing = false;
  Timer? _automaticSyncTimer;
  bool _draftReady = false;
  bool _draftScheduled = false;
  bool _draftWriting = false;
  Future<void> Function()? _pendingDraftWrite;
  String? _lastDraft;

  @override
  void setState(VoidCallback fn) {
    super.setState(() {
      fn();
      SaleData.applyOffers(_cart);
      if (_discountPercent != null) {
        _discount = double.parse(
          (_subtotal * _discountPercent! / 100).toStringAsFixed(2),
        );
      }
    });
    if (_draftReady) {
      if (!_draftScheduled) {
        _draftScheduled = true;
        scheduleMicrotask(() {
          _draftScheduled = false;
          if (mounted) _persistDraft();
        });
      }
    }
  }

  void _persistDraft() {
    if (!_draftReady) return;
    final store = ApiClient.offlineStore;
    if (store == null) return;
    final viewing = _viewingInvoice != null;
    final draft = <String, dynamic>{
      'items': viewing ? const [] : _cart,
      'customer_id': viewing ? null : _selectedCustomerId,
      'discount': viewing ? 0 : _discount,
      'delivery_fee': viewing ? 0 : _deliveryFee,
      'discount_percent': viewing ? null : _discountPercent,
      'notes': viewing ? '' : _invoiceNotes,
      'payment_method': _paymentMethod,
      'held_order_id': _activeHeldOrderId,
      'invoice_id': _editingInvoiceId,
      'local_held_id': _localHeldId,
    };
    final signature = jsonEncode(draft);
    if (signature == _lastDraft) return;
    _lastDraft = signature;
    final frozen = Map<String, dynamic>.from(jsonDecode(signature));
    frozen['saved_at'] = DateTime.now().toUtc().toIso8601String();
    final branchId = _branchId;
    // A scanner burst needs its latest draft, not a queue of obsolete snapshots.
    _pendingDraftWrite = () => store.saveDraft(branchId, frozen);
    if (!_draftWriting) unawaited(_drainDraftWrites());
  }

  Future<void> _drainDraftWrites() async {
    _draftWriting = true;
    try {
      while (_pendingDraftWrite != null) {
        final write = _pendingDraftWrite!;
        _pendingDraftWrite = null;
        try {
          await write();
        } catch (_) {
          _lastDraft = null;
          if (mounted) {
            _showMessage('تعذر حفظ مسودة الفاتورة على الجهاز.', isError: true);
          }
        }
      }
    } finally {
      _draftWriting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.synchronizeAutomatically();
      _refreshInBackground();
    } else {
      _persistDraft();
    }
  }

  bool _shortcutRunning = false;

  int get _branchId =>
      int.tryParse(widget.user['branch_id']?.toString() ?? '') ?? 0;

  int _customerPricingBranch(int? customerId) {
    for (final customer in _customers) {
      if (SaleData.id(customer['id']) == customerId) {
        return SaleData.id(customer['branch_id']) ?? _branchId;
      }
    }
    return _branchId;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _reloadProductsForCustomer(int? customerId) async {
    if (_isRepricing || _isCheckingOut) return;
    setState(() => _isRepricing = true);
    try {
      final categories = await _posService.fetchCategories(
        _branchId,
        customerId: customerId,
        pricingBranchId: _customerPricingBranch(customerId),
        preferCache: ApiClient.offline.value,
      );
      if (!mounted) return;
      final products = <int, Map>{};
      for (final category in categories) {
        for (final product in (category['products'] as List? ?? [])) {
          final id = SaleData.id(product['id']);
          if (id != null) products[id] = product;
        }
      }
      final repriced = <Map<String, dynamic>>[];
      for (final line in _cart) {
        final product = products[SaleData.id(line['product_id'])];
        final price = product == null ? null : _productPrice(product);
        if (price == null) {
          throw Exception(
            'لا يتوفر سعر معتمد للصنف ${line['name']} لهذا العميل.',
          );
        }
        repriced.add({
          ...line,
          'price': line['price_manual'] == true ? line['price'] : price,
          'discount': line['gift'] == true ? price : 0.0,
          'offer_quantity': product?['offer_quantity'],
          'offer_price': product?['offer_price'],
        });
      }
      setState(() {
        _categories = categories;
        _selectedCustomerId = customerId;
        _selectedCategoryId = null; // All products first, as on the web POS.
        _cart
          ..clear()
          ..addAll(repriced);
      });
      if (repriced.isNotEmpty) {
        _showMessage('تم تحديث أسعار السلة حسب العميل المختار.');
      }
    } catch (error) {
      if (mounted) _showMessage('تعذر تغيير العميل: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isRepricing = false);
      _restoreBarcodeFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkoutService = CheckoutService(
      offlineEndpoint: 'pos/orders',
      scope:
          '${ApiConfig.baseUrl}|${widget.user['tenant_id']}|${widget.user['id']}|$_branchId',
    );
    _heldService = CheckoutService(
      scope: [
        ApiConfig.baseUrl,
        widget.user['tenant_id'],
        widget.user['id'],
        _branchId,
        'held',
      ].join('|'),
      send: (body) => ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/pos/held'),
        body: body,
      ),
    );
    HardwareKeyboard.instance.addHandler(_handleShortcut);
    _wasOffline = ApiClient.offline.value;
    ApiClient.offline.addListener(_onOfflineChanged);
    _startNetworkMonitoring();
    _initializeCheckout();
    _automaticSyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) => _retryPendingAndConnection(timer.tick),
    );
  }

  Future<void> _initializeCheckout() async {
    try {
      final records = await Future.wait([
        _checkoutService.read(),
        _heldService.read(),
        ApiClient.offlineStore?.draft(_branchId) ?? Future.value(null),
      ]);
      if (!mounted) return;
      _checkoutRecord = records[0];
      _heldRecord = records[1];
      final draft = records[2];
      final lastSale = _checkoutRecord;
      final completedAfterDraft =
          draft != null &&
          lastSale != null &&
          const {'confirmed', 'queued'}.contains(lastSale['status']) &&
          '${lastSale['created_at']}'.compareTo('${draft['saved_at']}') >= 0;
      if (draft != null &&
          !completedAfterDraft &&
          !CheckoutService.needsReview(_checkoutRecord) &&
          !CheckoutService.needsReview(_heldRecord)) {
        final lines = (draft['items'] as List)
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        for (final line in lines) {
          SaleData.lineTotal(line);
        }
        _cart.addAll(lines);
        _selectedCustomerId = SaleData.id(draft['customer_id']);
        _discount = SaleData.number(draft['discount']) ?? 0;
        _deliveryFee = SaleData.number(draft['delivery_fee']) ?? 0;
        _discountPercent = SaleData.number(draft['discount_percent']);
        _invoiceNotes = draft['notes']?.toString() ?? '';
        _paymentMethod = draft['payment_method']?.toString() ?? 'cash';
        _activeHeldOrderId = SaleData.id(draft['held_order_id']);
        _editingInvoiceId = SaleData.id(draft['invoice_id']);
        _localHeldId = draft['local_held_id'] as String?;
      }
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر قراءة سجل البيع أو المسودة المحلية', isError: true);
      }
    }
    if (!mounted) return;
    setState(() => _isRestoringCheckout = false);
    // Render a saved workspace immediately, including on a connected network
    // whose API is unreachable. Refresh it independently after startup.
    await _loadData(preferCache: true);
    if (!mounted) return;
    _draftReady = true;
    unawaited(SyncService.synchronizeAutomatically());
  }

  bool _wasOffline = false;
  Stopwatch? _lastFreshRefresh;

  /// Any successful server call (sync, sync screen, probe) can end offline
  /// mode; replace the cached catalog/shift with fresh data when it does.
  void _onOfflineChanged() {
    final offline = ApiClient.offline.value;
    final reconnected = _wasOffline && !offline;
    _wasOffline = offline;
    if (!reconnected || !mounted) return;
    // Let the call that ended offline mode finish before refreshing.
    scheduleMicrotask(() {
      if (mounted) unawaited(_refreshInBackground());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.offline.removeListener(_onOfflineChanged);
    _persistDraft();
    _networkSubscription?.cancel();
    _automaticSyncTimer?.cancel();
    _loadRetryTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    _searchDebounce?.cancel();
    _barcodeController.dispose();
    _barcodeDebounce?.cancel();
    _keyboardFocusNode.dispose();
    _barcodeFocusNode.dispose();
    _catalogFocusNode.dispose();
    super.dispose();
  }

  Future<({List<List<dynamic>>? values, Object? error})> _fetchCatalogData({
    bool refreshCustomers = true,
    bool preferCache = false,
  }) async {
    try {
      return (
        values: await Future.wait([
          _posService.fetchCategories(
            _branchId,
            customerId: _selectedCustomerId,
            pricingBranchId: _customerPricingBranch(_selectedCustomerId),
            preferCache: preferCache,
          ),
          refreshCustomers
              ? _customerService.fetchCustomers(preferCache: preferCache)
              : Future.value(_customers),
        ]),
        error: null,
      );
    } catch (error) {
      return (values: null, error: error);
    }
  }

  void _scheduleLoadRetry() {
    if (!mounted || ApiClient.sessionExpired.value) return;
    _loadFailures++;
    final seconds = [5, 10, 20, 40, 60][(_loadFailures - 1).clamp(0, 4)];
    _loadRetrySeconds = seconds;
    final token = ApiClient.token;
    _loadRetryTimer?.cancel();
    _loadRetryTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted ||
          token != ApiClient.token ||
          ApiClient.sessionExpired.value) {
        return;
      }
      if (!_networkAvailable) {
        _scheduleLoadRetry();
        return;
      }
      // Resume with resources already downloaded, instead of downloading them again.
      unawaited(_loadData(preferCache: true));
    });
  }

  Future<void> _loadData({
    bool refreshCustomers = true,
    bool preferCache = false,
  }) async {
    if (_loadInFlight || !mounted) return;
    _loadInFlight = true;
    _loadRetryTimer?.cancel();
    final token = ApiClient.token;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _loadRetrySeconds = null;
    });
    try {
      if (_branchId <= 0) throw Exception('اختر فرعاً قبل استخدام نقطة البيع.');
      // Await all reads before retrying so attempts cannot overlap.
      final results = await Future.wait<dynamic>([
        _fetchCatalogData(
          refreshCustomers: refreshCustomers,
          preferCache: preferCache,
        ),
        _shiftService.fetchActiveShift(_branchId, preferCache: preferCache),
      ]);
      if (!mounted || token != ApiClient.token) return;
      final loaded =
          results[0] as ({List<List<dynamic>>? values, Object? error});
      if (loaded.error != null) throw loaded.error!;
      final data = loaded.values!;
      final activeShift = results[1] as Map<String, dynamic>?;
      _loadFailures = 0;
      if (!ApiClient.offline.value) _lastFreshRefresh = Stopwatch()..start();
      setState(() {
        _activeShift = activeShift;
        _categories = data[0];
        _customers = data[1];
        _selectedCategoryId = null; // All products first, as on the web POS.
        _isLoading = false;
      });
      if (activeShift == null) {
        _showOpenShiftDialog(_branchId);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _barcodeFocusNode.requestFocus();
          if (ApiClient.offline.value) {
            unawaited(_refreshInBackground());
          } else {
            unawaited(SyncService.synchronizeAutomatically());
            unawaited(
              _posService.prepareOfflineCustomerPricing(_branchId, _customers),
            );
          }
        }
      });
    } catch (error) {
      if (mounted && token == ApiClient.token) {
        final transient =
            error is TimeoutException ||
            error is http.ClientException ||
            (error is ApiException &&
                (error.statusCode == 429 || (error.statusCode ?? 0) >= 500));
        if (transient) _scheduleLoadRetry();
        setState(() {
          _loadError = error is TimeoutException
              ? 'تعذر تحميل نقطة البيع: ${error.message ?? 'لم يرد الخادم خلال المهلة المحددة.'}'
              : 'تعذر تحميل نقطة البيع: $error';
          _isLoading = false;
        });
      }
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _startNetworkMonitoring() async {
    final source = widget.networkStatus ?? DeviceNetworkStatus();
    try {
      final available = await source.available;
      if (!mounted) return;
      _networkAvailable = available;
      if (!available) ApiClient.offline.value = true;
      _networkSubscription = source.changes.listen(
        (available) {
          if (!mounted) return;
          final restored = available && !_networkAvailable;
          _networkAvailable = available;
          if (!available) {
            ApiClient.offline.value = true;
          } else if (restored || ApiClient.offline.value) {
            _refreshInBackground();
          }
        },
        onError: (Object _) {
          /* API checks remain available if OS events fail. */
        },
      );
    } catch (_) {
      /* Platforms without a network monitor still use API checks. */
    }
  }

  Future<void> _retryPendingAndConnection(int tick) async {
    if (!mounted || !_networkAvailable || ApiClient.sessionExpired.value) {
      return;
    }
    await SyncService.synchronizeAutomatically();
    if (!mounted ||
        !ApiClient.offline.value ||
        tick % 3 != 0 ||
        _probingConnection ||
        _isCheckingOut) {
      return;
    }
    // Retry only a small read while offline. Never periodically download the catalog online.
    _probingConnection = true;
    final token = ApiClient.token;
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/shifts/active?branch_id=$_branchId'),
      );
      if (mounted && token == ApiClient.token && response.statusCode == 200) {
        await _refreshInBackground();
      }
    } catch (_) {
      /* Stay on the local snapshot and try again later. */
    } finally {
      _probingConnection = false;
    }
  }

  Future<void> _refreshInBackground() async {
    if (!mounted ||
        _refreshing ||
        _isLoading ||
        _isCheckingOut ||
        _isRepricing ||
        _isRestoringCheckout ||
        SyncService.busy.value ||
        ApiClient.sessionExpired.value) {
      return;
    }
    if (_loadError != null) {
      await _loadData(preferCache: true);
      return;
    }
    _refreshing = true;
    final customerId = _selectedCustomerId;
    final token = ApiClient.token;
    // Use a separate service so an obsolete response cannot change the active contract.
    final service = PosService();
    try {
      await SyncService.synchronizeAutomatically();
      if (!mounted || token != ApiClient.token) return;
      final results = await Future.wait<dynamic>([
        service.fetchCategories(_branchId, customerId: customerId),
        _customerService.fetchCustomers(),
        _shiftService.fetchActiveShift(_branchId),
      ]);
      if (!mounted ||
          token != ApiClient.token ||
          customerId != _selectedCustomerId ||
          _isCheckingOut ||
          _isRepricing ||
          _isLoading) {
        return;
      }
      if (service.lastFetchOffline ||
          _customerService.lastFetchOffline ||
          _shiftService.lastFetchOffline) {
        return;
      }
      setState(() {
        _categories = results[0] as List;
        _customers = results[1] as List;
        _activeShift = results[2] as Map<String, dynamic>?;
        _posService.supportsGiftLines = service.supportsGiftLines;
        if (_selectedCategoryId != null &&
            !_categories.any(
              (category) => SaleData.id(category['id']) == _selectedCategoryId,
            )) {
          _selectedCategoryId = null;
        }
      });
      ApiClient.offline.value = false;
      ApiClient.cachedAt.value = null;
      _lastFreshRefresh = Stopwatch()..start();
      if (token == ApiClient.token) {
        await service.prepareOfflineCustomerPricing(_branchId, _customers);
      }
    } catch (_) {
      // Keep the usable snapshot and draft; retry on the next refresh.
    } finally {
      _refreshing = false;
    }
  }

  Future<List<dynamic>> _refreshCustomersForPicker() async {
    final customers = await _customerService.fetchCustomers();
    if (mounted) {
      setState(() => _customers = customers);
    }

    return customers;
  }

  Future<void> _showOpenShiftDialog(int branchId) async {
    if (_isCheckingOut) return;
    final entry = await showAmountDialog(
      context,
      title: 'فتح وردية جديدة',
      label: 'النقدية الافتتاحية',
      allowZero: true,
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    setState(() => _isCheckingOut = true);
    try {
      final result = await _shiftService.openShift(
        branchId: branchId,
        openingCash: entry.amount,
        notes: entry.notes,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        _activeShift = Map<String, dynamic>.from(result['shift']);
        await _loadData();
      } else {
        _showMessage(result['message'].toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
      _restoreBarcodeFocus();
    }
  }

  Future<void> _showCloseShiftDialog() async {
    if (_isCheckingOut) return;
    if (_cart.isNotEmpty) {
      _showMessage('أكمل الفاتورة أو علّقها قبل إغلاق الوردية.', isError: true);
      return;
    }
    Map<String, dynamic>? active;
    try {
      active = await _shiftService.fetchActiveShift(_branchId);
    } catch (error) {
      if (mounted) _showMessage('$error', isError: true);
      return;
    }
    if (!mounted || active == null) return;
    final summary = active['cash_summary'] as Map?;
    final expected = SaleData.number(summary?['expected_cash']);
    final entry = await showAmountDialog(
      context,
      title: 'تسوية وإغلاق الوردية',
      label: 'النقدية الفعلية بعد العد',
      allowZero: true,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('النقدية الافتتاحية: ${active['opening_cash']}'),
          if (summary != null) ...[
            Text('المقبوضات النقدية: ${summary['cash_receipts']}'),
            Text('المدفوعات النقدية: ${summary['cash_payments']}'),
            const SizedBox(height: 6),
            Text(
              'البنك — بطاقات وتحويل: ${summary['bank_receipts'] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('منها بطاقات: ${summary['card_receipts'] ?? 0}'),
            Text('منها تحويل بنكي: ${summary['bank_transfer_receipts'] ?? 0}'),
            Text(
              'النقدية المتوقعة: ${summary['expected_cash']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    setState(() => _isCheckingOut = true);
    try {
      final result = await _shiftService.closeShift(
        branchId: _branchId,
        shiftId: SaleData.id(active['id'])!,
        actualCash: entry.amount,
        expectedCash: expected,
        notes: entry.notes,
      );
      if (!mounted) return;
      _showMessage(
        result['message'].toString(),
        isError: result['success'] != true,
      );
      if (result['success'] == true) {
        setState(() => _activeShift = null);
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
      _restoreBarcodeFocus();
    }
  }

  void _showAddCustomerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عميل جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم العميل *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الجوال',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final result = await _customerService.createCustomer(
                name: nameController.text.trim(),
                phone: phoneController.text.trim().isNotEmpty
                    ? phoneController.text.trim()
                    : null,
              );
              if (!dialogContext.mounted) return;
              if (result['success']) {
                Navigator.of(dialogContext).pop();
                final newCust = result['customer'];
                setState(() {
                  _customers.add(newCust);
                });
                await _reloadProductsForCustomer(SaleData.id(newCust['id']));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم إضافة العميل بنجاح وتحديده للفاتورة'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message']),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('حفظ وإضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReturnDialog() async {
    await PosShell.open(
      context,
      'مرتجعات المبيعات',
      ReturnsScreen(user: widget.user, branchId: _branchId),
    );
    if (mounted) await _loadData();
  }

  Future<void> _postCashOperation(
    String endpoint,
    String resultKey,
    Map<String, dynamic> payload,
  ) async {
    if (_isCheckingOut) return;
    setState(() => _isCheckingOut = true);
    final service = CheckoutService(
      scope: [
        ApiConfig.baseUrl,
        widget.user['tenant_id'],
        widget.user['id'],
        _branchId,
        endpoint,
      ].join('|'),
      resultKey: resultKey,
      send: (body) => ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/$endpoint'),
        body: body,
      ),
    );
    try {
      if (CheckoutService.needsReview(await service.read())) {
        if (!mounted) return;
        final saved = await reviewOperation(context, service);
        if (mounted && saved != null) {
          _showMessage(
            'تم تسجيل نتيجة العملية السابقة. افتح النموذج مجدداً إذا أردت عملية جديدة.',
          );
        }
        return;
      }
      final result = await service.checkout(
        payload: {'branch_id': _branchId, ...payload},
        receiptItems: [],
        cashierName: widget.user['name']?.toString() ?? 'كاشير',
      );
      if (!mounted) return;
      _showMessage(
        result['success'] == true
            ? 'تم حفظ العملية بنجاح'
            : result['message'].toString(),
        isError: result['success'] != true,
      );
      if (result['success'] == true) await _loadData();
    } catch (error) {
      if (mounted) _showMessage('تعذر إتمام العملية: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
      _restoreBarcodeFocus();
    }
  }

  Future<void> _showExpenseDialog() async {
    if (_isCheckingOut) return;
    final entry = await showAmountDialog(
      context,
      title: 'تسجيل مصروف',
      label: 'المبلغ المصروف',
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    await _postCashOperation('expenses', 'expense', {
      'amount': entry.amount,
      'notes': entry.notes,
    });
  }

  Future<void> _showReceiptDialog() async {
    if (_isCheckingOut) return;
    int? customerId = _selectedCustomerId;
    final entry = await showAmountDialog(
      context,
      title: 'إصدار سند قبض',
      label: 'المبلغ المقبوض',
      details: DropdownButtonFormField<int>(
        initialValue: customerId ?? 0,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'العميل'),
        items: [
          const DropdownMenuItem(value: 0, child: Text('قبض عام دون عميل')),
          ..._customers.map(
            (customer) => DropdownMenuItem(
              value: SaleData.id(customer['id']),
              child: Text(customer['name']?.toString() ?? 'عميل'),
            ),
          ),
        ],
        onChanged: (id) => customerId = id == 0 ? null : id,
      ),
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    await _postCashOperation('vouchers/receipts', 'voucher', {
      'amount': entry.amount,
      'notes': entry.notes,
      'customer_id': customerId,
    });
  }

  void _scanBarcode() {
    _searchDebounce?.cancel();
    _barcodeDebounce?.cancel();
    Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    ).then((value) {
      if (!mounted || value == null) return;
      _barcodeController.text = value;
      final code = value.trim().toLowerCase();
      final match = _catalog.findBarcode(code);
      if (match != null) {
        _barcodeDebounce?.cancel();
        _barcodeController.clear();
        if (!_addToCart(match)) return;
        setState(() => _searchQuery = '');
        _showMessage('أضيف ${match['name']} إلى الفاتورة');
      } else {
        unawaited(_missingBarcode());
      }
    });
  }

  Future<void> _showProducts({bool gift = false}) async {
    if (_isCheckingOut || _isRepricing || _loadError != null) return;
    // Opening the picker must not wait for catalog downloads or queued sales.
    // A full refresh downloads every catalog, so at most once a minute.
    final last = _lastFreshRefresh;
    if (!ApiClient.offline.value &&
        (last == null || last.elapsed > const Duration(minutes: 1))) {
      unawaited(_refreshInBackground());
    }
    if (!mounted) return;
    var query = '';
    int? categoryId;
    // Reuse the screen's index instead of re-indexing the catalog per open.
    final pickerCatalog = _catalog;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final products = pickerCatalog.search(query, categoryId);
          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 1100,
              height: MediaQuery.sizeOf(context).height * .88,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFF0F172A),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            gift
                                ? 'اختر صنف الهدية — بدون مقابل'
                                : 'قائمة الأصناف',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          tooltip: 'إغلاق Esc',
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => update(() => query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ابحث باسم المنتج أو رقمه أو الباركود…',
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: const Text('الكل'),
                            selected: categoryId == null,
                            onSelected: (_) => update(() => categoryId = null),
                          ),
                        ),
                        for (final category in _categories)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text('${category['name']}'),
                              selected:
                                  categoryId == SaleData.id(category['id']),
                              onSelected: (_) => update(() {
                                categoryId = SaleData.id(category['id']);
                                query = '';
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: products.isEmpty
                        ? const Center(child: Text('لا توجد أصناف مطابقة'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 270,
                                  mainAxisExtent: 110,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: products.length,
                            itemBuilder: (_, index) {
                              final product = Map<String, dynamic>.from(
                                products[index],
                              );
                              final price = _productPrice(product);
                              return Card(
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  onTap: () {
                                    if (_addToCart(product, gift: gift)) {
                                      Navigator.pop(dialogContext);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${product['name']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          price?.toStringAsFixed(2) ??
                                              'غير مسعّر',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'رقم المنتج: ${product['product_number'] ?? product['id']}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF64748B),
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
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'عدد الأصناف: ${products.length} · اضغط على الصنف لإضافته إلى الفاتورة',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) _barcodeFocusNode.requestFocus();
  }

  void _onBarcodeInput(String value) {
    if (_missingBarcodeOpen) return;
    _barcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    final code = value.trim().toLowerCase();
    if (code.isEmpty) {
      if (_searchQuery.isNotEmpty) setState(() => _searchQuery = '');
      return;
    }
    if (_catalog.isCompleteBarcode(code)) {
      _addExactBarcodeMatch(code);
      return;
    }
    // Preserve the scanner's complete-code window (codes may be prefixes of others).
    _barcodeDebounce = Timer(
      const Duration(milliseconds: 180),
      () => _addExactBarcodeMatch(code),
    );
  }

  void _addExactBarcodeMatch(String code) {
    if (_missingBarcodeOpen) return;
    _barcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    if (!mounted || code.trim().isEmpty) return;
    final product = _catalog.findBarcode(code);
    if (product == null) {
      unawaited(_missingBarcode());
      return;
    }
    _searchDebounce?.cancel();
    _barcodeDebounce?.cancel();
    if (!_addToCart(product, fromBarcode: true)) return;
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _missingBarcode() async {
    if (!mounted || _missingBarcodeOpen || _isCheckingOut || _isRepricing) {
      return;
    }
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;
    _barcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _missingBarcodeOpen = true;
    try {
      final product = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => MissingBarcodeDialog(
          barcode: barcode,
          branchId: _branchId,
          categories: _categories,
          products: _catalog.search('', null),
        ),
      );
      if (!mounted) return;
      if (product != null) {
        final categoryId = SaleData.id(product['category_id']) ?? 0;
        final branches = product['branches'] as List? ?? [];
        final stockBranch = branches
            .whereType<Map>()
            .where((branch) => SaleData.id(branch['id']) == _branchId)
            .firstOrNull;
        final updated = {
          ...product,
          'stock_quantity': stockBranch?['pivot']?['stock_quantity'] ?? 0,
          'pricing_branch_id': _customerPricingBranch(_selectedCustomerId),
        };
        var found = false;
        final categories = _categories
            .map(
              (category) => <String, dynamic>{
                ...category,
                'products': (category['products'] as List? ?? []).map((
                  existing,
                ) {
                  if (SaleData.id(existing['id']) !=
                      SaleData.id(product['id'])) {
                    return existing;
                  }
                  found = true;
                  return {...existing, ...updated};
                }).toList(),
              },
            )
            .toList();
        if (!found) {
          var target = categories
              .where(
                (category) => (SaleData.id(category['id']) ?? 0) == categoryId,
              )
              .firstOrNull;
          if (target == null) {
            target = {
              'id': categoryId,
              'name': 'بدون تصنيف',
              'products': <dynamic>[],
            };
            categories.add(target);
          }
          (target['products'] as List).add(updated);
        }
        setState(() => _categories = categories);
        _showMessage(
          'تم حفظ الباركود. امسحه مرة أخرى لإضافة الصنف إلى الفاتورة.',
        );
        unawaited(_refreshInBackground());
      }
    } finally {
      _missingBarcodeOpen = false;
      if (mounted) {
        _barcodeController.clear();
        _restoreBarcodeFocus();
      }
    }
  }

  void _focusCatalogSearch() {
    _barcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _catalogFocusNode.requestFocus();
  }

  List<Map<String, dynamic>>? _serverItems() {
    try {
      return SaleData.uniqueItems(
        _cart,
        supportsGiftLines: _posService.supportsGiftLines,
      );
    } on FormatException catch (error) {
      _showMessage(error.message.toString(), isError: true);
      return null;
    }
  }

  Future<void> _saveHeldInvoice() async {
    if (_refuseWhileViewing()) return;
    if (_holdPromptOpen) return;
    if (_editingInvoiceId != null) {
      _showMessage(
        'احفظ تعديل الفاتورة السابقة أو ابدأ فاتورة جديدة أولاً.',
        isError: true,
      );
      return;
    }
    if (!_discountValid) {
      _showMessage('صحح خصم الفاتورة أولاً.', isError: true);
      return;
    }
    if (_cart.isEmpty ||
        _isCheckingOut ||
        CheckoutService.needsReview(_checkoutRecord)) {
      return;
    }
    if (CheckoutService.needsReview(_heldRecord)) {
      await _reviewHeld();
      return;
    }
    if (!((ApiClient.offline.value || _localHeldId != null) &&
            _activeHeldOrderId == null) &&
        _serverItems() == null) {
      return;
    }
    _holdPromptOpen = true;
    bool confirmed;
    try {
      confirmed = await _editInvoiceNotes(forHold: true);
    } finally {
      _holdPromptOpen = false;
    }
    if (!confirmed || !mounted) return;
    if ((ApiClient.offline.value || _localHeldId != null) &&
        _activeHeldOrderId == null) {
      final store = ApiClient.offlineStore;
      if (store == null) {
        _showMessage('يلزم حساب محفوظ لتعليق الفاتورة محلياً.');
        return;
      }
      final id = _localHeldId ?? OperationId.create();
      final order = <String, dynamic>{
        'id': 'local:$id',
        'local_held_id': id,
        'invoice_number': 'معلقة محلية ${id.substring(0, 8)}',
        'customer_id': _selectedCustomerId,
        'discount': _discount,
        'delivery_fee': _deliveryFee,
        'notes': _invoiceNotes,
        'payment_method': _paymentMethod,
        'total': _grandTotal,
        'items': _cart
            .map(
              (line) => {
                ...line,
                'unit_price':
                    SaleData.number(line['price'])! -
                    (SaleData.number(line['discount']) ?? 0),
                'is_gift': line['gift'] == true,
              },
            )
            .toList(),
      };
      setState(() => _isCheckingOut = true);
      try {
        await store.saveLocalHeld(_branchId, id, order);
        if (!mounted) return;
        setState(() {
          _cart.clear();
          _localHeldId = null;
          _invoiceNotes = '';
          _discountPercent = null;
          _discount = 0;
          _deliveryFee = 0;
          _discountValid = true;
        });
        _showMessage('تم تعليق الفاتورة محلياً على هذا الجهاز.');
      } catch (_) {
        if (mounted) {
          _showMessage('تعذر حفظ المعلقة؛ احتُفظ بالسلة.', isError: true);
        }
      } finally {
        if (mounted) setState(() => _isCheckingOut = false);
        _restoreBarcodeFocus();
      }
      return;
    }
    final serverItems = _serverItems();
    if (serverItems == null) return;
    setState(() => _isCheckingOut = true);
    try {
      final result = await _heldService.checkout(
        payload: {
          'branch_id': _branchId,
          'customer_id': _selectedCustomerId,
          'subtotal': _subtotal,
          'tax_amount': _taxAmount,
          'discount': _discount,
          'delivery_fee': _deliveryFee,
          'total_amount': _grandTotal,
          if (_invoiceNotes.isNotEmpty) 'notes': _invoiceNotes,
          'items': serverItems,
        },
        receiptItems: _cart
            .map((line) => Map<String, dynamic>.from(line))
            .toList(),
        cashierName: widget.user['name']?.toString() ?? 'كاشير',
        heldOrderId: _activeHeldOrderId,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _cart.clear();
          _invoiceNotes = '';
          _activeHeldOrderId = null;
          _localHeldId = null;
          _editingInvoiceId = null;
          _discountPercent = null;
          _discount = 0;
          _deliveryFee = 0;
          _discountValid = true;
        });
      }
      try {
        _heldRecord = await _heldService.read();
      } catch (_) {
        _heldRecord = result['success'] == true
            ? {'status': 'confirmed'}
            : {'status': 'uncertain'};
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? 'تم حفظ الفاتورة المعلقة'
                : result['message']?.toString() ?? 'تعذر التعليق',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
      _restoreBarcodeFocus();
    }
  }

  Future<void> _refreshHeldSnapshot() async {
    try {
      await _posService.fetchHeld(_branchId);
    } catch (_) {
      try {
        await ApiClient.offlineStore?.forget(
          Uri.parse('${ApiConfig.baseUrl}/pos/held?branch_id=$_branchId'),
        );
      } catch (_) {
        /* The operation journal still identifies the consumed invoice. */
      }
    }
  }

  Future<void> _openHeldInvoices() async {
    List<dynamic> invoices;
    final local = await ApiClient.offlineStore?.localHeld(_branchId) ?? [];
    final operations = await SyncService.records();
    if (_checkoutRecord != null &&
        const {'confirmed', 'queued'}.contains(_checkoutRecord!['status'])) {
      operations.add(_checkoutRecord!);
    }
    bool consumed(Map order) => operations.any(
      (record) =>
          record['status'] != 'rejected' &&
          ((order['local_held_id'] != null &&
                  record['payload']?['local_held_id'] ==
                      order['local_held_id']) ||
              (SaleData.id(order['id']) != null &&
                  SaleData.id(record['payload']?['held_order_id']) ==
                      SaleData.id(order['id']))),
    );
    try {
      invoices = [
        ...local,
        ...await _posService.fetchHeld(_branchId),
      ].where((order) => !consumed(order)).toList();
    } catch (error) {
      if (local.isEmpty) {
        if (mounted) _showMessage('تعذر تحميل المعلقات: $error', isError: true);
        return;
      }
      invoices = local.where((order) => !consumed(order)).toList();
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('الفواتير المعلقة'),
        content: SizedBox(
          width: 480,
          child: invoices.isEmpty
              ? const Text('لا توجد فواتير معلقة')
              : ListView(
                  shrinkWrap: true,
                  children: invoices.map((raw) {
                    final order = Map<String, dynamic>.from(raw);
                    return ListTile(
                      title: Text(
                        order['invoice_number']?.toString() ?? 'فاتورة',
                      ),
                      subtitle: Text(
                        '${order['items']?.length ?? 0} أصناف • ${order['total'] ?? 0} ر.س'
                        '${(order['notes']?.toString().trim() ?? '').isEmpty ? '' : '\nملاحظة: ${order['notes']}'}',
                      ),
                      onTap: () async {
                        try {
                          final lines = SaleData.heldLines(order);
                          if (_cart.isNotEmpty &&
                              !await _confirmReplaceCart()) {
                            return;
                          }
                          if (!mounted || !dialogContext.mounted) return;
                          setState(() {
                            _activeHeldOrderId = SaleData.id(order['id']);
                            _localHeldId = order['local_held_id'] as String?;
                            _selectedCustomerId = SaleData.id(
                              order['customer_id'],
                            );
                            _invoiceNotes = order['notes']?.toString() ?? '';
                            _discountPercent = null;
                            _discount = SaleData.number(order['discount']) ?? 0;
                            _deliveryFee =
                                SaleData.number(order['delivery_fee']) ?? 0;
                            _editingInvoiceId = null;
                            _paymentMethod =
                                order['payment_method']?.toString() ?? 'cash';
                            _cart
                              ..clear()
                              ..addAll(lines);
                          });
                          Navigator.pop(dialogContext);
                          await _loadData();
                        } catch (error) {
                          if (mounted) {
                            _showMessage(
                              'تعذر استعادة الفاتورة: $error',
                              isError: true,
                            );
                          }
                        }
                      },
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    _restoreBarcodeFocus();
  }

  Future<void> _reviewHeld() async {
    try {
      final saved = await reviewOperation(context, _heldService);
      final record = await _heldService.read();
      if (!mounted || saved == null) return;
      setState(() {
        _heldRecord = record;
        _cart.clear();
        _invoiceNotes = '';
        _discountPercent = null;
        _discount = 0;
        _deliveryFee = 0;
        _discountValid = true;
        _activeHeldOrderId = null;
        _localHeldId = null;
        _editingInvoiceId = null;
        if (!saved && record != null) {
          _cart.addAll(
            (record['items'] as List).map(
              (line) => Map<String, dynamic>.from(line),
            ),
          );
          _discount = SaleData.number(record['payload']['discount']) ?? 0;
          _selectedCustomerId = SaleData.id(record['payload']['customer_id']);
          _activeHeldOrderId = SaleData.id(record['held_order_id']);
        }
      });
      _showMessage(
        saved ? 'تم تأكيد حفظ المعلقة.' : 'استُعيدت السلة للمراجعة.',
      );
      await _loadData();
    } catch (error) {
      if (mounted) _showMessage('$error', isError: true);
    }
  }

  Future<void> _addMobileProduct(Map<String, dynamic> product) async {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing || _addDialogOpen) return;
    _addDialogOpen = true;
    try {
      await _addMobileProductOnce(product);
    } finally {
      _addDialogOpen = false;
    }
  }

  Future<void> _addMobileProductOnce(Map<String, dynamic> product) async {
    final price = _productPrice(product);
    if (price == null) {
      _showMessage('لا يوجد سعر معتمد لهذا الصنف', isError: true);
      return;
    }
    final customerId = _selectedCustomerId;
    final customer = _customers
        .whereType<Map>()
        .where((c) => SaleData.id(c['id']) == customerId)
        .firstOrNull;
    final selection = await showDialog<ProductSelection>(
      context: context,
      builder: (_) => ProductAddDialog(
        product: product,
        price: price,
        customerName: customer?['name']?.toString(),
        loadHistory: customerId == null
            ? null
            : () => WholesaleService().priceHistory(
                _branchId,
                customerId,
                SaleData.id(product['id'])!,
              ),
      ),
    );
    if (!mounted || selection == null || customerId != _selectedCustomerId) {
      return;
    }
    _addToCart(
      product,
      selectedPrice: selection.price,
      quantity: selection.quantity,
    );
  }

  bool _addToCart(
    Map<String, dynamic> product, {
    bool gift = false,
    bool fromBarcode = false,
    double? selectedPrice,
    double quantity = 1,
  }) {
    if (_refuseWhileViewing()) return false;
    if (_missingBarcodeOpen ||
        _isRepricing ||
        _isCheckingOut ||
        _loadError != null) {
      return false;
    }
    final price = selectedPrice ?? _productPrice(product);
    if (price == null) {
      _showMessage(
        'لا يوجد سعر معتمد لهذا الصنف. راجع تسعيره قبل البيع.',
        isError: true,
      );
      return false;
    }
    setState(() {
      if (fromBarcode) {
        _barcodeController.clear();
        _searchQuery = '';
      }
      final index = _cart.indexWhere(
        (item) =>
            _mergeSimilar &&
            SaleData.id(item['product_id']) == SaleData.id(product['id']) &&
            (item['gift'] == true) == gift &&
            (gift ||
                (SaleData.number(item['price']) == price &&
                    (SaleData.number(item['discount']) ?? 0) == 0)),
      );
      _addCount++;
      _addedLine = index >= 0 ? index : _cart.length;
      if (index >= 0) {
        _cart[index]['quantity'] =
            (SaleData.number(_cart[index]['quantity']) ?? 0) + quantity;
      } else {
        _cart.add({
          'product_id': SaleData.id(product['id']),
          'name': product['name'] ?? 'منتج',
          'price': price,
          'quantity': quantity,
          'unit': product['unit'] is String ? product['unit'] : 'قطعة',
          'discount': gift ? price : 0.0,
          'gift': gift,
          'stock_quantity': product['stock_quantity'],
          'shared_stock_quantity': product['shared_stock_quantity'],
          'cost_price': product['cost_price'],
          if (_posService.supportsGiftLines)
            'offer_quantity': product['offer_quantity'],
          if (_posService.supportsGiftLines)
            'offer_price': product['offer_price'],
        });
      }
    });
    _restoreBarcodeFocus();
    return true;
  }

  void _restoreBarcodeFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          PosShell.isActive(context) &&
          !_isCheckingOut &&
          !_isRepricing &&
          !_isLoading) {
        _barcodeFocusNode.requestFocus();
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    if (_refuseWhileViewing()) return;
    setState(() {
      _cart[index]['quantity'] += delta;
      if (_cart[index]['quantity'] <= 0) {
        _cart.removeAt(index);
      }
      if (_cart.isEmpty) {
        _discountPercent = null;
        _discount = 0;
        _deliveryFee = 0;
        _discountValid = true;
      }
    });
    _restoreBarcodeFocus();
  }

  Future<bool> _confirmReplaceCart({bool clear = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(clear ? 'تأكيد إفراغ الفاتورة' : 'السلة تحتوي أصنافاً'),
          content: Text(
            clear ? 'هل تريد إفراغ الفاتورة الحالية وبدء فاتورة جديدة؟' : 'هل تريد استبدال السلة الحالية؟ يمكنك تعليقها أولاً للاحتفاظ بها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(clear ? 'إفراغ الفاتورة' : 'استبدال السلة'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _confirmClearCart() async {
    if (_viewingInvoice != null) {
      _closeViewedInvoice();
      return;
    }
    if (_cart.isEmpty || _isCheckingOut || _isRepricing) return;
    if (await _confirmReplaceCart(clear: true) && mounted) {
      setState(() {
        _cart.clear();
        _invoiceNotes = '';
        _discountPercent = null;
        _discount = 0;
        _deliveryFee = 0;
        _discountValid = true;
        _activeHeldOrderId = null;
        _localHeldId = null;
        _editingInvoiceId = null;
      });
    }
    _restoreBarcodeFocus();
  }

  void _removeItem(int index) {
    if (_refuseWhileViewing()) return;
    setState(() {
      _cart.removeAt(index);
      if (_cart.isEmpty) {
        _discountPercent = null;
        _discount = 0;
        _deliveryFee = 0;
        _discountValid = true;
      }
    });
    _restoreBarcodeFocus();
  }

  double get _subtotal =>
      _cart.fold<double>(0, (total, item) => total + SaleData.lineTotal(item));

  double get _taxAmount =>
      (_subtotal - _discount) > 0 ? (_subtotal - _discount) * _taxRate : 0;
  double get _grandTotal => (_subtotal - _discount) + _taxAmount + _deliveryFee;

  Future<void> _reviewCheckout() async {
    final record = _checkoutRecord;
    if (!CheckoutService.needsReview(record)) return;
    try {
      if (await _checkoutService.reconcile()) {
        final confirmed = await _checkoutService.read();
        if (!mounted) return;
        setState(() {
          _checkoutRecord = confirmed;
          _cart.clear();
          _discountPercent = null;
          _discount = 0;
          _deliveryFee = 0;
          _discountValid = true;
          _activeHeldOrderId = null;
          _localHeldId = null;
          _editingInvoiceId = null;
        });
        _showMessage('أكد الخادم حفظ الفاتورة. يمكنك إعادة طباعتها.');
        return;
      }
    } catch (_) {
      // Keep the existing review record when the lookup cannot confirm success.
    }
    if (!mounted) return;
    final payload = Map<String, dynamic>.from(record!['payload']);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('عملية تحتاج التحقق'),
        content: Text(
          'قد يكون الخادم حفظ هذه الفاتورة رغم انقطاع الرد. تحقق من سجل المبيعات لدى الإدارة قبل اختيار النتيجة.\n'
          'التاريخ: ${record['created_at']}\nالإجمالي: ${payload['total_amount']}\n'
          'عدد الأصناف: ${(record['items'] as List).length}\n'
          'لن تُرسل العملية تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لاحقاً'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تحققت: الفاتورة محفوظة'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تحققت: الفاتورة غير محفوظة'),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    try {
      await _checkoutService.resolveAfterVerification(wasSaved: saved);
      final updated = await _checkoutService.read();
      if (!mounted) return;
      setState(() {
        _checkoutRecord = updated;
        _cart.clear();
        _activeHeldOrderId = null;
        _localHeldId = null;
        _editingInvoiceId = null;
        _discountPercent = null;
        _discount = 0;
        _deliveryFee = 0;
        _discountValid = true;
        if (!saved) {
          _cart.addAll(
            (record['items'] as List).map(
              (line) => Map<String, dynamic>.from(line),
            ),
          );
          _discount = (payload['discount'] as num).toDouble();
          _selectedCustomerId = payload['customer_id'] as int?;
          _paymentMethod = payload['payment_method'] as String;
          _invoiceNotes = payload['notes']?.toString() ?? '';
          _activeHeldOrderId = record['held_order_id'] as int?;
        }
      });
      _showMessage(
        saved
            ? 'تم تسجيل نتيجة التحقق؛ لن تُرسل الفاتورة مجدداً'
            : 'استُعيدت السلة؛ راجعها ثم أتمم البيع',
      );
      await _loadData();
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر حفظ نتيجة التحقق؛ العملية ما زالت قيد المراجعة',
          isError: true,
        );
      }
    }
  }

  Future<void> _restoreRejectedCart() async {
    final record = _checkoutRecord;
    if (record?['status'] != 'rejected' || _isCheckingOut) return;
    if (_cart.isNotEmpty) {
      _showMessage(
        'السلة تحتوي أصنافاً؛ أفرغها قبل استعادة العملية السابقة',
        isError: true,
      );
      return;
    }
    final payload = Map<String, dynamic>.from(record!['payload']);
    setState(() {
      _cart.addAll(
        (record['items'] as List).map(
          (line) => Map<String, dynamic>.from(line),
        ),
      );
      _discount = (payload['discount'] as num).toDouble();
      _selectedCustomerId = payload['customer_id'] as int?;
      _paymentMethod = payload['payment_method'] as String;
      _invoiceNotes = payload['notes']?.toString() ?? '';
      _activeHeldOrderId = record['held_order_id'] as int?;
    });
    await _loadData();
  }

  Future<void> _printQueue = Future<void>.value();
  Future<void> _queuePrint(Map<String, dynamic> record) {
    _printQueue = _printQueue.then((_) async {
      try {
        await PrinterService.printReceipt(
          order: _receiptOrder(record),
          items: (record['items'] as List).map((line) {
            final item = Map<String, dynamic>.from(line);
            item['price'] =
                (item['price'] as num) - (item['discount'] as num? ?? 0);
            return item;
          }).toList(),
          cashierName: record['cashier_name'] as String,
        );
      } catch (error) {
        if (mounted) {
          _showMessage(
            'تعذرت الطباعة؛ الفاتورة محفوظة. ${error is StateError ? error.message : 'يمكن إعادة طباعتها من سجل الفواتير.'}',
            isError: true,
          );
        }
      }
    });
    return _printQueue;
  }

  Future<void> _reprintLastReceipt() async {
    var record = _checkoutRecord;
    final id = record?['order']?['id'];
    if (record?['status'] == 'queued' &&
        id is String &&
        id.startsWith('local:')) {
      final saved = await ApiClient.offlineStore?.operation(id.substring(6));
      if (saved?['status'] == 'confirmed') {
        record = saved;
        if (mounted) setState(() => _checkoutRecord = saved);
      }
    }
    if (const {'confirmed', 'queued'}.contains(record?['status'])) {
      await _queuePrint(record!);
    }
  }

  Future<bool> _editInvoiceNotes({bool forHold = false}) async {
    if (_refuseWhileViewing()) return false;
    final controller = TextEditingController(text: _invoiceNotes);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(forHold ? 'ملاحظة الفاتورة المعلقة' : 'ملاحظات الفاتورة'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: forHold ? const Key('pos-hold-notes') : null,
            controller: controller,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'اكتب ملاحظات الفاتورة...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(forHold ? 'تعليق الفاتورة' : 'حفظ الملاحظات'),
          ),
        ],
      ),
    );
    if (mounted && result != null) setState(() => _invoiceNotes = result);
    _restoreBarcodeFocus();
    // Release the controller after the dialog's closing animation.
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    return result != null;
  }

  Map<String, dynamic> _receiptOrder(Map<String, dynamic> record) => {
    ...Map<String, dynamic>.from(record['order']),
    if (record['payload']?['notes'] != null)
      'notes': record['payload']['notes'],
  };

  Future<void> _exportInvoice() async {
    if (_isCheckingOut || _isRepricing) return;
    if (_cart.isNotEmpty) {
      await _checkout(printReceipt: false);
      if (!mounted || _cart.isNotEmpty) return;
    }
    final record = _checkoutRecord;
    if (!const {'confirmed', 'queued'}.contains(record?['status'])) {
      _showMessage('احفظ فاتورة أولاً لتصدير PDF.');
      return;
    }
    try {
      await PrinterService.shareReceipt(
        order: Map<String, dynamic>.from(record!['order']),
        items: (record['items'] as List).map((raw) {
          final line = Map<String, dynamic>.from(raw);
          line['price'] =
              (line['price'] as num) - (line['discount'] as num? ?? 0);
          return line;
        }).toList(),
        cashierName: record['cashier_name'] as String,
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر تصدير PDF؛ الفاتورة محفوظة ويمكن المحاولة مجدداً.',
          isError: true,
        );
      }
    }
  }

  Future<void> _browseInvoice({bool next = false, bool search = false}) async {
    if (_isCheckingOut || _isRepricing) return;
    String? query;
    if (search) {
      final controller = TextEditingController();
      query = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('البحث عن فاتورة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'رقم الفاتورة أو ID'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('بحث'),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (query == null || query.trim().isEmpty || !mounted) return;
    }
    try {
      final currentId = SaleData.id(
        _viewingInvoice?['id'] ?? _viewedInvoice?['id'],
      );
      final order = await _posService.fetchInvoice(
        _branchId,
        search: query?.trim(),
        before: search || next ? null : currentId,
        after: search || !next ? null : currentId,
      );
      if (!mounted) return;
      if (_viewingInvoice == null &&
          _cart.isNotEmpty &&
          !await _confirmReplaceCart()) {
        return;
      }
      if (!mounted) return;
      _showSavedInvoice(order);
    } catch (error) {
      if (mounted) {
        _showMessage(
          search
              ? 'تعذر العثور على الفاتورة: $error'
              : 'لا توجد فاتورة ${next ? 'أحدث' : 'أقدم'}.',
          isError: true,
        );
      }
    }
  }

  /// Shows a saved invoice in the cart, locked until «تعديل».
  void _showSavedInvoice(Map<String, dynamic> order) {
    final lines = SaleData.heldLines(order);
    setState(() {
      _viewedInvoice = order;
      _viewingInvoice = order;
      _cart
        ..clear()
        ..addAll(
          lines.map(
            (line) => {...line, 'price_manual': !SaleData.hasOffer(line)},
          ),
        );
      _editingInvoiceId = null;
      _activeHeldOrderId = null;
      _localHeldId = null;
      _selectedCustomerId = SaleData.id(order['customer_id']);
      _discountPercent = null;
      _discount = SaleData.number(order['discount']) ?? 0;
      _deliveryFee = SaleData.number(order['delivery_fee']) ?? 0;
      _invoiceNotes = order['notes']?.toString() ?? '';
    });
  }

  bool get _viewedInvoiceEditable =>
      _viewingInvoice?['editable_in_pos'] != false &&
      (_viewingInvoice?['type'] == null || _viewingInvoice?['type'] == 'pos');

  void _unlockViewedInvoice() {
    final order = _viewingInvoice;
    if (order == null) return;
    if (!_viewedInvoiceEditable) {
      _showMessage(
        'هذه فاتورة مبيعات من الويب أو الجملة؛ عدّلها من صفحة فاتورة المبيعات.',
        isError: true,
      );
      return;
    }
    if (ApiClient.offline.value) {
      _showMessage('اتصل بالخادم لتعديل فاتورة محفوظة.', isError: true);
      return;
    }
    setState(() {
      _editingInvoiceId = SaleData.id(order['id']);
      _viewingInvoice = null;
    });
    _showMessage(
      'تعديل الفاتورة ${order['invoice_number']}؛ الحفظ يحدّث نفس الفاتورة.',
    );
  }

  void _closeViewedInvoice() {
    setState(() {
      _viewingInvoice = null;
      _cart.clear();
      _editingInvoiceId = null;
      _selectedCustomerId = null;
      _invoiceNotes = '';
      _discountPercent = null;
      _discount = 0;
      _deliveryFee = 0;
      _discountValid = true;
    });
    _restoreBarcodeFocus();
  }

  /// True, with a message, while a saved invoice is only being viewed.
  bool _refuseWhileViewing() {
    if (_viewingInvoice == null) return false;
    _showMessage(
      'الفاتورة ${_viewingInvoice?['invoice_number'] ?? ''} محفوظة للعرض؛ اضغط «تعديل» لتغييرها.',
      isError: true,
    );
    return true;
  }

  Future<void> _printViewedInvoice({bool pdf = false}) async {
    final order = _viewingInvoice;
    if (order == null) return;
    final items = SaleData.heldLines(order);
    SaleData.applyOffers(items);
    try {
      if (pdf) {
        await PrinterService.shareReceipt(
          order: order,
          items: items,
          cashierName: widget.user['name']?.toString() ?? '—',
        );
      } else {
        await PrinterService.printReceipt(
          order: order,
          items: items,
          cashierName: widget.user['name']?.toString() ?? '—',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('$error', isError: true);
    }
  }

  Widget _viewedInvoiceBar() {
    final order = _viewingInvoice!;
    final created = DateTime.tryParse('${order['created_at']}')?.toLocal();
    final when = created == null
        ? ''
        : '${created.year}/${created.month.toString().padLeft(2, '0')}/${created.day.toString().padLeft(2, '0')} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final customer =
        order['party']?['name'] ?? order['customer_name'] ?? 'زبون عام';
    return Material(
      key: const Key('pos-viewed-invoice'),
      color: const Color(0xFFFEF3C7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFF92400E)),
            Text(
              'فاتورة محفوظة ${order['invoice_number'] ?? ''} — $customer${when.isEmpty ? '' : ' — $when'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF78350F),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _browseInvoice,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('السابقة'),
            ),
            OutlinedButton.icon(
              onPressed: () => _browseInvoice(next: true),
              icon: const Icon(Icons.arrow_back),
              label: const Text('التالية'),
            ),
            OutlinedButton.icon(
              onPressed: _printViewedInvoice,
              icon: const Icon(Icons.print),
              label: const Text('طباعة'),
            ),
            OutlinedButton.icon(
              onPressed: () => _printViewedInvoice(pdf: true),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
            ),
            if (_viewedInvoiceEditable)
              OutlinedButton.icon(
                onPressed: () => _deleteSavedInvoice(_viewingInvoice),
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف'),
              ),
            FilledButton.icon(
              key: const Key('pos-unlock-invoice'),
              onPressed: _unlockViewedInvoice,
              icon: const Icon(Icons.edit),
              label: const Text('تعديل'),
            ),
            TextButton.icon(
              onPressed: _closeViewedInvoice,
              icon: const Icon(Icons.close),
              label: const Text('فاتورة جديدة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSavedInvoice(Map<String, dynamic>? order) async {
    if (order == null) {
      _showMessage('اختر فاتورة محفوظة أولاً من البحث أو السابقة.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف الفاتورة ${order['invoice_number']}؟'),
        content: const Text('سيُعاد مخزونها وتُحذف دفعتها على الخادم.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف الفاتورة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _posService.deleteInvoice(SaleData.id(order['id'])!);
      _viewedInvoice = null;
      if (mounted &&
          SaleData.id(_viewingInvoice?['id']) == SaleData.id(order['id'])) {
        _closeViewedInvoice();
      }
      if (mounted && _editingInvoiceId == SaleData.id(order['id'])) {
        setState(() {
          _cart.clear();
          _editingInvoiceId = null;
          _discountPercent = null;
          _discount = 0;
          _deliveryFee = 0;
          _invoiceNotes = '';
        });
      }
      if (mounted) _showMessage('تم حذف الفاتورة وإعادة المخزون.');
      await _refreshInBackground();
    } catch (error) {
      if (mounted) _showMessage('$error', isError: true);
    }
  }

  String _invoiceText() {
    final record = _checkoutRecord;
    final lines = _cart.isNotEmpty
        ? _cart
        : (record?['items'] as List? ?? [])
              .map((line) => Map<String, dynamic>.from(line))
              .toList();
    final order = record?['order'] as Map?;
    final text = StringBuffer(
      _cart.isNotEmpty
          ? 'مسودة فاتورة'
          : 'فاتورة ${order?['invoice_number'] ?? ''}',
    );
    if (_cart.isEmpty && record?['status'] == 'queued') {
      text.write(' — محلية بانتظار المزامنة');
    }
    for (final line in lines) {
      text.write(
        '\n${line['name']}${line['gift'] == true ? ' (هدية)' : ''} × ${line['quantity']} = ${SaleData.lineTotal(line).toStringAsFixed(2)}',
      );
    }
    text.write(
      '\nالإجمالي: ${_cart.isNotEmpty ? _grandTotal.toStringAsFixed(2) : order?['total'] ?? 0}',
    );
    return text.toString();
  }

  Future<void> _copyInvoice() async {
    await Clipboard.setData(ClipboardData(text: _invoiceText()));
    if (mounted) _showMessage('تم نسخ الفاتورة.');
  }

  Future<void> _shareWhatsApp() async {
    if (_isCheckingOut || _isRepricing) return;
    if (_cart.isNotEmpty) {
      await _checkout(printReceipt: false);
      if (!mounted || _cart.isNotEmpty) return;
    }
    if (!const {'confirmed', 'queued'}.contains(_checkoutRecord?['status'])) {
      _showMessage('احفظ فاتورة أولاً لمشاركتها.');
      return;
    }
    try {
      final record = _checkoutRecord!;
      await PrinterService.shareReceipt(
        order: Map<String, dynamic>.from(record['order']),
        items: (record['items'] as List).map((raw) {
          final line = Map<String, dynamic>.from(raw);
          line['price'] =
              (line['price'] as num) - (line['discount'] as num? ?? 0);
          return line;
        }).toList(),
        cashierName: record['cashier_name'] as String,
        message: _invoiceText(),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذرت مشاركة ملف PDF؛ يمكنك تصديره من زر PDF.',
          isError: true,
        );
      }
    }
  }

  Future<void> _editPercentDiscount() async {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing) return;
    final entry = await showAmountDialog(
      context,
      title: 'خصم بالنسبة المئوية',
      label: 'النسبة من 0 إلى 100',
      allowZero: true,
      initialAmount: '${_discountPercent ?? 0}',
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    if (entry.amount > 100) {
      _showMessage('النسبة لا يمكن أن تتجاوز 100%.', isError: true);
      return;
    }
    setState(() => _discountPercent = entry.amount);
  }

  Future<void> _editFinalTotal() async {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing || _cart.isEmpty) return;
    final entry = await showAmountDialog(
      context,
      title: 'تعديل صافي الفاتورة',
      label: 'الصافي المطلوب',
      allowZero: true,
      initialAmount: '$_grandTotal',
    );
    _restoreBarcodeFocus();
    if (entry == null || !mounted) return;
    if (entry.amount < _deliveryFee ||
        entry.amount > _subtotal + _deliveryFee) {
      _showMessage(
        'أدخل صافياً بين رسوم التوصيل وإجمالي الأصناف مع التوصيل.',
        isError: true,
      );
      return;
    }
    setState(() {
      _discountPercent = null;
      _discount = _subtotal + _deliveryFee - entry.amount;
    });
  }

  Future<void> _editDelivery() async {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing) return;
    if (!_posService.supportsGiftLines) {
      _showMessage('حدّث خادم Laravel لتفعيل رسوم التوصيل.', isError: true);
      return;
    }
    final entry = await showAmountDialog(
      context,
      title: 'رسوم التوصيل',
      label: 'قيمة التوصيل',
      allowZero: true,
      initialAmount: '$_deliveryFee',
    );
    if (entry != null && mounted) setState(() => _deliveryFee = entry.amount);
    _restoreBarcodeFocus();
  }

  Future<void> _giftLine() async {
    if (_refuseWhileViewing()) return;
    await _showProducts(gift: true);
  }

  Future<void> _editLine(int index) async {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing || index >= _cart.length) return;
    final line = _cart[index];
    final result = await showCartLineDialog(context, line);
    _restoreBarcodeFocus();
    if (result == null || !mounted || !_cart.contains(line)) return;
    setState(() {
      line['quantity'] = result.quantity;
      if (line['gift'] != true) {
        if ((result.price - (SaleData.number(line['price']) ?? 0)).abs() >
            .005) {
          line['price_manual'] = true;
        }
        line['price'] = result.price;
        line['discount'] = 0.0;
      }
    });
  }

  void _setLineValue(int index, String field, double value) {
    if (_refuseWhileViewing()) return;
    if (_isCheckingOut || _isRepricing || index >= _cart.length) return;
    final line = _cart[index];
    if (field != 'quantity' && line['gift'] == true) return;
    setState(() {
      if (field == 'quantity') {
        line['quantity'] = value;
      } else {
        line['price'] = field == 'subtotal'
            ? value / (SaleData.number(line['quantity']) ?? 1)
            : value;
        line['discount'] = 0.0;
        line['price_manual'] = true;
      }
    });
  }

  Future<void> _showCost() async {
    await showCartCostDialog(context, _cart, _grandTotal - _deliveryFee);
    _restoreBarcodeFocus();
  }

  Future<void> _checkout({bool printReceipt = false}) async {
    if (_refuseWhileViewing()) return;
    if (_editingInvoiceId != null && ApiClient.offline.value) {
      _showMessage('اتصل بالخادم لحفظ تعديل فاتورة سابقة.', isError: true);
      return;
    }
    if (!_tenderValid) {
      _showMessage(
        'النقد المستلم غير صالح أو أقل من إجمالي الفاتورة.',
        isError: true,
      );
      return;
    }
    if (!_discountValid) {
      _showMessage('صحح خصم الفاتورة أولاً.', isError: true);
      return;
    }
    if (CheckoutService.needsReview(_heldRecord)) {
      await _reviewHeld();
      return;
    }
    if (_isCheckingOut ||
        _isRestoringCheckout ||
        _isRepricing ||
        _loadError != null) {
      return;
    }
    if (CheckoutService.needsReview(_checkoutRecord)) {
      await _reviewCheckout();
      return;
    }
    if (_cart.isEmpty) return;
    if (_branchId <= 0 ||
        _activeShift == null ||
        !_grandTotal.isFinite ||
        _grandTotal < 0) {
      _showMessage('تحقق من الفرع والوردية وقيمة الفاتورة', isError: true);
      return;
    }
    final serverItems = _serverItems();
    if (serverItems == null) return;
    setState(() => _isCheckingOut = true);
    if (printReceipt) {
      unawaited(
        PrinterService.prepareReceipt().catchError((Object _) {
          // A preparation failure must not cancel or retry a financial write.
          // The print job reports its own error after the sale is confirmed.
        }),
      );
    }
    final items = _cart.map((line) => Map<String, dynamic>.from(line)).toList();
    final heldOrderId = _activeHeldOrderId;
    final invoiceNotes = _invoiceNotes;
    final localHeldId = _localHeldId;
    try {
      final result = await _checkoutService.checkout(
        payload: {
          'branch_id': _branchId,
          'local_held_id': ?localHeldId,
          if (_editingInvoiceId != null) 'invoice_id': _editingInvoiceId,
          if (_selectedCustomerId != null) 'customer_id': _selectedCustomerId,
          'subtotal': _subtotal,
          'tax_amount': _taxAmount,
          'discount': _discount,
          'delivery_fee': _deliveryFee,
          'total_amount': _grandTotal,
          if (_invoiceNotes.isNotEmpty) 'notes': _invoiceNotes,
          'payment_method': _paymentMethod,
          'items': serverItems,
        },
        receiptItems: items,
        cashierName: widget.user['name']?.toString() ?? 'كاشير',
        heldOrderId: heldOrderId,
        offlineShiftId: _activeShift?['id'],
        probeWhenOffline: _networkAvailable,
      );
      // Clear a confirmed sale before any fallible printing or cleanup operation.
      if (result['success'] == true && mounted) {
        setState(() {
          _cart.clear();
          _invoiceNotes = '';
          _activeHeldOrderId = null;
          _localHeldId = null;
          _editingInvoiceId = null;
          _discountPercent = null;
          _discount = 0;
          _deliveryFee = 0;
          _discountValid = true;
          _searchQuery = '';
          _barcodeController.clear();
        });
      }
      if (result['success'] == true) {
        if (heldOrderId != null && result['queued'] != true) {
          unawaited(_refreshHeldSnapshot());
        }
        if (localHeldId != null) {
          try {
            await ApiClient.offlineStore?.deleteLocalHeld(
              _branchId,
              localHeldId,
            );
          } catch (_) {
            /* The outbox marks this draft as consumed. */
          }
        }
        final order = Map<String, dynamic>.from(result['order']);
        // Retain a printable in-memory copy even if post-response storage failed.
        _checkoutRecord = {
          'status': result['queued'] == true ? 'queued' : 'confirmed',
          'order': order,
          'items': items,
          'cashier_name': widget.user['name']?.toString() ?? 'كاشير',
          'payload': {
            'notes': invoiceNotes,
            'held_order_id': heldOrderId,
            'local_held_id': localHeldId,
          },
        };
        if (!mounted) return;
        _showMessage(
          '${result['queued'] == true ? 'حُفظت محليًا بانتظار المزامنة' : 'تم حفظ الفاتورة'}: ${order['invoice_number'] ?? order['id']}'
          '${result['local_save_failed'] == true ? '؛ تعذر حفظ النسخة المحلية' : ''}',
        );
        setState(() => _isCheckingOut = false);
        _barcodeFocusNode.requestFocus();
        // A new invoice uses the loaded catalog; explicit refresh/customer changes reload prices.
        // Queue a snapshot so printer dialogs cannot lock the next invoice or print a later sale.
        if (printReceipt) unawaited(_queuePrint(_checkoutRecord!));
      } else if (mounted) {
        _checkoutRecord = await _checkoutService.read();
        if (mounted) _showMessage(result['message'].toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
      _restoreBarcodeFocus();
    }
  }

  double? _productPrice(dynamic product) {
    // The API explicitly identifies the pricing branch; it can differ from the stock branch.
    final pricingBranchId =
        SaleData.id(product['pricing_branch_id']) ?? _branchId;
    return SaleData.retailPrice(product, pricingBranchId);
  }

  Future<void> _printStatement() async {
    if (_selectedCustomerId == null) {
      _showMessage('اختر عميلاً لعرض كشف الحساب.');
      return;
    }
    try {
      final statement = await StatementService.fetchPartyStatement(
        _selectedCustomerId!,
      );
      await StatementService.generateCustomerStatement(
        customer: Map<String, dynamic>.from(statement['party']),
        transactions: statement['transactions'] as List? ?? [],
      );
    } catch (error) {
      if (mounted) _showMessage('تعذر عرض كشف الحساب: $error', isError: true);
    }
  }

  Future<void> _newInvoice() async {
    if (_viewingInvoice != null) _closeViewedInvoice();
    if (_cart.isNotEmpty) await _confirmClearCart();
    if (!mounted || _cart.isNotEmpty) return;
    _searchDebounce?.cancel();
    _barcodeDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _editingInvoiceId = null;
      _activeHeldOrderId = null;
      _localHeldId = null;
      _selectedCustomerId = null;
      _invoiceNotes = '';
      _discountPercent = null;
      _discount = 0;
      _deliveryFee = 0;
      _discountValid = true;
      _tenderValid = true;
      _barcodeController.clear();
    });
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _runShortcut(
    FutureOr<void> Function() action, {
    bool restoreBarcode = true,
  }) async {
    _shortcutRunning = true;
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر تنفيذ الاختصار؛ حاول مجدداً.', isError: true);
      }
    } finally {
      _shortcutRunning = false;
      if (restoreBarcode) _restoreBarcodeFocus();
    }
  }

  bool _handleShortcut(KeyEvent event) {
    if (!mounted || !PosShell.isActive(context)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    final FutureOr<void> Function()? action = switch (event.logicalKey) {
      LogicalKeyboardKey.f1 => _openHeldInvoices,
      LogicalKeyboardKey.f2 => _saveHeldInvoice,
      LogicalKeyboardKey.f3 => () => _checkout(printReceipt: false),
      LogicalKeyboardKey.f4 => _newInvoice,
      LogicalKeyboardKey.f5 => _loadData,
      LogicalKeyboardKey.f6 => () => _checkout(printReceipt: true),
      LogicalKeyboardKey.f8 => _editInvoiceNotes,
      LogicalKeyboardKey.f9 => _giftLine,
      LogicalKeyboardKey.f10 => _focusCatalogSearch,
      // Esc never empties the invoice (as on the web): it closes dialogs and
      // clears the product search; F4 starts a new invoice.
      _ => null,
    };
    if (action == null || event is KeyUpEvent) return false;
    if (event is! KeyDownEvent) return true;
    if (_shortcutRunning ||
        _missingBarcodeOpen ||
        _holdPromptOpen ||
        _isCheckingOut ||
        _isRepricing ||
        _isLoading ||
        _isRestoringCheckout ||
        CheckoutService.needsReview(_heldRecord) ||
        CheckoutService.needsReview(_checkoutRecord)) {
      return true;
    }
    unawaited(
      _runShortcut(
        action,
        restoreBarcode: event.logicalKey != LogicalKeyboardKey.f10,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final products = _catalog.search(_searchQuery, _selectedCategoryId);
    final holdReview = CheckoutService.needsReview(_heldRecord);
    final review = CheckoutService.needsReview(_checkoutRecord) || holdReview;
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      child: PopScope(
        canPop: !_isCheckingOut,
        child: Stack(
          children: [
            Scaffold(
              body: SafeArea(
                child: _isLoading || _isRestoringCheckout
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            const Text(
                              'جارٍ تجهيز الأصناف والعملاء وبيانات الوردية تلقائياً…',
                              textAlign: TextAlign.center,
                            ),
                            if (_loadFailures > 0)
                              Text('المحاولة ${_loadFailures + 1}'),
                          ],
                        ),
                      )
                    : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_loadError!, textAlign: TextAlign.center),
                              if (_loadRetrySeconds != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'سيُستأنف تنزيل البيانات تلقائياً بعد $_loadRetrySeconds ثانية، أو عند عودة الاتصال.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _loadData,
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : AbsorbPointer(
                        absorbing: review,
                        child: Column(
                          children: [
                            if (_viewingInvoice != null) _viewedInvoiceBar(),
                            Expanded(
                              child: PosWorkspace(
                                embedded: PosShell.contains(context),
                                addedLine: _addedLine,
                                addCount: _addCount,
                                mergeSimilar: _mergeSimilar,
                                onMergeSimilar: (value) =>
                                    setState(() => _mergeSimilar = value),
                                products: products,
                                categories: _categories,
                                customers: _customers,
                                cart: _cart,
                                barcodeController: _barcodeController,
                                barcodeFocus: _barcodeFocusNode,
                                catalogFocus: _catalogFocusNode,
                                selectedCategoryId: _selectedCategoryId,
                                customerId: _selectedCustomerId,
                                subtotal: _subtotal,
                                discount: _discount,
                                deliveryFee: _deliveryFee,
                                editingInvoiceId: _editingInvoiceId,
                                tax: _taxAmount,
                                total: _grandTotal,
                                paymentMethod: _paymentMethod,
                                cashier:
                                    widget.user['name']?.toString() ??
                                    'الكاشير',
                                shiftId: _activeShift?['id'],
                                priceFor: _productPrice,
                                busy: _isCheckingOut,
                                repricing: _isRepricing,
                                onBarcode: _onBarcodeInput,
                                onSubmitBarcode: _addExactBarcodeMatch,
                                onScan: _scanBarcode,
                                onProducts: _focusCatalogSearch,
                                notice:
                                    _checkoutRecord?['status'] == 'confirmed'
                                    ? 'تم حفظ الفاتورة ${_checkoutRecord?['order']?['invoice_number'] ?? ''} على السيرفر.'
                                    : _checkoutRecord?['status'] == 'queued'
                                    ? 'حُفظت الفاتورة محليًا بانتظار المزامنة.'
                                    : null,
                                onCategory: (id) =>
                                    setState(() => _selectedCategoryId = id),
                                onCustomer: _reloadProductsForCustomer,
                                onRefreshCustomers: _refreshCustomersForPicker,
                                onAdd: _addToCart,
                                onMobileAdd: _addMobileProduct,
                                onQuantity: _updateQuantity,
                                onEditLine: _editLine,
                                onLineValue: _setLineValue,
                                onRemove: _removeItem,
                                onDiscount: (discount) => setState(() {
                                  _discountPercent = null;
                                  _discount = discount;
                                }),
                                onTenderValidity: (valid) =>
                                    _tenderValid = valid,
                                onDiscountValidity: (valid) =>
                                    setState(() => _discountValid = valid),
                                onPayment: (method) {
                                  setState(() => _paymentMethod = method);
                                  _restoreBarcodeFocus();
                                },
                                onCheckout: _checkout,
                                onHold: _saveHeldInvoice,
                                onHeld: _openHeldInvoices,
                                onClear: _confirmClearCart,
                                actions: {
                                  'إعادة طباعة آخر فاتورة': _reprintLastReceipt,
                                  'المزامنة': () => PosShell.open(
                                    context,
                                    'المزامنة والفواتير المحلية',
                                    const SyncScreen(),
                                  ),
                                  'لوحة التحكم': () => PosShell.open(
                                    context,
                                    'لوحة التحكم',
                                    DashboardScreen(user: widget.user),
                                  ),
                                  'مبيعات الجملة': () => PosShell.open(
                                    context,
                                    'مبيعات الجملة',
                                    WholesaleScreen(user: widget.user),
                                  ),
                                  if (ApiClient.employee != null)
                                    'شؤون الموظف': () => PosShell.open(
                                      context,
                                      'شؤون الموظف',
                                      EmployeeScreen(
                                        user: widget.user,
                                        initialProfile: ApiClient.session ?? {},
                                      ),
                                    ),
                                  'تسجيل الخروج': () =>
                                      LogoutButton.logout(context),
                                  'إضافة عميل': _showAddCustomerDialog,
                                  'إضافة هدية': _giftLine,
                                  'بحث فاتورة': () =>
                                      _browseInvoice(search: true),
                                  'الفاتورة السابقة': _browseInvoice,
                                  'الفاتورة التالية': () =>
                                      _browseInvoice(next: true),
                                  'حذف الفاتورة': () =>
                                      _deleteSavedInvoice(_viewedInvoice),
                                  'التكلفة': _showCost,
                                  'التوصيل': _editDelivery,
                                  'خصم نسبة': _editPercentDiscount,
                                  'تعديل الصافي': _editFinalTotal,
                                  'نسخ': _copyInvoice,
                                  'واتساب': _shareWhatsApp,
                                  'PDF': _exportInvoice,
                                  'ملاحظات': _editInvoiceNotes,
                                  'فاتورة جديدة': _newInvoice,
                                  'حفظ': () => _checkout(printReceipt: false),
                                  'حفظ وطباعة': () =>
                                      _checkout(printReceipt: true),
                                  'مرتجعات المبيعات': _showReturnDialog,
                                  'تسجيل مصروف': _showExpenseDialog,
                                  'سند قبض': _showReceiptDialog,
                                  'كشف حساب العميل': _printStatement,
                                  'سجل الفواتير': () => PosShell.open(
                                    context,
                                    'سجل الفواتير',
                                    SalesHistoryScreen(user: widget.user),
                                  ),
                                  if (_activeShift != null)
                                    'إغلاق الوردية': _showCloseShiftDialog,
                                  if (_activeShift == null)
                                    'فتح وردية': () =>
                                        _showOpenShiftDialog(_branchId),
                                  'تحديث الأصناف': _loadData,
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              bottomNavigationBar:
                  review && MediaQuery.sizeOf(context).width >= 1050
                  ? Material(
                      color: const Color(0xFFFEF3C7),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFF92400E),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'توقفت نقطة البيع لحماية عملية سابقة لم يتأكد حفظها. تحقّق من نتيجتها للمتابعة.',
                                  style: TextStyle(
                                    color: Color(0xFF78350F),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => PosShell.open(
                                  context,
                                  'سجل الفواتير',
                                  SalesHistoryScreen(user: widget.user),
                                ),
                                child: const Text('سجل الفواتير'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                key: const Key('pos-review-operation'),
                                onPressed: holdReview
                                    ? _reviewHeld
                                    : _reviewCheckout,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('التحقق من العملية'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : null,
              persistentFooterButtons: MediaQuery.sizeOf(context).width >= 1050
                  ? null
                  : [
                      if (_checkoutRecord?['status'] == 'rejected')
                        TextButton.icon(
                          onPressed: _restoreRejectedCart,
                          icon: const Icon(Icons.restore),
                          label: const Text('استعادة سلة العملية المرفوضة'),
                        ),
                      if (review)
                        TextButton.icon(
                          onPressed: holdReview ? _reviewHeld : _reviewCheckout,
                          icon: const Icon(Icons.warning_amber),
                          label: const Text(
                            'عملية غير محسومة — تحقق قبل البيع',
                          ),
                        ),
                      if (const {
                        'confirmed',
                        'queued',
                      }.contains(_checkoutRecord?['status']))
                        TextButton.icon(
                          onPressed: _reprintLastReceipt,
                          icon: const Icon(Icons.print),
                          label: const Text('إعادة طباعة آخر فاتورة'),
                        ),
                    ],
            ),
            if (_isCheckingOut)
              const Positioned.fill(child: CheckoutLoadingOverlay()),
          ],
        ),
      ),
    );
  }
}
