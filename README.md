# flutter_moolre

Accept Ghanaian mobile-money payments (MTN, Telecel, AT) in Flutter through
[Moolre](https://moolre.com), with a ready-made **Pay with Moolre** button and a
checkout that only reports success after Moolre confirms the payment.

- **Live:** native Flutter checkout. The customer picks a network, enters a
  number, enters an SMS code if asked, and approves the prompt on their phone.
- **Sandbox:** Moolre's own sandbox payment page opens inside your app. It
  shows a test OTP on screen (no SMS) and lets you choose **Success**,
  **Pending** or **Failed**, so you can test every outcome without real money.
- **No third-party packages** for checkout. The in-app browser uses the
  platform's built-in WebView (Android `WebView`, iOS `WKWebView`).

> **Upgrading from 0.0.1?** 0.1.0 is a breaking release. See
> [Migrating from 0.0.1](#migrating-from-001).

## Contents

1. [How it works](#how-it-works)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Credentials](#credentials)
5. [Quick start](#quick-start)
6. [Testing in sandbox](#testing-in-sandbox)
7. [Handling the result](#handling-the-result)
8. [Saving payments across restarts](#saving-payments-across-restarts)
9. [Going live](#going-live)
10. [Custom checkout UI](#custom-checkout-ui)
11. [Using your own backend](#using-your-own-backend)
12. [Migrating from 0.0.1](#migrating-from-001)
13. [Example app and development](#example-app-and-development)

## How it works

|  | Live | Sandbox |
| --- | --- | --- |
| Server | `https://api.moolre.com` | `https://sandbox.moolre.com` |
| Checkout screen | Native Flutter bottom sheet | Moolre's hosted sandbox page in an in-app browser |
| Customer enters number | In the Flutter sheet | On the Moolre page |
| Verification code | Sent by SMS when Moolre asks (`TP14`) | Shown on the page; no SMS |
| Outcome | Customer approves on their phone | You choose Success, Pending or Failed |
| Moolre endpoints | `/open/transact/payment` | [`/embed/link`](https://docs.moolre.com/ai/sandbox/generate-payment-link.md) |
| How success is confirmed | `/open/transact/status` | `/open/transact/status` |

In both modes, **a payment is only "succeeded" when Moolre's status lookup
returns a paid transaction** with the same reference, amount and account.
Closing the sheet, a page redirect or a timeout never counts as paid.

### Sandbox flow, step by step

1. The customer taps **Pay with Moolre**, then **Continue to pay**.
2. The SDK saves the payment reference locally, then asks Moolre to create a
   payment page for that reference (`/embed/link`).
3. The page opens in the in-app browser. The payer enters a test number, types
   the OTP shown on the page, and chooses an outcome.
4. When the page finishes (or the payer closes it with ✕ or Back), the browser
   closes and the SDK checks the payment status with Moolre.
5. The sheet shows the confirmed result. If Moolre still reports it as pending,
   the sheet keeps checking and offers **Reopen Moolre payment page**.

## Requirements

- Flutter 3.32+ / Dart 3.8+
- Android 5.0+ (API 21). iOS 12+.
- A Moolre account: see [Credentials](#credentials).

## Installation

```yaml
dependencies:
  flutter_moolre: ^0.1.0
```

Then run `flutter pub get`. That's it:

- **Android:** the plugin adds the `INTERNET` permission and its checkout
  activity to your app automatically through manifest merging.
- **iOS:** nothing to configure. The plugin uses `WKWebView` (built into iOS)
  and only HTTPS, so no App Transport Security exceptions are needed.

## Credentials

| Value | Live | Sandbox | Notes |
| --- | --- | --- | --- |
| Username (`apiUser`) | Required | Required | Sent as `X-API-USER` |
| Account number (`accountNumber`) | Required | Required | Your Moolre wallet account |
| Public key (`publicKey`) | Required | Sent if set | Sent as `X-API-PUBKEY`. Public key only |
| Business email (`merchantEmail`) | Not used | Required | Moolre needs it to create the sandbox page |

**Never put a private or secret key in an app.** Anything compiled into an app
can be extracted. Load these values from your build configuration (for example
`--dart-define-from-file`, as the [example app](example/README.md) does) rather
than committing them.

## Quick start

```dart
import 'package:flutter_moolre/flutter_moolre.dart';

// One gateway per order and environment. Close it when you're done.
final payments = MoolreDirectPaymentGateway(
  apiUser: moolreUsername,
  accountNumber: moolreAccount,
  publicKey: moolrePublicKey,
  merchantEmail: moolreBusinessEmail, // Needed for sandbox.
  environment: MoolreEnvironment.sandbox, // or MoolreEnvironment.live
  orderId: order.id,
  amountMinor: order.totalPesewas, // Integer pesewas: 70 is GHS 0.70.
  storage: paymentStorage, // See "Saving payments across restarts".
);

MoolrePayButton(
  gateway: payments,
  orderId: order.id,
  checkoutNotice: 'Sandbox: test payments only.', // Optional banner.
  onSuccess: (reference) {
    // Moolre confirmed the payment. Show a receipt.
  },
  onError: (code, message) {
    // Failed or expired. Let the customer try again.
  },
  onResult: (result) {
    // Every outcome, including pending and dismissed.
  },
);

// When the order screen is disposed:
payments.close();
```

Amounts are **integer minor units** (pesewas) to avoid rounding errors. Use a new
`orderId` whenever the amount changes. A payment attempt is tied to its order,
amount and reference.

Prefer to open checkout yourself? `showMoolreCheckout(context: ..., gateway: ...,
orderId: ...)` shows the same sheet and returns a `MoolrePaymentResult`.

## Testing in sandbox

1. Create the gateway with `environment: MoolreEnvironment.sandbox` and your
   `merchantEmail`.
2. Tap **Pay with Moolre** → **Continue to pay**. Moolre's sandbox page opens.
3. Enter any Ghanaian number (for example `0241234567`) and pick a provider.
4. The page shows a **Sandbox OTP**. Type it and tap **Authorize**.
5. Choose an outcome:
   - **Success:** the app should show *Payment received*.
   - **Pending:** the app keeps the payment pending. Reopen the page to pick
     another outcome for the same payment.
   - **Failed:** the app shows *Payment was not completed*.

Sandbox moves no real money. The outcome you choose is recorded by Moolre, and
the app only shows it after reading it back from Moolre's status API.

## Handling the result

`onResult` (or the value returned by `showMoolreCheckout`) gives a
`MoolrePaymentResult`:

| `result.outcome` | Meaning | What to do |
| --- | --- | --- |
| `succeeded` | Moolre confirmed the payment (`result.isSuccessful` is true) | Show success; fulfil after your server also confirms (see [Going live](#going-live)) |
| `failed` | Moolre recorded a failure, or refused to create the payment | Let the customer retry; the button starts a fresh attempt |
| `expired` | The attempt was never used and expired (15 minutes) | Let the customer retry |
| `pending` | Not confirmed yet: approval outstanding, or the sheet was closed while waiting | **Do not treat as failed.** Keep the order open and check again later |
| `dismissed` | Closed before any payment was started | Nothing to do |

`result.session` holds the `reference` (your Moolre `externalref`), the amount
and Moolre's `message` when there is one.

## Saving payments across restarts

The gateway saves each attempt (its reference and status) through a
`MoolrePaymentStorage` **before** contacting Moolre. If the app is killed
mid-payment, the same reference is checked when the customer returns, so a
customer is never charged twice for one order.

```dart
abstract class MoolrePaymentStorage {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
}
```

- `write` must finish saving before it returns, and throw if it can't.
- The example's [`FilePaymentStorage`](example/lib/payment_storage.dart) is a
  ready-to-copy implementation that writes atomically to a JSON file.
- No OTPs or keys are ever stored. Don't clear this data while a payment is
  pending.

To resume an unfinished payment after a restart:

```dart
final saved = await payments.loadSavedSession(); // Reads storage only.
MoolrePayButton(
  gateway: payments,
  orderId: order.id,
  resumeSessionId: saved?.isTerminal == false ? saved!.id : null,
  // ...
);
```

## Going live

1. Switch to `environment: MoolreEnvironment.live` and provide `publicKey`.
2. Test a small real payment end to end on a real device.
3. **Confirm payments on your server before delivering anything.** The app's
   result is fine for showing a receipt, but an app can be modified, so it is
   not proof of payment. Have your server check the reference with
   `/open/transact/status` (or Moolre's webhook) before fulfilling the order.
4. Keep live and sandbox orders separate. The SDK stores them under different
   keys, and a sandbox reference never appears in live.

## Custom checkout UI

Build your own screens with `MoolrePaymentController`. It is UI-independent
and drives the same gateway:

```dart
final controller = MoolrePaymentController(gateway: payments, orderId: order.id);
await controller.initialize(); // Creates or resumes the session.

if (controller.usesHostedCheckout) {
  await controller.openHostedCheckout(); // Sandbox: opens the Moolre page.
} else {
  await controller.submitPhone('0241234567', MoolreNetwork.mtn);
  // If controller.phase == MoolreCheckoutPhase.otpRequired:
  await controller.submitOtp(codeFromUser);
}
```

- Listen to the controller (it's a `ChangeNotifier`) and read `phase`,
  `session`, `error` and `result`.
- While a payment is pending it polls status every 3 seconds for up to 2
  minutes. `refresh()` checks again on demand.
- Call `pause()`/`resume()` with your app lifecycle and `dispose()` at the end.
- `MoolreCheckoutScreen(controller: controller)` is the stock UI, if you want
  to embed it in your own route.

## Using your own backend

By default, `MoolreDirectPaymentGateway` calls Moolre straight from the app, so
your Moolre username, account and public key are compiled into the app. For a
production shop you may prefer to keep Moolre behind your own server.

`MoolrePaymentService` is a ready-made gateway for that setup. The app calls
**your** API, and your server calls Moolre.

### Why use it

- **No Moolre credentials in the app.** An app can be decompiled; a server can't.
- **Your server owns the price.** A modified app can't change the amount.
- **Your server confirms the payment** (status lookup or Moolre's webhook)
  before you deliver anything.

### How to use it

1. Implement the four endpoints in [the backend contract](doc/backend-contract.md):
   create a session, start the payment, submit an OTP, and get the status.
2. In the app, pass the service to the same button or checkout as usual:

```dart
final payments = MoolrePaymentService(
  baseUrl: Uri.parse('https://shop.example.com/api/moolre'), // HTTPS only.
  headersProvider: () async => {
    'Authorization': 'Bearer ${await auth.currentToken()}',
  },
);

MoolrePayButton(gateway: payments, orderId: order.id, onResult: handleResult);
```

`headersProvider` runs before every request, so tokens can refresh. Your server
must check that the signed-in customer owns the order or session in each request.

### Sandbox with a backend

With this service the app always shows the native phone-number checkout. It
doesn't open Moolre's hosted sandbox page. To test against sandbox, point your
server at `https://sandbox.moolre.com`. To test sandbox from the app
alone, use `MoolreDirectPaymentGateway` with `MoolreEnvironment.sandbox`.

## Migrating from 0.0.1

0.0.1 opened a WebView and treated the deep-link callback as success. 0.1.0
replaces that with verified payments:

| 0.0.1 | 0.1.0 |
| --- | --- |
| `MoolrePayButton(amount:, publicKey:, accountNumber:, …)` | Create a `MoolreDirectPaymentGateway`, then `MoolrePayButton(gateway:, orderId:)` |
| `amount: 50.0` (double, cedis) | `amountMinor: 5000` (int, pesewas) |
| `callbackUrl` / deep links / `MoolreDeepLinkHandler` | Removed: no URL schemes; status is read from Moolre |
| `onError(code, message)` on close | Closing is `dismissed` or `pending`, not an error |
| `webview_flutter`, `url_launcher` dependencies | None; built-in platform WebView for sandbox only |

## Example app and development

The [example app](example/README.md) is an editable cart with a Sandbox/Live
switch. It runs against the real Moolre APIs with your credentials.

```sh
flutter analyze
flutter test           # plugin tests (no network)
cd example
flutter test           # example tests (no network)
```

Tests use fake HTTP clients and never contact Moolre or move money. An opt-in
integration test creates a real sandbox payment page; see the example README.
Android has been tested on a device. The iOS code has not yet been built or
tested on a device.

Moolre API references: [sandbox payment link](https://docs.moolre.com/ai/sandbox/generate-payment-link.md),
[live collection](https://docs.moolre.com/ai/live/initiate-payment.md),
[payment status](https://docs.moolre.com/ai/live/payment-status.md).

MIT License.
