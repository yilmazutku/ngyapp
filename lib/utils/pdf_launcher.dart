import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dialog_utils.dart';

/// Opens [url] (typically a recipe / attachment PDF) in the device's external
/// browser or PDF viewer, matching how other PDFs in the app are opened.
///
/// Shows an error dialog when the URL is empty, malformed, or cannot be
/// launched. Safe to call from any widget with a valid [context].
Future<void> openPdfUrl(BuildContext context, String? url) async {
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
        message: 'PDF açılamadı.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'PDF açılırken bir hata oluştu.',
      );
    }
  }
}
