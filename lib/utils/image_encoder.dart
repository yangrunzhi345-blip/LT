import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageEncoder {
  static const int maxWidth = 1024;
  static const int maxSizeBytes = 512 * 1024; // 512KB

  /// 将图片文件编码为 Base64，自动压缩
  static Future<String> encodeToBase64(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ImageEncodeException('图片文件不存在');
    }

    Uint8List bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ImageEncodeException('无法解码图片，请确认格式为 JPG 或 PNG');
    }
    img.Image image = decoded;

    if (image.width > maxWidth) {
      image = img.copyResize(image, width: maxWidth);
    }

    Uint8List jpeg = img.encodeJpg(image, quality: 75);

    int retries = 0;
    while (jpeg.length > maxSizeBytes && retries < 2) {
      image = img.copyResize(image, width: (image.width * 0.7).round());
      jpeg = img.encodeJpg(image, quality: 60);
      retries++;
    }

    return base64Encode(jpeg);
  }
}

class ImageEncodeException implements Exception {
  final String message;
  ImageEncodeException(this.message);
  @override
  String toString() => message;
}
