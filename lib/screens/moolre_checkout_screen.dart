import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MoolreCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final String? callbackUrl;
  final void Function(String reference)? onSuccess;
  final void Function(String code, String message)? onError;

  const MoolreCheckoutScreen({
    Key? key,
    required this.checkoutUrl,
    this.callbackUrl,
    this.onSuccess,
    this.onError,
  }) : super(key: key);

  @override
  State<MoolreCheckoutScreen> createState() => _MoolreCheckoutScreenState();
}

class _MoolreCheckoutScreenState extends State<MoolreCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            // 💡 Detect deep link and launch outside WebView
            if (url.startsWith('moolre://')) {
              _launchDeepLink(Uri.parse(url));
              return NavigationDecision.prevent; // stop WebView
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            _handleNavigation(url);
          },
          onWebResourceError: (error) {
            widget.onError?.call('WEBVIEW_ERROR', error.description);
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _handleNavigation(String url) {
    if (widget.callbackUrl != null && url.startsWith(widget.callbackUrl!)) {
      final uri = Uri.parse(url);
      final reference = uri.queryParameters['reference'];
      if (reference != null) {
        widget.onSuccess?.call(reference);
      } else {
        widget.onError?.call(
          'MISSING_REFERENCE',
          'Payment reference not found',
        );
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _launchDeepLink(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      widget.onError?.call(
        'DEEP_LINK_LAUNCH_FAILED',
        'Could not launch deep link',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            widget.onError?.call(
              'USER_CANCELLED',
              'Payment was cancelled by user',
            );
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
