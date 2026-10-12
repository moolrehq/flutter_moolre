import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'demo_cart.dart';
import 'payment_configuration.dart';
import 'payment_storage.dart';
import 'pages/payment_result_page.dart';

void main() => runApp(const MoolreApp());

class MoolreApp extends StatelessWidget {
  const MoolreApp({
    super.key,
    this.configuration = const PaymentConfiguration.fromEnvironment(),
    this.storage,
  });
  final PaymentConfiguration configuration;
  final MoolrePaymentStorage? storage;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Moolre checkout demo',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF142A4A)),
      useMaterial3: true,
    ),
    home: MoolreExamplePage(configuration: configuration, storage: storage),
  );
}

class MoolreExamplePage extends StatefulWidget {
  const MoolreExamplePage({
    super.key,
    required this.configuration,
    this.storage,
  });
  final PaymentConfiguration configuration;
  final MoolrePaymentStorage? storage;
  @override
  State<MoolreExamplePage> createState() => _MoolreExamplePageState();
}

class _MoolreExamplePageState extends State<MoolreExamplePage> {
  late MoolreEnvironment _environment;
  MoolrePaymentStorage? _storage;
  DemoCart _cart = DemoCart();
  MoolreDirectPaymentGateway? _gateway;
  MoolrePaymentSession? _session;
  List<DemoCart> _savedSandboxCarts = [];
  bool _busy = true, _pendingResult = false;
  String? _storageError, _message;
  int _revision = 0, _buttonVersion = 0;

  bool get _locked =>
      _pendingResult ||
      _session?.status == MoolrePaymentStatus.pending ||
      _session?.status == MoolrePaymentStatus.otpRequired ||
      _session?.isSuccessful == true;
  String get _cartKey =>
      '${widget.configuration.identity}:${_environment.name}:cart';
  String get _selectionKey => '${widget.configuration.identity}:selected-mode';
  String get _sandboxHistoryKey =>
      '${widget.configuration.identity}:sandbox:saved-carts';
  bool get _legacySandboxAttempt =>
      _environment == MoolreEnvironment.sandbox &&
      _session != null &&
      !_session!.isTerminal &&
      _locked &&
      _gateway?.usesHostedCheckout == false;
  String get _notice => _environment == MoolreEnvironment.sandbox
      ? 'Moolre sandbox. Test payments only.'
      : 'Live payment. Money can be collected after approval.';

