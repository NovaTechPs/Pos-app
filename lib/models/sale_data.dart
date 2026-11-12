/// Parsing and pricing rules shared by the catalog, cart and saved invoices.
abstract final class SaleData {
  static final _localizedDigits = RegExp('[٠-٩۰-۹]');
  static double? number(Object? value) {
    if (value is num) {
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }
    if (value == null) return null;
    final text = '$value'.trim().replaceAll('٫', '.').replaceAllMapped(
      _localizedDigits,
      (match) {
        final code = match[0]!.codeUnitAt(0);
        return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
      },
    );
    final parsed = double.tryParse(text);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int? id(Object? value) =>
      value is int ? value : int.tryParse('$value');

  static double? retailPrice(Map<dynamic, dynamic> product, int branchId) {
    final branches = product['branches'];
    if (branches is List) {
      for (final branch in branches.whereType<Map>()) {
        final pivot = branch['pivot'];
        if (pivot is! Map) continue;
        final priceBranch = id(pivot['branch_id'] ?? branch['id']);
        if (priceBranch == branchId) {
          final price = number(pivot['retail_price']);
          return price != null && price >= 0 ? price : null;
        }
      }
      // Never borrow a price belonging to a different branch.
      if (branches.isNotEmpty) return null;
    }
    final price = number(product['retail_price']);
    return price != null && price >= 0 ? price : null;
  }

  static double offerTotal(
    double quantity,
    double price,
    double offerQuantity,
    double? offerPrice,
  ) {
    if (offerQuantity <= 0 ||
        offerPrice == null ||
        offerPrice < 0 ||
        offerPrice >= offerQuantity * price) {
      return double.parse((quantity * price).toStringAsFixed(2));
    }
    final bundles = (quantity / offerQuantity).floor();
    final remainder = double.parse(
      (quantity - bundles * offerQuantity).toStringAsFixed(6),
    );
    return double.parse(
      (bundles * offerPrice + remainder * price).toStringAsFixed(2),
    );
  }

  static bool hasOffer(Map line) =>
      line['gift'] != true &&
      line['price_manual'] != true &&
      (number(line['offer_quantity']) ?? 0) > 0 &&
      number(line['offer_price']) != null;

  static void applyOffers(List<Map<String, dynamic>> lines) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final line in lines) {
      line.remove('promotion_total');
      if (!hasOffer(line)) continue;
      final key =
          '${line['product_id']}|${line['price']}|${line['offer_quantity']}|${line['offer_price']}';
      (groups[key] ??= []).add(line);
    }
    for (final group in groups.values) {
      final quantity = group.fold<double>(
        0,
        (sum, line) => sum + number(line['quantity'])!,
      );
      final first = group.first;
      final total = offerTotal(
        quantity,
        number(first['price'])!,
        number(first['offer_quantity'])!,
        number(first['offer_price']),
      );
      var allocatedQuantity = 0.0;
      var allocatedTotal = 0.0;
      for (final line in group) {
        allocatedQuantity += number(line['quantity'])!;
        final cumulative = double.parse(
          (total * allocatedQuantity / quantity).toStringAsFixed(2),
        );
        line['promotion_total'] = double.parse(
          (cumulative - allocatedTotal).toStringAsFixed(2),
        );
        allocatedTotal = cumulative;
      }
    }
  }

  static double lineTotal(Map<dynamic, dynamic> line) {
    final price = number(line['price']);
    final discount = number(line['discount'] ?? 0);
    final quantity = number(line['quantity']);
    if (price == null ||
        discount == null ||
        quantity == null ||
        price < 0 ||
        discount < 0 ||
        discount > price ||
        quantity <= 0) {
      throw const FormatException('بيانات أحد أصناف الفاتورة غير صالحة');
    }
    final promotion = number(line['promotion_total']);
    return promotion ??
        double.parse(((price - discount) * quantity).toStringAsFixed(2));
  }

  /// The POS API requires one entry per product_id. Never average different prices.
  static List<Map<String, dynamic>> uniqueItems(
    List<Map<String, dynamic>> lines, {
    bool supportsGiftLines = false,
  }) {
    if (supportsGiftLines) {
      final items = <Map<String, dynamic>>[];
      final offers = <String, Map<String, dynamic>>{};
      for (final line in lines) {
        lineTotal(line);
        final productId = id(line['product_id']);
        if (productId == null || productId <= 0) {
          throw const FormatException('معرّف أحد الأصناف غير صالح.');
        }
        final item = <String, dynamic>{
          'product_id': productId,
          'quantity': number(line['quantity'])!,
          'price': number(line['price'])! - number(line['discount'] ?? 0)!,
          'is_gift': line['gift'] == true,
        };
        if (hasOffer(line)) {
          final key =
              '$productId|${line['price']}|${line['offer_quantity']}|${line['offer_price']}';
          final existing = offers[key];
          if (existing != null) {
            existing['quantity'] += item['quantity'];
            continue;
          }
          item['use_offer'] = true;
          offers[key] = item;
        }
        items.add(item);
      }
      return items;
    }
    final grouped = <int, Map<String, dynamic>>{};
    final totals = <int, double>{};
    for (final line in lines) {
      final productId = id(line['product_id']);
      if (productId == null || productId <= 0) {
        throw const FormatException('معرّف أحد الأصناف غير صالح.');
      }
      final total = lineTotal(line);
      final price = number(line['price'])! - number(line['discount'] ?? 0)!;
      final quantity = number(line['quantity'])!;
      final existing = grouped[productId];
      if (existing != null && existing['price'] != price) {
        throw const FormatException(
          'الصنف مكرر بأسعار مختلفة أو كهدية وصنف مدفوع. الخادم يقبل سعراً واحداً لكل صنف؛ وحّد السعر أو ضع الهدية في فاتورة مستقلة.',
        );
      }
      grouped[productId] = {
        'product_id': productId,
        'price': price,
        'quantity': (number(existing?['quantity']) ?? 0) + quantity,
      };
      totals[productId] = (totals[productId] ?? 0) + total;
    }
    for (final entry in grouped.entries) {
      if ((lineTotal(entry.value) * 100).round() !=
          (totals[entry.key]! * 100).round()) {
        throw const FormatException(
          'تجميع الكميات الكسرية يغيّر التقريب. اجمع كمية الصنف في سطر واحد ثم احفظ.',
        );
      }
    }
    return grouped.values.toList(growable: false);
  }

  static List<Map<String, dynamic>> heldLines(Map<dynamic, dynamic> order) {
    final raw = order['items'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('الفاتورة المعلقة لا تحتوي أصنافاً صالحة');
    }
    return raw.map((item) {
      if (item is! Map || id(item['product_id']) == null) {
        throw const FormatException('تعذر قراءة صنف الفاتورة المعلقة');
      }
      final line = <String, dynamic>{
        'product_id': id(item['product_id']),
        'name': item['product']?['name'] ?? item['name'] ?? 'منتج',
        // unit_price is the effective price sent when the draft was saved.
        'price': number(item['unit_price'] ?? item['price']),
        'quantity': number(item['quantity']),
        'unit': item['unit'] ?? 'قطعة',
        'discount': 0.0,
        'gift': item['is_gift'] == true,
        'cost_price': item['cost_price'],
        'offer_quantity': item['offer_quantity'],
        'offer_price': item['offer_price'],
      };
      final originalTotal = number(item['total_price']);
      if (originalTotal != null &&
          !hasOffer(line) &&
          number(line['quantity']) != null &&
          number(line['quantity'])! > 0 &&
          (lineTotal(line) - originalTotal).abs() > .005) {
        line['price'] = originalTotal / number(line['quantity'])!;
        line['price_manual'] = true;
      }
      lineTotal(line);
      return line;
    }).toList();
  }
}
