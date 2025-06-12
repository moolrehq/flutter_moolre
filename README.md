# flutter_moolre

is a modern Flutter plugin for seamless integration with the **Moolre Payments** platform. Accept mobile payments in Ghana with a single button and beautiful in-app checkout flow.

---

## ✨ Features

- ✅ One-line payment integration
- ✅ Secure WebView checkout
- ✅ Callback handling via deep links or custom URLs
- ✅ Customizable payment button
- ✅ Lightweight, clean API
- ✅ Handles success, cancellation, and errors
- ✅ Built for production apps

---

## 📦 Installation

Add `flutter_moolre` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_moolre: ^1.0.0
```

Then run:

```bash
flutter pub get
```

> ⚠️ Make sure your app supports WebView. You may need to configure Android/iOS WebView permissions appropriately.

---

## 🚀 Quick Start

### 1. Import the Button

```dart
import 'package:flutter_moolre/flutter_moolre.dart';
```

### 2. Use the `MoolrePayButton`

```dart
MoolrePayButton(
  amount: 50.0,
  publicKey: 'your_public_key',
  accountNumber: 'your_account_number',
  email: 'user@example.com',
  onSuccess: (reference) {
    print('Payment successful. Ref: \$reference');
  },
  onError: (code, message) {
    print('Payment failed [\$code]: \$message');
  },
)
```

> 💡 Want to handle redirection with your backend or a browser URL? Use the optional `callbackUrl` prop:

```dart
callbackUrl: 'https://yourdomain.com/payment/callback'
```

---

## 🛒 Example Checkout UI

```dart
import 'package:flutter/material.dart';
import 'package:flutter_moolre/flutter_moolre.dart';

class ExampleCheckout extends StatelessWidget {
  final products = [
    {'id': '1', 'name': 'Sneakers', 'price': 120.0},
    {'id': '2', 'name': 'T-Shirt', 'price': 40.0},
    {'id': '3', 'name': 'Cap', 'price': 25.0},
  ];

  double get total =>
      products.fold(0, (sum, item) => sum + (item['price'] as double));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ...products.map(
              (item) => ListTile(
                title: Text(item['name'] as String),
                trailing: Text('GHS \${(item['price'] as double).toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Total: GHS \${total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            MoolrePayButton(
              amount: total,
              publicKey: 'your_public_key',
              accountNumber: 'your_account_number',
              email: 'user@example.com',
              onSuccess: (ref) => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Success'),
                  content: Text('Payment ref: \$ref'),
                ),
              ),
              onError: (code, message) => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Error [\$code]'),
                  content: Text(message),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 🧠 MoolrePayButton Props

| Prop            | Type                                | Required | Description                          |
| --------------- | ----------------------------------- | -------- | ------------------------------------ |
| `amount`        | `double`                            | ✅       | Payment amount in Ghana cedis (GHS)  |
| `publicKey`     | `String`                            | ✅       | Your Moolre public API key           |
| `accountNumber` | `String`                            | ✅       | Your Moolre merchant account number  |
| `currency`      | `String`                            | ❌       | Defaults to "GHS"                    |
| `email`         | `String?`                           | ❌       | Customer email address               |
| `reference`     | `String?`                           | ❌       | Optional payment reference           |
| `callbackUrl`   | `String?`                           | ❌       | Optional redirect URL after payment  |
| `style`         | `ButtonStyle?`                      | ❌       | Custom button styling                |
| `onSuccess`     | `Function(String reference)`        | ✅       | Triggered on successful payment      |
| `onError`       | `Function(String code, String msg)` | ✅       | Triggered on failure or cancellation |

---

## 📱 Deep Link Handling

By default, `flutter_moolre` uses Flutter’s navigation stack. You can optionally handle redirects using deep links or a custom URL via the `callbackUrl` prop.

> Want a smoother UX? Add a custom success screen and failure fallback to your deep link logic.

---

## 💻 WebView & Platform Notes

- **Android:** Ensure `INTERNET` permission is enabled in `AndroidManifest.xml`.
- **iOS:** Add `NSAppTransportSecurity` exceptions for the Moolre domain if needed.

---

## 🤝 Contributing

We welcome pull requests and feature suggestions!

1. Fork this repo
2. Make your changes in a feature branch
3. Submit a PR — let’s improve mobile payments together!

---

## 📄 License

MIT License © Moolre HQ\
Built with ❤️ in Ghana.
