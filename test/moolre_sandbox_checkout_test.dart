import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'moolre_direct_payment_gateway_test.dart' show MemoryPaymentStorage;

/// Fake of the documented sandbox endpoints: /embed/link and status lookup.
class SandboxProvider {
  final links = <Map<String, dynamic>>[];
  final statusChecks = <Map<String, dynamic>>[];
  int? txstatus;
  String statusCode = 'SS01';
  bool loseLink = false, badReceipt = false;
  String authorizationUrl = 'https://sandbox.moolre.com/checkout_code';
  Map<String, dynamic>? rejectLink;
  MemoryPaymentStorage? storage;
  List<String>? statusesAtLinkRequest;
  late final client = MockClient((request) async {
    expect(request.url.host, 'sandbox.moolre.com');
    expect(request.headers['X-API-USER'], 'user');
    expect(request.headers['X-API-PUBKEY'], 'sandbox_key');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path == '/open/transact/status') {
      statusChecks.add(body);
      if (txstatus == null) {
        return http.Response(
          jsonEncode({
            'status': 1,
            'code': 'SS07',
            'data': {'txstatus': 3},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 1,
          'code': statusCode,
          'data': {
            'txstatus': txstatus,
            'externalref': badReceipt ? 'other_reference' : body['id'],
            'accountnumber': 'account',
            'amount': '0.70',
          },
        }),
        200,
      );
    }
    expect(request.url.path, '/embed/link');
    links.add(body);
    statusesAtLinkRequest = [
      for (final Map<String, dynamic> record
          in storage?.records.values ?? const <Map<String, dynamic>>[])
        (record['session'] as Map)['status'] as String,
    ];
    if (rejectLink != null) {
      return http.Response(jsonEncode(rejectLink), 400);
    }
    if (loseLink) throw http.ClientException('Lost link response');
    return http.Response(
      jsonEncode({
        'status': 1,
        'code': 'POS09',
        'message': 'POS payment link successfully generated.',
        'data': {
          'authorization_url': authorizationUrl,
          'reference': body['externalref'],
        },
      }),
      200,
    );
  });
}

MoolreDirectPaymentGateway sandboxGateway(
  MemoryPaymentStorage storage,
  SandboxProvider provider,
) {
  provider.storage = storage;
  return MoolreDirectPaymentGateway(
    apiUser: 'user',
    accountNumber: 'account',
    publicKey: 'sandbox_key',
    merchantEmail: 'merchant@example.com',
    orderId: 'order_001',
    amountMinor: 70,
    storage: storage,
    client: provider.client,
  );
}

Future<MoolreHostedCheckout> begin(MoolreDirectPaymentGateway gateway) async {
  final session = await gateway.createSession(
    orderId: 'order_001',
    idempotencyKey: 'sandbox_request_key',
  );
  expect(gateway.usesHostedCheckout, isTrue);
  return gateway.startHostedCheckout(session.id);
}

