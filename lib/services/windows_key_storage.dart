import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// Windows DPAPI records, individually replaced and processed off the UI isolate.
/// The previous encrypted map is read once, preserved, and shadowed by new records.
class WindowsKeyStorage extends FlutterSecureStoragePlatform {
  WindowsKeyStorage._(this._worker);
  final SendPort _worker;

  static Future<void> install() async {
    if (!Platform.isWindows) return;
    final directory = await getApplicationSupportDirectory();
    FlutterSecureStoragePlatform.instance = await open(directory.path);
  }

  static Future<WindowsKeyStorage> open(String directory) async {
    final ready = ReceivePort();
    await Isolate.spawn(_serveStorage, [ready.sendPort, directory]);
    final result = await ready.first;
    ready.close();
    if (result is! SendPort) {
      throw StateError('تعذر فتح التخزين المشفر: $result');
    }
    return WindowsKeyStorage._(result);
  }

  Future<dynamic> _request(String command, [String? key, String? value]) async {
    final reply = ReceivePort();
    _worker.send([reply.sendPort, command, key, value]);
    final result = await reply.first as List;
    reply.close();
    if (result[0] != true) {
      throw StateError('تعذر تنفيذ التخزين المشفر: ${result[1]}');
    }
    return result[1];
  }

  Future<void> close() async => await _request('close');

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => await _request('read', key) as String?;
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => await _request('write', key, value);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => await _request('delete', key);
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => await read(key: key, options: options) != null;
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map<String, String>.from(await _request('all') as Map);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      await _request('clear');
}

Future<void> _serveStorage(List<dynamic> arguments) async {
  final ready = arguments[0] as SendPort;
  final requests = ReceivePort();
  late final _KeyFiles files;
  try {
    files = _KeyFiles(arguments[1] as String);
    await files.initialize();
    ready.send(requests.sendPort);
  } catch (error) {
    ready.send(error.toString());
    requests.close();
    return;
  }
  await for (final raw in requests) {
    final message = raw as List;
    final reply = message[0] as SendPort;
    final command = message[1] as String;
    try {
      dynamic result;
      switch (command) {
        case 'read':
          result = await files.read(message[2] as String);
        case 'write':
          await files.write(message[2] as String, message[3] as String);
        case 'delete':
          await files.write(message[2] as String, null);
        case 'all':
          result = await files.all();
        case 'clear':
          for (final key in (await files.all()).keys) {
            await files.write(key, null);
          }
        case 'close':
          requests.close();
        default:
          throw ArgumentError('Unknown storage command');
      }
      reply.send([true, result]);
    } catch (error) {
      // Corrupt financial records remain errors; never delete or fall back silently.
      reply.send([false, error.toString()]);
    }
  }
}

class _KeyFiles {
  _KeyFiles(this.root);
  final String root;
  late final Directory directory = Directory('$root/wasla_secure_records_v1');
  Future<Map<String, String>>? _legacy;

  Future<void> initialize() async {
    await directory.create(recursive: true);
  }

  Future<Map<String, String>> _legacyData() => _legacy ??= _loadLegacy();

  Future<Map<String, String>> _loadLegacy() async {
    final legacy = File('$root/flutter_secure_storage.dat');
    if (await legacy.exists()) {
      return Map<String, String>.from(
        jsonDecode(utf8.decode(windowsUnprotect(await legacy.readAsBytes())))
            as Map,
      );
    }
    return {};
  }

  File _file(String key) =>
      File('${directory.path}/${sha256.convert(utf8.encode(key))}.dat');

  Future<Map<String, dynamic>> _record(File file) async {
    final record = jsonDecode(
      utf8.decode(windowsUnprotect(await file.readAsBytes())),
    );
    if (record is! Map ||
        record['key'] is! String ||
        (record['value'] != null && record['value'] is! String) ||
        !record.containsKey('value') ||
        _file(record['key'] as String).absolute.uri != file.absolute.uri) {
      throw const FormatException('سجل مشفر غير صالح');
    }
    return Map<String, dynamic>.from(record);
  }

  Future<String?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return (await _legacyData())[key];
    return (await _record(file))['value'] as String?;
  }

  Future<void> write(String key, String? value) async {
    final file = _file(key);
    final temporary = File('${file.path}.$pid.${Isolate.current.hashCode}.tmp');
    try {
      final bytes = windowsProtect(
        utf8.encode(jsonEncode({'key': key, 'value': value})),
      );
      await temporary.writeAsBytes(bytes, flush: true);
      // Atomic replacement also preserves the old record if encryption/write fails.
      using((arena) {
        final result = MoveFileEx(
          PCWSTR(temporary.path.toNativeUtf16(allocator: arena)),
          PCWSTR(file.path.toNativeUtf16(allocator: arena)),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        );
        if (!result.value) throw WindowsException(result.error.toHRESULT());
      });
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Map<String, String>> all() async {
    final records = Map<String, String>.from(await _legacyData());
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.dat')) continue;
      final record = await _record(entry);
      final key = record['key'] as String;
      final value = record['value'] as String?;
      if (value == null) {
        records.remove(key);
      } else {
        records[key] = value;
      }
    }
    return records;
  }
}

/// Current Windows user's DPAPI protection; no plaintext keys or values on disk.
Uint8List windowsProtect(List<int> bytes) => _crypt(bytes, protect: true);
Uint8List windowsUnprotect(List<int> bytes) => _crypt(bytes, protect: false);

Uint8List _crypt(List<int> bytes, {required bool protect}) => using((arena) {
  final input = arena<Uint8>(bytes.length);
  input.asTypedList(bytes.length).setAll(0, bytes);
  final source = arena<CRYPT_INTEGER_BLOB>()
    ..ref.cbData = bytes.length
    ..ref.pbData = input;
  final output = arena<CRYPT_INTEGER_BLOB>();
  final result = protect
      ? CryptProtectData(source, null, null, null, 0, output)
      : CryptUnprotectData(source, null, null, null, 0, output);
  if (!result.value) throw WindowsException(result.error.toHRESULT());
  try {
    return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
  } finally {
    LocalFree(HLOCAL(output.ref.pbData.cast()));
  }
});
