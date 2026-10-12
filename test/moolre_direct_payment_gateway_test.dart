import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryPaymentStorage implements MoolrePaymentStorage {
  final records = <String, Map<String, dynamic>>{};
  bool failWrites = false;
  @override
  Future<Map<String, dynamic>?> read(String key) async => records[key] == null
      ? null
      : jsonDecode(jsonEncode(records[key])) as Map<String, dynamic>;
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    if (failWrites) throw StateError('Storage unavailable');
    records[key] = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

MoolreDirectPaymentGateway gateway(
  MemoryPaymentStorage storage,
  http.Client client, {
  MoolreEnvironment environment = MoolreEnvironment.live,
  Duration timeout = const Duration(seconds: 20),
}) => MoolreDirectPaymentGateway(
  apiUser: 'user',
  accountNumber: 'account',
  publicKey: environment == MoolreEnvironment.live ? 'public_key' : '',
  orderId: 'order_001',
  amountMinor: 70,
  storage: storage,
  environment: environment,
  client: client,
  requestTimeout: timeout,
);

void main() {
  test('live API contract, OTP continuation, and verified receipt', () async {
    final storage = MemoryPaymentStorage();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonDecode(request.body) as Map;
      if (request.url.path.endsWith('/status')) {
        return http.Response(
          jsonEncode({
            'status': 1,
            'data': {
              'txstatus': 1,
              'externalref': body['id'],
              'accountnumber': 'account',
              'amount': '0.70',
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 1,
          'code': requests.length == 1
              ? 'TP14'
              : body.containsKey('otpcode')
              ? 'TP17'
              : 'TR099',
        }),
        200,
      );
    });
    final payments = gateway(storage, client);
    final session = await payments.createSession(
      orderId: 'order_001',
      idempotencyKey: 'request_key_001',
    );
    expect(requests, isEmpty);
    expect(
      (await payments.initiatePayment(
        sessionId: session.id,
        phoneNumber: '+233241234567',
        network: MoolreNetwork.mtn,
      )).status,
      MoolrePaymentStatus.otpRequired,
    );
    expect(
      (await payments.submitOtp(sessionId: session.id, otp: '654321')).verified,
      isFalse,
    );
    expect((await payments.getSession(session.id)).isSuccessful, isTrue);
    expect(
      requests.first.url.toString(),
      'https://api.moolre.com/open/transact/payment',
    );
    expect(requests.first.headers['X-API-USER'], 'user');
    expect(requests.first.headers['X-API-PUBKEY'], 'public_key');
    expect(requests.first.followRedirects, isFalse);
    final body = jsonDecode(requests.first.body) as Map;
    expect(body, {
      'type': 1,
      'channel': '13',
      'currency': 'GHS',
      'payer': '0241234567',
      'amount': '0.70',
      'externalref': session.reference,
      'accountnumber': 'account',
    });
    expect(jsonDecode(requests.last.body), {
      'type': 1,
      'idtype': 1,
      'id': session.reference,
      'accountnumber': 'account',
    });
    expect(jsonEncode(storage.records).contains('654321'), isFalse);
    payments.close();
    client.close();
  });

  test(
    'concurrent initiation and restored pending attempts never recollect',
    () async {
      final storage = MemoryPaymentStorage();
      var collections = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/payment')) {
          collections++;
          throw http.ClientException('Lost response');
        }
        return http.Response('{"status":1,"data":{"txstatus":2}}', 200);
      });
      final first = gateway(storage, client);
      final session = await first.createSession(
        orderId: 'order_001',
        idempotencyKey: 'request_key_001',
      );
      await Future.wait(
        List.generate(
          2,
          (_) => first.initiatePayment(
            sessionId: session.id,
            phoneNumber: '0241234567',
            network: MoolreNetwork.mtn,
          ),
        ),
      );
      first.close();
      final restored = gateway(storage, client);
      expect(
        (await restored.createSession(
          orderId: 'order_001',
          idempotencyKey: 'different_request_key',
        )).reference,
        session.reference,
      );
      await restored.initiatePayment(
        sessionId: session.id,
        phoneNumber: '0241234567',
        network: MoolreNetwork.mtn,
      );
      expect(
        (await restored.getSession(session.id)).status,
        MoolrePaymentStatus.pending,
      );
      expect(collections, 1);
      restored.close();
      client.close();
    },
  );

  test('failed persistence prevents collection before dispatch', () async {
    final storage = MemoryPaymentStorage();
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{"status":1,"code":"TR099"}', 200);
    });
    final payments = gateway(storage, client);
    final session = await payments.createSession(
      orderId: 'order_001',
      idempotencyKey: 'request_key_001',
    );
    storage.failWrites = true;
    await expectLater(
      payments.initiatePayment(
        sessionId: session.id,
        phoneNumber: '0241234567',
        network: MoolreNetwork.mtn,
      ),
      throwsStateError,
    );
    expect(calls, 0);
    payments.close();
    client.close();
  });

  test(
    'mismatched provider fields and boolean success never become paid',
    () async {
      for (final change in [
        {'txstatus': true},
        {'externalref': 'wrong'},
        {'amount': '0.71'},
        {'amount': true},
        {'accountnumber': null},
        {'accountnumber': 'wrong'},
        {'currency': 'NGN'},
      ]) {
        final storage = MemoryPaymentStorage();
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/payment')) {
            return http.Response('{"status":1,"code":"TR099"}', 200);
          }
          final body = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': {
                'txstatus': 1,
                'externalref': body['id'],
                'amount': '0.70',
                'accountnumber': 'account',
                ...change,
              },
            }),
            200,
          );
        });
        final payments = gateway(storage, client);
        final session = await payments.createSession(
          orderId: 'order_001',
          idempotencyKey: 'request_key_001',
        );
        await payments.initiatePayment(
          sessionId: session.id,
          phoneNumber: '0241234567',
          network: MoolreNetwork.mtn,
        );
        expect((await payments.getSession(session.id)).verified, isFalse);
        payments.close();
        client.close();
      }
    },
  );

  test(
    'live and sandbox have separate persisted references and correct endpoints',
    () async {
      final storage = MemoryPaymentStorage();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"status":1,"code":"TR099"}', 200);
      });
      final sandbox = gateway(
        storage,
        client,
        environment: MoolreEnvironment.sandbox,
      );
      final live = gateway(
        storage,
        client,
        environment: MoolreEnvironment.live,
      );
      final a = await sandbox.createSession(
        orderId: 'order_001',
        idempotencyKey: 'same_request_key',
      );
      final b = await live.createSession(
        orderId: 'order_001',
        idempotencyKey: 'same_request_key',
      );
      expect(a.reference, isNot(b.reference));
      for (final pair in [(sandbox, a), (live, b)]) {
        await pair.$1.initiatePayment(
          sessionId: pair.$2.id,
          phoneNumber: '0241234567',
          network: MoolreNetwork.telecel,
        );
      }
      expect(requests.last.url.host, 'api.moolre.com');
      expect(requests.last.headers['X-API-PUBKEY'], 'public_key');
      expect(
        requests.first.url.toString(),
        'https://sandbox.moolre.com/open/transact/payment',
      );
      for (final request in requests) {
        expect(
          (jsonDecode(request.body) as Map).containsKey('skipotp'),
          isFalse,
        );
      }
      await expectLater(
        live.getSession(a.id),
        throwsA(isA<MoolrePaymentException>()),
      );
      sandbox.close();
      live.close();
      client.close();
    },
  );

  test(
    'invalid responses and timeout remain pending, without closing a caller-owned client',
    () async {
      for (final response in [
        http.Response('{"status":1,"code":"TR099"}', 503),
        http.Response('{"status":1}', 302),
        http.Response('[]', 200),
        http.Response('x' * 65537, 200),
      ]) {
        final client = MockClient((_) async => response);
        final payments = gateway(MemoryPaymentStorage(), client);
        final session = await payments.createSession(
          orderId: 'order_001',
          idempotencyKey: 'request_key_001',
        );
        expect(
          (await payments.initiatePayment(
            sessionId: session.id,
            phoneNumber: '0241234567',
            network: MoolreNetwork.mtn,
          )).status,
          MoolrePaymentStatus.pending,
        );
        payments.close();
        client.close();
      }
      final late = Completer<http.Response>();
      final client = MockClient((_) => late.future);
      final payments = gateway(
        MemoryPaymentStorage(),
        client,
        timeout: const Duration(milliseconds: 20),
      );
      final session = await payments.createSession(
        orderId: 'order_001',
        idempotencyKey: 'request_key_001',
      );
      expect(
        (await payments.initiatePayment(
          sessionId: session.id,
          phoneNumber: '0241234567',
          network: MoolreNetwork.mtn,
        )).status,
        MoolrePaymentStatus.pending,
      );
      late.complete(http.Response('{"status":1,"code":"TP14"}', 200));
      payments.close();
      expect(
        (await client.get(Uri.parse('https://example.test'))).statusCode,
        200,
      );
      client.close();
    },
  );

  test(
    'credential rejection is explicit and malformed recovery fails closed',
    () async {
      final storage = MemoryPaymentStorage();
      final client = MockClient(
        (_) async => http.Response(
          '{"status":0,"code":"AIN01","message":"private"}',
          400,
        ),
      );
      final payments = gateway(storage, client);
      final session = await payments.createSession(
        orderId: 'order_001',
        idempotencyKey: 'request_key_001',
      );
      final failed = await payments.initiatePayment(
        sessionId: session.id,
        phoneNumber: '0241234567',
        network: MoolreNetwork.mtn,
      );
      expect(failed.status, MoolrePaymentStatus.failed);
      expect(failed.message, isNot(contains('private')));
      payments.close();
      storage.records.values.single['session']['amountMinor'] = 71;
      final restored = gateway(storage, client);
      await expectLater(restored.loadSavedSession(), throwsFormatException);
      restored.close();
      client.close();
    },
  );

  test(
    'live options and required collection settings fail before requests',
    () {
      final storage = MemoryPaymentStorage();
      for (final values in [
        {
          'account': '',
          'key': 'key',
          'mode': MoolreEnvironment.sandbox,
          'amount': 70,
        },
        {
          'account': 'account',
          'key': '',
          'mode': MoolreEnvironment.live,
          'amount': 70,
        },
        {
          'account': 'account',
          'key': 'key',
          'mode': MoolreEnvironment.sandbox,
          'amount': 0,
        },
      ]) {
        expect(
          () => MoolreDirectPaymentGateway(
            apiUser: 'user',
            accountNumber: values['account'] as String,
            publicKey: values['key'] as String,
            environment: values['mode'] as MoolreEnvironment,
            amountMinor: values['amount'] as int,
            orderId: 'order_001',
            storage: storage,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'unused expiry allows a fresh key while dispatched expiry stays pending',
    () async {
      final storage = MemoryPaymentStorage();
      final client = MockClient(
        (_) async => http.Response('{"status":1,"data":{"txstatus":2}}', 200),
      );
      final first = gateway(storage, client);
      final original = await first.createSession(
        orderId: 'order_001',
        idempotencyKey: 'request_key_001',
      );
      first.close();
      storage.records.values.single['session']['expiresAt'] = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final restored = gateway(storage, client);
      expect(
        (await restored.loadSavedSession())!.status,
        MoolrePaymentStatus.expired,
      );
      expect(
        (await restored.createSession(
          orderId: 'order_001',
          idempotencyKey: 'request_key_001',
        )).id,
        original.id,
      );
      final next = await restored.createSession(
        orderId: 'order_001',
        idempotencyKey: 'new_request_key',
      );
      expect(next.id, isNot(original.id));
      restored.close();
      final saved = storage.records.values.single;
      saved['session']['status'] = 'pending';
      saved['session']['expiresAt'] = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      saved['phone'] = '0241234567';
      saved['network'] = 'mtn';
      final pending = gateway(storage, client);
      expect(
        (await pending.loadSavedSession())!.status,
        MoolrePaymentStatus.pending,
      );
      pending.close();
      client.close();
    },
  );
}