  @override
  void initState() {
    super.initState();
    _environment = widget.configuration.initialEnvironment;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      _storage = widget.storage ?? await FilePaymentStorage.open();
      final selection = await _storage!.read(_selectionKey);
      if (!mounted) return;
      final mode = selection?['environment'];
      if (mode == 'sandbox' || mode == 'live') {
        _environment = MoolreEnvironment.values.byName(mode as String);
      }
      await _loadMode(_environment);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _storageError =
              'Could not restore saved checkout. Retry before making a payment.';
        });
      }
    }
  }

  Future<void> _loadMode(
    MoolreEnvironment environment, {
    DemoCart? cart,
  }) async {
    final revision = ++_revision;
    _gateway?.close();
    setState(() {
      _busy = true;
      _storageError = null;
      _gateway = null;
    });
    try {
      final key = '${widget.configuration.identity}:${environment.name}:cart';
      final saved = await _storage!.read(key);
      final next =
          cart ?? (saved == null ? DemoCart() : DemoCart.fromJson(saved));
      final history = environment == MoolreEnvironment.sandbox
          ? await _storage!.read(_sandboxHistoryKey)
          : null;
      final savedCarts = <DemoCart>[];
      if (history != null) {
        final raw = history['carts'];
        if (raw is! List) {
          throw const FormatException('Invalid saved sandbox carts.');
        }
        for (final item in raw) {
          savedCarts.add(
            DemoCart.fromJson(Map<String, dynamic>.from(item as Map)),
          );
        }
      }
      await _storage!.write(key, next.toJson());
      await _storage!.write(_selectionKey, {'environment': environment.name});
      MoolreDirectPaymentGateway? gateway;
      MoolrePaymentSession? session;
      final config = widget.configuration;
      if (next.totalMinor > 0 && config.problems(environment).isEmpty) {
        gateway = MoolreDirectPaymentGateway(
          apiUser: config.apiUser,
          accountNumber: config.accountNumber,
          publicKey: config.publicKey,
          merchantEmail: config.merchantEmail,
          environment: environment,
          orderId: next.orderId,
          amountMinor: next.totalMinor,
          storage: _storage!,
        );
        try {
          session = await gateway.loadSavedSession();
        } catch (_) {
          gateway.close();
          rethrow;
        }
      }
      if (!mounted || revision != _revision) {
        gateway?.close();
        return;
      }
      setState(() {
        _environment = environment;
        _cart = next;
        _gateway = gateway;
        _session = session;
        _savedSandboxCarts = savedCarts;
        _pendingResult = false;
        _message = null;
        _busy = false;
        _buttonVersion++;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() {
          _busy = false;
          _storageError =
              'Could not restore or save checkout. Retry before making a payment.';
        });
      }
    }
  }

  void _change(String product, int quantity) {
    if (_busy || _locked || _storageError != null) return;
    unawaited(_loadMode(_environment, cart: _cart.change(product, quantity)));
  }

  Future<void> _switchSandboxCart(DemoCart next) async {
    if (_busy ||
        _storageError != null ||
        _environment != MoolreEnvironment.sandbox) {
      return;
    }
    setState(() => _busy = true);
    try {
      final carts = {
        for (final cart in _savedSandboxCarts) cart.orderId: cart,
        _cart.orderId: _cart,
      };
      // Save the full current cart before changing the active order. Its gateway
      // record remains intact, so it can be resumed from Saved sandbox tests.
      await _storage!.write(_sandboxHistoryKey, {
        'carts': carts.values.map((cart) => cart.toJson()).toList(),
      });
      if (!mounted) return;
      await _loadMode(MoolreEnvironment.sandbox, cart: next);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _storageError =
              'Could not save this test cart. Your existing payment is retained.';
        });
      }
    }
  }

  void _result(MoolrePaymentResult result, int revision) {
    if (!mounted || revision != _revision) return;
    setState(() {
      _session = result.session ?? _session;
      _pendingResult = result.outcome == MoolrePaymentOutcome.pending;
      _message = _pendingResult
          ? 'Payment pending. Reopen checkout to check its status.'
          : 'Checkout closed. You can continue when ready.';
      if (result.outcome == MoolrePaymentOutcome.failed ||
          result.outcome == MoolrePaymentOutcome.expired) {
        _buttonVersion++;
      }
    });
    if (result.isSuccessful ||
        result.outcome == MoolrePaymentOutcome.failed ||
        result.outcome == MoolrePaymentOutcome.expired) {
      final sandbox = _environment == MoolreEnvironment.sandbox;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentResultPage(
            isSuccess: result.isSuccessful,
            isSandbox: sandbox,
            reference: result.session?.reference,
            errorCode: result.outcome.name.toUpperCase(),
            errorMessage:
                result.session?.message ?? 'Payment was not completed.',
          ),
        ),
      );
    }
  }

  Widget _payButton() {
    final revision = _revision;
    if (_session?.isSuccessful == true) {
      return FilledButton(
        onPressed: _busy
            ? null
            : () => unawaited(
                _loadMode(
                  _environment,
                  cart: DemoCart(quantities: _cart.quantities),
                ),
              ),
        child: const Text('Start a new test cart'),
      );
    }
    if (_gateway == null || _busy || _storageError != null) {
      return const FilledButton(
        onPressed: null,
        child: Text('Pay with Moolre'),
      );
    }
    return MoolrePayButton(
      key: ValueKey('$_cartKey:$_buttonVersion'),
      gateway: _gateway!,
      orderId: _cart.orderId,
      resumeSessionId: _session?.isTerminal == false ? _session?.id : null,
      checkoutNotice: _notice,
      onSessionCreated: (session) {
        if (mounted && revision == _revision) {
          setState(() => _session = session);
        }
      },
      onResult: (result) => _result(result, revision),
    );
  }

  @override
  void dispose() {
    _revision++;
    _gateway?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.configuration;
    final issues = config.problems(_environment);
    final editable = !_busy && !_locked && _storageError == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout demo')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<MoolreEnvironment>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(
                        value: MoolreEnvironment.sandbox,
                        label: Text('Sandbox'),
                      ),
                      ButtonSegment(
                        value: MoolreEnvironment.live,
                        label: const Text('Live'),
                        enabled: config.publicKey.isNotEmpty,
                      ),
                    ],
                    selected: {_environment},
                    onSelectionChanged: _busy
                        ? null
                        : (modes) => unawaited(_loadMode(modes.single)),
                  ),
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_notice)),
                  const SizedBox(height: 28),
                  Text(
                    'Your cart',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Sample products for testing the Moolre plugin.'),
                  const SizedBox(height: 20),
                  if (_cart.quantities.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Your cart is empty. Add an item to start checkout.',
                      ),
                    ),
                  for (final product in demoProducts.where(
                    (product) => _cart.quantities.containsKey(product.id),
                  )) ...[
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${formatGhs(product.priceMinor)} each'),
                        IconButton(
                          tooltip: 'Decrease ${product.name}',
                          onPressed: editable
                              ? () => _change(
                                  product.id,
                                  _cart.quantities[product.id]! - 1,
                                )
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Semantics(
                          label: '${product.name} quantity',
                          child: Text('${_cart.quantities[product.id]}'),
                        ),
                        IconButton(
                          tooltip: 'Increase ${product.name}',
                          onPressed:
                              editable && _cart.quantities[product.id]! < 99
                              ? () => _change(
                                  product.id,
                                  _cart.quantities[product.id]! + 1,
                                )
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Remove ${product.name}',
                          onPressed: editable
                              ? () => _change(product.id, 0)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                  ],
                  PopupMenuButton<DemoProduct>(
                    enabled: editable,
                    tooltip: 'Add a sample item',
                    onSelected: (product) => _change(
                      product.id,
                      (_cart.quantities[product.id] ?? 0) + 1,
                    ),
                    itemBuilder: (_) => demoProducts
                        .where(
                          (product) => (_cart.quantities[product.id] ?? 0) < 99,
                        )
                        .map(
                          (product) => PopupMenuItem(
                            value: product,
                            child: Text(
                              '${product.name} - ${formatGhs(product.priceMinor)}',
                            ),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add,
                            color: editable
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor,
                          ),
                          const SizedBox(width: 8),
                          const Text('Add item'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    formatGhs(_cart.totalMinor),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  if (issues.isNotEmpty) ...[
                    Text(
                      'Payment configuration required:\n${issues.join('\n')}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_storageError != null) ...[
                    Text(_storageError!),
                    TextButton(
                      onPressed: () => unawaited(_initialize()),
                      child: const Text('Retry saved checkout'),
                    ),
                  ],
                  if (_locked && _session?.isSuccessful != true) ...[
                    const Text(
                      'Cart editing is paused while this payment is unresolved. Reopen checkout to continue.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _payButton(),
                  if (_legacySandboxAttempt) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'This test was started by an older app version. Keep checking its original reference, or start a separate test on the Moolre sandbox page.',
                    ),
                    OutlinedButton(
                      onPressed: _busy || _storageError != null
                          ? null
                          : () => unawaited(
                              _switchSandboxCart(
                                DemoCart(quantities: _cart.quantities),
                              ),
                            ),
                      child: const Text('Start a separate sandbox test'),
                    ),
                  ],
                  if (_environment == MoolreEnvironment.sandbox &&
                      _savedSandboxCarts.any(
                        (cart) => cart.orderId != _cart.orderId,
                      ))
                    PopupMenuButton<DemoCart>(
                      enabled: !_busy && _storageError == null,
                      onSelected: (cart) => unawaited(_switchSandboxCart(cart)),
                      itemBuilder: (_) => [
                        for (final cart in _savedSandboxCarts)
                          if (cart.orderId != _cart.orderId)
                            PopupMenuItem(
                              value: cart,
                              child: Text(
                                '${formatGhs(cart.totalMinor)} · ${cart.orderId.substring(0, cart.orderId.length < 8 ? cart.orderId.length : 8)}',
                              ),
                            ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Saved sandbox tests'),
                      ),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(_message!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
