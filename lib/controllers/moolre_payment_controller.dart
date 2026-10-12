import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/moolre_payment.dart';
import '../services/moolre_hosted_checkout_launcher.dart';
import '../services/moolre_payment_service.dart';

enum MoolreCheckoutPhase {
  loading,
  ready,
  submitting,
  otpRequired,

  /// Moolre's hosted payment page is open.
  hostedCheckout,
  pending,
  verifying,
  succeeded,
  failed,
  expired,
  error,
}

/// A UI-independent checkout controller. Call [dispose] when finished.
class MoolrePaymentController extends ChangeNotifier {
  MoolrePaymentController({
    required this.gateway,
    required this.orderId,
    this.resumeSessionId,
    String? idempotencyKey,
    this.onSessionCreated,
    this.pollInterval = const Duration(seconds: 3),
    this.pollingTimeout = const Duration(minutes: 2),
    this.operationTimeout = const Duration(seconds: 30),
    this.hostedCheckoutLauncher = openMoolreHostedCheckout,
  }) : idempotencyKey = idempotencyKey ?? const Uuid().v4() {
    if (orderId.trim().isEmpty ||
        orderId.length > 200 ||
        (resumeSessionId != null && !isMoolreSessionId(resumeSessionId!)) ||
        !RegExp(r'^[\w-]{8,128}$').hasMatch(this.idempotencyKey) ||
        pollInterval <= Duration.zero ||
        pollingTimeout <= Duration.zero ||
        operationTimeout <= Duration.zero) {
      throw ArgumentError(
        'Provide valid order/session IDs, a request key, and positive timeouts.',
      );
    }
  }

  final MoolrePaymentGateway gateway;
  final String orderId;
  final String? resumeSessionId;
  final String idempotencyKey;
  final FutureOr<void> Function(MoolrePaymentSession session)? onSessionCreated;
  final Duration pollInterval;
  final Duration pollingTimeout;

  /// Bounds calls made through custom gateways as well as the HTTP service.
  final Duration operationTimeout;

  /// Shows Moolre's hosted page for gateways that use hosted checkout.
  final MoolreHostedCheckoutLauncher hostedCheckoutLauncher;
  MoolrePaymentSession? _session;
  MoolreCheckoutPhase _phase = MoolreCheckoutPhase.loading;
  MoolrePaymentException? _error;
  Timer? _timer;
  Stopwatch? _pollClock;
  bool _disposed = false;
  bool _busy = false;
  bool _active = true;
  bool _reportedSession = false;
  bool _pollingStopped = false;
  bool _uncertainSubmission = false;

  MoolrePaymentSession? get session => _session;
  MoolreCheckoutPhase get phase => _phase;
  MoolrePaymentException? get error => _error;
  bool get isBusy => _busy;
  bool get pollingStopped => _pollingStopped;
  MoolreHostedCheckoutGateway? get _hosted =>
      gateway is MoolreHostedCheckoutGateway
      ? gateway as MoolreHostedCheckoutGateway
      : null;
  bool get isSandbox => _hosted?.isSandbox == true;
  bool get usesHostedCheckout => _hosted?.usesHostedCheckout == true;

  MoolrePaymentResult get result {
    final value = _session;
    final outcome = switch (value?.status) {
      MoolrePaymentStatus.succeeded when value!.verified =>
        MoolrePaymentOutcome.succeeded,
      MoolrePaymentStatus.failed => MoolrePaymentOutcome.failed,
      MoolrePaymentStatus.expired => MoolrePaymentOutcome.expired,
      MoolrePaymentStatus.pending => MoolrePaymentOutcome.pending,
      _
          when _uncertainSubmission ||
              (value == null && resumeSessionId != null) =>
        MoolrePaymentOutcome.pending,
      _ => MoolrePaymentOutcome.dismissed,
    };
    return MoolrePaymentResult(outcome: outcome, session: value);
  }

