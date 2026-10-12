import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'support/fake_gateway.dart';

void main() {
  test(
    'an unavailable saved session remains pending until it can be checked',
    () async {
      final gateway = FakeGateway()
        ..checkCompleter = Completer<MoolrePaymentSession>();
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
        resumeSessionId: 'session_001',
        operationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.phase, MoolreCheckoutPhase.error);
      expect(controller.result.outcome, MoolrePaymentOutcome.pending);
      expect(controller.result.session, isNull);
      gateway.checkCompleter!.complete(gateway.session);
    },
  );

  test(
    'polling stops at the deadline even when the interval is longer',
    () async {
      final gateway = FakeGateway()..status = MoolrePaymentStatus.pending;
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
        pollInterval: const Duration(seconds: 1),
        pollingTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.pollingStopped, isTrue);
      expect(controller.result.outcome, MoolrePaymentOutcome.pending);
      expect(gateway.checks, 0);
    },
  );

  test(
    'custom gateway calls are bounded and late dispatch cannot alter results',
    () async {
      final gateway = FakeGateway()
        ..initiationCompleter = Completer<MoolrePaymentSession>();
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
        operationTimeout: const Duration(milliseconds: 10),
      )..pause();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(controller.isBusy, isFalse);
      expect(controller.error?.code, 'REQUEST_TIMEOUT');
      expect(controller.result.outcome, MoolrePaymentOutcome.pending);
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(gateway.initiations, 1);
      gateway.status = MoolrePaymentStatus.succeeded;
      gateway.verified = true;
      gateway.initiationCompleter!.complete(gateway.session);
      await Future<void>.delayed(Duration.zero);
      expect(controller.result.isSuccessful, isFalse);
      gateway.checkCompleter = Completer<MoolrePaymentSession>();
      await controller.refresh();
      expect(controller.isBusy, isFalse);
      expect(controller.error?.code, 'REQUEST_TIMEOUT');
      gateway.checkCompleter!.complete(gateway.session);
    },
  );

  test('refresh cannot bypass a failed session persistence callback', () async {
    final gateway = FakeGateway();
    var failStorage = true;
    var saves = 0;
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
      onSessionCreated: (_) {
        saves++;
        if (failStorage) throw StateError('Storage unavailable');
      },
    )..pause();
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.error?.code, 'SESSION_STORAGE_ERROR');
    await controller.refresh();
    await controller.submitPhone('0241234567', MoolreNetwork.mtn);
    expect(gateway.initiations, 0);
    expect(saves, 2);
    failStorage = false;
    await controller.refresh();
    await controller.submitPhone('0241234567', MoolreNetwork.mtn);
    expect(gateway.initiations, 1);
    expect(gateway.creates, 1);
  });

  test(
    'stale ready status cannot reopen collection or downgrade a paid session',
    () async {
      final gateway = FakeGateway()..requireOtp = false;
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
      )..pause();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      gateway.status = MoolrePaymentStatus.ready;
      await controller.refresh();
      expect(controller.error?.code, 'SESSION_MISMATCH');
      expect(controller.phase, MoolreCheckoutPhase.pending);
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(gateway.initiations, 1);
      gateway.status = MoolrePaymentStatus.succeeded;
      gateway.verified = true;
      await controller.refresh();
      final checks = gateway.checks;
      gateway.status = MoolrePaymentStatus.ready;
      gateway.verified = false;
      await controller.initialize();
      await controller.refresh();
      expect(controller.result.isSuccessful, isTrue);
      expect(gateway.checks, checks);
    },
  );

  test(
    'confirmed failed and expired sessions return terminal outcomes',
    () async {
      for (final status in [
        MoolrePaymentStatus.failed,
        MoolrePaymentStatus.expired,
      ]) {
        final gateway = FakeGateway()..status = status;
        final controller = MoolrePaymentController(
          gateway: gateway,
          orderId: 'order_001',
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.result.outcome.name, status.name);
        expect(controller.result.isSuccessful, isFalse);
        await controller.submitPhone('0241234567', MoolreNetwork.mtn);
        expect(gateway.initiations, 0);
      }
    },
  );

  test('OTP flow reports success only after verified status', () async {
    final gateway = FakeGateway();
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
    )..pause();
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, MoolreCheckoutPhase.ready);
    await controller.submitPhone('+233 24 123 4567', MoolreNetwork.mtn);
    expect(gateway.receivedPhone, '0241234567');
    expect(controller.phase, MoolreCheckoutPhase.otpRequired);
    expect(controller.result.isSuccessful, isFalse);
    await controller.submitOtp('123456');
    expect(controller.phase, MoolreCheckoutPhase.pending);
    expect(controller.result.outcome, MoolrePaymentOutcome.pending);
    gateway.status = MoolrePaymentStatus.succeeded;
    gateway.verified = true;
    await controller.refresh();
    expect(controller.result.isSuccessful, isTrue);
    expect(gateway.initiations, 1);
  });

  test('unverified success and a different order are rejected', () async {
    final gateway = FakeGateway()..status = MoolrePaymentStatus.succeeded;
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, MoolreCheckoutPhase.error);
    expect(controller.result.isSuccessful, isFalse);
    gateway.status = MoolrePaymentStatus.ready;
    gateway.overrideSession = const MoolrePaymentSession(
      id: 'other',
      orderId: 'other_order',
      reference: 'other',
      amountMinor: 5000,
      currency: 'GHS',
      status: MoolrePaymentStatus.ready,
    );
    await controller.initialize();
    expect(controller.error?.code, 'SESSION_MISMATCH');
  });

  test(
    'concurrent submissions dispatch once and disposal ignores completion',
    () async {
      final gateway = FakeGateway()
        ..initiationCompleter = Completer<MoolrePaymentSession>();
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
      );
      await controller.initialize();
      final first = controller.submitPhone('0241234567', MoolreNetwork.mtn);
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(gateway.initiations, 1);
      controller.dispose();
      gateway.initiationCompleter!.complete(gateway.session);
      await first;
    },
  );

  test(
    'lost response stays pending and prevents blind initiation retry',
    () async {
      final gateway = FakeGateway()
        ..initiationError = const MoolrePaymentException(
          'REQUEST_TIMEOUT',
          'Request timed out.',
          retryable: true,
        );
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
      )..pause();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(controller.result.outcome, MoolrePaymentOutcome.pending);
      await controller.submitPhone('0241234567', MoolreNetwork.mtn);
      expect(gateway.initiations, 1);
      gateway.status = MoolrePaymentStatus.pending;
      await controller.refresh();
      expect(controller.phase, MoolreCheckoutPhase.pending);
    },
  );

  test('session details cannot change during verification', () async {
    final gateway = FakeGateway()..requireOtp = false;
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
    )..pause();
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.submitPhone('0241234567', MoolreNetwork.mtn);
    gateway.overrideSession = const MoolrePaymentSession(
      id: 'session_001',
      orderId: 'order_001',
      reference: 'reference_001',
      amountMinor: 1,
      currency: 'GHS',
      status: MoolrePaymentStatus.succeeded,
      verified: true,
    );
    await controller.refresh();
    expect(controller.error?.code, 'SESSION_MISMATCH');
    expect(controller.result.isSuccessful, isFalse);
    expect(controller.session?.amountMinor, 5000);
  });

  test('resuming uses stored session and persistence is awaited', () async {
    final gateway = FakeGateway();
    final persisted = Completer<void>();
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
      resumeSessionId: 'session_001',
      onSessionCreated: (_) => persisted.future,
    );
    addTearDown(controller.dispose);
    final loading = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBusy, isTrue);
    expect(gateway.creates, 0);
    persisted.complete();
    await loading;
    expect(controller.isBusy, isFalse);
    expect(gateway.checks, 1);
  });

  test('bounded polling stops without failing the payment', () async {
    final gateway = FakeGateway()..status = MoolrePaymentStatus.pending;
    final controller = MoolrePaymentController(
      gateway: gateway,
      orderId: 'order_001',
      pollInterval: const Duration(milliseconds: 5),
      pollingTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(controller.pollingStopped, isTrue);
    expect(controller.result.outcome, MoolrePaymentOutcome.pending);
    final checks = gateway.checks;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.checks, checks);
    controller.pause();
    controller.resume();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.checks, greaterThan(checks));
  });
}
