import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import 'dialog_utils.dart';

/// The postponement-right side of deleting or un-postponing an appointment.
///
/// `postponementsUsed` only counts user-originated postponements, so only
/// appointments carrying that marker have a right behind them to talk about. Deleting
/// such an appointment deliberately does **not** give the right back — the
/// customer did ask for the postponement — but the admin is told, because an
/// admin-side mistake can then only be corrected from the package editor.
/// The right comes back automatically in two cases: the appointment goes back
/// to "Planlandı", or its postponement source is switched away from the
/// customer — each with its own notice below.
class PostponementNotices {
  PostponementNotices._();

  static const String _title = 'Erteleme Hakkı';

  /// Shown after deleting an appointment that had consumed a postponement
  /// right.
  static const String _rightKeptMessage =
      'Danışan erteleme hakkı kullanılan bir randevuyu sildiniz. Bu randevuda '
      'danışan erteleme hakkından düşülmüştü. Silme işlemi sizden kaynaklıysa '
      'paket düzenleme ekranında "Kullanılan Erteleme Sayısı"nı 1 azaltarak '
      'kalan erteleme hakkına 1 ekleyebilirsiniz.';

  static const String _rightReturnedByRescheduleMessage =
      'Randevu tekrar planlandı durumuna alındı. Bu randevu için kullanılan '
      'erteleme hakkı danışana geri verildi.';

  /// Shown when the appointment stays postponed but the source is no longer
  /// the customer, so the spent right goes back without any status change.
  static const String _rightReturnedBySourceMessage =
      'Erteleme kaynağı ofis kaynaklı olarak değiştirildi. Bu randevu için '
      'kullanılan erteleme hakkı danışana geri verildi.';

  static const String _noRightsLeftTitle = 'Erteleme Hakkı Yok';

  static const String _noRightsLeftMessage =
      'Danışan erteleme hakkı bulunmamaktadır. Erteleme sebebini danışan '
      'kaynaklı yaparsanız erteleme hakkı eksiye düşecektir.';

  /// Whether [appointment] consumed one of the customer's postponement rights,
  /// i.e. whether any of the notices below are relevant at all.
  ///
  /// The status is not part of the test: a user-originated postponement keeps
  /// its marker (and its spent right) after the appointment is completed or
  /// burned, so deleting it then is just as worth warning about.
  static bool consumedRight(AppointmentModel appointment) =>
      appointment.postponedBy == PostponeSource.user &&
      (appointment.subscriptionId?.isNotEmpty ?? false);

  /// Tells the admin the right stayed spent after a delete.
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
  static Future<void> informRightReturnedByReschedule(BuildContext context) {
    return DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: _rightReturnedByRescheduleMessage,
    );
  }

  /// Tells the admin the right was given back because the postponement source
  /// was switched away from the customer, with the status left as it was.
  static Future<void> informRightReturnedBySourceChange(BuildContext context) {
    return DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: _rightReturnedBySourceMessage,
    );
  }

  /// Asks the admin whether to record a customer-originated postponement even
  /// though no right is left, which pushes the counter below zero.
  static Future<bool> confirmNoRightsLeft(BuildContext context) {
    return DialogUtils.openAttentionConfirm(
      context,
      title: _noRightsLeftTitle,
      message: _noRightsLeftMessage,
    );
  }
}
