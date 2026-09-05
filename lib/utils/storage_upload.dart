import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/logger.dart';

final Logger _log = Logger('StorageUpload');

/// Maximum accepted upload size, in bytes (50 MB).
///
/// Files larger than this are rejected up-front (with a clear message) instead
/// of being pushed through Storage. On Windows desktop `firebase_storage` runs
/// on the Firebase C++ SDK and an in-memory upload copies the whole byte buffer
/// across the Dart<->native boundary; a very large PDF can momentarily occupy
/// several times its own size in RAM and take the process down. Guarding the
/// size keeps a single pathological file from hanging or crashing the app.
const int kMaxUploadBytes = 50 * 1024 * 1024;

/// Human-readable form of [kMaxUploadBytes] for user-facing messages.
const String kMaxUploadSizeLabel = '50 MB';

const String kDocxContentType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Cleans [fileName] so it can be used as the last segment of a Cloud Storage
/// object name, keeping the name the user recognises (Turkish letters and
/// spaces included) and only replacing characters that are problematic in an
/// object path or in a `Content-Disposition` header.
String sanitizeStorageFileName(String fileName, {String fallback = 'dosya'}) {
  final leaf = fileName.split(RegExp(r'[\\/]')).last;
  final cleaned = leaf
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll(RegExp(r'[#\[\]*?"\\]'), '_')
      .trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

/// `Content-Disposition` value that makes a download save the file as
/// [fileName] instead of the generated object name.
///
/// Carries both the plain `filename` (ASCII fallback for old clients) and the
/// RFC 5987 `filename*`, so Turkish characters survive.
String attachmentContentDisposition(String fileName) {
  final ascii = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_')
      .replaceAll('"', '');
  return 'attachment; filename="$ascii"; '
      "filename*=UTF-8''${_encodeRfc5987(fileName)}";
}

/// Percent-encodes [value] leaving only RFC 3986 unreserved characters, as the
/// RFC 5987 `ext-value` grammar requires (`Uri.encodeComponent` is too lax: it
/// leaves `'`, `!`, `*`, `(`, `)` unescaped, which would break the header).
String _encodeRfc5987(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final bool unreserved = (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5F ||
        byte == 0x7E;
    if (unreserved) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

/// Ceiling for a single upload. If an upload does not finish within this window
/// it is cancelled and an [UploadTimeoutException] is thrown, so the user is
/// told it did not complete and can retry instead of the UI spinning forever.
const Duration kUploadTimeout = Duration(minutes: 2);

/// Thrown when an upload does not finish within [kUploadTimeout]. Carries a
/// ready, user-facing message asking the user to try again.
class UploadTimeoutException implements Exception {
  final Duration timeout;
  const UploadTimeoutException(this.timeout);

  /// Short, user-facing reason suitable for a dialog / summary line.
  String get userMessage =>
      '${timeout.inMinutes} dakika içinde tamamlanamadı, lütfen tekrar deneyin';

  @override
  String toString() => 'UploadTimeoutException($userMessage)';
}

/// Uploads a local file to [ref], streaming it from disk with
/// [Reference.putFile] (low, constant memory) rather than holding the whole
/// file in memory.
///
/// Why streaming matters: `putFile` streams the file from disk in chunks, so
/// peak memory stays small and constant regardless of the file size. `putData`
/// requires the entire file to live in the Dart heap **and** copies it across
/// the platform channel to the native SDK. On Windows desktop (Firebase C++
/// SDK) that whole-buffer copy is both the main reason large PDF uploads are
/// slow and the most likely trigger for the app closing itself under memory
/// pressure.
///
/// Provide [filePath] whenever the file exists on disk (the normal case). Only
/// pass [bytes] when the file is available in memory but not on disk (e.g. a
/// buffer already read into state). If a `putFile` attempt fails for a
/// non-timeout reason, the bytes are used as a fallback (read from [filePath]
/// if needed).
///
/// Throws [UploadTimeoutException] on timeout, the underlying error on other
/// failures, or a [StateError] if neither a usable path nor bytes are given.
Future<void> uploadFileToStorage({
  required Reference ref,
  required SettableMetadata metadata,
  String? filePath,
  Uint8List? bytes,
  Duration timeout = kUploadTimeout,
}) async {
  assert(
    (filePath != null && filePath.isNotEmpty) || bytes != null,
    'uploadFileToStorage needs either a filePath or bytes.',
  );

  // Preferred path: stream straight from disk (low, constant memory).
  if (filePath != null && filePath.isNotEmpty) {
    try {
      await _awaitUpload(ref.putFile(File(filePath), metadata), timeout);
      return;
    } on UploadTimeoutException {
      rethrow; // A timeout is final; surface it so the user can retry.
    } catch (e) {
      // Streaming failed for a non-timeout reason. Fall back to an in-memory
      // upload rather than failing outright, reading the bytes now only if the
      // caller did not already hand them to us.
      _log.warn('putFile failed, falling back to putData: {}', [e]);
      bytes ??= await File(filePath).readAsBytes();
    }
  }

  if (bytes == null) {
    throw StateError('No file bytes available to upload.');
  }
  await _awaitUpload(ref.putData(bytes, metadata), timeout);
}

/// Awaits an [UploadTask], enforcing [timeout] and cancelling the task if it
/// elapses so a stalled upload releases its resources. Converts the timeout
/// into an [UploadTimeoutException] carrying a user-facing message.
Future<void> _awaitUpload(UploadTask task, Duration timeout) async {
  try {
    await task.timeout(timeout);
  } on TimeoutException {
    try {
      await task.cancel();
    } catch (_) {
      // Best-effort cancel; the timeout is what we surface to the caller.
    }
    throw UploadTimeoutException(timeout);
  }
}
