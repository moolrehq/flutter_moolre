import 'dart:convert';
import 'package:flutter_moolre/flutter_moolre.dart';

class PaymentConfiguration {
  const PaymentConfiguration({
    this.apiUser = '',
    this.accountNumber = '',
    this.publicKey = '',
    this.merchantEmail = '',
    this.initialMode = 'sandbox',
  });
  const PaymentConfiguration.fromEnvironment()
    : apiUser = const String.fromEnvironment('MOOLRE_API_USER'),
      accountNumber = const String.fromEnvironment('MOOLRE_ACCOUNT_NUMBER'),
      publicKey = const String.fromEnvironment('MOOLRE_PUBLIC_KEY'),
      merchantEmail = const String.fromEnvironment('MOOLRE_EMAIL'),
      initialMode = const String.fromEnvironment(
        'MOOLRE_ENVIRONMENT',
        defaultValue: 'sandbox',
      );
  final String apiUser, accountNumber, publicKey, merchantEmail, initialMode;
  String get identity => jsonEncode([apiUser, accountNumber]);
  MoolreEnvironment get initialEnvironment => initialMode == 'live'
      ? MoolreEnvironment.live
      : MoolreEnvironment.sandbox;
  List<String> problems(MoolreEnvironment environment) {
    final issues = <String>[];
    if (!['sandbox', 'live'].contains(initialMode)) {
      issues.add('MOOLRE_ENVIRONMENT must be sandbox or live.');
    }
    for (final field in {
      'MOOLRE_API_USER': apiUser,
      'MOOLRE_ACCOUNT_NUMBER': accountNumber,
      if (environment == MoolreEnvironment.live || publicKey.isNotEmpty)
        'MOOLRE_PUBLIC_KEY': publicKey,
      // The sandbox payment page is created with the business email.
      if (environment == MoolreEnvironment.sandbox || merchantEmail.isNotEmpty)
        'MOOLRE_EMAIL': merchantEmail,
    }.entries) {
      if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(field.value)) {
        issues.add('${field.key} is missing or invalid.');
      }
    }
    return issues;
  }
}
