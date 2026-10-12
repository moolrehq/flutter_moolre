import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'package:flutter_moolre_example/payment_configuration.dart';
import 'package:flutter_moolre_example/payment_storage.dart';
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('RUN_MOOLRE_SANDBOX_TEST');
  const config = PaymentConfiguration.fromEnvironment();

  // The hosted page itself runs in a native WebView, outside Flutter's reach,
  // so this checks the real link creation and status lookup it depends on.
  testWidgets(
    'real Moolre sandbox creates a hosted payment page',
    (tester) async {
      expect(config.problems(MoolreEnvironment.sandbox), isEmpty);
      final orderId = const Uuid().v4();
      final gateway = MoolreDirectPaymentGateway(
        apiUser: config.apiUser,
        accountNumber: config.accountNumber,
        publicKey: config.publicKey,
        merchantEmail: config.merchantEmail,
        environment: MoolreEnvironment.sandbox,
        orderId: orderId,
        amountMinor: 70,
        storage: await FilePaymentStorage.open(),
      );
      addTearDown(gateway.close);
      final session = await gateway.createSession(
        orderId: orderId,
        idempotencyKey: const Uuid().v4(),
      );
      final started = await gateway.startHostedCheckout(session.id);
      expect(
        started.url,
        isNotNull,
        reason: started.session.message ?? 'No sandbox payment page returned.',
      );
      expect(started.url!.host, endsWith('moolre.com'));
      final checked = await gateway.getSession(session.id);
      expect(checked.isSuccessful, isFalse);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
