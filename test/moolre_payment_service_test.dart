import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_moolre/flutter_moolre.dart';

class AppOwnedClient extends MockClient {
  AppOwnedClient(super.fn) : super.streaming();
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

Map<String, dynamic> sessionJson({
  String status = 'ready',
  bool verified = false,
}) => {
  'id': 'session_001',
  'orderId': 'order_001',
  'reference': 'reference_001',
  'amountMinor': 5000,
  'currency': 'GHS',
  'status': status,
  'verified': verified,
};

void main() {
  test(
    'timeouts and close abort only service requests, preserving a shared client',
    () async {
      for (final close in [true, false]) {
        var requests = 0;
        var aborted = false;
        final client = AppOwnedClient((request, _) async {
          if (++requests > 1) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(sessionJson()))),
              200,
            );
          }
          await (request as http.Abortable).abortTrigger;
          aborted = true;
          throw http.RequestAbortedException(request.url);
        });
        final service = MoolrePaymentService(
          baseUrl: Uri.parse('https://merchant.example/moolre'),
          headersProvider: () => {},
          client: client,
          requestTimeout: close
              ? const Duration(seconds: 1)
              : const Duration(milliseconds: 100),
        );
        addTearDown(service.close);
        final pending = service.getSession('session_001');
        final expectation = expectLater(
          pending,
          throwsA(
            isA<MoolrePaymentException>().having(
              (error) => error.code,
              'code',
              close ? 'REQUEST_ABORTED' : 'REQUEST_TIMEOUT',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        if (close) service.close();
        await expectation;
        await Future<void>.delayed(Duration.zero);
        expect(aborted, isTrue);
        expect(client.closed, isFalse);
        expect(
          (await client.get(
            Uri.parse('https://merchant.example/other'),
          )).statusCode,
          200,
        );
        client.close();
      }
    },
  );

  test(
    'redirects are rejected without forwarding customer credentials',
    () async {
      var requests = 0;
      final service = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => {'Authorization': 'Bearer private_token'},
        client: MockClient((request) async {
          requests++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'Location': 'https://other.example'},
          );
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.getSession('session_001'),
        throwsA(isA<MoolrePaymentException>()),
      );
      expect(requests, 1);
    },
  );

  test(
    'oversized and stalled response streams are bounded and cancelled',
    () async {
      for (final oversized in [true, false]) {
        var cancelled = false;
        final stream = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final service = MoolrePaymentService(
          baseUrl: Uri.parse('https://merchant.example/moolre'),
          headersProvider: () => {},
          requestTimeout: const Duration(milliseconds: 10),
          client: MockClient.streaming((_, _) async {
            if (oversized) stream.add(List.filled(64 * 1024 + 1, 65));
            return http.StreamedResponse(stream.stream, 200);
          }),
        );
        addTearDown(service.close);
        await expectLater(
          service.getSession('session_001'),
          throwsA(
            isA<MoolrePaymentException>().having(
              (error) => error.code,
              'code',
              oversized ? 'INVALID_RESPONSE' : 'REQUEST_TIMEOUT',
            ),
          ),
        );
        expect(cancelled, isTrue);
        await stream.close();
      }
    },
  );

  test(
    'authentication stalls cannot dispatch and late headers are cancelled',
    () async {
      var requests = 0;
      final authentication = Completer<Map<String, String>>();
      final blocked = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => authentication.future,
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(sessionJson()), 200);
        }),
      );
      addTearDown(blocked.close);
      await expectLater(
        blocked.getSession('session_001'),
        throwsA(isA<MoolrePaymentException>()),
      );
      authentication.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);

      var cancelled = false;
      final headers = Completer<http.StreamedResponse>();
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final delayed = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => {},
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient.streaming((_, _) => headers.future),
      );
      addTearDown(delayed.close);
      await expectLater(
        delayed.getSession('session_001'),
        throwsA(isA<MoolrePaymentException>()),
      );
      headers.complete(http.StreamedResponse(stream.stream, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  test(
    'session paths and request keys are validated before HTTP dispatch',
    () async {
      var requests = 0;
      final service = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => {},
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(sessionJson()), 200);
        }),
      );
      addTearDown(service.close);
      for (final id in ['', '..', '../another-order', 'a/b']) {
        await expectLater(service.getSession(id), throwsArgumentError);
      }
      expect(
        () =>
            service.createSession(orderId: 'order_001', idempotencyKey: 'bad'),
        throwsArgumentError,
      );
      expect(requests, 0);
    },
  );

  test(
    'backend paths, refreshed authentication, and authoritative amount',
    () async {
      final requests = <http.Request>[];
      var token = 'first';
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(sessionJson()), 200);
      });
      final service = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/api/moolre/'),
        headersProvider: () => {'Authorization': 'Bearer $token'},
        client: client,
      );
      addTearDown(service.close);
      await service.createSession(
        orderId: 'order_001',
        idempotencyKey: 'key_0001',
      );
      token = 'second';
      await service.initiatePayment(
        sessionId: 'session_001',
        phoneNumber: '+233241234567',
        network: MoolreNetwork.telecel,
      );
      expect(requests.first.url.path, '/api/moolre/sessions');
      expect(requests.first.headers['Idempotency-Key'], 'key_0001');
      expect(jsonDecode(requests.first.body), {'orderId': 'order_001'});
      expect(
        requests.last.url.path,
        '/api/moolre/sessions/session_001/initiate',
      );
      expect(requests.last.headers['Authorization'], 'Bearer second');
      expect(jsonDecode(requests.last.body), {
        'phoneNumber': '0241234567',
        'network': 'telecel',
      });
    },
  );

  test('malformed and unverified success responses fail closed', () async {
    for (final body in [
      '<html>unavailable</html>',
      jsonEncode(sessionJson(status: 'succeeded')),
      jsonEncode({...sessionJson(), 'amountMinor': 0}),
    ]) {
      final service = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => {},
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(service.close);
      await expectLater(
        service.getSession('session_001'),
        throwsA(
          isA<MoolrePaymentException>().having(
            (error) => error.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
    }
  });

  test(
    'HTTP failure cannot be accepted because its body looks successful',
    () async {
      final service = MoolrePaymentService(
        baseUrl: Uri.parse('https://merchant.example/moolre'),
        headersProvider: () => {},
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(sessionJson(status: 'succeeded', verified: true)),
            503,
          ),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.getSession('session_001'),
        throwsA(
          isA<MoolrePaymentException>().having(
            (error) => error.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    },
  );

  test('network timeout is bounded and HTTPS is required by default', () async {
    expect(
      () => MoolrePaymentService(
        baseUrl: Uri.parse('http://merchant.example'),
        headersProvider: () => {},
      ),
      throwsArgumentError,
    );
    final service = MoolrePaymentService(
      baseUrl: Uri.parse('https://merchant.example/moolre'),
      headersProvider: () => {},
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(service.close);
    await expectLater(
      service.getSession('session_001'),
      throwsA(
        isA<MoolrePaymentException>().having(
          (error) => error.code,
          'code',
          'REQUEST_TIMEOUT',
        ),
      ),
    );
  });

  test(
    'money uses exact minor units and invalid phone/OTP inputs are rejected',
    () {
      expect(
        MoolrePaymentSession.fromJson(sessionJson()).amountLabel,
        'GHS 50.00',
      );
      expect(normalizeMoolrePhoneNumber('00233 24 123 4567'), '0241234567');
      expect(
        () => normalizeMoolrePhoneNumber('123'),
        throwsA(isA<MoolrePaymentException>()),
      );
    },
  );
}
