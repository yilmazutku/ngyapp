// file_handler_mobile.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<String> parseDocx(Uint8List bytes) async {
  // Implement parsing logic compatible with web
  return docxToText(bytes);
}

Future<void> handleFile(
    Uint8List fileBytes,
    String fileName,
    Function(String text, String filePath) onSuccess,
    Function(String error) onError) async {
  try {
    // Save the file locally
    Directory tempDir = await getTemporaryDirectory();
    String localPath = path.join(tempDir.path, fileName);
    File localFile = File(localPath);
    await localFile.writeAsBytes(fileBytes);

    // Parse the file content
    String text = await parseDocx(fileBytes);
    onSuccess(text, localPath);
  } catch (e) {
    onError(e.toString());
  }
}
