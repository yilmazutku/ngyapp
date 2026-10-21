import 'package:cloud_firestore/cloud_firestore.dart';

import 'appointment_model.dart';

/// Bir randevunun saat seçicide kapladığı aralık: `busySlots` aynasındaki
/// doküman (functions/index.js, mirrorBusySlot). Aynada yalnızca saat ve süre
/// var; randevunun kime ait olduğu, notu ya da paketi danışanlara açılmaz.
class BusySlot {
  static const String collection = 'busySlots';
  static const String startField = 'appointmentDateTime';
  static const String durationField = 'durationMinutes';

  /// Süresi olmayan eski randevular için [AppointmentModel.fromDocument] ile
  /// aynı varsayılan.
  static const int _defaultDurationMinutes = 30;

  final DateTime start;
  final int durationMinutes;

  const BusySlot({required this.start, required this.durationMinutes});

  factory BusySlot.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return BusySlot(
      start: (data[startField] as Timestamp).toDate(),
      durationMinutes: (data[durationField] as num?)?.toInt() ??
          _defaultDurationMinutes,
    );
  }

  factory BusySlot.ofAppointment(AppointmentModel appointment) => BusySlot(
        start: appointment.appointmentDateTime,
        durationMinutes: appointment.durationMinutes,
      );

  /// [slotDateTime] bu aralığa düşüyor mu: [start, start + süre).
  bool blocks(DateTime slotDateTime) =>
      !slotDateTime.isBefore(start) &&
      slotDateTime.isBefore(start.add(Duration(minutes: durationMinutes)));
}
