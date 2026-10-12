import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'package:flutter_moolre_example/demo_cart.dart';
import 'package:flutter_moolre_example/main.dart';
import 'package:flutter_moolre_example/payment_configuration.dart';

class MemoryStorage implements MoolrePaymentStorage {
  final records = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String key) async => records[key] == null
      ? null
      : jsonDecode(jsonEncode(records[key])) as Map<String, dynamic>;
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    records[key] = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

const config = PaymentConfiguration(
  apiUser: 'user',
  accountNumber: 'account',
  publicKey: 'public_key',
  merchantEmail: 'merchant@example.com',
);

void main() {
  testWidgets('cart works without credentials and never needs a backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      MoolreApp(
        configuration: const PaymentConfiguration(),
        storage: MemoryStorage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('GHS 0.70'), findsOneWidget);
    expect(find.textContaining('MOOLRE_API_USER is missing'), findsOneWidget);
    expect(find.text('Backend configuration required'), findsNothing);
    expect(find.byType(MoolrePayButton), findsNothing);
  });

  testWidgets('quantity, remove, add, and empty cart use exact amounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MoolreApp(configuration: config, storage: MemoryStorage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Wireless headphones'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 1.20'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Bluetooth speaker'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 1.00'), findsOneWidget);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backpack - GHS 0.80'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 1.80'), findsOneWidget);
    final pay = tester.widget<MoolrePayButton>(find.byType(MoolrePayButton));
    expect((pay.gateway as MoolreDirectPaymentGateway).amountMinor, 180);
    await tester.tap(find.byTooltip('Remove Wireless headphones'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Backpack'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 0.00'), findsOneWidget);
    expect(
      find.text('Your cart is empty. Add an item to start checkout.'),
      findsOneWidget,
    );
    expect(find.byType(MoolrePayButton), findsNothing);
  });

  testWidgets('mode switch isolates carts and survives app reopening', (
    tester,
  ) async {
    final storage = MemoryStorage();
    await tester.pumpWidget(MoolreApp(configuration: config, storage: storage));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Wireless headphones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 0.70'), findsOneWidget);
    expect(
      find.textContaining('Money can be collected after approval'),
      findsOneWidget,
    );
    final pay = tester.widget<MoolrePayButton>(find.byType(MoolrePayButton));
    expect(
      (pay.gateway as MoolreDirectPaymentGateway).environment,
      MoolreEnvironment.live,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MoolreApp(configuration: config, storage: storage));
    await tester.pumpAndSettle();
    expect(find.textContaining('Live payment.'), findsOneWidget);
    await tester.tap(find.text('Sandbox'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 1.20'), findsOneWidget);
  });

  testWidgets('live is disabled without a public key', (tester) async {
    await tester.pumpWidget(
      MoolreApp(
        configuration: const PaymentConfiguration(
          apiUser: 'user',
          accountNumber: 'account',
          merchantEmail: 'merchant@example.com',
        ),
        storage: MemoryStorage(),
      ),
    );
    await tester.pumpAndSettle();
    final control = tester.widget<SegmentedButton<MoolreEnvironment>>(
      find.byType(SegmentedButton<MoolreEnvironment>),
    );
    expect(
      control.segments
          .singleWhere((segment) => segment.value == MoolreEnvironment.live)
          .enabled,
      isFalse,
    );
  });

  testWidgets('small screen and large text stay scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: MoolreExamplePage(
          configuration: config,
          storage: MemoryStorage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Pay with Moolre'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test(
    'cart recovery rejects corrupted quantities instead of silently changing totals',
    () {
      expect(
        () => DemoCart.fromJson({
          'orderId': 'order',
          'quantities': {'headphones': -1},
        }),
        throwsFormatException,
      );
      expect(
        () => DemoCart.fromJson({
          'orderId': 'order',
          'quantities': {'unknown': 1},
        }),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'recovered pending payment locks cart edits and retains its session',
    (tester) async {
      final storage = MemoryStorage();
      final cart = DemoCart(orderId: 'pending_order');
      await storage.write('${config.identity}:sandbox:cart', cart.toJson());
      final key = jsonEncode(['sandbox', 'user', 'account', 'pending_order']);
      await storage.write(key, {
        'requestKey': 'pending_request_key',
        'phone': '0241234567',
        'network': 'mtn',
        'session': {
          'id': 'pending_session',
          'orderId': 'pending_order',
          'reference': 'pending_reference',
          'amountMinor': 70,
          'currency': 'GHS',
          'status': 'pending',
          'verified': false,
        },
      });
      await tester.pumpWidget(
        MoolreApp(configuration: config, storage: storage),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Cart editing is paused'), findsOneWidget);
      final button = tester.widget<MoolrePayButton>(
        find.byType(MoolrePayButton),
      );
      expect(button.resumeSessionId, 'pending_session');
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Increase Wireless headphones',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Remove Wireless headphones',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('GHS 0.70'), findsOneWidget);
      await tester.ensureVisible(find.text('Start a separate sandbox test'));
      await tester.tap(find.text('Start a separate sandbox test'));
      await tester.pumpAndSettle();
      final fresh = tester.widget<MoolrePayButton>(
        find.byType(MoolrePayButton),
      );
      expect(fresh.resumeSessionId, isNull);
      expect(fresh.orderId, isNot('pending_order'));
      expect(find.textContaining('Cart editing is paused'), findsNothing);
      await tester.ensureVisible(find.text('Saved sandbox tests'));
      await tester.tap(find.text('Saved sandbox tests'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('pending_'));
      await tester.pumpAndSettle();
      final resumed = tester.widget<MoolrePayButton>(
        find.byType(MoolrePayButton),
      );
      expect(resumed.resumeSessionId, 'pending_session');
      expect(resumed.orderId, 'pending_order');
      expect(find.textContaining('Cart editing is paused'), findsOneWidget);
    },
  );
}
