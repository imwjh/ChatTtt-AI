import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> pickMimoReferenceAudioDataUri() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['mp3', 'wav'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.single;
  Uint8List? bytes = file.bytes;
  if (bytes == null && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException('The selected reference audio is empty.');
  }
  if (bytes.lengthInBytes > 10 * 1024 * 1024) {
    throw const FormatException('Reference audio must not exceed 10 MB.');
  }

  final name = file.name.toLowerCase();
  final mime = name.endsWith('.wav') ? 'audio/wav' : 'audio/mpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
