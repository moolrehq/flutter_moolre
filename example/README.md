# flutter_moolre example

A sample shop cart that pays through the plugin against the **real** Moolre
sandbox and live APIs. Only the products are fake; there is no simulated payment
provider, backend server or hardcoded OTP.

## 1. Add your credentials

Copy `payment-config.example.json` to `payment-config.json` (Git ignores it)
and fill it in:

```json
{
  "MOOLRE_ENVIRONMENT": "sandbox",
  "MOOLRE_API_USER": "your-moolre-username",
  "MOOLRE_ACCOUNT_NUMBER": "your-account-number",
  "MOOLRE_PUBLIC_KEY": "your-public-key",
  "MOOLRE_EMAIL": "you@yourbusiness.com"
}
```

| Key | Needed for | What it is |
| --- | --- | --- |
| `MOOLRE_API_USER` | Sandbox and live | Your Moolre username |
| `MOOLRE_ACCOUNT_NUMBER` | Sandbox and live | Your Moolre account number |
| `MOOLRE_PUBLIC_KEY` | Live (sent in sandbox if set) | Your **public** key. Never use a private key |
| `MOOLRE_EMAIL` | Sandbox | Business email Moolre uses to create the sandbox page |
| `MOOLRE_ENVIRONMENT` | — | Mode on first launch: `sandbox` or `live`. Afterwards the app remembers your choice |

If something is missing, the app shows which key under the cart and disables
the pay button for that mode.

## 2. Run it

```sh
flutter pub get
flutter run --dart-define-from-file=payment-config.json
```

The values are compiled into the app, so **rebuild after changing the file**.
Switching Sandbox/Live inside the app doesn't need a rebuild. Since the public
key ends up in the APK, don't share test builds widely.

## 3. Try a sandbox payment

1. Select **Sandbox** at the top. The cart starts at GHS 0.70; add, remove or
   change items as you like.
2. Tap **Pay with Moolre**, then **Continue to pay**. Moolre's sandbox page
   opens inside the app.
3. Enter a test number (for example `0241234567`), choose a provider and tap
   **Confirm**.
4. Type the **Sandbox OTP** shown on the page and tap **Authorize**. No SMS is sent.
5. Choose **Success**, **Pending** or **Failed**.
6. The page closes (or tap ✕). The app asks Moolre for the payment status and
   shows the confirmed result.

If the result is pending, the cart stays locked. Use **Reopen Moolre payment
page** to go back to the same payment, or **Check payment status**.

## 4. Live payments

Select **Live** (enabled only when a public key is configured). Checkout is
native: choose the network, enter the mobile-money number, enter the SMS code
if asked, and approve the prompt on the phone. **Live moves real money.**

## How the demo behaves

- Sandbox and live each keep their own cart and payment, saved in the app's
  private storage, so payments survive restarts.
- The cart is locked while a payment is unresolved. That way a pending payment
  can't be silently replaced by a new one. A successful payment offers
  **Start a new test cart**.
- **Start a separate sandbox test** appears for sandbox payments started by
  older versions of the app. It starts a new cart while keeping the old one,
  and **Saved sandbox tests** lets you switch back to it.
- Don't uninstall the app or clear its data while a payment is pending.

## Tests

```sh
flutter test
```

These tests use fake storage and never contact Moolre. An opt-in device test
creates a real GHS 0.70 **sandbox** payment page and checks its status. The page
itself runs in a native WebView, so finish the OTP and outcome steps by hand in
the app:

```sh
flutter test integration_test/plugin_integration_test.dart -d YOUR_DEVICE_ID --dart-define-from-file=payment-config.json --dart-define=RUN_MOOLRE_SANDBOX_TEST=true
```
