import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/app.dart';
import 'package:sticker_maker/services/image_export_service.dart';

void main() {
  testWidgets('Splash screen renders Bocchi Stickers and Kessoku themes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: StickerMakerApp(),
      ),
    );

    expect(find.text('BOCCHI STICKERS'), findsOneWidget);
    expect(find.text('Bocchi'), findsOneWidget);
    expect(find.text('Kita'), findsOneWidget);
    expect(find.text('Ryo'), findsOneWidget);
    expect(find.text('Nijika'), findsOneWidget);
  });

  group('ImageExportService header validation', () {
    test('detects valid RIFF WEBP header', () {
      final validHeader = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x24,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(ImageExportService.hasValidWebpHeader(validHeader), isTrue);
    });

    test('rejects invalid PNG header as WebP', () {
      final pngHeader = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
      ]);
      expect(ImageExportService.hasValidWebpHeader(pngHeader), isFalse);
    });
  });
}
