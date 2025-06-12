import 'package:flutter/material.dart';
import 'package:flutter_moolre/screens/moolre_checkout_screen.dart';
import 'package:flutter_moolre/services/moolre_payment_service.dart';

class MoolrePayButton extends StatefulWidget {
  final double amount;
  final String publicKey;
  final String accountNumber;
  final String currency;
  final String? email;
  final String? reference;
  final String? callbackUrl;
  final ButtonStyle? style;
  final void Function(String reference)? onSuccess;
  final void Function(String code, String message)? onError;

  const MoolrePayButton({
    Key? key,
    required this.amount,
    required this.publicKey,
    required this.accountNumber,
    this.currency = 'GHS',
    this.email,
    this.reference,
    this.callbackUrl,
    this.style,
    this.onSuccess,
    this.onError,
  }) : super(key: key);

  @override
  State<MoolrePayButton> createState() => _MoolrePayButtonState();
}

class _MoolrePayButtonState extends State<MoolrePayButton> {
  bool _isProcessing = false;

  Future<void> _initiatePayment() async {
    setState(() => _isProcessing = true);
    try {
      final response = await MoolrePaymentService.initiatePayment(
        publicKey: widget.publicKey,
        accountNumber: widget.accountNumber,
        amount: widget.amount,
        currency: widget.currency,
        email: widget.email,
        reference: widget.reference,
        callback: widget.callbackUrl,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MoolreCheckoutScreen(
            checkoutUrl: response['authorization_url'],
            callbackUrl: widget.callbackUrl,
            onSuccess: widget.onSuccess,
            onError: widget.onError,
          ),
        ),
      );
    } catch (e) {
      widget.onError?.call('INITIATION_FAILED', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style:
          widget.style ??
          ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF142A4A),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      onPressed: _isProcessing ? null : _initiatePayment,
      child: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'packages/flutter_moolre/assets/images/moolre_logo.png',
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pay with Moolre',
                  style: TextStyle(
                    color:
                        widget.style?.foregroundColor?.resolve({}) ??
                        Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
    );
  }
}
