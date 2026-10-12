/// Local payment recovery, independent of any merchant backend.
/// Implementations must finish writing before returning and preserve failures.
abstract class MoolrePaymentStorage {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
}
