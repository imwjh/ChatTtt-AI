import 'dart:typed_data';

import 'package:downsize/downsize.dart';

/// helpful extensions for Uint8List.
extension Uint8ListDownsize on Uint8List {
  /// return data size in KB.
  double get sizeKb => (lengthInBytes / 1024).roundToDouble();

  /// Decrease data size.
  Future<Uint8List?> downsize({
    int minQuality = 60,
    double? maxSize,
  }) =>
      Downsize.downsize(data: this, minQuality: minQuality, maxSize: maxSize);
}
