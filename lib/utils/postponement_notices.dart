import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import 'date_formatter.dart';
import 'dialog_utils.dart';

/// The postponement-right side of deleting or un-postponing an appointment.
///
/// `postponementsUsed` only counts user-originated postponements, so only
/// appointments carrying that marker have a right behind them to talk about.
/// Deleting such an appointment asks the admin whether the right goes back to
/// the customer ([askReturnRightOnDelete]).
/// The right comes back automatically in two cases: the appointment goes back
/// to "Planlandı", or its postponement source is switched away from the
/// customer — each with its own notice below. Moving the postponed date of a
/// customer-postponed appointment asks whether it is postponed again
/// ([askRepostponement]); each re-postponement spends one more right.
class PostponementNotices {
  PostponementNotices._();

  static const String _title = 'Erteleme Hakkı';

  static const String _returnRightOption = 'Danışana Erteleme Hakkını Geri Ver';
  static const String _keepRightOption = 'Geri Verme';
  static const String _deleteConfirmText = 'Randevuyu Sil';

  static const String _rightReturnedByRescheduleLead =
      'Randevu tekrar planlandı durumuna alındı.';

  /// Shown when the appointment stays postponed but the source is no longer
  /// the customer, so the spent right goes back without any status change.
  static const String _rightReturnedBySourceLead =
      'Erteleme kaynağı ofis kaynaklı olarak değiştirildi.';

  static const String _repostponeTitle = 'Tekrar Erteleme';
  static const String _repostponeQuestion =
      'Tekrar erteleme mi yapılıyor; danışanın erteleme hakkından bir kez daha '
      'düşülsün mü?';
  static const String _repostponeOption =
      'Evet, tekrar erteleme: erteleme hakkından düş';
  static const String _dateOnlyOption = 'Hayır, yalnızca tarihi değiştir';
  static const String _repostponeConfirmText = 'Kaydet';
  static const String _repostponeCancelText = 'Vazgeç';
  static const String _remainingLabel = 'Kalan erteleme hakkı';

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

  static String _spentText(int count) => count > 1
      ? 'danışan kaynaklı $count kez ertelendi ve danışanın erteleme '
          'hakkından $count kez düşüldü'
      : 'danışan kaynaklı ertelendi ve danışanın erteleme hakkından düşüldü';

  static String _rightsText(int count) =>
      count > 1 ? '$count erteleme hakkı' : 'erteleme hakkı';

  static String _returnedText(int count) =>
      'Bu randevu için kullanılan ${_rightsText(count)} danışana geri verildi.';

  /// [appointment] silinmeden önce sorulur: randevu danışanın erteleme
  /// hakkını kullandıysa hak geri verilsin mi (true) verilmesin mi (false);
  /// randevu hak kullanmadıysa soru sorulmaz, false. Vazgeçilirse null:
  /// randevu silinmez.
  static Future<bool?> askReturnRightOnDelete(
    BuildContext context,
    AppointmentModel appointment,
  ) async {
    if (!consumedRight(appointment)) return false;
    final int count = appointment.postponementRightsSpent;
    return DialogUtils.openAttentionChoice<bool>(
      context,
      title: _title,
      message: 'Bu randevu ${_spentText(count)}. Randevu silinirken '
          '${_rightsText(count)} danışana geri verilsin mi?',
      options: [
        (
          true,
          count > 1
              ? 'Danışana $count Erteleme Hakkını Geri Ver'
              : _returnRightOption,
        ),
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
    final int count = appointment.postponementRightsSpent;
    final String rights =
        count > 1 ? '$count erteleme hakkı' : 'Erteleme hakkı';
    return returned
        ? ' $rights danışana geri verildi.'
        : ' $rights danışana geri verilmedi.';
  }

  /// Tells the admin the right was given back after the appointment went back
  /// to "Planlandı".
  static Future<void> informRightReturnedByReschedule(
    BuildContext context, {
    required int count,
  }) {
    return DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: '$_rightReturnedByRescheduleLead ${_returnedText(count)}',
    );
  }

  /// Tells the admin the right was given back because the postponement source
  /// was switched away from the customer, with the status left as it was.
  static Future<void> informRightReturnedBySourceChange(
    BuildContext context, {
    required int count,
  }) {
    return DialogUtils.openAttentionInfo(
      context,
      title: _title,
      message: '$_rightReturnedBySourceLead ${_returnedText(count)}',
    );
  }

  /// Danışan kaynaklı ertelenmiş [appointment]'ın ertelendiği tarih [newDate]
  /// olarak değiştirilirken sorulur: tekrar erteleme ise true (hak bir kez
  /// daha düşülür), yalnızca tarih değişiyorsa false, vazgeçilirse null.
  static Future<bool?> askRepostponement(
    BuildContext context, {
    required AppointmentModel appointment,
    required DateTime newDate,
    int? remainingRights,
  }) {
    final String from =
        DateFormatter.formatNumericDateTime(appointment.postponedDate!);
    final String to = DateFormatter.formatNumericDateTime(newDate);
    final String remaining = remainingRights == null
        ? ''
        : '\n\n$_remainingLabel: $remainingRights';
    return DialogUtils.openAttentionChoice<bool>(
      context,
      title: _repostponeTitle,
      message: 'Bu randevu ${_spentText(appointment.postponementRightsSpent)}. '
          'Ertelendiği tarih $from → $to olarak değişiyor.\n\n'
          '$_repostponeQuestion$remaining',
      options: const [
        (true, _repostponeOption),
        (false, _dateOnlyOption),
      ],
      confirmText: _repostponeConfirmText,
      cancelText: _repostponeCancelText,
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
