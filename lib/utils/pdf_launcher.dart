import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dialog_utils.dart';

/// Opens [url] (typically an attachment such as a recipe PDF or the imported
/// Word document) in the device's external browser or default viewer.
///
/// [fileLabel] names the kind of file in the error messages. Shows an error
/// dialog when the URL is empty, malformed, or cannot be launched. Safe to
/// call from any widget with a valid [context].
Future<void> openFileUrl(
  BuildContext context,
  String? url, {
  String fileLabel = 'Dosya',
}) async {
  final trimmed = (url ?? '').trim();
  if (trimmed.isEmpty) {
    await DialogUtils.openError(
      context,
      title: 'Hata',
      message: 'Geçerli bir bağlantı bulunamadı.',
    );
    return;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    if (context.mounted) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bağlantı açılamadı.',
      );
    }
    return;
  }

  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: '$fileLabel açılamadı.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: '$fileLabel açılırken bir hata oluştu.',
      );
    }
  }
}

/// Opens a recipe / attachment PDF. Thin wrapper over [openFileUrl].
Future<void> openPdfUrl(BuildContext context, String? url) =>
    openFileUrl(context, url, fileLabel: 'PDF');
