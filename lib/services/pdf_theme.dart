import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

abstract final class PdfTheme {
  static Future<pw.ThemeData>? _theme;
  static Future<pw.ThemeData> load() => _theme ??= _load();

  static Future<pw.ThemeData> _load() async {
    final fonts = await Future.wait([
      rootBundle.load('assets/fonts/Amiri-Regular.ttf'),
      rootBundle.load('assets/fonts/Amiri-Bold.ttf'),
      rootBundle.load('assets/fonts/NotoSansHebrew-Regular.ttf'),
    ]);
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts[0]),
      bold: pw.Font.ttf(fonts[1]),
      fontFallback: [pw.Font.ttf(fonts[2])],
    );
  }
}
