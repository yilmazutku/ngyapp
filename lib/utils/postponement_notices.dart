import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import 'dialog_utils.dart';

/// The postponement-right side of cancelling, deleting or un-postponing an
/// appointment.
///
/// `postponementsUsed` only counts user-originated postponements, so only those
/// appointments have a right behind them to talk about. Cancelling or deleting
/// such an appointment deliberately does **not** give the right back — the
/// customer did ask for the postponement — but the admin is told, because an
/// admin-side mistake can then only be corrected from the package editor.
/// Putting the appointment back to "Planlandı" is the one case where the right
/// is returned automatically.
class PostponementNotices {
  PostponementNotices._();

  static const String _title = 'Erteleme Hakkı';

  /// Shown after cancelling or deleting an appointment that had consumed a
  /// postponement right. Wording is deliberately identical for both actions.
  static const String _rightKeptMessage =
      'Danışan erteleme hakkı kullanılan bir randevuyu iptal ettiniz / '
      'sildiniz. Eğer sizden kaynaklı bir iptal/silme işlemi ise danışan '
      'erteleme hakkını düzeltmek isterseniz paket düzenleme kısmından '
      'ayarlayınız.';

  static const String _rightReturnedMessage =
      'Randevu tekrar planlandı durumuna alındı. Bu randevu için kullanılan '
      'erteleme hakkı danışana geri verildi.';

  /// Whether [appointment] consumed one of the customer's postponement rights,
  /// i.e. whether any of the notices below are relevant at all.
  static bool consumedRight(AppointmentModel appointment) =>
      appointment.status == AppointmentStatus.postponed &&
      appointment.postponedBy == PostponeSource.user &&
      (appointment.subscriptionId?.isNotEmpty ?? false);

  /// Tells the admin the right stayed spent after a cancel or a delete.
  /// Does nothing when the appointment never consumed one.
  static Future<void> warnRightKept(
    BuildContext context,
    AppointmentModel appointment,
  ) async {
    if (!consumedRight(appointment)) return;
    await DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: _rightKeptMessage,
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
