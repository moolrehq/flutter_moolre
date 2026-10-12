import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/moolre_payment_controller.dart';
import '../models/moolre_payment.dart';
import '../services/moolre_payment_service.dart';

/// Opens a native payment sheet and closes only its own route.
///
/// Persist the session in [onSessionCreated] to resume after app termination.
/// A dismissed pending session can still complete on the payment network.
Future<MoolrePaymentResult> showMoolreCheckout({
  required BuildContext context,
  required MoolrePaymentGateway gateway,
  required String orderId,
  String? resumeSessionId,
  String? idempotencyKey,
  FutureOr<void> Function(MoolrePaymentSession)? onSessionCreated,
  Duration pollInterval = const Duration(seconds: 3),
  Duration pollingTimeout = const Duration(minutes: 2),
  Duration operationTimeout = const Duration(seconds: 30),
  String? notice,
}) async {
  final controller = MoolrePaymentController(
    gateway: gateway,
    orderId: orderId,
    resumeSessionId: resumeSessionId,
    idempotencyKey: idempotencyKey,
    onSessionCreated: onSessionCreated,
    pollInterval: pollInterval,
    pollingTimeout: pollingTimeout,
    operationTimeout: operationTimeout,
  );
  try {
    final result = await showModalBottomSheet<MoolrePaymentResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          MoolreCheckoutScreen(controller: controller, notice: notice),
    );
    // System back can return null; use the latest authoritative session.
    return result ?? controller.result;
  } finally {
    controller.dispose();
  }
}

/// Native checkout content. The caller owns [controller] when used directly.
class MoolreCheckoutScreen extends StatefulWidget {
  const MoolreCheckoutScreen({
    super.key,
    required this.controller,
    this.notice,
  });
  final MoolrePaymentController controller;
  final String? notice;

  @override
  State<MoolreCheckoutScreen> createState() => _MoolreCheckoutScreenState();
}

