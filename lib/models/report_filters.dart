/// The filters of the web «مركز التقارير», and which of them each report shows.
class ReportFilters {
  ReportFilters({required this.from, required this.to});

  static const partyReports = {
    'statement',
    'balances',
    'aging',
    'cashflow',
    'customer-invoice-profit',
  };
  static const productReports = {
    'product-history',
    'product-sales',
    'product-profit',
    'movements',
    'movement-summary',
    'inventory',
    'stagnant',
    'expiring',
  };
  static const searchReports = {
    'balances',
    'aging',
    'cashflow',
    'expenses',
    ...productReports,
  };
  static const partyTypeReports = {'balances', 'aging'};
  static const voucherTypeReports = {'cashflow', 'daily-cash'};
  static const paymentMethodReports = {'cashflow', 'daily-cash', 'expenses'};
  static const sourceReports = {
    'sales',
    'product-sales',
    'product-profit',
    'customer-invoice-profit',
    'customer-profit',
    'profit',
    'shifts',
    'tax',
    'branches',
  };
  static const productViewReports = {'product-sales', 'product-profit'};
  static const costMethodReports = {
    'profit',
    'product-profit',
    'customer-invoice-profit',
    'customer-profit',
  };

  static const partyTypes = {
    'all': 'الجميع',
    'customer': 'زبون',
    'supplier': 'مورد',
    'both': 'زبون ومورد',
  };
  static const balanceSides = {
    'all': 'مدين ودائن معاً',
    'debit': 'مدين / لنا',
    'credit': 'دائن / علينا',
    'settled': 'مسدد',
  };
  static const voucherTypes = {
    '': 'قبض وصرف',
    'receipt': 'قبض فقط',
    'payment': 'صرف فقط',
  };
  static const paymentMethods = {
    '': 'كل الطرق',
    'cash': 'نقدي',
    'card': 'بطاقة',
    'bank_transfer': 'تحويل',
    'cheque': 'شيك',
  };
  static const salesInvoiceScopes = {
    '': 'فواتير الزبون العام',
    'customer': 'فواتير مربوطة بزبون',
    'all': 'كل الفواتير',
  };
  static const posInvoiceScopes = {
    '': 'كل الفواتير',
    'walk_in': 'فواتير الزبون العام',
    'customer': 'فواتير مربوطة بزبون',
  };
  static const sources = {
    '': 'الكل',
    'pos': 'نقطة البيع (زبون نقدي)',
    'web': 'فواتير المبيعات (تشمل فواتير نقطة البيع لزبون)',
    'api': 'التطبيق / API',
    'online': 'المتجر الإلكتروني',
  };
  static const saleKinds = {'': 'الكل', 'retail': 'مفرق', 'wholesale': 'جملة'};
  static const productViews = {'summary': 'إجمالي', 'detailed': 'تفصيلي'};
  static const costMethods = {
    'recorded': 'التكلفة المسجلة وقت البيع',
    'latest_purchase': 'آخر سعر شراء',
    'weighted_average': 'متوسط أسعار الشراء المرجّح بالكميات',
  };
  static const stockFilters = {
    'all': 'الكل',
    'low': 'أقل من حد التنبيه',
    'zero': 'نافد',
    'negative': 'رصيد سالب',
  };

  DateTime from, to;
  int? branchId;
  int? partyId;
  String? partyName;
  int? productId;
  String? productName;
  String search = '';
  String partyType = 'all';
  String balanceSide = 'all';
  String stockFilter = 'all';
  String source = '';
  String saleKind = '';
  String invoiceScope = '';
  String costMethod = 'recorded';
  String productView = 'summary';
  String voucherType = '';
  String paymentMethod = '';

  static String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// The web quick periods, keyed by their button label.
  static Map<String, (DateTime, DateTime)> periods(DateTime now) {
    final today = _day(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastMonthEnd = DateTime(today.year, today.month, 0);
    return {
      'اليوم': (today, today),
      'أمس': (yesterday, yesterday),
      'هذا الشهر': (DateTime(today.year, today.month), today),
      'الشهر السابق': (
        DateTime(lastMonthEnd.year, lastMonthEnd.month),
        lastMonthEnd,
      ),
      'آخر 30 يوم': (today.subtract(const Duration(days: 29)), today),
    };
  }

  /// Fresh filters for [report], as the web resets them when another report is picked:
  /// this month, or the next 30 days for the expiry report.
  factory ReportFilters.forReport(
    String report,
    DateTime now, {
    int? branchId,
  }) {
    final today = _day(now);
    return ReportFilters(
      from: DateTime(today.year, today.month),
      to: report == 'expiring' ? today.add(const Duration(days: 30)) : today,
    )..branchId = branchId;
  }

  /// Sets one date and keeps the other in order, as the web does.
  void setFrom(DateTime value) {
    from = _day(value);
    if (to.isBefore(from)) to = from;
  }

  void setTo(DateTime value) {
    to = _day(value);
    if (from.isAfter(to)) from = to;
  }

  static bool showsCostMethod(String report, {required bool canSeeProfit}) =>
      costMethodReports.contains(report) ||
      (report == 'product-sales' && canSeeProfit);

  /// The query the API takes, with only the filters [report] shows.
  Map<String, String> query(String report, {bool canSeeProfit = false}) => {
    'from': date(from),
    'to': date(to),
    if (branchId != null) 'branch_id': '$branchId',
    if (partyReports.contains(report) && partyId != null)
      'party_id': '$partyId',
    if (productReports.contains(report) && productId != null)
      'product_id': '$productId',
    if (searchReports.contains(report) && search.trim().isNotEmpty)
      'search': search.trim(),
    if (partyTypeReports.contains(report)) ...{
      'party_type': partyType,
      'balance_side': balanceSide,
    },
    if (voucherTypeReports.contains(report) && voucherType.isNotEmpty)
      'voucher_type': voucherType,
    if (paymentMethodReports.contains(report) && paymentMethod.isNotEmpty)
      'payment_method': paymentMethod,
    if ((report == 'sales' || report == 'pos-invoices') &&
        invoiceScope.isNotEmpty)
      'invoice_scope': invoiceScope,
    if (sourceReports.contains(report)) ...{
      if (source.isNotEmpty) 'source': source,
      if (saleKind.isNotEmpty) 'sale_kind': saleKind,
    },
    if (productViewReports.contains(report)) 'product_view': productView,
    if (showsCostMethod(report, canSeeProfit: canSeeProfit))
      'cost_method': costMethod,
    if (report == 'inventory') 'stock_filter': stockFilter,
  };
}
