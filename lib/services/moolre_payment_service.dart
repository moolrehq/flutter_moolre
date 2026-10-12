import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/moolre_payment.dart';

/// Implement this contract to use an existing merchant backend.
abstract class MoolrePaymentGateway {
  Future<MoolrePaymentSession> createSession({
    required String orderId,
    required String idempotencyKey,
  });
  Future<MoolrePaymentSession> initiatePayment({
    required String sessionId,
    required String phoneNumber,
    required MoolreNetwork network,
  });
  Future<MoolrePaymentSession> submitOtp({
    required String sessionId,
    required String otp,
  });
  Future<MoolrePaymentSession> getSession(String sessionId);
}

/// Optional: complete payment on Moolre's hosted payment page.
/// Sandbox uses it because its test OTP and Success/Pending/Failed choices
/// exist only on that page. The outcome is always confirmed by status lookup.
abstract class MoolreHostedCheckoutGateway {
  bool get isSandbox;

  /// True when the current session is paid on Moolre's hosted page.
  bool get usesHostedCheckout;

  /// The hosted page redirects here when finished; the in-app browser closes.
  Uri get hostedReturnUrl;

  /// Creates, or reuses, the hosted payment page for [sessionId].
  Future<MoolreHostedCheckout> startHostedCheckout(String sessionId);
}

class MoolreHostedCheckout {
  const MoolreHostedCheckout({required this.session, this.url});
  final MoolrePaymentSession session;

  /// Null when no page can be opened; follow [session] status instead.
  final Uri? url;
}

/// Calls the merchant backend, never the Moolre collection API directly.
/// [headersProvider] runs for each request so app authentication can refresh.
class MoolrePaymentService implements MoolrePaymentGateway {
  MoolrePaymentService({
    required this.baseUrl,
    required this.headersProvider,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    bool allowInsecureHttp = false,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (!baseUrl.hasAuthority ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        (baseUrl.scheme != 'https' &&
            !(allowInsecureHttp && baseUrl.scheme == 'http'))) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Use an HTTPS backend URL.',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  final Uri baseUrl;
  final FutureOr<Map<String, String>> Function() headersProvider;
  final Duration requestTimeout;
  final http.Client _client;
  final bool _ownsClient;
  final Set<Completer<void>> _requests = {};
  bool _closed = false;

  @override
  Future<MoolrePaymentSession> createSession({
    required String orderId,
    required String idempotencyKey,
  }) {
    if (orderId.trim().isEmpty ||
        orderId.length > 200 ||
        !RegExp(r'^[\w-]{8,128}$').hasMatch(idempotencyKey)) {
      throw ArgumentError(
        'Provide an order ID and an 8–128 character request key.',
      );
    }
    return _request(
      'POST',
      ['sessions'],
      body: {'orderId': orderId},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
  }

  @override
  Future<MoolrePaymentSession> initiatePayment({
    required String sessionId,
    required String phoneNumber,
    required MoolreNetwork network,
  }) => _request(
    'POST',
    ['sessions', sessionId, 'initiate'],
    body: {
      'phoneNumber': normalizeMoolrePhoneNumber(phoneNumber),
      'network': network.name,
    },
  );

  @override
  Future<MoolrePaymentSession> submitOtp({
    required String sessionId,
    required String otp,
  }) {
    if (!RegExp(r'^\d{4,10}$').hasMatch(otp)) {
      throw const MoolrePaymentException(
        'INVALID_OTP',
        'Enter the verification code from your SMS.',
      );
    }
    return _request('POST', ['sessions', sessionId, 'otp'], body: {'otp': otp});
  }

  @override
  Future<MoolrePaymentSession> getSession(String sessionId) =>
      _request('GET', ['sessions', sessionId]);

  Future<MoolrePaymentSession> _request(
    String method,
    List<String> path, {
    Map<String, dynamic>? body,
    Map<String, String> extraHeaders = const {},
  }) async {
    if (_closed) throw StateError('Payment service has been closed.');
    if (path.length > 1 && !isMoolreSessionId(path[1])) {
      throw ArgumentError.value(
        path[1],
        'sessionId',
        'Use a URL-safe session ID.',
      );
    }
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        ...path,
      ],
    );
    final deadline = Stopwatch()..start();
    final abort = Completer<void>();
    _requests.add(abort);
    Duration remaining() {
      final time = requestTimeout - deadline.elapsed;
      if (time <= Duration.zero) {
        throw TimeoutException('Payment request timed out.');
      }
      return time;
    }

    try {
      final headers = await Future.any<Map<String, String>>([
        Future.sync(headersProvider),
        abort.future.then((_) => throw http.RequestAbortedException(uri)),
      ]).timeout(remaining());
      if (_closed) throw StateError('Payment service has been closed.');
      final request =
          http.AbortableRequest(method, uri, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers.addAll(headers)
            ..headers.addAll(extraHeaders)
            ..headers['Accept'] = 'application/json'
            ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      final response = await _send(request, remaining);
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        // Error responses may be HTML or empty; retain the HTTP error.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MoolrePaymentException(
          decoded?['code'] is String
              ? decoded!['code'] as String
              : 'BACKEND_ERROR',
          decoded?['message'] is String
              ? decoded!['message'] as String
              : 'Could not reach the payment service. Please try again.',
          retryable:
              response.statusCode == 408 ||
              response.statusCode == 429 ||
              response.statusCode >= 500,
        );
      }
      if (decoded == null) throw const FormatException('Missing session.');
      return MoolrePaymentSession.fromJson(decoded);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const MoolrePaymentException(
        'REQUEST_TIMEOUT',
        'The request timed out. Check the payment status before trying again.',
        retryable: true,
      );
    } on http.RequestAbortedException {
      throw const MoolrePaymentException(
        'REQUEST_ABORTED',
        'The request stopped. Check the payment status before trying again.',
        retryable: true,
      );
    } on http.ClientException {
      throw const MoolrePaymentException(
        'NETWORK_ERROR',
        'Check your connection and try again.',
        retryable: true,
      );
    } on FormatException {
      throw const MoolrePaymentException(
        'INVALID_RESPONSE',
        'The payment service returned an invalid response.',
      );
    } finally {
      _requests.remove(abort);
    }
  }

  Future<http.Response> _send(
    http.Request request,
    Duration Function() remaining,
  ) async {
    final timeout = remaining();
    final future = _client.send(request);
    late http.StreamedResponse response;
    try {
      response = await future.timeout(timeout);
    } on TimeoutException {
      // The caller may own the client, so do not close shared connections.
      // Drain no late response: cancel its stream once headers arrive.
      unawaited(
        future.then<void>((late) {
          unawaited(late.stream.listen(null).cancel());
        }, onError: (Object _) {}),
      );
      rethrow;
    }
    const maximumBytes = 64 * 1024;
    final iterator = StreamIterator<List<int>>(response.stream);
    try {
      final bytes = BytesBuilder(copy: false);
      if ((response.contentLength ?? 0) > maximumBytes) {
        throw const FormatException('Payment response is too large.');
      }
      while (await iterator.moveNext().timeout(remaining())) {
        if (bytes.length + iterator.current.length > maximumBytes) {
          throw const FormatException('Payment response is too large.');
        }
        bytes.add(iterator.current);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    } finally {
      await iterator.cancel();
    }
  }

  /// Closes only the HTTP client created by this service.
  void close() {
    _closed = true;
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) _client.close();
  }
}
