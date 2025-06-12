import 'package:flutter/material.dart';

class PaymentResultPage extends StatelessWidget {
  final bool isSuccess;
  final String? reference;
  final String? errorCode;
  final String? errorMessage;

  const PaymentResultPage({
    super.key,
    required this.isSuccess,
    this.reference,
    this.errorCode,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
      appBar: AppBar(
        title: const Text('Payment Result'),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
      body: Center(
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
                isSuccess ? 'Payment Successful' : 'Payment Failed',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              if (isSuccess)
                Text('Reference: $reference')
              else
                Text('Error: [$errorCode] $errorMessage'),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
