import 'dart:math';
import 'dart:typed_data';

import 'package:family_health/services/importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a big photo is stored as a JPEG at most 1600 px long', () async {
    // A photo-like page: speckled, so it doesn't compress to almost nothing as PNG.
    final page = img.Image(width: 2400, height: 3200);
    final rnd = Random(1);
    for (final p in page) {
      final v = 200 + rnd.nextInt(56);
      p.setRgb(v, v, v);
    }
    final photo = img.encodePng(page);
    final out = await ImportService.compactImage(photo);
    final back = img.decodeJpg(out)!;
    expect((back.width, back.height), (1200, 1600));
    expect(out.length, lessThan(photo.length));
  });

  test('a small photo keeps its size and something unreadable is left alone', () async {
    final small = img.encodeJpg(img.Image(width: 800, height: 600));
    expect(img.decodeJpg(await ImportService.compactImage(small))!.width, 800);
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(await ImportService.compactImage(junk), junk);
  });
}
