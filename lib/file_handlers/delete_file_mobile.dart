// delete_file_mobile.dart
import 'dart:io';

Future<void> deleteFile(String filePath) async {
  final file = File(filePath);
  if (await file.exists()) {
    await file.delete();
  }
}
