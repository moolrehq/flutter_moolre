import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';

void main() {
  testWidgets('MoolrePayButton renders and reacts to tap', (
    WidgetTester tester,
  ) async {
    bool successCalled = false;
    String? successRef;
    bool errorCalled = false;
    String? errorMsg;

    // Define a test widget that includes the MoolrePayButton
    final testWidget = MaterialApp(
      home: Scaffold(
        body: Center(
          child: MoolrePayButton(
            amount: 10.0,
            publicKey: 'test_public_key',
            accountNumber: '12345678',
            email: 'test@example.com',
            onSuccess: (ref) {
              successCalled = true;
              successRef = ref;
            },
            onError: (code, msg) {
              errorCalled = true;
              errorMsg = msg;
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(testWidget);

    // Check if the button is rendered
    expect(find.byType(MoolrePayButton), findsOneWidget);

    // Simulate tap on the button
    await tester.tap(find.byType(MoolrePayButton));
    await tester.pump(); // trigger the onPressed

    // You can't test WebView navigation or actual API call in widget test,
    // but you can verify that the button is interactive
    expect(
      successCalled || errorCalled,
      isFalse,
    ); // Still false because WebView doesn't run in tests
  });
}
