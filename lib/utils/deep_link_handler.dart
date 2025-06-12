import 'dart:async';
import 'package:flutter/services.dart';

class MoolreDeepLinkHandler {
  static const MethodChannel _channel = MethodChannel('moolre/deeplink');
  static bool _isProcessing = false;

  static bool isMoolreCallback(String url) {
    return url.startsWith('moolre://payment-callback');
  }

  static Map<String, String>? parseMoolreCallback(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters;
    } catch (e) {
      return null;
    }
  }

  static Future<void> configureDeepLinks({
    required void Function(String reference) onSuccess,
    required void Function(String code, String message) onError,
  }) async {
    // Handle initial link (cold start)
    try {
      final String? initialLink = await _channel.invokeMethod<String>(
        'getInitialLink',
      );
      if (initialLink != null && isMoolreCallback(initialLink)) {
        await _processDeepLink(initialLink, onSuccess, onError);
      }
    } catch (e) {
      onError('DEEP_LINK_ERROR', 'Failed to get initial link: ${e.toString()}');
    }

    // Listen for new incoming links (hot/warm start)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLinkReceived') {
        final String? uriString = call.arguments;
        if (uriString != null && isMoolreCallback(uriString)) {
          await _processDeepLink(uriString, onSuccess, onError);
        }
      }
    });
  }

  static Future<void> _processDeepLink(
    String url,
    void Function(String reference) onSuccess,
    void Function(String code, String message) onError,
  ) async {
    if (_isProcessing) return;
    _isProcessing = true;

    final params = parseMoolreCallback(url);
    final reference = params?['reference'];
    final status = params?['status'];

    if (reference == null) {
      onError('MISSING_REFERENCE', 'Payment reference not found');
      _isProcessing = false;
      return;
    }

    if (status == 'success') {
      onSuccess(reference);
    } else {
      onError('PAYMENT_FAILED', 'Payment was not successful');
    }

    _isProcessing = false;
  }

  static void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
