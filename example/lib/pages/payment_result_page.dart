import 'package:flutter/material.dart';

class PaymentResultPage extends StatelessWidget {
  final bool isSuccess;
  final bool isSandbox;
  final String? reference;
  final String? errorCode;
  final String? errorMessage;

  const PaymentResultPage({
    super.key,
    required this.isSuccess,
    this.isSandbox = false,
    this.reference,
    this.errorCode,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
      appBar: AppBar(
        title: Text(isSandbox ? 'Sandbox result' : 'Payment result'),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle : Icons.error,
                    size: 80,
                    color: isSuccess ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isSandbox
                        ? (isSuccess
                              ? 'Sandbox payment successful'
                              : 'Sandbox payment failed')
                        : (isSuccess ? 'Payment Successful' : 'Payment Failed'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isSuccess ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isSandbox) ...[
                    const Text(
                      'This attempt used Moolre sandbox. It is a test payment.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isSuccess)
                    Text('Reference: $reference')
                  else
                    Text('Error: [$errorCode] $errorMessage'),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
