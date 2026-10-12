import 'dart:async';
import 'package:flutter_moolre/flutter_moolre.dart';

class FakeGateway implements MoolrePaymentGateway, MoolreHostedCheckoutGateway {
  bool sandbox = false;
  int hostedStarts = 0;
  Uri? hostedUrl = Uri.parse('https://sandbox.moolre.com/checkout_code');
  @override
  bool get isSandbox => sandbox;
  @override
  bool get usesHostedCheckout => sandbox;
  @override
  Uri get hostedReturnUrl => Uri.parse('https://example.invalid/return');
  @override
  Future<MoolreHostedCheckout> startHostedCheckout(String sessionId) async {
    hostedStarts++;
    if (status == MoolrePaymentStatus.ready) {
      status = MoolrePaymentStatus.pending;
    }
    return MoolreHostedCheckout(session: session, url: hostedUrl);
  }

  MoolrePaymentStatus status = MoolrePaymentStatus.ready;
  bool verified = false;
  int creates = 0;
  int initiations = 0;
  int otpSubmissions = 0;
  int checks = 0;
  bool requireOtp = true;
  Object? initiationError;
  Completer<MoolrePaymentSession>? initiationCompleter;
  Completer<MoolrePaymentSession>? creationCompleter;
  Completer<MoolrePaymentSession>? checkCompleter;
  String? receivedPhone;
  String? receivedKey;
  String? receivedSessionId;
  MoolrePaymentSession? overrideSession;

  MoolrePaymentSession get session =>
      overrideSession ??
      MoolrePaymentSession(
        id: 'session_001',
        orderId: 'order_001',
        reference: 'reference_001',
        amountMinor: 5000,
        currency: 'GHS',
        status: status,
        verified: verified,
      );
  @override
  Future<MoolrePaymentSession> createSession({
    required String orderId,
    required String idempotencyKey,
  }) async {
    creates++;
    receivedKey = idempotencyKey;
    return creationCompleter == null ? session : creationCompleter!.future;
  }

  @override
  Future<MoolrePaymentSession> initiatePayment({
    required String sessionId,
    required String phoneNumber,
    required MoolreNetwork network,
  }) async {
    initiations++;
    receivedPhone = phoneNumber;
    if (initiationError != null) throw initiationError!;
    if (initiationCompleter != null) return initiationCompleter!.future;
    status = requireOtp
        ? MoolrePaymentStatus.otpRequired
        : MoolrePaymentStatus.pending;
    return session;
  }

  @override
  Future<MoolrePaymentSession> submitOtp({
    required String sessionId,
    required String otp,
  }) async {
    otpSubmissions++;
    status = MoolrePaymentStatus.pending;
    return session;
  }

  @override
  Future<MoolrePaymentSession> getSession(String sessionId) async {
    checks++;
    receivedSessionId = sessionId;
    return checkCompleter == null ? session : checkCompleter!.future;
  }
}
