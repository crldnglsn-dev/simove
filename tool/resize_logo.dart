import 'dart:io';

import 'package:image/image.dart' as img;

/// One-off helper: converts the generated SIMOVE logo images into the PNG
/// sizes used by the app assets and launcher icons.
Future<void> main() async {
  final source = File('D:/System Project/simove/logo/main app icon.jpg');
  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode ${source.path}');
    exitCode = 1;
    return;
  }
  for (final size in [1024, 512, 432]) {
    final resized = img.copyResize(decoded, width: size, height: size);
    final bytes = img.encodePng(resized);
    final name = size == 432 ? 'adaptive' : size.toString();
    final out = File(
      'D:/System Project/simove/assets/logo/simove_icon_$name.png',
    );
    await out.writeAsBytes(bytes);
    stderr.writeln('Wrote ${out.path} $size');
  }
}
