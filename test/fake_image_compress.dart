import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

class FakeImageCompress extends FlutterImageCompressPlatform {
  FakeImageCompress(this.result);

  final Uint8List result;

  Uint8List? input;
  int? minWidth;
  int? minHeight;
  int? quality;
  int? inSampleSize;

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    input = image;
    this.minWidth = minWidth;
    this.minHeight = minHeight;
    this.quality = quality;
    this.inSampleSize = inSampleSize;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
