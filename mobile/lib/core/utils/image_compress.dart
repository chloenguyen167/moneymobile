import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compress without cropping: re-encode JPEG at [quality] (default 70).
/// Optionally downscale long edge if larger than [maxEdge] while keeping aspect ratio.
Uint8List compressImageBytes(
  Uint8List bytes, {
  int quality = 70,
  int maxEdge = 2000,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  var image = decoded;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > maxEdge) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxEdge);
    } else {
      image = img.copyResize(image, height: maxEdge);
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
