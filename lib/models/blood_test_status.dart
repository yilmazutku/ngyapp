import '../utils/date_formatter.dart';
import '../utils/search_text.dart';
import 'admin_notification.dart';

enum BloodTestStatusGroup {
  overdue('Gecikmiş'),
  upcoming('Yaklaşan'),
  undated('Tarihi bilinmiyor'),
  upToDate('Güncel');

  const BloodTestStatusGroup(this.label);

  final String label;
}

enum BloodTestStatusKind {
  missingFirst(BloodTestStatusGroup.overdue, 'İlk kan tahlili yüklenmedi'),
  expired(BloodTestStatusGroup.overdue, 'Kan tahlilinin üzerinden 3 ay geçti'),
  expiringSoon(BloodTestStatusGroup.upcoming, 'Kan tahlili 3 ayı dolduruyor'),
  waitingFirst(BloodTestStatusGroup.upcoming, 'İlk kan tahlili bekleniyor'),
  undated(BloodTestStatusGroup.undated, 'Kan tahlili var, tarihi girilmemiş'),
  upToDate(BloodTestStatusGroup.upToDate, 'Kan tahlili güncel');

  const BloodTestStatusKind(this.group, this.label);

  final BloodTestStatusGroup group;
  final String label;
}

class BloodTestStatus {
  static const int firstTestGraceDays = 7;

  static const int expiringSoonDays = 14;

  final NotificationCustomer customer;
  final BloodTestStatusKind kind;
  final DateTime? createdAt;
  final DateTime? lastTestDate;
  final DateTime? deadline;

  const BloodTestStatus({
    required this.customer,
    required this.kind,
    this.createdAt,
    this.lastTestDate,
    this.deadline,
  });

  static BloodTestStatus evaluate({
    required NotificationCustomer customer,
    required DateTime? createdAt,
    required bool hasBloodTest,
    required DateTime? lastTestDate,
    required DateTime now,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (lastTestDate != null) {
      final DateTime due = BloodTestReminderSchedule.dueDay(lastTestDate);
      final BloodTestStatusKind kind =
          BloodTestReminderSchedule.isDue(lastTestDate, now)
              ? BloodTestStatusKind.expired
              : DateFormatter.calendarDaysBetween(today, due) <=
                      expiringSoonDays
                  ? BloodTestStatusKind.expiringSoon
                  : BloodTestStatusKind.upToDate;
      return BloodTestStatus(
        customer: customer,
        kind: kind,
        createdAt: createdAt,
        lastTestDate: lastTestDate,
        deadline: due,
      );
    }
    if (hasBloodTest) {
      return BloodTestStatus(
        customer: customer,
        kind: BloodTestStatusKind.undated,
        createdAt: createdAt,
      );
    }
    final DateTime? deadline = firstTestDeadline(createdAt);
    return BloodTestStatus(
      customer: customer,
      kind: deadline == null || !deadline.isAfter(today)
          ? BloodTestStatusKind.missingFirst
          : BloodTestStatusKind.waitingFirst,
      createdAt: createdAt,
      deadline: deadline,
    );
  }

  static DateTime? firstTestDeadline(DateTime? createdAt) => createdAt == null
      ? null
      : DateTime(createdAt.year, createdAt.month,
          createdAt.day + firstTestGraceDays);

  int? daysUntilDeadline(DateTime now) {
    final DateTime? deadline = this.deadline;
    return deadline == null
        ? null
        : DateFormatter.calendarDaysBetween(now, deadline);
  }

  static int compare(BloodTestStatus a, BloodTestStatus b) {
    final int byGroup = a.kind.group.index.compareTo(b.kind.group.index);
    if (byGroup != 0) return byGroup;
    final DateTime? aDeadline = a.deadline;
    final DateTime? bDeadline = b.deadline;
    if (aDeadline != null || bDeadline != null) {
      if (aDeadline == null) return -1;
      if (bDeadline == null) return 1;
      final int byDeadline = aDeadline.compareTo(bDeadline);
      if (byDeadline != 0) return byDeadline;
    }
    return compareSearchText(a.customer.name, b.customer.name);
  }
}

enum BloodTestTimelineEventKind {
  created('Danışan eklendi'),
  graceEnds('İlk kan tahlili için 1 haftalık süre doldu'),
  listedInDailyScan('Günlük taramada "Kan tahlili eksik danışanlar" listesine '
      'girer'),
  testTaken('Kan tahlili yapıldı'),
  dayBeforeReminder('"Kan tahlili yarın 3 ayı dolduruyor" hatırlatması'),
  dueDayReminder('"Kan tahlilinin üzerinden 3 ay geçti" hatırlatması');

  const BloodTestTimelineEventKind(this.label);

  final String label;

  bool get sendsNotification =>
      this == listedInDailyScan ||
      this == dayBeforeReminder ||
      this == dueDayReminder;

  bool get isWholeDay =>
      this == graceEnds || this == listedInDailyScan || this == testTaken;
}

class BloodTestTimelineEvent {
  final DateTime at;
  final BloodTestTimelineEventKind kind;

  const BloodTestTimelineEvent(this.at, this.kind);

  static List<BloodTestTimelineEvent> plan({
    required DateTime createdAt,
    DateTime? lastTestDate,
    required DateTime now,
  }) {
    final List<BloodTestTimelineEvent> events = [
      BloodTestTimelineEvent(createdAt, BloodTestTimelineEventKind.created),
    ];
    if (lastTestDate == null) {
      final DateTime graceEnds = BloodTestStatus.firstTestDeadline(createdAt)!;
      events
        ..add(BloodTestTimelineEvent(
            graceEnds, BloodTestTimelineEventKind.graceEnds))
        ..add(BloodTestTimelineEvent(
            graceEnds, BloodTestTimelineEventKind.listedInDailyScan));
    } else {
      events.add(BloodTestTimelineEvent(
        DateTime(lastTestDate.year, lastTestDate.month, lastTestDate.day),
        BloodTestTimelineEventKind.testTaken,
      ));
      BloodTestReminderSchedule.plan(lastTestDate, now).forEach((stage, at) {
        events.add(BloodTestTimelineEvent(
          at,
          stage == BloodTestReminderStage.dayBefore
              ? BloodTestTimelineEventKind.dayBeforeReminder
              : BloodTestTimelineEventKind.dueDayReminder,
        ));
      });
    }
    return events
      ..sort((a, b) {
        final int byTime = a.at.compareTo(b.at);
        return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
      });
  }
}

class BloodTestReport {
  final DateTime checkedAt;
  final List<BloodTestStatus> statuses;

  const BloodTestReport({required this.checkedAt, required this.statuses});

  int countOf(BloodTestStatusGroup group) =>
      statuses.where((status) => status.kind.group == group).length;
}
