import 'package:uuid/uuid.dart';

class DemoProduct {
  const DemoProduct(this.id, this.name, this.priceMinor);
  final String id, name;
  final int priceMinor;
}

const demoProducts = [
  DemoProduct('headphones', 'Wireless headphones', 50),
  DemoProduct('speaker', 'Bluetooth speaker', 20),
  DemoProduct('watch', 'Smart watch', 100),
  DemoProduct('charger', 'USB charger', 30),
  DemoProduct('bottle', 'Water bottle', 10),
  DemoProduct('backpack', 'Backpack', 80),
];

String formatGhs(int minor) =>
    'GHS ${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

class DemoCart {
  DemoCart({String? orderId, Map<String, int>? quantities})
    : orderId = orderId ?? const Uuid().v4(),
      quantities = Map.unmodifiable(
        quantities ?? {'headphones': 1, 'speaker': 1},
      );
  final String orderId;
  final Map<String, int> quantities;
  int get totalMinor => demoProducts.fold(
    0,
    (sum, product) => sum + product.priceMinor * (quantities[product.id] ?? 0),
  );
  DemoCart change(String id, int quantity) {
    if (!demoProducts.any((p) => p.id == id) || quantity < 0 || quantity > 99) {
      throw ArgumentError('Invalid cart quantity.');
    }
    final next = {...quantities};
    if (quantity == 0) {
      next.remove(id);
    } else {
      next[id] = quantity;
    }
    return DemoCart(quantities: next);
  }

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'quantities': quantities,
  };
  factory DemoCart.fromJson(Map<String, dynamic> value) {
    final order = value['orderId'];
    final items = value['quantities'];
    if (order is! String ||
        !RegExp(r'^[\w-]{1,200}$').hasMatch(order) ||
        items is! Map ||
        items.entries.any(
          (entry) =>
              !demoProducts.any((p) => p.id == entry.key) ||
              entry.value is! int ||
              entry.value < 1 ||
              entry.value > 99,
        )) {
      throw const FormatException('Invalid saved cart.');
    }
    return DemoCart(orderId: order, quantities: Map<String, int>.from(items));
  }
}
