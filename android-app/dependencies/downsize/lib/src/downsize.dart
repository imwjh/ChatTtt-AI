import 'dart:typed_data';

import 'package:downsize/downsize.dart';
import 'package:image/image.dart';

/// Config class holds raw data with compression options.
class Config {
  /// initial image data.
  final Uint8List data;

  /// JPEG encoding quality.
  final int quality;

  /// minimum image quality.
  final int minQuality;

  /// desired file size.
  final double? maxSize;

  /// Maximum length of the image's longest edge.
  final int? maxLongEdge;

  Config({
    required this.data,
    this.quality = 90,
    this.minQuality = 60,
    this.maxSize,
    this.maxLongEdge,
  });
}

class Downsize {
  static Future<Uint8List?> downsize({
    required Uint8List data,
    int quality = 90,
    int minQuality = 60,
    double? maxSize,
    int? maxLongEdge,
  }) async {
    if (data.isEmpty) return data;
    return Downsize().compress(
      Config(
        data: data,
        quality: quality,
        minQuality: minQuality,
        maxSize: maxSize,
        maxLongEdge: maxLongEdge,
      ),
    );
  }

  /// Decode and Compress image data.
  Uint8List? compress(Config config) {
    Image? image = decodeImage(config.data, frame: 0);
    if (image == null) {
      throw Exception("Unsupported image type.");
    }

    image = _prepareImage(image, config);
    return compressJpg(image: image, config: config, preTreatment: false);
  }

  /// Compress JPG image.
  Uint8List compressJpg({
    required Image image,
    required Config config,
    int? quality,
    bool preTreatment = true,
  }) {
    if (preTreatment) {
      image = _prepareImage(image, config);
    }

    final currentQuality = (quality ?? config.quality).clamp(1, 100).toInt();
    final minQuality = config.minQuality.clamp(1, 100).toInt();
    final im = encodeJpg(image, quality: currentQuality);
    final nextQuality = currentQuality - 10;
    if (config.maxSize != null &&
        im.sizeKb > config.maxSize! &&
        nextQuality >= minQuality) {
      return compressJpg(
        image: image,
        config: config,
        quality: nextQuality,
        preTreatment: false,
      );
    }

    return im;
  }

  /// Compress PNG image.
  Uint8List compressPng({
    required Image image,
    required Config config,
    int level = 9,
  }) =>
      compressJpg(image: image, config: config);

  /// Resize the image to fit within [maxLongEdge].
  Image dynamicResize(Image image, {int? maxLongEdge}) {
    if (maxLongEdge == null ||
        maxLongEdge <= 0 ||
        (image.width <= maxLongEdge && image.height <= maxLongEdge)) {
      return image;
    }

    return copyResize(
      image,
      width: image.width >= image.height ? maxLongEdge : null,
      height: image.height > image.width ? maxLongEdge : null,
      interpolation: Interpolation.average,
    );
  }

  Image _prepareImage(Image image, Config config) {
    image = bakeOrientation(image);
    image.exif.clear();

    if (image.hasAlpha) {
      final background = Image(
        width: image.width,
        height: image.height,
        numChannels: 3,
      )..clear(ColorRgb8(255, 255, 255));
      image = compositeImage(background, image);
    }

    return dynamicResize(image, maxLongEdge: config.maxLongEdge);
  }
}
