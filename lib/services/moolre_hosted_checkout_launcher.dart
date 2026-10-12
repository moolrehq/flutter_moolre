import 'package:flutter/services.dart';
import '../models/moolre_payment.dart';

enum MoolreHostedCheckoutEvent { redirected, closed }

/// Opens Moolre's hosted payment page and completes when it closes.
typedef MoolreHostedCheckoutLauncher =
    Future<MoolreHostedCheckoutEvent> Function(Uri url, Uri returnUrl);

const _channel = MethodChannel('flutter_moolre/hosted_checkout');

/// Shows [url] in the plugin's in-app browser (Android WebView, iOS
/// WKWebView). The browser closes itself when the page navigates to
/// [returnUrl]. Neither event proves payment; confirm by status lookup.
Future<MoolreHostedCheckoutEvent> openMoolreHostedCheckout(
  Uri url,
  Uri returnUrl,
) async {
  try {
    final result = await _channel.invokeMapMethod<String, Object?>('open', {
      'url': url.toString(),
      'returnUrl': returnUrl.toString(),
      'title': 'Moolre checkout',
    });
    return result?['event'] == 'redirected'
        ? MoolreHostedCheckoutEvent.redirected
        : MoolreHostedCheckoutEvent.closed;
  } on MissingPluginException {
    throw const MoolrePaymentException(
      'HOSTED_CHECKOUT_UNAVAILABLE',
      'The Moolre payment page is not supported on this platform.',
    );
  } on PlatformException {
    throw const MoolrePaymentException(
      'HOSTED_CHECKOUT_ERROR',
      'Could not open the Moolre payment page. Check payment status.',
      retryable: true,
    );
  }
}
