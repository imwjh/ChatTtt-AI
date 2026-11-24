# Downsize

 
|  | Origin | Compressed |
|--|--|--|
| size | 2.1 MB | 312 KB |
| image |  <a href="https://raw.githubusercontent.com/YassineDabbous/downsize/refs/heads/main/example/test.png"><img src="https://raw.githubusercontent.com/YassineDabbous/downsize/refs/heads/main/example/compressed.png" align="left" height="100" width="100"></a> | <a href="https://raw.githubusercontent.com/YassineDabbous/downsize/refs/heads/main/example/compressed.png"><img src="https://raw.githubusercontent.com/YassineDabbous/downsize/refs/heads/main/example/compressed.png" align="left" height="100" width="100"></a> |


**Downsize** is a pure Dart package for image compression across multiple formats, such as JPG, PNG, GIF, BMP, TIFF, TGA, PVR, and ICO. It effectively reduces file sizes while maintaining image quality, featuring dynamic resizing and format-specific compression techniques. Whether you're optimizing images for web or mobile applications, Downsize is designed to be flexible and easy to use.

This package is built on top of the **[image](https://pub.dev/packages/image)** Dart package, providing additional functionality for compression and resizing with an easy-to-use API.

## Features

- Supports compression for a wide range of image formats: JPG, PNG, GIF, BMP, TIFF, TGA, PVR, ICO, and more.
- Dynamically resizes images based on dimensions to prevent unnecessarily large files.
- Customizable compression quality and target file size.
- Specific compression techniques for different formats, such as reducing color depth for PNG files.
- Built-in extensions for easy integration with Uint8List and File objects.

## Getting started

### Prerequisites

- Dart SDK version **2.12.0** or higher: [Install Dart](https://dart.dev/get-dart).

### Installation

1. Add **downsize** to your project’s `pubspec.yaml` file:

```yaml
dependencies:
  downsize:
```

2. Install the dependencies:

```bash
dart pub get
```

## Usage

Here’s a simple example to compress an image using **Downsize**:

```dart
import 'dart:io';
import 'package:downsize/downsize.dart';

void main() async {
  File imageFile = File('path/to/your/image.jpg'); // Replace with any supported format

  // Using "downsize" extension on File class.
  Uint8List? compressedData = await imageFile.downsize(data: imageData);

  // OR
  // Using "downsize" extension on Uint8List class.
  Uint8List imageData = await imageFile.readAsBytes();
  Uint8List? compressedData = await imageData.downsize(data: imageData);

  // OR
  // Using Downsize class
  Uint8List imageData = await imageFile.readAsBytes();
  Uint8List? compressedData = await Downsize.downsize(data: imageData, maxSize: 500, minQuality: 60); // Compress to 500 KB with 60% as minimum quality
  
  // Save compressed image.
  if (compressedData != null) {
    await File('path/to/save/compressed_image.jpg').writeAsBytes(compressedData);
  }
}
```

The same function works with all supported image formats. Simply provide the image data and specify the desired file size or compression quality.

## Additional information

For more information, visit the [repository](https://github.com/YassineDabbous/downsize). You can report issues or contribute by opening a pull request or an issue on GitHub.

### Contributing

Contributions are welcome! Please ensure your code follows best practices and the included lints. To contribute:
1. Fork the repository.
2. Create a feature branch.
3. Submit a pull request.

Thank you for using **Downsize**!