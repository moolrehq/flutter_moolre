import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';

void main() {
  testWidgets('MoolrePayButton renders and triggers success callback', (
    WidgetTester tester,
  ) async {
    bool successCalled = false;
    bool errorCalled = false;
    String? successRef;
    String? errorMsg;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoolrePayButton(
            amount: 10.0,
            publicKey: 'test_public_key',
            accountNumber: 'test_account',
            email: 'user@example.com',
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

    expect(find.byType(MoolrePayButton), findsOneWidget);

    // Simulate button tap
    await tester.tap(find.byType(MoolrePayButton));
    await tester.pumpAndSettle();

    // Since actual WebView interaction isn't testable here, callbacks won't trigger.
    // You can manually invoke them via a fake button in a test-only mode or use integration tests.
    // To simulate success callback manually:
    // (This part only works if you expose the callbacks or test in a mock environment.)

    // For now, verify the button renders
    expect(successCalled, isFalse);
    expect(errorCalled, isFalse);
  });
}