void main() {
  test(
    'creates the documented sandbox link after saving a claim, then verifies',
    () async {
      final storage = MemoryPaymentStorage();
      final provider = SandboxProvider();
      final gateway = sandboxGateway(storage, provider);
      final started = await begin(gateway);
      expect(started.url.toString(), provider.authorizationUrl);
      expect(started.session.status, MoolrePaymentStatus.pending);
      expect(provider.statusesAtLinkRequest, ['pending']);
      expect(provider.links.single, {
        'type': 1,
        'amount': '0.70',
        'email': 'merchant@example.com',
        'externalref': started.session.reference,
        'redirect': defaultMoolreHostedReturnUrl.toString(),
        'reusable': '0',
        'currency': 'GHS',
        'accountnumber': 'account',
      });
      expect(
        (await gateway.getSession(started.session.id)).status,
        MoolrePaymentStatus.pending,
      );
      provider.txstatus = 1;
      final paid = await gateway.getSession(started.session.id);
      expect(paid.isSuccessful, isTrue);
      expect(provider.statusChecks.last['id'], started.session.reference);
      gateway.close();
    },
  );

  test('reopening, and restoring from storage, reuse the same page', () async {
    final storage = MemoryPaymentStorage();
    final provider = SandboxProvider();
    final gateway = sandboxGateway(storage, provider);
    final first = await begin(gateway);
    final again = await gateway.startHostedCheckout(first.session.id);
    expect(again.url, first.url);
    gateway.close();
    final restored = sandboxGateway(storage, provider);
    final saved = (await restored.loadSavedSession())!;
    expect(restored.usesHostedCheckout, isTrue);
    expect((await restored.startHostedCheckout(saved.id)).url, first.url);
    expect(provider.links, hasLength(1));
    restored.close();
  });

  test('a lost link response retries with the same reference', () async {
    final storage = MemoryPaymentStorage();
    final provider = SandboxProvider()..loseLink = true;
    final gateway = sandboxGateway(storage, provider);
    final lost = await begin(gateway);
    expect(lost.url, isNull);
    expect(lost.session.status, MoolrePaymentStatus.pending);
    provider.loseLink = false;
    final retried = await gateway.startHostedCheckout(lost.session.id);
    expect(retried.url.toString(), provider.authorizationUrl);
    expect(provider.links, hasLength(2));
    expect(provider.links.map((link) => link['externalref']).toSet(), {
      lost.session.reference,
    });
    gateway.close();
  });

  test('a rejected link fails with the provider message', () async {
    final storage = MemoryPaymentStorage();
    final provider = SandboxProvider()
      ..rejectLink = {
        'status': 0,
        'code': 'INP01',
        'message': ['Email is required'],
      };
    final gateway = sandboxGateway(storage, provider);
    final rejected = await begin(gateway);
    expect(rejected.url, isNull);
    expect(rejected.session.status, MoolrePaymentStatus.failed);
    expect(rejected.session.message, 'Moolre: Email is required');
    gateway.close();
  });

  test('a duplicate reference stays pending for status lookup', () async {
    final storage = MemoryPaymentStorage();
    final provider = SandboxProvider()
      ..rejectLink = {
        'status': 0,
        'code': 'INP02',
        'message': 'Transaction already exits!',
      };
    final gateway = sandboxGateway(storage, provider);
    final duplicate = await begin(gateway);
    expect(duplicate.url, isNull);
    expect(duplicate.session.status, MoolrePaymentStatus.pending);
    gateway.close();
  });

  test('page URLs outside Moolre are never opened', () async {
    final storage = MemoryPaymentStorage();
    final provider = SandboxProvider()
      ..authorizationUrl = 'https://moolre.example.com/checkout_code';
    final gateway = sandboxGateway(storage, provider);
    final started = await begin(gateway);
    expect(started.url, isNull);
    expect(started.session.status, MoolrePaymentStatus.pending);
    gateway.close();
  });

  test(
    'failed status needs the original receipt; unknown stays pending',
    () async {
      final storage = MemoryPaymentStorage();
      final provider = SandboxProvider();
      final gateway = sandboxGateway(storage, provider);
      final started = await begin(gateway);
      final id = started.session.id;
      expect(
        (await gateway.getSession(id)).status,
        MoolrePaymentStatus.pending,
      );
      provider
        ..txstatus = 3
        ..statusCode = 'SS02'
        ..badReceipt = true;
      expect(
        (await gateway.getSession(id)).status,
        MoolrePaymentStatus.pending,
      );
      provider.badReceipt = false;
      expect((await gateway.getSession(id)).status, MoolrePaymentStatus.failed);
      gateway.close();
    },
  );

  test(
    'attempts from the former in-app sandbox flow are status-checked only',
    () async {
      final storage = MemoryPaymentStorage();
      final provider = SandboxProvider();
      final key = jsonEncode(['sandbox', 'user', 'account', 'order_001']);
      storage.records[key] = {
        'session': {
          'id': 'legacy_session',
          'orderId': 'order_001',
          'reference': 'moolre_legacy_session',
          'amountMinor': 70,
          'currency': 'GHS',
          'status': 'sandbox_outcome_required',
          'verified': false,
          'message': null,
          'expiresAt': null,
        },
        'requestKey': 'legacy_request_key',
        'phone': '0201234567',
        'network': 'telecel',
        'sandboxCheckout': {
          'initClaimed': true,
          'otpVerified': true,
          'link': 'checkout_code',
          'transaction': 'provider_tx',
          'otpTransaction': '42',
        },
      };
      final gateway = sandboxGateway(storage, provider);
      final saved = (await gateway.loadSavedSession())!;
      expect(saved.status, MoolrePaymentStatus.pending);
      expect(gateway.usesHostedCheckout, isFalse);
      expect((await gateway.startHostedCheckout(saved.id)).url, isNull);
      provider.txstatus = 1;
      expect((await gateway.getSession(saved.id)).isSuccessful, isTrue);
      expect(provider.links, isEmpty);
      expect(storage.records[key]!.containsKey('sandboxCheckout'), isFalse);
      gateway.close();
    },
  );

  test('live never uses hosted checkout', () async {
    final gateway = MoolreDirectPaymentGateway(
      apiUser: 'user',
      accountNumber: 'account',
      publicKey: 'live_key',
      environment: MoolreEnvironment.live,
      orderId: 'order_001',
      amountMinor: 70,
      storage: MemoryPaymentStorage(),
      client: MockClient((_) async => throw StateError('No requests')),
    );
    final session = await gateway.createSession(
      orderId: 'order_001',
      idempotencyKey: 'live_request_key',
    );
    expect(gateway.usesHostedCheckout, isFalse);
    await expectLater(
      gateway.startHostedCheckout(session.id),
      throwsA(isA<MoolrePaymentException>()),
    );
    gateway.close();
  });
}
