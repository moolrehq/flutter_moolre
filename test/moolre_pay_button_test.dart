import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'support/fake_gateway.dart';

Future<void> chooseNetwork(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<MoolreNetwork>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('MTN').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an open checkout cannot overwrite a newly supplied resume session',
    (tester) async {
      final gateway = FakeGateway()
        ..creationCompleter = Completer<MoolrePaymentSession>();
      String? resumeId;
      late StateSetter updateParent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                updateParent = setState;
                return MoolrePayButton(
                  gateway: gateway,
                  orderId: 'order_001',
                  resumeSessionId: resumeId,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      updateParent(() => resumeId = 'session_new');
      await tester.pump();
      gateway.creationCompleter!.complete(gateway.session);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close payment sheet'));
      await tester.pumpAndSettle();
      gateway.overrideSession = const MoolrePaymentSession(
        id: 'session_new',
        orderId: 'order_001',
        reference: 'new_reference',
        amountMinor: 5000,
        currency: 'GHS',
        status: MoolrePaymentStatus.ready,
      );
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pumpAndSettle();
      expect(gateway.receivedSessionId, 'session_new');
      expect(gateway.creates, 1);
      await tester.tap(find.byTooltip('Close payment sheet'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'consumer callback errors are reported without changing payment results',
    (tester) async {
      final gateway = FakeGateway()
        ..status = MoolrePaymentStatus.succeeded
        ..verified = true;
      final results = <MoolrePaymentResult>[];
      var errors = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoolrePayButton(
              gateway: gateway,
              orderId: 'order_001',
              onSuccess: (_) => throw StateError('Application callback failed'),
              onError: (_, _) => errors++,
              onResult: results.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(results.single.isSuccessful, isTrue);
      expect(errors, 0);
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(results.length, 1);
    },
  );

  testWidgets('persisted request keys are rotated only by the caller', (
    tester,
  ) async {
    final gateway = FakeGateway()..status = MoolrePaymentStatus.failed;
    var requestKey = 'request_key_001';
    late StateSetter updateParent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              updateParent = setState;
              return MoolrePayButton(
                gateway: gateway,
                orderId: 'order_001',
                idempotencyKey: requestKey,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    expect(gateway.creates, 1);
    expect(gateway.receivedKey, 'request_key_001');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    updateParent(() => requestKey = 'request_key_002');
    gateway.status = MoolrePaymentStatus.ready;
    await tester.pump();
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    expect(gateway.creates, 2);
    expect(gateway.receivedKey, 'request_key_002');
    await tester.tap(find.byTooltip('Close payment sheet'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'closing during dispatch reports pending and ignores late completion',
    (tester) async {
      final gateway = FakeGateway()
        ..initiationCompleter = Completer<MoolrePaymentSession>();
      final results = <MoolrePaymentResult>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoolrePayButton(
              gateway: gateway,
              orderId: 'order_001',
              onResult: results.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pumpAndSettle();
      await chooseNetwork(tester);
      await tester.enterText(find.byType(TextFormField), '0241234567');
      await tester.tap(find.text('Pay GHS 50.00'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Close payment sheet'));
      await tester.pumpAndSettle();
      expect(results.single.outcome, MoolrePaymentOutcome.pending);
      gateway.status = MoolrePaymentStatus.pending;
      gateway.initiationCompleter!.complete(gateway.session);
      await tester.pump();
      expect(results.length, 1);
      expect(tester.takeException(), isNull);
      expect(gateway.initiations, 1);
    },
  );

  testWidgets('native phone and OTP flow returns verified success once', (
    tester,
  ) async {
    final gateway = FakeGateway();
    var successes = 0;
    final results = <MoolrePaymentResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoolrePayButton(
            gateway: gateway,
            orderId: 'order_001',
            onSuccess: (_) => successes++,
            onResult: results.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 50.00'), findsOneWidget);
    await chooseNetwork(tester);
    await tester.enterText(find.byType(TextFormField), '0241234567');
    await tester.tap(find.text('Pay GHS 50.00'));
    await tester.pumpAndSettle();
    expect(find.text('Verify your phone number'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify and continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Approve the payment on your phone'), findsOneWidget);
    expect(successes, 0);
    gateway.status = MoolrePaymentStatus.succeeded;
    gateway.verified = true;
    await tester.tap(find.text('Check payment status'));
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(successes, 1);
    expect(results.single.isSuccessful, isTrue);
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(successes, 1);
    expect(gateway.initiations, 1);
  });

  testWidgets(
    'closing pending checkout preserves caller route and resumes it',
    (tester) async {
      final gateway = FakeGateway()..requireOtp = false;
      final results = <MoolrePaymentResult>[];
      var errors = 0;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Home'))),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Column(
              children: [
                const Text('Order page'),
                MoolrePayButton(
                  gateway: gateway,
                  orderId: 'order_001',
                  onResult: results.add,
                  onError: (_, _) => errors++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pumpAndSettle();
      await chooseNetwork(tester);
      await tester.enterText(find.byType(TextFormField), '0241234567');
      await tester.tap(find.text('Pay GHS 50.00'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Close payment sheet'));
      await tester.pumpAndSettle();
      expect(results.single.outcome, MoolrePaymentOutcome.pending);
      expect(errors, 0);
      expect(find.text('Order page'), findsOneWidget);
      await tester.tap(find.text('Pay with Moolre'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateway.creates, 1);
      expect(gateway.initiations, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(results.last.outcome, MoolrePaymentOutcome.pending);
      expect(find.text('Order page'), findsOneWidget);
    },
  );

  testWidgets('invalid input never initiates payment and close is dismissal', (
    tester,
  ) async {
    final gateway = FakeGateway();
    MoolrePaymentResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoolrePayButton(
            gateway: gateway,
            orderId: 'order_001',
            onResult: (value) => result = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay with Moolre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay GHS 50.00'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your network.'), findsOneWidget);
    expect(gateway.initiations, 0);
    await tester.tap(find.byTooltip('Close payment sheet'));
    await tester.pumpAndSettle();
    expect(result?.outcome, MoolrePaymentOutcome.dismissed);
  });
}
