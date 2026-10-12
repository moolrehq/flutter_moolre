# Changelog

## [0.1.0] - 2026-10-12

A rewrite focused on verified payments. **Breaking:** see "Migrating from 0.0.1"
in the README.

### Added

- **Live checkout in native Flutter UI:** choose MTN, Telecel or AT, enter the
  number, enter the SMS code when Moolre asks, approve on the phone.
- **Sandbox checkout on Moolre's hosted sandbox page**, opened in an in-app
  browser built on the platform WebView (Android `WebView`, iOS `WKWebView`).
  The page shows the test OTP and lets you choose Success, Pending or Failed.
  The link is created with the documented `/embed/link` endpoint.
- Every outcome is confirmed with Moolre's `/open/transact/status`; success
  must match the original reference, amount and account.
- `MoolreDirectPaymentGateway` with `merchantEmail` (needed for sandbox).
- `MoolrePaymentController` and `MoolreCheckoutScreen` for custom UIs, including
  `usesHostedCheckout` and `openHostedCheckout()`.
- `MoolrePaymentStorage` for crash-safe recovery: the reference is saved before
  Moolre is contacted, and a restarted app checks the same payment instead of
  starting a new one.
- Optional `MoolrePaymentService` adapter for merchant backends.
- Example app: editable cart, Sandbox/Live switch, credentials from
  `payment-config.json`.

### Changed

- Amounts are integer minor units (`amountMinor: 5000` is GHS 50.00).
- `MoolrePayButton` takes a `gateway` and `orderId` instead of amount and keys.
- Closing checkout reports `dismissed` or `pending`, not an error.

### Removed

- WebView/deep-link checkout, `callbackUrl`, `MoolreDeepLinkHandler`.
- `webview_flutter`, `url_launcher` and `confetti` dependencies. The plugin has
  no third-party runtime dependencies besides `http` and `uuid`.

## [0.0.1] - 2025-06-12

### Added

- `PaymentResultPage`: Displays payment success or failure, with reference or error message.
- `onSuccess` and `onError` callbacks support in `MoolreCheckoutScreen`.
- Custom `MoolrePayButton` with full checkout flow example and payment state handling.

### Changed

- `MoolreCheckoutScreen` now detects deep links and invokes callbacks.
- `AppBar` close button in checkout screen now triggers `onError` with `USER_CANCELLED` and exits correctly.

### Fixed

- Navigation bug: closing the WebView after payment now correctly returns to the previous screen (e.g., form or result screen).
- Test cleanup: removed obsolete `flutter_moolre_platform_interface` and `flutter_moolre_method_channel`.
- Removed broken test `flutter_moolre_test.dart` due to refactor and simplified plugin implementation.
