import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/moolre_payment.dart';
import 'moolre_payment_service.dart';
import 'moolre_payment_storage.dart';

enum MoolreEnvironment { sandbox, live }

/// Where the hosted page sends the payer when finished. The in-app browser
/// intercepts it, so it is never loaded.
final defaultMoolreHostedReturnUrl = Uri.parse(
  'https://flutter-moolre.invalid/return',
);

/// Collection directly against Moolre, using its public collection key.
/// Live collects natively; sandbox pays on Moolre's hosted sandbox page.
/// Client-side verification is not an authority for production fulfilment.
class MoolreDirectPaymentGateway
    implements MoolrePaymentGateway, MoolreHostedCheckoutGateway {
  MoolreDirectPaymentGateway({
    required this.apiUser,
    required this.accountNumber,
    required this.orderId,
    required this.amountMinor,
    required this.storage,
    this.publicKey = '',
    this.merchantEmail = '',
    this.environment = MoolreEnvironment.sandbox,
    this.requestTimeout = const Duration(seconds: 20),
    Uri? hostedReturnUrl,
    http.Client? client,
  }) : hostedReturnUrl = hostedReturnUrl ?? defaultMoolreHostedReturnUrl,
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    final returnUrl = this.hostedReturnUrl;
    if (apiUser.trim().isEmpty ||
        accountNumber.trim().isEmpty ||
        orderId.trim().isEmpty ||
        orderId.length > 200 ||
        [
          apiUser,
          accountNumber,
          publicKey,
          merchantEmail,
        ].any((v) => v.isNotEmpty && !RegExp(r'^[\x21-\x7e]+$').hasMatch(v)) ||
        !['https', 'http'].contains(returnUrl.scheme) ||
        returnUrl.host.isEmpty ||
        (environment == MoolreEnvironment.live && publicKey.isEmpty) ||
        amountMinor <= 0 ||
        amountMinor > 9007199254740991 ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError(
        'Provide a username, account, order, positive GHS amount and valid options; live requires a public key.',
      );
    }
  }

  final String apiUser, accountNumber, publicKey, orderId;

  /// Business email sent when creating a hosted (sandbox) payment page.
  final String merchantEmail;
  final int amountMinor;
  final MoolreEnvironment environment;
  final Duration requestTimeout;
  @override
  final Uri hostedReturnUrl;
  final MoolrePaymentStorage storage;
  final http.Client _client;
  final bool _ownsClient;
  final Set<Completer<void>> _requests = {};
  Future<void> _operations = Future.value();
  bool _loaded = false, _closed = false;
  MoolrePaymentSession? _session;
  String? _requestKey, _phone;
  MoolreNetwork? _network;
  bool _hostedClaimed = false;
  String? _hostedUrl;

  @override
  bool get isSandbox => environment == MoolreEnvironment.sandbox;

  /// New sandbox sessions pay on the hosted page. Attempts dispatched by an
  /// older version keep their original reference and are only status-checked.
  @override
  bool get usesHostedCheckout =>
      isSandbox &&
      !_closed &&
      (_hostedClaimed ||
          _session == null ||
          _session!.status == MoolrePaymentStatus.ready);

  String get storageKey =>
      jsonEncode([environment.name, apiUser, accountNumber, orderId]);
  String get _base => environment == MoolreEnvironment.live
      ? 'https://api.moolre.com'
      : 'https://sandbox.moolre.com';
  String get _amount =>
      '${amountMinor ~/ 100}.${(amountMinor % 100).toString().padLeft(2, '0')}';

  /// Reads local recovery state without initiating or querying a payment.
  Future<MoolrePaymentSession?> loadSavedSession() => _run(() async {
    await _expire();
    return _session;
  });

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        if (_closed) throw StateError('Payment gateway is closed.');
        if (!_loaded) {
          final saved = await storage.read(storageKey);
          if (saved != null) {
            final value = MoolrePaymentSession.fromJson(
              Map<String, dynamic>.from(saved['session'] as Map),
            );
            if (value.orderId != orderId ||
                value.amountMinor != amountMinor ||
                saved['requestKey'] is! String ||
                !RegExp(
                  r'^[\w-]{8,128}$',
                ).hasMatch(saved['requestKey'] as String)) {
              throw const FormatException(
                'Saved payment does not match the order.',
              );
            }
            _session = value;
            final hosted = saved['hostedCheckout'];
            if (hosted != null) {
              if (!isSandbox ||
                  hosted is! Map ||
                  hosted['claimed'] is! bool ||
                  (hosted['url'] != null &&
                      _hostedLink(hosted['url']) == null)) {
                throw const FormatException('Invalid saved hosted checkout.');
              }
              _hostedClaimed = hosted['claimed'] as bool;
              _hostedUrl = hosted['url'] as String?;
            }
            // Records from the former in-app sandbox flow ('sandboxCheckout')
            // keep their reference and are resolved by status lookup only.
            _requestKey = saved['requestKey'] as String;
            _phone = saved['phone'] as String?;
            if (saved['network'] != null) {
              _network = MoolreNetwork.values.byName(
                saved['network'] as String,
              );
            }
            // Hosted payments collect the phone number on Moolre's page.
            if (!_hostedClaimed &&
                [
                  MoolrePaymentStatus.pending,
                  MoolrePaymentStatus.otpRequired,
                ].contains(value.status) &&
                (_phone == null ||
                    _network == null ||
                    normalizeMoolrePhoneNumber(_phone!) != _phone)) {
              throw const FormatException('Invalid saved payment details.');
            }
          }
          _loaded = true;
        }
        if (_closed) throw StateError('Payment gateway is closed.');
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<MoolrePaymentSession> _save(MoolrePaymentSession value) async {
    await storage.write(storageKey, {
      'session': {
        'id': value.id,
        'orderId': value.orderId,
        'reference': value.reference,
        'amountMinor': value.amountMinor,
        'currency': value.currency,
        'status': value.status.value,
        'verified': value.verified,
        'message': value.message,
        'expiresAt': value.expiresAt?.toIso8601String(),
      },
      'requestKey': _requestKey,
      'phone': _phone,
      'network': _network?.name,
      if (_hostedClaimed)
        'hostedCheckout': {'claimed': _hostedClaimed, 'url': _hostedUrl},
    });
    _session = value;
    return value;
  }

  Future<MoolrePaymentSession> _status(
    MoolrePaymentStatus status, [
    String? message,
    DateTime? expiresAt,
  ]) {
    final value = _session!;
    return _save(
      MoolrePaymentSession(
        id: value.id,
        orderId: value.orderId,
        reference: value.reference,
        amountMinor: value.amountMinor,
        currency: value.currency,
        status: status,
        verified: status == MoolrePaymentStatus.succeeded,
        message: message,
        expiresAt: expiresAt ?? value.expiresAt,
      ),
    );
  }

  Future<void> _expire() async {
    final value = _session;
    if (value != null &&
        [
          MoolrePaymentStatus.ready,
          MoolrePaymentStatus.otpRequired,
        ].contains(value.status) &&
        value.expiresAt != null &&
        !DateTime.now().isBefore(value.expiresAt!)) {
      await _status(
        MoolrePaymentStatus.expired,
        'This unused payment attempt expired.',
      );
    }
  }

  @override
  Future<MoolrePaymentSession> createSession({
    required String orderId,
    required String idempotencyKey,
  }) => _run(() async {
    if (orderId != this.orderId ||
        !RegExp(r'^[\w-]{8,128}$').hasMatch(idempotencyKey)) {
      throw ArgumentError(
        'Provide the configured order and a valid request key.',
      );
    }
    await _expire();
    if (_session != null &&
        (_requestKey == idempotencyKey ||
            ![
              MoolrePaymentStatus.failed,
              MoolrePaymentStatus.expired,
            ].contains(_session!.status))) {
      return _session!;
    }
    _requestKey = idempotencyKey;
    _phone = null;
    _network = null;
    _hostedClaimed = false;
    _hostedUrl = null;
    final id = const Uuid().v4();
    return _save(
      MoolrePaymentSession(
        id: id,
        orderId: orderId,
        reference: 'moolre_$id',
        amountMinor: amountMinor,
        currency: 'GHS',
        status: MoolrePaymentStatus.ready,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      ),
    );
  });

  void _checkId(String id) {
    if (_session?.id != id) {
      throw const MoolrePaymentException(
        'SESSION_NOT_FOUND',
        'Saved payment was not found.',
      );
    }
  }

  @override
  Future<MoolrePaymentSession> initiatePayment({
    required String sessionId,
    required String phoneNumber,
    required MoolreNetwork network,
  }) => _run(() async {
    _checkId(sessionId);
    await _expire();
    if (_session!.status != MoolrePaymentStatus.ready) return _session!;
    _phone = normalizeMoolrePhoneNumber(phoneNumber);
    _network = network;
    // Persist the dispatch claim before contacting Moolre. Recovery checks the
    // same reference and never silently dispatches a new collection.
    await _status(MoolrePaymentStatus.pending);
    return _dispatch();
  });

  @override
  Future<MoolrePaymentSession> submitOtp({
    required String sessionId,
    required String otp,
  }) => _run(() async {
    _checkId(sessionId);
    await _expire();
    if (_session!.status != MoolrePaymentStatus.otpRequired) return _session!;
    if (!RegExp(r'^\d{4,10}$').hasMatch(otp)) {
      throw const MoolrePaymentException(
        'INVALID_OTP',
        'Enter the verification code.',
      );
    }
    await _status(MoolrePaymentStatus.pending);
    return _dispatch(otp);
  });

  Future<Map<String, dynamic>> _collect([String? otp]) =>
      _post('/open/transact/payment', {
        'type': 1,
        'channel': _network!.channel,
        'currency': 'GHS',
        'payer': _phone,
        'amount': _amount,
        'externalref': _session!.reference,
        'accountnumber': accountNumber,
        if (otp != null) 'otpcode': otp,
      });
  bool _accepted(dynamic value) => value == 1 || value == '1';

  @override
  Future<MoolreHostedCheckout> startHostedCheckout(String sessionId) => _run(
    () async {
      _checkId(sessionId);
      await _expire();
      if (!isSandbox) {
        throw const MoolrePaymentException(
          'HOSTED_CHECKOUT_UNAVAILABLE',
          'Live payments use native checkout.',
        );
      }
      if (_session!.isTerminal ||
          (!_hostedClaimed && _session!.status != MoolrePaymentStatus.ready)) {
        return MoolreHostedCheckout(session: _session!);
      }
      if (_hostedUrl == null) {
        if (!_hostedClaimed) {
          // Persist the claim before contacting Moolre. The page is keyed by
          // this session's unique reference, so a retry after a lost
          // response can never create a second payment for the order.
          _hostedClaimed = true;
          await _status(MoolrePaymentStatus.pending);
        }
        await _createHostedLink();
      }
      final url = _hostedUrl;
      return MoolreHostedCheckout(
        session: _session!,
        url: url == null || _session!.isTerminal ? null : Uri.parse(url),
      );
    },
  );

  /// Documented sandbox endpoint: https://sandbox.moolre.com/embed/link
  Future<void> _createHostedLink() async {
    final Map<String, dynamic> response;
    try {
      response = await _post('/embed/link', {
        'type': 1,
        'amount': _amount,
        'email': merchantEmail,
        'externalref': _session!.reference,
        'redirect': hostedReturnUrl.toString(),
        'reusable': '0',
        'currency': 'GHS',
        'accountnumber': accountNumber,
      });
    } catch (_) {
      return; // Unknown outcome. Retrying with the same reference is safe.
    }
    if (_closed) return;
    final data = response['data'];
    final url = data is Map ? _hostedLink(data['authorization_url']) : null;
    if (_accepted(response['status']) && url != null) {
      _hostedUrl = url.toString();
      await _save(_session!);
      return;
    }
    if (response['status'] == 0 || response['status'] == '0') {
      if (response['code'] == 'INP02') {
        await _status(
          MoolrePaymentStatus.pending,
          'A payment page already exists for this reference. Check payment status.',
        );
      } else {
        // Moolre refused to create the page, so no payment exists for it.
        await _status(
          MoolrePaymentStatus.failed,
          _providerMessage(response) ??
              'Moolre could not create the payment page. Check your configuration.',
        );
      }
    }
  }

  Uri? _hostedLink(Object? raw) {
    final url = raw is String ? Uri.tryParse(raw) : null;
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        !(url.host == 'moolre.com' || url.host.endsWith('.moolre.com'))) {
      return null;
    }
    return url;
  }

  String? _providerMessage(Map<String, dynamic> response) {
    final message = response['message'];
    final text = message is List ? message.join(', ') : message?.toString();
    return text == null || text.trim().isEmpty
        ? null
        : 'Moolre: ${text.length > 200 ? text.substring(0, 200) : text}';
  }

  Future<MoolrePaymentSession> _dispatch([String? otp]) async {
    Map<String, dynamic> response;
    try {
      response = await _collect(otp);
      if (_accepted(response['status']) && response['code'] == 'TP17') {
        response = await _collect();
      }
    } catch (_) {
      return _session!;
    }
    if (_closed) return _session!;
    if (_accepted(response['status']) && response['code'] == 'TP14') {
      return _status(
        MoolrePaymentStatus.otpRequired,
        'Enter the code from the Moolre verification flow.',
      );
    }
    if ((response['status'] == 0 || response['status'] == '0') &&
        ['AIN01', 'TP01', 'TP09', 'APGW06'].contains(response['code'])) {
      return _status(
        MoolrePaymentStatus.failed,
        response['code'] == 'AIN01'
            ? 'Moolre rejected the collection credentials. Check your username, account and public key.'
            : 'Moolre rejected the currency or selected network.',
      );
    }
    return _session!; // Acceptance, duplicates and unknown outcomes are pending.
  }

  @override
  Future<MoolrePaymentSession> getSession(String sessionId) => _run(() async {
    _checkId(sessionId);
    await _expire();
    if (_session!.status != MoolrePaymentStatus.pending) return _session!;
    return _lookupStatus();
  });

  Future<MoolrePaymentSession> _lookupStatus() async {
    Map<String, dynamic> response;
    try {
      response = await _post('/open/transact/status', {
        'type': 1,
        'idtype': 1,
        'id': _session!.reference,
        'accountnumber': accountNumber,
      });
    } catch (_) {
      return _session!;
    }
    final data = response['data'];
    if (!_closed &&
        _accepted(response['status']) &&
        data is Map &&
        _accepted(data['txstatus']) &&
        data['externalref'] == _session!.reference &&
        data['accountnumber'].toString() == accountNumber &&
        _minor(data['amount']) == amountMinor &&
        (data['currency'] == null || data['currency'] == 'GHS')) {
      return _status(MoolrePaymentStatus.succeeded);
    }
    // In the hosted sandbox, 3 is failed. A bare 3 from status lookup is also
    // used for unknown references, so require all the original payment details.
    if (!_closed &&
        isSandbox &&
        _hostedClaimed &&
        _accepted(response['status']) &&
        response['code'] == 'SS02' &&
        data is Map &&
        (data['txstatus'] == 3 || data['txstatus'] == '3') &&
        _matchesReceipt(data, 'externalref')) {
      return _status(
        MoolrePaymentStatus.failed,
        'Moolre recorded this sandbox payment as failed.',
      );
    }
    return _session!;
  }

  bool _matchesReceipt(Map data, String referenceKey) =>
      data[referenceKey] == _session!.reference &&
      data['accountnumber'].toString() == accountNumber &&
      _minor(data['amount']) == amountMinor &&
      (data['currency'] == null || data['currency'] == 'GHS');

  int? _minor(dynamic value) {
    final match = RegExp(
      r'^(0|[1-9]\d*)(?:\.(\d{1,2}))?$',
    ).firstMatch('$value');
    if (match == null) return null;
    final whole = int.tryParse(match[1]!);
    if (whole == null || whole > 90071992547409) return null;
    return whole * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (_closed) throw StateError('Payment gateway is closed.');
    final abort = Completer<void>();
    _requests.add(abort);
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = requestTimeout - clock.elapsed;
      if (_closed || value <= Duration.zero) {
        throw TimeoutException('Payment request stopped.');
      }
      return value;
    }

    try {
      final request =
          http.AbortableRequest(
              'POST',
              Uri.parse('$_base$path'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-API-USER': apiUser,
              if (publicKey.isNotEmpty) 'X-API-PUBKEY': publicKey,
            })
            ..body = jsonEncode(body);
      final sent = _client.send(request);
      late http.StreamedResponse response;
      try {
        response = await sent.timeout(remaining());
      } on TimeoutException {
        unawaited(
          sent.then<void>((late) {
            unawaited(late.stream.listen(null).cancel());
          }, onError: (Object _) {}),
        );
        rethrow;
      }
      final iterator = StreamIterator<List<int>>(response.stream);
      final bytes = BytesBuilder(copy: false);
      try {
        if ((response.contentLength ?? 0) > 65536) {
          throw const FormatException('Response too large.');
        }
        while (await iterator.moveNext().timeout(remaining())) {
          if (bytes.length + iterator.current.length > 65536) {
            throw const FormatException('Response too large.');
          }
          bytes.add(iterator.current);
        }
      } finally {
        await iterator.cancel();
      }
      final value = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (value is! Map<String, dynamic> ||
          response.statusCode >= 500 ||
          response.statusCode >= 300 &&
              (response.statusCode < 400 || _accepted(value['status']))) {
        throw const FormatException('Invalid Moolre response.');
      }
      return value;
    } finally {
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
    }
  }

  void close() {
    _closed = true;
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) _client.close();
  }
}
