import 'dart:convert';
import 'dart:io';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'package:path_provider/path_provider.dart';

class FilePaymentStorage implements MoolrePaymentStorage {
  FilePaymentStorage(this.file);
  final File file;
  Map<String, dynamic>? _records;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  static Future<FilePaymentStorage> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return FilePaymentStorage(File('${directory.path}/moolre-payments.json'));
  }

  Future<void> _load() async {
    if (_records != null) return;
    _initializing ??= _initializeRecords();
    await _initializing;
  }

  Future<void> _initializeRecords() async {
    if (!await file.exists()) {
      _records = {};
      return;
    }
    if (await file.length() > 4 * 1024 * 1024) {
      throw const FormatException('Saved checkout is too large.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved checkout.');
    }
    _records = decoded;
  }

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    await _writes;
    await _load();
    final value = _records![key];
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) {
    final result = _writes.then((_) async {
      await _load();
      final next = {..._records!, key: value};
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(next), flush: true);
      await temporary.rename(file.path);
      _records = next;
    });
    _writes = result.catchError((Object _) {});
    return result;
  }
}
