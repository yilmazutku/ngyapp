import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/models/busy_slot.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';

void main() {
  final DateTime start = DateTime(2030, 1, 10, 10);
  final BusySlot slot = BusySlot(start: start, durationMinutes: 45);

  group('BusySlot.blocks', () {
    test('başlangıç dahil, bitiş hariç: [başlangıç, başlangıç + süre)', () {
      expect(slot.blocks(start), isTrue);
      expect(slot.blocks(start.add(const Duration(minutes: 30))), isTrue);
      expect(slot.blocks(start.add(const Duration(minutes: 45))), isFalse);
      expect(slot.blocks(start.subtract(const Duration(minutes: 1))), isFalse);
    });
  });

  test('BusySlot.ofAppointment randevunun saatini ve süresini alır', () {
    final AppointmentModel appointment = AppointmentModel(
      appointmentId: 'a1',
      userId: 'u1',
      meetingType: MeetingType.online,
      appointmentType: AppointmentType.og,
      appointmentDateTime: start,
      status: AppointmentStatus.scheduled,
      createDate: DateTime(2030, 1, 1),
      durationMinutes: 45,
    );

    final BusySlot fromAppointment = BusySlot.ofAppointment(appointment);
    expect(fromAppointment.start, start);
    expect(fromAppointment.durationMinutes, 45);
    expect(
        TimeslotManager().isSlotBlockedByAppointment(
            start.add(const Duration(minutes: 44)), appointment),
        isTrue);
  });

  group('TimeslotManager.isTimeSlotAvailable', () {
    final TimeslotManager manager = TimeslotManager();
    final DateTime day = DateTime(2030, 1, 10);

    test('dolu aralığa düşen saat dolu, sonrası boş', () {
      expect(
          manager.isTimeSlotAvailable(
              day, const TimeOfDay(hour: 10, minute: 30), [slot]),
          isFalse);
      expect(
          manager.isTimeSlotAvailable(
              day, const TimeOfDay(hour: 10, minute: 45), [slot]),
          isTrue);
    });

    test('aynı randevu aynadan ve kendi randevularından iki kez gelse de sonuç aynı',
        () {
      expect(
          manager.isTimeSlotAvailable(
              day, const TimeOfDay(hour: 10, minute: 0), [slot, slot]),
          isFalse);
      expect(
          manager.isTimeSlotAvailable(
              day, const TimeOfDay(hour: 11, minute: 0), [slot, slot]),
          isTrue);
    });

    test('geçmiş saat boş sayılmaz', () {
      expect(
          manager.isTimeSlotAvailable(DateTime(2020, 1, 1),
              const TimeOfDay(hour: 10, minute: 0), const <BusySlot>[]),
          isFalse);
    });
  });

  test('BusySlot.fromDocument: süresiz eski randevu 30 dakika sayılır',
      () async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    final DateTime start = DateTime(2030, 1, 10, 10);
    final DocumentReference<Map<String, dynamic>> doc =
        db.collection(BusySlot.collection).doc('a1');
    await doc.set({BusySlot.startField: Timestamp.fromDate(start)});

    final BusySlot slot = BusySlot.fromDocument(await doc.get());
    expect(slot.start, start);
    expect(slot.durationMinutes, 30,
        reason: 'AppointmentModel.fromDocument ile aynı varsayılan');

    await doc.set({
      BusySlot.startField: Timestamp.fromDate(start),
      BusySlot.durationField: 45,
    });
    expect(BusySlot.fromDocument(await doc.get()).durationMinutes, 45);
  });
}
