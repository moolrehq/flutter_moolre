import 'package:flutter/material.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'pages/payment_result_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoolreApp());
}

class MoolreApp extends StatelessWidget {
  const MoolreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moolre Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF8F8F8),
      ),
      home: const MoolreExamplePage(),
    );
  }
}

class MoolreExamplePage extends StatefulWidget {
  const MoolreExamplePage({super.key});

  @override
  State<MoolreExamplePage> createState() => _MoolreExamplePageState();
}

class _MoolreExamplePageState extends State<MoolreExamplePage> {
  final List<Map<String, dynamic>> _cart = [
    {"name": "Wireless Headphones", "price": 0.5, "quantity": 1},
    {"name": "Bluetooth Speaker", "price": 0.2, "quantity": 1},
  ];

  @override
  void initState() {
    super.initState();
    _configureDeepLinks();
  }

  @override
  void dispose() {
    MoolreDeepLinkHandler.dispose();
    super.dispose();
  }

  void _configureDeepLinks() {
    MoolreDeepLinkHandler.configureDeepLinks(
      onSuccess: _handlePaymentSuccess,
      onError: _handlePaymentError,
    );
  }

  void _handlePaymentSuccess(String reference) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PaymentResultPage(isSuccess: true, reference: reference),
      ),
    );
  }

  void _handlePaymentError(String code, String message) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentResultPage(
          isSuccess: false,
          errorCode: code,
          errorMessage: message,
        ),
      ),
    );
  }

  double get _totalAmount {
    return _cart.fold(
      0,
      (sum, item) => sum + (item["price"] * item["quantity"]),
    );
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _cart[index]["quantity"] += delta;
      if (_cart[index]["quantity"] <= 0) {
        _cart.removeAt(index);
      }
    });
  }

  void _addRandomProduct() {
    final sampleProducts = [
      "Smart Watch",
      "USB Charger",
      "Gaming Mouse",
      "LED Bulb",
      "Water Bottle",
      "Backpack",
    ];

    setState(() {
      _cart.add({
        "name": sampleProducts[_cart.length % sampleProducts.length],
        "price": double.parse((0.1 + (_cart.length * 0.2)).toStringAsFixed(2)),
        "quantity": 1,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moolre Payment Example'), elevation: 0),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Checkout',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ..._cart.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item["name"],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'GHS ${item["price"]}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        color: Colors.red,
                                        onPressed: () => _updateQuantity(
                                          index,
                                          -item["quantity"],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(),
                          InkWell(
                            onTap: _addRandomProduct,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: const [
                                  Icon(Icons.add_circle, color: Colors.green),
                                  SizedBox(width: 6),
                                  Text(
                                    'Add Random Item',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'GHS ${_totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_cart.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Center(
                                child: SizedBox(
                                  width: 280,
                                  child: MoolrePayButton(
                                    amount: _totalAmount,
                                    publicKey: '',
                                    accountNumber: '',
                                    currency: 'GHS',
                                    email: 'customer@example.com',
                                    reference:
                                        'order_${DateTime.now().millisecondsSinceEpoch}',
                                    callbackUrl: 'moolre://payment-callback',
                                    onSuccess: _handlePaymentSuccess,
                                    onError: _handlePaymentError,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: const BorderSide(
                                          color: Color(0xFFFDB93C),
                                        ),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
