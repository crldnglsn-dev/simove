import 'dart:io';

import 'package:image/image.dart' as img;

Future<void> main() async {
  final dir = Directory('D:/System Project/simove/logo/');
  File? source;
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last.toLowerCase();
    if (name.contains('removebg')) source = e;
  }
  if (source == null) {
    stderr.writeln('No removebg source found in logo folder.');
    exitCode = 1;
    return;
  }
  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode ${source.path}');
    exitCode = 1;
    return;
  }
  stderr.writeln('source=${source.path} ${decoded.width}x${decoded.height}');
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
