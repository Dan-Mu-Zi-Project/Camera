import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> rotateAndFlipImage(Uint8List bytes,
    {bool flip = false, int rotateDegrees = 0}) async {
  return compute((Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final flip = args['flip'] as bool;
    final rotateDegrees = args['rotateDegrees'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;
    img.Image processed = original;
    if (flip) {
      processed = img.flipHorizontal(processed);
    }
    if (rotateDegrees != 0) {
      processed = img.copyRotate(processed, angle: rotateDegrees);
    }
    return Uint8List.fromList(img.encodeJpg(processed));
  }, {'bytes': bytes, 'flip': flip, 'rotateDegrees': rotateDegrees});
}
