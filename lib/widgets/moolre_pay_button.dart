import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/moolre_payment.dart';
import '../screens/moolre_checkout_screen.dart';
import '../services/moolre_payment_service.dart';

class MoolrePayButton extends StatefulWidget {
  const MoolrePayButton({
    super.key,
    required this.gateway,
    required this.orderId,
    this.resumeSessionId,
    this.idempotencyKey,
    this.onSessionCreated,
    this.onSuccess,
    this.onError,
    this.onResult,
    this.style,
    this.checkoutNotice,
  });

  final MoolrePaymentGateway gateway;
  final String orderId;
  final String? resumeSessionId;

  /// Persist a stable key for retries that happen before a session is returned.
  final String? idempotencyKey;
  final FutureOr<void> Function(MoolrePaymentSession)? onSessionCreated;
  final ValueChanged<String>? onSuccess;
  final void Function(String code, String message)? onError;
  final ValueChanged<MoolrePaymentResult>? onResult;
  final ButtonStyle? style;

  /// Visible throughout checkout, for example to identify sandbox payments.
  final String? checkoutNotice;

  @override
  State<MoolrePayButton> createState() => _MoolrePayButtonState();
}

class _MoolrePayButtonState extends State<MoolrePayButton> {
  bool _processing = false;
  String? _sessionId;
  late String _requestKey;
  int _configurationRevision = 0;
  final Set<String> _completedSessions = {};

  @override
  void initState() {
    super.initState();
    _resetSession();
  }

  void _resetSession() {
    _sessionId = widget.resumeSessionId;
    _requestKey = widget.idempotencyKey ?? const Uuid().v4();
  }

  @override
  void didUpdateWidget(covariant MoolrePayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.gateway != widget.gateway) {
      _completedSessions.clear();
    }
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.idempotencyKey != widget.idempotencyKey ||
        (oldWidget.resumeSessionId != widget.resumeSessionId &&
            widget.resumeSessionId != _sessionId)) {
      _configurationRevision++;
      _resetSession();
    }
  }

  Future<void> _pay() async {
    if (_processing) return;
    setState(() => _processing = true);
    final orderId = widget.orderId;
    final gateway = widget.gateway;
    final revision = _configurationRevision;
    final sessionCreated = widget.onSessionCreated;
    final onSuccess = widget.onSuccess;
    final onError = widget.onError;
    final onResult = widget.onResult;
    MoolrePaymentResult? result;
    MoolrePaymentException? failure;
    try {
      result = await showMoolreCheckout(
        context: context,
        gateway: gateway,
        orderId: orderId,
        resumeSessionId: _sessionId,
        idempotencyKey: _requestKey,
        notice: widget.checkoutNotice,
        onSessionCreated: (session) async {
          if (mounted && _configurationRevision == revision) {
            _sessionId = session.id;
          }
          await sessionCreated?.call(session);
        },
      );
      if (mounted &&
          _configurationRevision == revision &&
          (result.outcome == MoolrePaymentOutcome.failed ||
              result.outcome == MoolrePaymentOutcome.expired) &&
          widget.idempotencyKey == null &&
          widget.resumeSessionId == null) {
        _sessionId = null;
        _requestKey = const Uuid().v4();
      }
    } catch (error) {
      failure = error is MoolrePaymentException
          ? error
          : const MoolrePaymentException(
              'CHECKOUT_ERROR',
              'Could not open the payment sheet.',
            );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (!mounted) return;
    final checkoutFailure = failure;
    final completedResult = result;
    // Consumer callbacks run outside the transport catch, after the sheet
    // closes. A callback exception is never misreported as a payment failure.
    if (checkoutFailure != null) {
      _notify(
        () => onError?.call(checkoutFailure.code, checkoutFailure.message),
      );
    } else if (completedResult != null) {
      if (completedResult.session?.isTerminal == true &&
          widget.orderId == orderId &&
          widget.gateway == gateway &&
          !_completedSessions.add(completedResult.session!.id)) {
        return;
      }
      if (completedResult.isSuccessful) {
        _notify(() => onSuccess?.call(completedResult.session!.reference));
      } else if (completedResult.outcome == MoolrePaymentOutcome.failed ||
          completedResult.outcome == MoolrePaymentOutcome.expired) {
        _notify(
          () => onError?.call(
            completedResult.outcome.name.toUpperCase(),
            completedResult.session?.message ?? 'Payment was not completed.',
          ),
        );
      }
      _notify(() => onResult?.call(completedResult));
    }
  }

  void _notify(VoidCallback callback) {
    try {
      callback();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_moolre',
          context: ErrorDescription('while notifying a checkout result'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ElevatedButton(
    style:
        widget.style ??
        ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF142A4A),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
    onPressed: _processing ? null : _pay,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/moolre_logo.png',
          package: 'flutter_moolre',
          width: 24,
          height: 24,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(_processing ? 'Payment in progress' : 'Pay with Moolre'),
        ),
      ],
    ),
  );
}
