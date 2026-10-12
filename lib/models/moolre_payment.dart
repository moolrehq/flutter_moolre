/// Ghanaian mobile-money networks supported by native checkout.
enum MoolreNetwork {
  mtn('MTN', '13'),
  telecel('Telecel', '6'),
  at('AT', '7');

  const MoolreNetwork(this.label, this.channel);
  final String label;
  final String channel;
}

enum MoolrePaymentStatus {
  ready('ready'),
  otpRequired('otp_required'),
  pending('pending'),
  succeeded('succeeded'),
  failed('failed'),
  expired('expired');

  const MoolrePaymentStatus(this.value);
  final String value;
}

/// An order-backed session from the direct gateway or a merchant backend.
/// Amounts are integer minor units: 5000 is GHS 50.00.
class MoolrePaymentSession {
  const MoolrePaymentSession({
    required this.id,
    required this.orderId,
    required this.reference,
    required this.amountMinor,
    required this.currency,
    required this.status,
    this.verified = false,
    this.message,
    this.expiresAt,
  });

  final String id;
  final String orderId;
  final String reference;
  final int amountMinor;
  final String currency;
  final MoolrePaymentStatus status;

  /// True only after the gateway verifies provider details against the order.
  final bool verified;
  final String? message;
  final DateTime? expiresAt;

  bool get isSuccessful => status == MoolrePaymentStatus.succeeded && verified;
  bool get isTerminal =>
      status == MoolrePaymentStatus.succeeded ||
      status == MoolrePaymentStatus.failed ||
      status == MoolrePaymentStatus.expired;

  String get amountLabel {
    final whole = amountMinor ~/ 100;
    final fraction = (amountMinor % 100).toString().padLeft(2, '0');
    return '$currency $whole.$fraction';
  }

  factory MoolrePaymentSession.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty || value.length > 200) {
        throw const FormatException('Invalid payment session.');
      }
      return value;
    }

    final amount = json['amountMinor'];
    final currency = requiredString('currency');
    var rawStatus = requiredString('status');
    // Saved by the former in-app sandbox flow; resolved by status lookup now.
    if (rawStatus == 'sandbox_outcome_required') rawStatus = 'pending';
    final statuses = MoolrePaymentStatus.values.where(
      (status) => status.value == rawStatus,
    );
    if (amount is! int ||
        amount <= 0 ||
        amount > 9007199254740991 ||
        currency != 'GHS' ||
        statuses.isEmpty ||
        json['verified'] is! bool ||
        (json['message'] != null && json['message'] is! String)) {
      throw const FormatException('Invalid payment session.');
    }
    final status = statuses.single;
    final verified = json['verified'] as bool;
    if ((status == MoolrePaymentStatus.succeeded) != verified) {
      throw const FormatException('Payment success must be verified.');
    }
    final rawExpiry = json['expiresAt'];
    DateTime? expiry;
    if (rawExpiry != null) {
      if (rawExpiry is! String ||
          (expiry = DateTime.tryParse(rawExpiry)) == null) {
        throw const FormatException('Invalid payment session expiry.');
      }
    }
    final id = requiredString('id');
    if (!isMoolreSessionId(id)) {
      throw const FormatException('Invalid payment session ID.');
    }
    return MoolrePaymentSession(
      id: id,
      orderId: requiredString('orderId'),
      reference: requiredString('reference'),
      amountMinor: amount,
      currency: currency,
      status: status,
      verified: verified,
      message: json['message'] as String?,
      expiresAt: expiry,
    );
  }
}

/// Session IDs are opaque URL-safe identifiers, never paths.
bool isMoolreSessionId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(value);

enum MoolrePaymentOutcome { succeeded, failed, expired, pending, dismissed }

/// Closing checkout is distinct from cancelling an initiated payment.
class MoolrePaymentResult {
  const MoolrePaymentResult({required this.outcome, this.session});
  final MoolrePaymentOutcome outcome;
  final MoolrePaymentSession? session;
  bool get isSuccessful =>
      outcome == MoolrePaymentOutcome.succeeded &&
      session?.isSuccessful == true;
}

class MoolrePaymentException implements Exception {
  const MoolrePaymentException(
    this.code,
    this.message, {
    this.retryable = false,
  });
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => '$code: $message';
}

/// Normalizes Ghanaian local and +233 numbers without guessing the network.
String normalizeMoolrePhoneNumber(String input) {
  var number = input.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  if (number.startsWith('+233')) {
    number = '0${number.substring(4)}';
  } else if (number.startsWith('00233')) {
    number = '0${number.substring(5)}';
  } else if (number.startsWith('233')) {
    number = '0${number.substring(3)}';
  }
  if (!RegExp(r'^0\d{9}$').hasMatch(number)) {
    throw const MoolrePaymentException(
      'INVALID_PHONE',
      'Enter a valid Ghanaian mobile number.',
    );
  }
  return number;
}
