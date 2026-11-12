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

  group('ertelenmiş randevu, takvimde durduğu saati kaplar', () {
    final DateTime planned = DateTime(2030, 1, 10, 11);
    final DateTime postponedTo = DateTime(2030, 1, 12, 14);

    AppointmentModel appointment(AppointmentStatus status,
            {DateTime? postponedDate}) =>
        AppointmentModel(
          appointmentId: 'a1',
          userId: 'u1',
          meetingType: MeetingType.online,
          appointmentType: AppointmentType.haftalik,
          appointmentDateTime: planned,
          status: status,
          postponedDate: postponedDate,
          createDate: DateTime(2030, 1, 1),
          durationMinutes: 30,
        );

    test('calendarDateTime: ertelenmişse ertelendiği tarih, değilse kendi '
        'tarihi', () {
      expect(appointment(AppointmentStatus.scheduled).calendarDateTime,
          planned);
      expect(
          appointment(AppointmentStatus.postponed, postponedDate: postponedTo)
              .calendarDateTime,
          postponedTo);
      expect(appointment(AppointmentStatus.postponed).calendarDateTime,
          planned,
          reason: 'yeni tarihi seçilmemiş erteleme');
      expect(
          appointment(AppointmentStatus.completed, postponedDate: postponedTo)
              .calendarDateTime,
          planned,
          reason: 'takvim sayfası da Yapıldı randevuyu kendi tarihinde '
              'gösteriyor');
    });

    test('BusySlot.ofAppointment ertelendiği saati doldurur, ilk saati '
        'boşaltır', () {
      final AppointmentModel postponed =
          appointment(AppointmentStatus.postponed, postponedDate: postponedTo);
      final BusySlot busy = BusySlot.ofAppointment(postponed);
      expect(busy.start, postponedTo);
      expect(busy.durationMinutes, 30);

      final TimeslotManager manager = TimeslotManager();
      expect(manager.isSlotBlockedByAppointment(planned, postponed), isFalse);
      expect(
          manager.isSlotBlockedByAppointment(
              postponedTo.add(const Duration(minutes: 29)), postponed),
          isTrue);
    });
  });

  group('TimeslotManager, ertelenmiş randevular', () {
    final DateTime day0 = DateTime(2030, 1, 9);
    final DateTime day1 = DateTime(2030, 1, 10);
    final DateTime day2 = DateTime(2030, 1, 12);

    late FakeFirebaseFirestore db;

    DateTime at(DateTime day, int hour, [int minute = 0]) =>
        DateTime(day.year, day.month, day.day, hour, minute);

    Future<void> addAppointment(
      String userId,
      String id,
      DateTime start, {
      AppointmentStatus status = AppointmentStatus.scheduled,
      DateTime? postponedDate,
      PostponeSource? postponedBy,
      int durationMinutes = 30,
    }) =>
        db
            .collection('users')
            .doc(userId)
            .collection('appointments')
            .doc(id)
            .set(AppointmentModel(
              appointmentId: id,
              userId: userId,
              meetingType: MeetingType.online,
              appointmentType: AppointmentType.haftalik,
              appointmentDateTime: start,
              status: status,
              postponedDate: postponedDate,
              postponedBy: postponedBy,
              createDate: DateTime(2030, 1, 1),
              durationMinutes: durationMinutes,
            ).toMap());

    Future<void> setAdminSlots(DateTime day, List<String> slots) => db
        .collection('admininput')
        .doc('timeslots')
        .collection('dates')
        .doc('${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}')
        .set({'slots': slots});

    setUp(() async {
      db = FakeFirebaseFirestore();
      await addAppointment('u1', 'a', at(day1, 10));
      await addAppointment('u2', 'b', at(day1, 11),
          status: AppointmentStatus.postponed,
          postponedDate: at(day2, 14),
          postponedBy: PostponeSource.user);
      await addAppointment('u3', 'c', at(day0, 9),
          status: AppointmentStatus.postponed,
          postponedDate: at(day1, 15),
          postponedBy: PostponeSource.admin);
    });

    test('Saat Yönetimi: ertelenen randevunun ilk saati boş, ertelendiği saat '
        'dolu görünür', () async {
      await setAdminSlots(day1, ['10:00', '11:00', '15:00', '16:00']);
      final TimeslotManager manager = TimeslotManager(db: db);

      final Map<String, dynamic> data =
          await manager.fetchTimeslotDataForDate(day1);
      final List<String> booked = data['bookedTimeSlots'] as List<String>;
      expect(booked, unorderedEquals(<String>['10:00', '15:00']));
      final Map<String, List<AppointmentModel>> bySlot =
          data['appointmentsBySlot'] as Map<String, List<AppointmentModel>>;
      expect(bySlot['15:00']!.single.appointmentId, 'c');
      expect(bySlot.containsKey('11:00'), isFalse);

      final Map<String, dynamic> nextDay =
          await manager.fetchTimeslotDataForDate(day2);
      expect(nextDay['bookedTimeSlots'], <String>['14:00']);
      expect(nextDay['storedTimes'], contains('14:00'),
          reason: 'saat yönetiminde açılmamış saate ertelenen randevu da '
              'listede görünür');
    });

    test('Saat Yönetimi: aynı kimlikli randevular farklı danışanlarda '
        'birbirini ezmez', () async {
      await addAppointment('u4', 'a', at(day1, 16));
      await setAdminSlots(day1, ['10:00', '16:00']);

      final Map<String, dynamic> data =
          await TimeslotManager(db: db).fetchTimeslotDataForDate(day1);
      expect(data['bookedTimeSlots'],
          unorderedEquals(<String>['10:00', '15:00', '16:00']));
    });

    test('Saatleri silerken dolu saatler korunur: ertelendiği saat kalır, '
        'boşalan ilk saat gider', () async {
      await setAdminSlots(day1, ['10:00', '11:00', '15:00', '16:00']);

      await TimeslotManager(db: db).deleteTimeSlots(day1);

      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc('2030-01-10')
          .get();
      expect(List<String>.from(doc.data()!['slots'] as List<dynamic>),
          unorderedEquals(<String>['10:00', '15:00']));
    });

    test('Danışanın saat listesi: kendi ertelenmiş randevusu, ayna henüz '
        'güncellenmemişken de ertelendiği saati doldurur', () async {
      await addAppointment('u5', 'd', at(day1, 12),
          status: AppointmentStatus.postponed,
          postponedDate: at(day1, 13),
          postponedBy: PostponeSource.user);
      await addAppointment('u5', 'e', at(day0, 9),
          status: AppointmentStatus.postponed,
          postponedDate: at(day1, 16),
          postponedBy: PostponeSource.user);
      await addAppointment('u5', 'f', at(day1, 17),
          status: AppointmentStatus.postponed,
          postponedDate: at(day2, 10),
          postponedBy: PostponeSource.user);
      await setAdminSlots(
          day1, ['10:00', '12:00', '13:00', '16:00', '17:00', '18:00']);
      await db.collection(BusySlot.collection).doc('ayna-a').set({
        BusySlot.startField: Timestamp.fromDate(at(day1, 10)),
        BusySlot.durationField: 30,
      });

      final TimeslotManager manager =
          TimeslotManager(db: db, currentUid: () => 'u5');
      final List<TimeOfDay> available =
          await manager.getAvailableTimeSlotsForDate(day1);

      expect(available, <TimeOfDay>[
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 17, minute: 0),
        const TimeOfDay(hour: 18, minute: 0),
      ]);
    });
  });
}
