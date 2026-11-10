import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('3 ay hesabı', () {
    test('takvim ayı eklenir, ay sonu taşarsa ayın son gününe çekilir', () {
      expect(BloodTestReminderSchedule.addMonths(DateTime(2026, 8, 6), 3),
          DateTime(2026, 11, 6));
      expect(BloodTestReminderSchedule.addMonths(DateTime(2026, 11, 30), 3),
          DateTime(2027, 2, 28));
      expect(BloodTestReminderSchedule.addMonths(DateTime(2027, 11, 30), 3),
          DateTime(2028, 2, 29));
      expect(BloodTestReminderSchedule.addMonths(DateTime(2026, 1, 31), 3),
          DateTime(2026, 4, 30));
      expect(BloodTestReminderSchedule.addMonths(DateTime(2026, 12, 15), 3),
          DateTime(2027, 3, 15));
    });

    test('hatırlatmalar bir gün önce ve dolduğu gün saat 10:30', () {
      final DateTime testDate = DateTime(2026, 8, 6, 15, 30);
      expect(
        BloodTestReminderSchedule.fireTime(
            testDate, BloodTestReminderStage.dayBefore),
        DateTime(2026, 11, 5, 10, 30),
      );
      expect(
        BloodTestReminderSchedule.fireTime(
            testDate, BloodTestReminderStage.dueDay),
        DateTime(2026, 11, 6, 10, 30),
      );
    });

    test('ayın ilk gününde dolan tahlilin bir önceki günü önceki aydır', () {
      expect(
        BloodTestReminderSchedule.fireTime(
            DateTime(2026, 9, 1), BloodTestReminderStage.dayBefore),
        DateTime(2026, 11, 30, 10, 30),
      );
    });

    test('3 ayın dolması saate değil güne bakar', () {
      final DateTime testDate = DateTime(2026, 8, 6);
      bool dueAt(DateTime now) =>
          BloodTestReminderSchedule.isDue(testDate, now);
      expect(dueAt(DateTime(2026, 11, 5, 23, 59)), isFalse);
      expect(dueAt(DateTime(2026, 11, 6)), isTrue);
      expect(dueAt(DateTime(2026, 11, 6, 8)), isTrue);
    });
  });

  group('kurulacak hatırlatmalar', () {
    final DateTime testDate = DateTime(2026, 8, 6);

    test('ikisi de ileride', () {
      final DateTime now = DateTime(2026, 8, 7, 12);
      expect(BloodTestReminderSchedule.plan(testDate, now), {
        BloodTestReminderStage.dayBefore: DateTime(2026, 11, 5, 10, 30),
        BloodTestReminderStage.dueDay: DateTime(2026, 11, 6, 10, 30),
      });
    });

    test('bir gün önceki gün 10:30 olmadan girilirse o gün 10:30\'da düşer',
        () {
      final DateTime now = DateTime(2026, 11, 5, 8);
      expect(BloodTestReminderSchedule.plan(testDate, now), {
        BloodTestReminderStage.dayBefore: DateTime(2026, 11, 5, 10, 30),
        BloodTestReminderStage.dueDay: DateTime(2026, 11, 6, 10, 30),
      });
    });

    test('bir gün önceki geçtiyse hemen düşer, dolduğu gün yerinde kalır', () {
      final DateTime now = DateTime(2026, 11, 5, 14);
      expect(BloodTestReminderSchedule.plan(testDate, now), {
        BloodTestReminderStage.dayBefore: now,
        BloodTestReminderStage.dueDay: DateTime(2026, 11, 6, 10, 30),
      });
    });

    test('3 ayın dolduğu gün 10:30 olmadan girilirse "yarın doluyor" kurulmaz',
        () {
      final DateTime now = DateTime(2026, 11, 6, 8);
      expect(BloodTestReminderSchedule.plan(testDate, now), {
        BloodTestReminderStage.dueDay: DateTime(2026, 11, 6, 10, 30),
      });
    });

    test('3 ayı dolmuş tahlilde yalnızca "doldu" hatırlatması hemen düşer',
        () {
      final DateTime now = DateTime(2026, 12, 1, 10);
      expect(BloodTestReminderSchedule.plan(testDate, now), {
        BloodTestReminderStage.dueDay: now,
      });
    });
  });

  test('aynı günün tahlili tek hatırlatma kimliği paylaşır', () {
    final String morning = AdminNotification.bloodTestReminderId(
        'u1', DateTime(2026, 8, 6, 8), BloodTestReminderStage.dueDay);
    final String evening = AdminNotification.bloodTestReminderId(
        'u1', DateTime(2026, 8, 6, 20), BloodTestReminderStage.dueDay);
    expect(morning, evening);
    expect(morning, 'bloodTest_u1_2026-08-06_dueDay');
  });

  group('günlük taramada eksik sayılma', () {
    final DateTime now = DateTime(2026, 11, 20, 10);

    UserModel customer({bool? present, String name = 'Ayşe', String role = 'customer'}) =>
        UserModel(
          userId: 'u1',
          name: name,
          surname: 'Yılmaz',
          email: 'a@b.c',
          password: '',
          role: role,
          isBloodTestPresent: present,
        );

    bool missing(
      UserModel user, {
      DateTime? createdAt,
      bool removalRequested = false,
    }) =>
        BloodTestProvider.isMissingBloodTest(
          user,
          createdAt: createdAt,
          removalRequested: removalRequested,
          now: now,
        );

    test('eklendiği günden 7 gün sonra hâlâ yoksa eksik; saat fark etmez', () {
      expect(missing(customer(present: false),
          createdAt: DateTime(2026, 11, 13, 23, 59)), isTrue);
      expect(missing(customer(present: false),
          createdAt: DateTime(2026, 11, 14, 0, 1)), isFalse);
    });

    test('alanı olmayan eski danışan "yok" sayılır', () {
      expect(missing(customer(present: null),
          createdAt: now.subtract(const Duration(days: 300))), isTrue);
      expect(missing(customer(present: null)), isTrue);
    });

    test('"Evet" işaretli, çalışan, admin ya da silme isteyen sayılmaz', () {
      final DateTime old = now.subtract(const Duration(days: 30));
      expect(missing(customer(present: true), createdAt: old), isFalse);
      expect(
          missing(customer(present: false, name: 'Simge', role: 'customer')
              .copyWithSurname('Erdoğan'), createdAt: old),
          isFalse);
      expect(missing(customer(present: false, role: 'admin'), createdAt: old),
          isFalse);
      expect(
          missing(customer(present: false),
              createdAt: old, removalRequested: true),
          isFalse);
    });
  });
}

extension on UserModel {
  UserModel copyWithSurname(String surname) => UserModel(
        userId: userId,
        name: name,
        surname: surname,
        email: email,
        password: password,
        role: role,
        isBloodTestPresent: isBloodTestPresent,
      );
}
