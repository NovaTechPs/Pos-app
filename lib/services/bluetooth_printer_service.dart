import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

class BluetoothPrinterService {
  static const channel = MethodChannel('waslapos/bluetooth_print');
  static const prefix = 'bluetooth:';

  Future<List<Printer>> printers() async {
    final builtIn =
        await channel.invokeMethod<bool>('builtInAvailable') ?? false;
    List<dynamic>? devices;
    try {
      devices = await channel.invokeListMethod<dynamic>('pairedDevices');
    } on PlatformException {
      if (!builtIn) rethrow;
    }
    return [
      if (builtIn)
        const Printer(
          url: '${prefix}internal-q6',
          name: 'Q6 Pro — الطابعة المدمجة 58 مم',
        ),
      ...(devices ?? []).map((value) {
        final device = Map<String, dynamic>.from(value as Map);
        return Printer(
          url: '$prefix${device['address']}',
          name: '${device['name']} (Bluetooth)',
        );
      }),
    ];
  }

  Future<void> printPdf(Printer printer, Uint8List bytes, int width) async {
    final builtIn = printer.url == '${prefix}internal-q6';
    await channel.invokeMethod<void>(builtIn ? 'printBuiltIn' : 'printPdf', {
      'address': printer.url.substring(prefix.length),
      'bytes': bytes,
      'width': builtIn ? 384 : width,
    });
  }
}
