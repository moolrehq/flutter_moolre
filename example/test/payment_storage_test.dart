import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre_example/payment_storage.dart';
import 'package:flutter_moolre_example/payment_configuration.dart';
import 'package:flutter_moolre/flutter_moolre.dart';

void main() {
  test(
    'atomic local storage survives reopening and preserves concurrent writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'moolre-local-storage-',
      );
      addTearDown(() async {
        final root = Directory.systemTemp.absolute.path;
        if (!directory.absolute.path.startsWith(
          '$root${Platform.pathSeparator}moolre-local-storage-',
        )) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/payments.json');
      final store = FilePaymentStorage(file);
      await Future.wait([
        store.write('sandbox', {'reference': 'sandbox_ref'}),
        store.write('live', {'reference': 'live_ref'}),
      ]);
      final reopened = FilePaymentStorage(file);
      expect((await reopened.read('sandbox'))!['reference'], 'sandbox_ref');
      expect((await reopened.read('live'))!['reference'], 'live_ref');
      await file.writeAsString('invalid json');
      await expectLater(
        FilePaymentStorage(file).read('sandbox'),
        throwsFormatException,
      );
    },
  );

  test(
    'sandbox needs username/account/email; live also needs a public key',
    () {
      const settings = PaymentConfiguration(
        apiUser: 'user',
        accountNumber: 'account',
        merchantEmail: 'merchant@example.com',
      );
      expect(settings.problems(MoolreEnvironment.sandbox), isEmpty);
      expect(settings.problems(MoolreEnvironment.live), [
        'MOOLRE_PUBLIC_KEY is missing or invalid.',
      ]);
      expect(
        const PaymentConfiguration(
          apiUser: 'user',
        ).problems(MoolreEnvironment.sandbox),
        [
          'MOOLRE_ACCOUNT_NUMBER is missing or invalid.',
          'MOOLRE_EMAIL is missing or invalid.',
        ],
      );
    },
  );
}
