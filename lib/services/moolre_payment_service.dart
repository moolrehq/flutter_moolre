import 'dart:convert';
import 'package:http/http.dart' as http;

class MoolrePaymentService {
  static const String _apiUrl = 'https://api.moolre.com/embed/src/start';

  static Future<Map<String, dynamic>> initiatePayment({
    required String publicKey,
    required String accountNumber,
    required double amount,
    required String currency,
    String? email,
    String? reference,
    String? callback,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'X-Api-Pubkey': publicKey,
    };

    final body = json.encode({
      'state': 'starter',
      'accountnumber': accountNumber,
      'reference':
          reference ?? 'moolre_${DateTime.now().millisecondsSinceEpoch}',
      'email': email ?? '',
      'amount': amount,
      'currency': currency,
      'callback': callback ?? 'moolre://payment-callback',
      'tx_source': 'flutter-sdk',
    });

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: headers,
      body: body,
    );

    final jsonResponse = json.decode(response.body);

    final status = jsonResponse['status'];
    final message = jsonResponse['message']?.toString() ?? '';
    final hasUrl = jsonResponse['data']?['authorization_url'] != null;

    if ((status != true && status != 1) && !hasUrl) {
      throw Exception(
        message.isNotEmpty ? message : 'Payment initiation failed',
      );
    }

    return {
      'authorization_url': jsonResponse['data']['authorization_url'],
      'reference': jsonResponse['data']['reference'],
    };
  }

  static Future<Map<String, dynamic>> verifyPayment({
    required String publicKey,
    required String accountNumber,
    required String reference,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'X-Api-Pubkey': publicKey,
    };

    final body = json.encode({
      'state': 'confirm',
      'accountnumber': accountNumber,
      'reference': reference,
    });

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: headers,
      body: body,
    );

    final jsonResponse = json.decode(response.body);

    if (response.statusCode != 200 || jsonResponse['status'] != true) {
      throw Exception(jsonResponse['message'] ?? 'Payment verification failed');
    }

    return jsonResponse['data'];
  }
}
