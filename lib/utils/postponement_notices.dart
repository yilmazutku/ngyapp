import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import 'dialog_utils.dart';

/// The postponement-right side of cancelling, deleting or un-postponing an
/// appointment.
///
/// A right is spent in two ways: a user-originated postponement, or a
/// cancellation where the admin answered "evet, düşülsün". Deleting such an
/// appointment does **not** give the right back, and the admin is told so,
/// because the correction can then only be made from the package editor.
/// Putting a postponed appointment back to "Planlandı" is the one case where
/// the right is returned automatically.
class PostponementNotices {
  PostponementNotices._();

  static const String _title = 'Erteleme Hakkı';

  /// Shown after deleting a *postponed* appointment that had consumed a right.
  /// Deliberately loud: the admin did not choose to spend that right here, so
  /// a quiet line would be easy to miss.
  static const String _rightKeptMessage =
      'Danışan erteleme hakkı kullanılan bir randevuyu iptal ettiniz / '
      'sildiniz. Eğer sizden kaynaklı bir iptal/silme işlemi ise danışan '
      'erteleme hakkını düzeltmek isterseniz paket düzenleme kısmından '
      'ayarlayınız.';

  /// Shown after deleting a *cancelled* appointment whose cancellation had
  /// deducted a right. The admin took that decision knowingly at cancel time,
  /// so this is a plain note rather than the loud warning above.
  static const String _canceledRightKeptMessage =
      'Bu randevu iptal edilirken danışanın erteleme hakkından bir adet '
      'düşülmüştü. Randevu silindi, ancak düşülen hak geri verilmedi.\n\n'
      'Geri vermek isterseniz paket düzenleme kısmından ayarlayabilirsiniz.';

  static const String _rightReturnedMessage =
      'Randevu tekrar planlandı durumuna alındı. Bu randevu için kullanılan '
      'erteleme hakkı danışana geri verildi.';

  /// Whether cancelling [appointment] deducted a postponement right.
  static bool _canceledWithDeduction(AppointmentModel appointment) =>
      appointment.status == AppointmentStatus.canceled &&
      appointment.postponementDeducted == true &&
      (appointment.subscriptionId?.isNotEmpty ?? false);

  /// Whether [appointment] consumed one of the customer's postponement rights,
  /// i.e. whether any of the notices below are relevant at all.
  static bool consumedRight(AppointmentModel appointment) =>
      (appointment.status == AppointmentStatus.postponed &&
          appointment.postponedBy == PostponeSource.user &&
          (appointment.subscriptionId?.isNotEmpty ?? false)) ||
      _canceledWithDeduction(appointment);

  /// Tells the admin the right stayed spent after a cancel or a delete.
  /// Does nothing when the appointment never consumed one.
  static Future<void> warnRightKept(
    BuildContext context,
    AppointmentModel appointment,
  ) async {
    if (_canceledWithDeduction(appointment)) {
      await DialogUtils.openInfo(
        context,
        title: _title,
        message: _canceledRightKeptMessage,
      );
      return;
    }
    if (!consumedRight(appointment)) return;
    await DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: _rightKeptMessage,
    );
  }

  /// Asks whether cancelling should spend one of the customer's postponement
  /// rights. Returns null when the admin backs out of the cancellation.
  static Future<bool?> askDeductOnCancel(
    BuildContext context, {
    int? remainingRights,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erteleme Hakkı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu randevu iptal ediliyor. Danışanın erteleme hakkından bir '
              'adet düşülsün mü?',
            ),
            if (remainingRights != null) ...[
              const SizedBox(height: 12),
              Text(
                'Kalan erteleme hakkı: $remainingRights',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hayır, Düşülmesin'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Evet, Düşülsün'),
          ),
        ],
      ),
    );
  }

  /// Tells the admin the right was given back after the appointment went back
  /// to "Planlandı".
  static Future<void> informRightReturned(BuildContext context) {
    return DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: _rightReturnedMessage,
    );
  }
}
