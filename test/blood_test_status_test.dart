import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/blood_test_status.dart';

void main() {
  const NotificationCustomer ayse =
      NotificationCustomer(userId: 'u1', name: 'Ayşe Demir');
  final DateTime now = DateTime(2026, 11, 7, 14, 30);

  BloodTestStatus evaluate({
    DateTime? createdAt,
    bool hasBloodTest = false,
    DateTime? lastTestDate,
  }) =>
      BloodTestStatus.evaluate(
        customer: ayse,
        createdAt: createdAt,
        hasBloodTest: hasBloodTest,
        lastTestDate: lastTestDate,
        now: now,
      );

  group('durum', () {
    test('ilk tahlil 1 hafta içinde yüklenmediyse gecikmiş', () {
      final BloodTestStatus status =
          evaluate(createdAt: now.subtract(const Duration(days: 8)));
      expect(status.kind, BloodTestStatusKind.missingFirst);
      expect(status.kind.group, BloodTestStatusGroup.overdue);
      expect(status.deadline, now.subtract(const Duration(days: 1)));
      expect(status.daysUntilDeadline(now), -1);
    });

    test('1 hafta dolmadıysa yaklaşan', () {
      final BloodTestStatus status =
          evaluate(createdAt: now.subtract(const Duration(days: 3)));
      expect(status.kind, BloodTestStatusKind.waitingFirst);
      expect(status.kind.group, BloodTestStatusGroup.upcoming);
      expect(status.daysUntilDeadline(now), 4);
    });

    test('eklenme tarihi bilinmeyen tahlilsiz danışan gecikmiş sayılır', () {
      expect(evaluate().kind, BloodTestStatusKind.missingFirst);
    });

    test('tahlil var ama tarihi yoksa tarihi bilinmiyor', () {
      expect(
          evaluate(
                  createdAt: now.subtract(const Duration(days: 30)),
                  hasBloodTest: true)
              .kind,
          BloodTestStatusKind.undated);
    });

    test('3 ay dolmuşsa gecikmiş, 14 gün kala yaklaşan, sonra güncel', () {
      expect(evaluate(lastTestDate: DateTime(2026, 8, 7)).kind,
          BloodTestStatusKind.expired);
      expect(evaluate(lastTestDate: DateTime(2026, 7, 1)).deadline,
          DateTime(2026, 10, 1));
      expect(evaluate(lastTestDate: DateTime(2026, 8, 21)).kind,
          BloodTestStatusKind.expiringSoon);
      expect(evaluate(lastTestDate: DateTime(2026, 8, 22)).kind,
          BloodTestStatusKind.upToDate);
    });

    test('tarihli tahlil, kayıttaki işaretten önce gelir', () {
      expect(
          evaluate(hasBloodTest: false, lastTestDate: DateTime(2026, 10, 1))
              .kind,
          BloodTestStatusKind.upToDate);
    });

    test('sıralama: en çok geciken en üstte, sonra yaklaşan, bilinmeyen, '
        'güncel', () {
      final List<BloodTestStatus> statuses = [
        evaluate(lastTestDate: DateTime(2026, 10, 1)),
        evaluate(hasBloodTest: true, createdAt: DateTime(2026, 1, 1)),
        evaluate(createdAt: now.subtract(const Duration(days: 2))),
        evaluate(lastTestDate: DateTime(2026, 8, 1)),
        evaluate(createdAt: now.subtract(const Duration(days: 30))),
      ]..sort(BloodTestStatus.compare);
      expect(statuses.map((s) => s.kind), [
        BloodTestStatusKind.missingFirst,
        BloodTestStatusKind.expired,
        BloodTestStatusKind.waitingFirst,
        BloodTestStatusKind.undated,
        BloodTestStatusKind.upToDate,
      ]);
    });
  });

  group('zaman çizelgesi', () {
    test('tahlilsiz danışan 1 hafta sonraki ilk 09:00 taramasında listelenir',
        () {
      final List<BloodTestTimelineEvent> events = BloodTestTimelineEvent.plan(
          createdAt: DateTime(2026, 11, 1, 15, 0), now: now);
      expect(events.map((e) => e.kind), [
        BloodTestTimelineEventKind.created,
        BloodTestTimelineEventKind.graceEnds,
        BloodTestTimelineEventKind.listedInDailyScan,
      ]);
      expect(events[1].at, DateTime(2026, 11, 8, 15, 0));
      expect(events[2].at, DateTime(2026, 11, 9, 9));
    });

    test('sabah eklenen danışan 7. günün taramasına girer', () {
      final List<BloodTestTimelineEvent> events = BloodTestTimelineEvent.plan(
          createdAt: DateTime(2026, 11, 1, 8, 0), now: now);
      expect(events.last.at, DateTime(2026, 11, 8, 9));
    });

    test('tahlilli danışanın 3 ay hatırlatmaları', () {
      final List<BloodTestTimelineEvent> events = BloodTestTimelineEvent.plan(
        createdAt: DateTime(2026, 6, 1, 10),
        lastTestDate: DateTime(2026, 8, 31),
        now: now,
      );
      expect(events.map((e) => e.kind), [
        BloodTestTimelineEventKind.created,
        BloodTestTimelineEventKind.testTaken,
        BloodTestTimelineEventKind.dayBeforeReminder,
        BloodTestTimelineEventKind.dueDayReminder,
      ]);
      expect(events[2].at, DateTime(2026, 11, 29, 9));
      expect(events[3].at, DateTime(2026, 11, 30, 9));
    });
  });

  test('3 ayı çoktan dolmuş tahlilde gerçek yükleme gibi yalnızca '
      '"3 ay geçti" hatırlatması hemen düşer', () {
    final List<BloodTestTimelineEvent> events = BloodTestTimelineEvent.plan(
      createdAt: DateTime(2026, 1, 1, 10),
      lastTestDate: DateTime(2026, 7, 7),
      now: now,
    );
    expect(events.where((e) => e.kind.sendsNotification).map((e) => e.kind),
        [BloodTestTimelineEventKind.dueDayReminder]);
    expect(events.last.at, now);
  });

  test('3 ay hatırlatması istenen günden önce düşmeyen tahlil tarihi', () {
    for (final DateTime day in [
      DateTime(2026, 5, 31),
      DateTime(2026, 5, 30),
      DateTime(2026, 12, 31),
      DateTime(2026, 11, 8),
    ]) {
      final DateTime testDate =
          BloodTestReminderSchedule.testDateDueOnOrAfter(day);
      final DateTime due = BloodTestReminderSchedule.dueDay(testDate);
      expect(due.isBefore(day), isFalse, reason: '$day');
      expect(due.difference(day).inDays, lessThanOrEqualTo(3),
          reason: '$day');
    }
    expect(BloodTestReminderSchedule.dueDay(
            BloodTestReminderSchedule.testDateDueOnOrAfter(
                DateTime(2026, 11, 8))),
        DateTime(2026, 11, 8));
  });
}
