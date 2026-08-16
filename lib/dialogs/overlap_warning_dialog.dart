import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';

final DateFormat _overlapTimeFmt = DateFormat('HH:mm');

/// Informational (non-blocking) warning shown when a new appointment or event
/// would overlap one or more existing meetings. The admin is only warned — they
/// can still proceed. Returns `true` when the admin taps "Devam Et" and `false`
/// when they cancel (or dismiss the dialog).
///
/// Each conflict is listed as "DosyaNo-Ad Soyad (09:30-10:00)". When the client
/// has no file number, the number and dash are omitted.
Future<bool> showOverlapWarningDialog(
  BuildContext context, {
  required List<AppointmentModel> conflicts,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Çakışma Uyarısı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu saatte mevcut görüşme(ler) var:'),
            const SizedBox(height: 8),
            ...conflicts.map((a) {
              final DateTime start =
                  (a.status == AppointmentStatus.postponed &&
                          a.postponedDate != null)
                      ? a.postponedDate!
                      : a.appointmentDateTime;
              final DateTime end =
                  start.add(Duration(minutes: a.durationMinutes));
              final String? dosyaNo = a.user?.dosyaNo?.trim();
              final String name =
                  '${a.user?.name ?? ''} ${a.user?.surname ?? ''}'.trim();
              final String who = (dosyaNo != null && dosyaNo.isNotEmpty)
                  ? '$dosyaNo-$name'
                  : name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $who '
                  '(${_overlapTimeFmt.format(start)}-${_overlapTimeFmt.format(end)})',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              );
            }),
            const SizedBox(height: 12),
            const Text('Bilginiz dahilinde ise devam ediniz.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Devam Et'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
