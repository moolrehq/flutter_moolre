import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moolre/flutter_moolre.dart';
import 'support/fake_gateway.dart';

void main() {
  setUpAll(() async {
    // Widget tests default to Ahem. Load the SDK fonts for readable QA renders.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final flutter = (config['packages'] as List).cast<Map>().firstWhere(
      (package) => package['name'] == 'flutter',
    );
    final packageUri = configFile.uri.resolve('${flutter['rootUri']}/');
    final fonts = packageUri.resolve(
      '../../bin/cache/artifacts/material_fonts/',
    );
    for (final entry in {
      'Roboto': ['roboto-regular.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final filename in entry.value) {
        final bytes = await File.fromUri(fonts.resolve(filename)).readAsBytes();
        loader.addFont(Future.value(bytes.buffer.asByteData()));
      }
      await loader.load();
    }
  });
  for (final variant in [
    (MoolrePaymentStatus.ready, false),
    (MoolrePaymentStatus.otpRequired, false),
    (MoolrePaymentStatus.pending, false),
    (MoolrePaymentStatus.ready, true),
    (MoolrePaymentStatus.pending, true),
  ]) {
    final status = variant.$1;
    final name = '${status.name}${variant.$2 ? '_sandbox' : ''}';
    testWidgets('native layout at phone size: $name', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeGateway()
        ..status = status
        ..sandbox = variant.$2;
      final controller = MoolrePaymentController(
        gateway: gateway,
        orderId: 'order_001',
      )..pause();
      final imageKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: imageKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF142A4A),
              ),
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFFE8ECF1),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: MoolreCheckoutScreen(
                    controller: controller,
                    notice:
                        'Moolre sandbox test. No live payment is collected.',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(
            'assets/images/moolre_logo.png',
            package: 'flutter_moolre',
          ),
          tester.element(find.byType(MoolreCheckoutScreen)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            imageKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/native_checkout_preview')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('small screen and large text remain scrollable with keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final controller = MoolrePaymentController(
      gateway: FakeGateway(),
      orderId: 'order_001',
    )..pause();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: MoolreCheckoutScreen(
            controller: controller,
            notice: 'Moolre sandbox test. No live payment is collected.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      find.text('Moolre sandbox test. No live payment is collected.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Pay GHS 50.00'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