  Future<void> initialize() async {
    if (_busy || _disposed) return;
    if (_reportedSession && _session?.isTerminal == true) return;
    _begin(MoolreCheckoutPhase.loading);
    try {
      final existingId = _session?.id ?? resumeSessionId;
      final value = await _call(
        () => existingId == null
            ? gateway.createSession(
                orderId: orderId,
                idempotencyKey: idempotencyKey,
              )
            : gateway.getSession(existingId),
      );
      if (_disposed) return;
      _accept(value);
      _uncertainSubmission = false;
      await _persistSession(value);
    } catch (error) {
      if (_disposed) return;
      _error = _asPaymentError(error);
      _phase = MoolreCheckoutPhase.error;
    } finally {
      _finish();
    }
  }

  Future<void> submitPhone(String phoneNumber, MoolreNetwork network) async {
    if (_busy || _disposed || _phase != MoolreCheckoutPhase.ready) return;
    String normalized;
    try {
      normalized = normalizeMoolrePhoneNumber(phoneNumber);
    } on MoolrePaymentException catch (error) {
      _error = error;
      notifyListeners();
      return;
    }
    await _submit(
      () => gateway.initiatePayment(
        sessionId: _session!.id,
        phoneNumber: normalized,
        network: network,
      ),
    );
  }

  Future<void> submitOtp(String otp) async {
    if (_busy || _disposed || _phase != MoolreCheckoutPhase.otpRequired) return;
    if (!RegExp(r'^\d{4,10}$').hasMatch(otp)) {
      _error = const MoolrePaymentException(
        'INVALID_OTP',
        'Enter the verification code.',
      );
      notifyListeners();
      return;
    }
    await _submit(() => gateway.submitOtp(sessionId: _session!.id, otp: otp));
  }

  /// Opens Moolre's hosted page, then confirms the outcome by status lookup.
  /// Closing or being redirected from the page never proves payment.
  Future<void> openHostedCheckout() async {
    final hosted = _hosted;
    if (_busy ||
        _disposed ||
        hosted == null ||
        !hosted.usesHostedCheckout ||
        _session == null ||
        _session!.isTerminal) {
      return;
    }
    _pollClock = null;
    _pollingStopped = false;
    _uncertainSubmission = true;
    _begin(MoolreCheckoutPhase.submitting);
    try {
      final started = await _call(
        () => hosted.startHostedCheckout(_session!.id),
      );
      if (_disposed) return;
      _accept(started.session);
      final url = started.url;
      if (url != null && !started.session.isTerminal) {
        _phase = MoolreCheckoutPhase.hostedCheckout;
        notifyListeners();
        // The payer may take minutes on the page, so this is not bounded.
        await hostedCheckoutLauncher(url, hosted.hostedReturnUrl);
        if (_disposed) return;
        _phase = MoolreCheckoutPhase.verifying;
        notifyListeners();
        final value = await _call(() => gateway.getSession(_session!.id));
        if (_disposed) return;
        _accept(value);
      }
      _uncertainSubmission = false;
    } catch (error) {
      if (_disposed) return;
      _error = _asPaymentError(error);
      _phase = _session?.status == MoolrePaymentStatus.ready
          ? MoolreCheckoutPhase.ready
          : MoolreCheckoutPhase.pending;
    } finally {
      _finish();
    }
  }

  Future<void> _submit(Future<MoolrePaymentSession> Function() action) async {
    _pollClock = null;
    _pollingStopped = false;
    _uncertainSubmission = true;
    _begin(MoolreCheckoutPhase.submitting);
    try {
      final value = await _call(action);
      if (_disposed) return;
      _accept(value);
      _uncertainSubmission = false;
    } catch (error) {
      if (_disposed) return;
      // A lost HTTP response does not prove the request was rejected.
      // Resolve the durable session before allowing another submission.
      _uncertainSubmission = true;
      _error = _asPaymentError(error);
      _phase = MoolreCheckoutPhase.pending;
    } finally {
      _finish();
    }
  }

  Future<void> refresh({bool restartPolling = true}) async {
    if (_busy || _disposed || _session == null || _session!.isTerminal) return;
    if (!_reportedSession) {
      await initialize();
      return;
    }
    if (restartPolling) {
      _pollClock = Stopwatch()..start();
      _pollingStopped = false;
    }
    _begin(MoolreCheckoutPhase.verifying);
    try {
      final value = await _call(() => gateway.getSession(_session!.id));
      if (_disposed) return;
      _accept(value);
      _uncertainSubmission = false;
    } catch (error) {
      if (_disposed) return;
      _error = _asPaymentError(error);
      _phase = MoolreCheckoutPhase.pending;
    } finally {
      _finish();
    }
  }

