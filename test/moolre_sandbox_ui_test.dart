import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'support/fake_gateway.dart';

Future<MoolrePaymentController> pumpCheckout(
  WidgetTester tester,
  FakeGateway gateway,
  MoolreHostedCheckoutLauncher launcher,
) async {
  final controller = MoolrePaymentController(
    gateway: gateway,
    orderId: 'order_001',
    hostedCheckoutLauncher: launcher,
  )..pause();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MoolreCheckoutScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// Pending checkout animates a progress bar while polling, so it never settles.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'sandbox opens the hosted page and trusts only the status check',
    (tester) async {
      final gateway = FakeGateway()..sandbox = true;
      final opened = <(Uri, Uri)>[];
      final controller = await pumpCheckout(tester, gateway, (
        url,
        returnUrl,
      ) async {
        opened.add((url, returnUrl));
        expect(
          checkoutController(tester).phase,
          MoolreCheckoutPhase.hostedCheckout,
        );
        gateway
          ..status = MoolrePaymentStatus.succeeded
          ..verified = true;
        return MoolreHostedCheckoutEvent.redirected;
      });
      expect(find.text('Pay on the Moolre sandbox page'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<MoolreNetwork>), findsNothing);
      await tester.tap(find.text('Continue to pay GHS 50.00'));
      await tester.pumpAndSettle();
      expect(opened.single.$1, gateway.hostedUrl);
      expect(opened.single.$2, gateway.hostedReturnUrl);
      expect(gateway.checks, 1);
      expect(find.text('Payment received'), findsOneWidget);
      expect(controller.result.isSuccessful, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('closing the page leaves payment pending and can reopen it', (
    tester,
  ) async {
    final gateway = FakeGateway()..sandbox = true;
    var launches = 0;
    final controller = await pumpCheckout(tester, gateway, (_, _) async {
      launches++;
      if (launches == 2) gateway.status = MoolrePaymentStatus.failed;
      return MoolreHostedCheckoutEvent.closed;
    });
    await tester.tap(find.text('Continue to pay GHS 50.00'));
    await settle(tester);
    expect(find.text('Sandbox payment pending'), findsOneWidget);
    expect(controller.result.outcome, MoolrePaymentOutcome.pending);
    await tester.ensureVisible(find.text('Reopen Moolre payment page'));
    await tester.tap(find.text('Reopen Moolre payment page'));
    await tester.pumpAndSettle();
    expect(gateway.hostedStarts, 2);
    expect(controller.result.outcome, MoolrePaymentOutcome.failed);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a browser error keeps the claimed payment pending', (
    tester,
  ) async {
    final gateway = FakeGateway()..sandbox = true;
    final controller = await pumpCheckout(
      tester,
      gateway,
      (_, _) => throw const MoolrePaymentException(
        'HOSTED_CHECKOUT_UNAVAILABLE',
        'The Moolre payment page is not supported on this platform.',
      ),
    );
    await tester.tap(find.text('Continue to pay GHS 50.00'));
    await settle(tester);
    expect(controller.phase, MoolreCheckoutPhase.pending);
    expect(
      find.text('The Moolre payment page is not supported on this platform.'),
      findsOneWidget,
    );
    expect(controller.result.outcome, MoolrePaymentOutcome.pending);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final status in [
    MoolrePaymentStatus.ready,
    MoolrePaymentStatus.pending,
  ]) {
    testWidgets(
      'sandbox ${status.name} fits small screen with large text and keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final gateway = FakeGateway()
          ..sandbox = true
          ..status = status;
        final controller = MoolrePaymentController(
          gateway: gateway,
          orderId: 'order_001',
        )..pause();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: MoolreCheckoutScreen(controller: controller)),
          ),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.text(
            status == MoolrePaymentStatus.ready
                ? 'Continue to pay GHS 50.00'
                : 'Reopen Moolre payment page',
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}

MoolrePaymentController checkoutController(WidgetTester tester) => tester
    .widget<MoolreCheckoutScreen>(find.byType(MoolreCheckoutScreen))
    .controller;
