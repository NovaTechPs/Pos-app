abstract final class InvoiceReference {
  /// A short printed reference; the complete server reference stays in storage.
  static String receipt(Map<String, dynamic> order) {
    final reference = display(order);
    if (order['offline_pending'] == true || reference.length <= 12) {
      return reference;
    }
    final serverId = '${order['id'] ?? ''}'.trim();
    if (RegExp(r'^\d+$').hasMatch(serverId)) return serverId;
    // Without a server ID, retain the real reference rather than invent a number.
    return reference;
  }

  static String display(Map<String, dynamic> order) {
    final number = '${order['invoice_number'] ?? order['id'] ?? '—'}';
    // Keep old queued receipts printable without changing their sync identity.
    if (order['offline_pending'] == true &&
        RegExp(
          r'^OFF-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(number)) {
      final uuid = number.substring(4).replaceAll('-', '');
      final short = (BigInt.parse(uuid, radix: 16) % BigInt.from(1000000))
          .toInt();
      return 'OFF${short.toString().padLeft(6, '0')}';
    }
    return number;
  }
}
