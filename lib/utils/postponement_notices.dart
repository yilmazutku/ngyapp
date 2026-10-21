import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import 'dialog_utils.dart';

/// The postponement-right side of deleting or un-postponing an appointment.
///
/// `postponementsUsed` only counts user-originated postponements, so only
/// appointments carrying that marker have a right behind them to talk about.
/// Deleting such an appointment asks the admin whether the right goes back to
/// the customer ([askReturnRightOnDelete]).
/// The right comes back automatically in two cases: the appointment goes back
/// to "Planlandı", or its postponement source is switched away from the
/// customer — each with its own notice below.
class PostponementNotices {
  PostponementNotices._();

  static const String _title = 'Erteleme Hakkı';

  /// Silinecek randevu danışanın erteleme hakkını kullandıysa sorulur.
  static const String _deleteChoiceMessage =
      'Bu randevu danışan kaynaklı ertelendi ve danışanın erteleme hakkından '
      'düşüldü. Randevu silinirken erteleme hakkı danışana geri verilsin mi?';
  static const String _returnRightOption = 'Danışana Erteleme Hakkını Geri Ver';
  static const String _keepRightOption = 'Geri Verme';
  static const String _deleteConfirmText = 'Randevuyu Sil';

  static const String _rightReturnedNote =
      ' Erteleme hakkı danışana geri verildi.';
  static const String _rightKeptNote =
      ' Erteleme hakkı danışana geri verilmedi.';

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

  /// [appointment] silinmeden önce sorulur: randevu danışanın erteleme
  /// hakkını kullandıysa hak geri verilsin mi (true) verilmesin mi (false);
  /// randevu hak kullanmadıysa soru sorulmaz, false. Vazgeçilirse null:
  /// randevu silinmez.
  static Future<bool?> askReturnRightOnDelete(
    BuildContext context,
    AppointmentModel appointment,
  ) async {
    if (!consumedRight(appointment)) return false;
    return DialogUtils.openAttentionChoice<bool>(
      context,
      title: _title,
      message: _deleteChoiceMessage,
      options: const [
        (true, _returnRightOption),
        (false, _keepRightOption),
      ],
      confirmText: _deleteConfirmText,
    );
  }

  /// Silme başarı mesajının sonuna eklenen erteleme hakkı notu ([returned]:
  /// hak gerçekten geri verildi mi); randevu hak kullanmadıysa boş.
  static String deleteResultNote(
    AppointmentModel appointment, {
    required bool returned,
  }) {
    if (!consumedRight(appointment)) return '';
    return returned ? _rightReturnedNote : _rightKeptNote;
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