  void _accept(MoolrePaymentSession value) {
    final previous = _session;
    if (value.orderId != orderId ||
        (previous == null &&
            resumeSessionId != null &&
            value.id != resumeSessionId) ||
        (previous != null &&
            (value.id != previous.id ||
                value.reference != previous.reference ||
                value.amountMinor != previous.amountMinor ||
                value.currency != previous.currency)) ||
        !isMoolreSessionId(value.id) ||
        value.reference.trim().isEmpty ||
        value.reference.length > 200 ||
        value.amountMinor <= 0 ||
        value.amountMinor > 9007199254740991 ||
        value.currency != 'GHS' ||
        ((value.status == MoolrePaymentStatus.succeeded) != value.verified) ||
        (previous != null &&
            ((previous.isTerminal && value.status != previous.status) ||
                (previous.status != MoolrePaymentStatus.ready &&
                    value.status == MoolrePaymentStatus.ready)))) {
      throw const MoolrePaymentException(
        'SESSION_MISMATCH',
        'The payment details could not be verified.',
      );
    }
    _session = value;
    _phase = switch (value.status) {
      MoolrePaymentStatus.ready => MoolreCheckoutPhase.ready,
      MoolrePaymentStatus.otpRequired => MoolreCheckoutPhase.otpRequired,
      MoolrePaymentStatus.pending => MoolreCheckoutPhase.pending,
      MoolrePaymentStatus.succeeded => MoolreCheckoutPhase.succeeded,
      MoolrePaymentStatus.failed => MoolreCheckoutPhase.failed,
      MoolrePaymentStatus.expired => MoolreCheckoutPhase.expired,
    };
  }

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(operationTimeout);
    } on TimeoutException {
      throw const MoolrePaymentException(
        'REQUEST_TIMEOUT',
        'The request timed out. Check the payment status before trying again.',
        retryable: true,
      );
    }
  }

  Future<void> _persistSession(MoolrePaymentSession value) async {
    if (_reportedSession) return;
    try {
      await Future.sync(
        () => onSessionCreated?.call(value),
      ).timeout(operationTimeout);
      if (!_disposed) _reportedSession = true;
    } catch (_) {
      throw const MoolrePaymentException(
        'SESSION_STORAGE_ERROR',
        'Could not save your payment session. Please try again.',
        retryable: true,
      );
    }
  }

  MoolrePaymentException _asPaymentError(Object error) =>
      error is MoolrePaymentException
      ? error
      : const MoolrePaymentException(
          'PAYMENT_ERROR',
          'Could not complete the request. Please try again.',
          retryable: true,
        );

  void _begin(MoolreCheckoutPhase phase) {
    _timer?.cancel();
    _busy = true;
    _error = null;
    _phase = phase;
    notifyListeners();
  }

  void _finish() {
    if (_disposed) return;
    _busy = false;
    _schedulePoll();
    notifyListeners();
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (!_active || _disposed || _phase != MoolreCheckoutPhase.pending) return;
    _pollClock ??= Stopwatch()..start();
    final remaining = pollingTimeout - _pollClock!.elapsed;
    if (remaining <= Duration.zero) {
      _pollingStopped = true;
      return;
    }
    _timer = Timer(pollInterval < remaining ? pollInterval : remaining, () {
      if (_disposed || !_active) return;
      if (_pollClock!.elapsed >= pollingTimeout) {
        _pollingStopped = true;
        notifyListeners();
      } else {
        unawaited(refresh(restartPolling: false));
      }
    });
  }

  /// Pause polling while the host app is backgrounded.
  void pause() {
    _active = false;
    _timer?.cancel();
  }

  /// Recheck an outstanding session when the host app returns.
  void resume() {
    if (_disposed) return;
    _active = true;
    if (_phase == MoolreCheckoutPhase.pending && !_busy) {
      unawaited(refresh());
    } else {
      _schedulePoll();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
