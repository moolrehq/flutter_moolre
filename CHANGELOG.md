# Changelog

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
