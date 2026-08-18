import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/logger.dart';

final Logger _log = Logger('StorageUpload');

/// Maximum accepted upload size, in bytes (50 MB).
///
/// Files larger than this are rejected up-front (with a clear message) instead
/// of being pushed through Storage. On Windows desktop `firebase_storage` runs
/// on the Firebase C++ SDK and an in-memory upload copies the whole byte buffer
/// across the Dart↔native boundary; a very large PDF can momentarily occupy
/// several times its own size in RAM and take the process down. Guarding the
/// size keeps a single pathological file from hanging or crashing the app.
const int kMaxUploadBytes = 50 * 1024 * 1024;

/// Human-readable form of [kMaxUploadBytes] for user-facing messages.
const String kMaxUploadSizeLabel = '50 MB';

/// Absolute ceiling for a single upload. A stalled upload (e.g. a flaky
/// connection that never errors) would otherwise leave the UI spinning
/// forever; this makes it fail cleanly so the user is told and can retry.
const Duration kUploadTimeout = Duration(minutes: 15);

/// Uploads a local file to [ref], preferring a *streamed* [Reference.putFile]
/// from [filePath] over an in-memory [Reference.putData] of [bytes].
///
/// Why streaming matters: `putFile` streams the file from disk in chunks, so
/// peak memory stays small and constant regardless of the file size. `putData`
/// requires the entire file to live in the Dart heap **and** copies it across
/// the platform channel to the native SDK. On Windows desktop (Firebase C++
/// SDK) that whole-buffer copy is both the main reason large PDF uploads are
/// slow and the most likely trigger for the app closing itself under memory
/// pressure.
///
/// Behaviour:
/// * When a real [filePath] is available and we are not on web, stream it with
///   `putFile`. If that fails for any reason, fall back to an in-memory
///   `putData` (reading the bytes lazily only if they were not supplied).
/// * On web (no filesystem path) upload the provided [bytes] with `putData`.
///
/// Throws if neither a usable path nor bytes are available, if the upload
/// fails, or if it exceeds [timeout].
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
  if (!kIsWeb && filePath != null && filePath.isNotEmpty) {
    try {
      await _awaitUpload(ref.putFile(File(filePath), metadata), timeout);
      return;
    } catch (e) {
      // Streaming failed (unsupported platform, transient error, timeout...).
      // Fall back to an in-memory upload rather than failing outright, reading
      // the bytes now only if the caller did not already hand them to us.
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
/// elapses so a stalled upload releases its resources instead of lingering.
Future<void> _awaitUpload(UploadTask task, Duration timeout) async {
  try {
    await task.timeout(timeout);
  } on TimeoutException {
    try {
      await task.cancel();
    } catch (_) {
      // Best-effort cancel; the timeout is what we surface to the caller.
    }
    rethrow;
  }
}