class _MoolreCheckoutScreenState extends State<MoolreCheckoutScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  MoolreNetwork? _network;

  MoolrePaymentController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.initialize());
  }

  @override
  void didUpdateWidget(covariant MoolreCheckoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.pause();
      _phone.clear();
      _otp.clear();
      _network = null;
      unawaited(_controller.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
    } else {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.pause();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_controller.result);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/moolre_logo.png',
                          package: 'flutter_moolre',
                          width: 28,
                          height: 28,
                          excludeFromSemantics: true,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pay with Moolre',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close payment sheet',
                          onPressed: _close,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (widget.notice?.trim().isNotEmpty == true) ...[
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.notice!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_controller.session != null) ...[
                      Text('Payment amount', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        _controller.session!.amountLabel,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    ..._content(theme),
                    if (_controller.error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _controller.error!.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    switch (_controller.phase) {
      case MoolreCheckoutPhase.loading:
        return const [
          LinearProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading payment details…'),
        ];
      case MoolreCheckoutPhase.ready:
        return _controller.usesHostedCheckout
            ? _hostedStart(theme)
            : [_phoneForm()];
      case MoolreCheckoutPhase.otpRequired:
        return [_otpForm(theme)];
      case MoolreCheckoutPhase.hostedCheckout:
        return [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: const Text(
              'Complete the payment on the Moolre page.',
              textAlign: TextAlign.center,
            ),
          ),
        ];
      case MoolreCheckoutPhase.submitting:
        return [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: const Text('Sending your request. Please wait…'),
          ),
        ];
      case MoolreCheckoutPhase.pending:
      case MoolreCheckoutPhase.verifying:
        return [
          Icon(Icons.phone_android, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _controller.isSandbox
                  ? 'Sandbox payment pending'
                  : _controller.pollingStopped
                  ? 'Still waiting for approval'
                  : 'Approve the payment on your phone',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _controller.isSandbox
                ? (_controller.session?.message ??
                      'Waiting for Moolre to confirm this test payment.')
                : 'Follow the mobile-money prompt on your phone to approve payment.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (!_controller.pollingStopped) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          const Text(
            'Waiting for payment confirmation.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _controller.isBusy
                ? null
                : () => unawaited(_controller.refresh()),
            child: const Text('Check payment status'),
          ),
          const SizedBox(height: 12),
          if (_controller.usesHostedCheckout) ...[
            FilledButton(
              onPressed: _controller.isBusy
                  ? null
                  : () => unawaited(_controller.openHostedCheckout()),
              child: const Text('Reopen Moolre payment page'),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'You can close this sheet. Your payment can still complete.',
            textAlign: TextAlign.center,
          ),
        ];
      case MoolreCheckoutPhase.succeeded:
        return _terminal(
          theme,
          Icons.check_circle_outline,
          'Payment received',
          'Your payment has been confirmed.',
        );
      case MoolreCheckoutPhase.failed:
        return _terminal(
          theme,
          Icons.error_outline,
          'Payment was not completed',
          _controller.session?.message ?? 'The payment was declined.',
        );
      case MoolreCheckoutPhase.expired:
        return _terminal(
          theme,
          Icons.schedule,
          'This payment session expired',
          'Close this sheet and start a new payment.',
        );
      case MoolreCheckoutPhase.error:
        return [
          Text(
            'Could not load payment details',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _controller.isBusy
                ? null
                : () => unawaited(_controller.initialize()),
            child: const Text('Try again'),
          ),
        ];
    }
  }

  Widget _phoneForm() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<MoolreNetwork>(
          value: _network,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Mobile network'),
          items: [
            for (final network in MoolreNetwork.values)
              DropdownMenuItem(value: network, child: Text(network.label)),
          ],
          onChanged: _controller.isBusy
              ? null
              : (network) => setState(() => _network = network),
          validator: (value) => value == null ? 'Choose your network.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phone,
          enabled: !_controller.isBusy,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Mobile-money number',
            hintText: '024 123 4567',
          ),
          validator: (value) {
            try {
              normalizeMoolrePhoneNumber(value ?? '');
              return null;
            } on MoolrePaymentException catch (error) {
              return error.message;
            }
          },
        ),
        const SizedBox(height: 8),
        const Text('Use the number linked to your mobile-money wallet.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _controller.isBusy
              ? null
              : () {
                  if (_formKey.currentState!.validate()) {
                    FocusScope.of(context).unfocus();
                    unawaited(_controller.submitPhone(_phone.text, _network!));
                  }
                },
          child: Text('Pay ${_controller.session?.amountLabel ?? ''}'),
        ),
      ],
    ),
  );

  Widget _otpForm(ThemeData theme) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Verify your phone number', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Enter the verification code sent to you by SMS.'),
        const SizedBox(height: 16),
        TextFormField(
          controller: _otp,
          enabled: !_controller.isBusy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 10,
          decoration: const InputDecoration(labelText: 'Verification code'),
          validator: (value) => RegExp(r'^\d{4,10}$').hasMatch(value ?? '')
              ? null
              : 'Enter the verification code.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _controller.isBusy
              ? null
              : () {
                  if (_formKey.currentState!.validate()) {
                    FocusScope.of(context).unfocus();
                    final code = _otp.text;
                    _otp.clear();
                    unawaited(_controller.submitOtp(code));
                  }
                },
          child: const Text('Verify and continue'),
        ),
      ],
    ),
  );

  List<Widget> _hostedStart(ThemeData theme) => [
    Text(
      _controller.isSandbox
          ? 'Pay on the Moolre sandbox page'
          : 'Pay on the Moolre page',
      style: theme.textTheme.titleLarge,
    ),
    const SizedBox(height: 8),
    Text(
      _controller.isSandbox
          ? 'Enter a test number there. The sandbox shows the OTP on the page '
                '(no SMS is sent), then lets you choose Success, Pending or Failed.'
          : 'Enter your mobile-money number on the secure Moolre page.',
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _controller.isBusy
          ? null
          : () => unawaited(_controller.openHostedCheckout()),
      child: Text('Continue to pay ${_controller.session?.amountLabel ?? ''}'),
    ),
  ];

  List<Widget> _terminal(
    ThemeData theme,
    IconData icon,
    String title,
    String message,
  ) => [
    Icon(icon, size: 40, color: theme.colorScheme.primary),
    const SizedBox(height: 16),
    Semantics(
      liveRegion: true,
      child: Text(
        title,
        style: theme.textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
    ),
    const SizedBox(height: 8),
    Text(message, textAlign: TextAlign.center),
    const SizedBox(height: 16),
    Text(
      'Reference: ${_controller.session!.reference}',
      style: theme.textTheme.bodySmall,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    FilledButton(onPressed: _close, child: const Text('Done')),
  ];
}
