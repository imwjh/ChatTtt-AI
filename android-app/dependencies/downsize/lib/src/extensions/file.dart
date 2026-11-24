import 'dart:io';
import 'dart:typed_data';

import 'package:downsize/downsize.dart';

extension FileDownsize on File {
  /// Decrease file size.
  Future<Uint8List?> downsize({int minQuality = 60, double? maxSize}) =>
      Downsize.downsize(
          data: readAsBytesSync(), minQuality: minQuality, maxSize: maxSize);
}
