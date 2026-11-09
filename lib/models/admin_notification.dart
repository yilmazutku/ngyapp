import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/date_formatter.dart';

enum AdminNotificationType {
  bloodTestReminder('bloodTestReminder'),

  missingBloodTests('missingBloodTests'),

  test('test');

  const AdminNotificationType(this.value);

  final String value;

  static AdminNotificationType? fromValue(Object? value) {
    for (final AdminNotificationType type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

enum AdminTestNotificationKind {
  plain,

  bloodTestDayBefore,

  bloodTestDueDay,

  missingBloodTests,
}

enum BloodTestReminderStage {
  dayBefore('dayBefore'),

  dueDay('dueDay');

  const BloodTestReminderStage(this.value);

  final String value;

  static BloodTestReminderStage? fromValue(Object? value) {
    for (final BloodTestReminderStage stage in values) {
      if (stage.value == value) return stage;
    }
    return null;
  }
}

class NotificationCustomer {
  final String userId;
  final String name;

  const NotificationCustomer({required this.userId, required this.name});

  static NotificationCustomer? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? userId = raw['userId'];
    final Object? name = raw['name'];
    if (userId is! String || userId.isEmpty) return null;
    return NotificationCustomer(
      userId: userId,
      name: name is String && name.isNotEmpty ? name : userId,
    );
  }

  Map<String, dynamic> toMap() => {'userId': userId, 'name': name};
}

class BloodTestReminderSchedule {
  BloodTestReminderSchedule._();

  static const int monthsAfterTest = 3;
  static const int reminderHour = 9;

  static DateTime addMonths(DateTime date, int months) {
    final int monthIndex = date.year * 12 + (date.month - 1) + months;
    final int year = monthIndex ~/ 12;
    final int month = monthIndex % 12 + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, math.min(date.day, lastDay));
  }

  static DateTime dueDay(DateTime testDate) => addMonths(
      DateTime(testDate.year, testDate.month, testDate.day), monthsAfterTest);

  static DateTime testDateDueOnOrAfter(DateTime day) {
    final DateTime target = DateTime(day.year, day.month, day.day);
    DateTime testDate = addMonths(target, -monthsAfterTest);
    while (dueDay(testDate).isBefore(target)) {
      testDate = DateTime(testDate.year, testDate.month, testDate.day + 1);
    }
    return testDate;
  }

  static DateTime fireTime(DateTime testDate, BloodTestReminderStage stage) {
    final DateTime due = dueDay(testDate);
    final DateTime day = stage == BloodTestReminderStage.dayBefore
        ? DateTime(due.year, due.month, due.day - 1)
        : due;
    return DateTime(day.year, day.month, day.day, reminderHour);
  }

  static Map<BloodTestReminderStage, DateTime> plan(
    DateTime testDate,
    DateTime now,
  ) {
    final DateTime due = fireTime(testDate, BloodTestReminderStage.dueDay);
    if (!due.isAfter(now)) {
      return {BloodTestReminderStage.dueDay: now};
    }
    final DateTime dayBefore =
        fireTime(testDate, BloodTestReminderStage.dayBefore);
    return {
      BloodTestReminderStage.dayBefore: dayBefore.isAfter(now) ? dayBefore : now,
      BloodTestReminderStage.dueDay: due,
    };
  }
}

class BloodTestReminderSync {
  const BloodTestReminderSync({
    required this.latestTestDate,
    required this.remindFor,
    required this.written,
    required this.removed,
    this.remindersAllowed = true,
  });

  final DateTime? latestTestDate;
  final DateTime? remindFor;
  final int written;
  final int removed;
  final bool remindersAllowed;

  bool get hasBloodTests => latestTestDate != null;
}

class AdminNotification {
  static const String typeField = 'type';
  static const String titleField = 'title';
  static const String bodyField = 'body';
  static const String fireAtField = 'fireAt';
  static const String createdAtField = 'createdAt';
  static const String createdByField = 'createdBy';
  static const String readByField = 'readBy';
  static const String userIdField = 'userId';
  static const String userNameField = 'userName';
  static const String testDateField = 'testDate';
  static const String stageField = 'stage';
  static const String dayField = 'day';
  static const String customersField = 'customers';
  static const String supersededField = 'superseded';
  static const String onlyForField = 'onlyFor';
  static const String isTestField = 'isTest';

  static const String testTitle = 'Deneme hatırlatması';
  static const String testBody =
      'Bu bir deneme bildirimidir. Uygulama açıkken şerit, kapalıyken sistem '
      'bildirimi olarak gelmesi gerekir.';

  final String id;
  final AdminNotificationType type;
  final String title;
  final String body;
  final DateTime fireAt;
  final Map<String, DateTime> readBy;

  final String? userId;
  final String? userName;
  final DateTime? testDate;
  final BloodTestReminderStage? stage;

  final List<NotificationCustomer> customers;

  final bool superseded;

  final String? onlyFor;

  final bool isTest;

  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.fireAt,
    this.readBy = const {},
    this.userId,
    this.userName,
    this.testDate,
    this.stage,
    this.customers = const [],
    this.superseded = false,
    this.onlyFor,
    this.isTest = false,
  });

  static AdminNotification? fromDocument(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    final AdminNotificationType? type =
        AdminNotificationType.fromValue(data[typeField]);
    final Object? fireAt = data[fireAtField];
    if (type == null || fireAt is! Timestamp) return null;

    final Map<String, DateTime> readBy = {};
    final Object? rawReadBy = data[readByField];
    if (rawReadBy is Map) {
      rawReadBy.forEach((key, value) {
        if (key is String && value is Timestamp) readBy[key] = value.toDate();
      });
    }

    final Object? rawCustomers = data[customersField];
    final List<NotificationCustomer> customers = rawCustomers is List
        ? rawCustomers
            .map(NotificationCustomer.fromMap)
            .whereType<NotificationCustomer>()
            .toList()
        : const [];

    final Object? testDate = data[testDateField];
    final Object? userId = data[userIdField];
    final Object? userName = data[userNameField];
    final Object? title = data[titleField];
    final Object? body = data[bodyField];
    final Object? onlyFor = data[onlyForField];
    return AdminNotification(
      id: doc.id,
      type: type,
      title: title is String ? title : '',
      body: body is String ? body : '',
      fireAt: fireAt.toDate(),
      readBy: readBy,
      userId: userId is String ? userId : null,
      userName: userName is String ? userName : null,
      testDate: testDate is Timestamp ? testDate.toDate() : null,
      stage: BloodTestReminderStage.fromValue(data[stageField]),
      customers: customers,
      superseded: data[supersededField] == true,
      onlyFor: onlyFor is String && onlyFor.isNotEmpty ? onlyFor : null,
      isTest: type == AdminNotificationType.test || data[isTestField] == true,
    );
  }

  bool isVisibleTo(String uid) => onlyFor == null || onlyFor == uid;

  bool isReadBy(String uid) => readBy.containsKey(uid);

  bool isUnreadFor(String uid) => !superseded && !isReadBy(uid);

  AdminNotification markedReadBy(String uid, DateTime at) => AdminNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        fireAt: fireAt,
        readBy: {...readBy, uid: at},
        userId: userId,
        userName: userName,
        testDate: testDate,
        stage: stage,
        customers: customers,
        superseded: superseded,
        onlyFor: onlyFor,
        isTest: isTest,
      );

  bool isDueAt(DateTime now) => !fireAt.isAfter(now);

  static String bloodTestReminderId(
    String userId,
    DateTime testDate,
    BloodTestReminderStage stage,
  ) =>
      'bloodTest_${userId}_${DateFormatter.formatIsoDate(testDate)}_${stage.value}';

  static String bloodTestReminderTitle(BloodTestReminderStage stage) {
    switch (stage) {
      case BloodTestReminderStage.dayBefore:
        return 'Kan tahlili yarın 3 ayı dolduruyor';
      case BloodTestReminderStage.dueDay:
        return 'Kan tahlilinin üzerinden 3 ay geçti';
    }
  }

  static String bloodTestReminderBody(
    String userName,
    DateTime testDate,
    BloodTestReminderStage stage,
  ) {
    final String date = DateFormatter.formatNumericDate(testDate);
    switch (stage) {
      case BloodTestReminderStage.dayBefore:
        return '$userName · $date tarihli tahlil yarın 3 ayı dolduruyor. '
            'Yeni tahlil için hatırlatabilirsiniz.';
      case BloodTestReminderStage.dueDay:
        return '$userName · $date tarihli tahlilin üzerinden 3 ay geçti. '
            'Yeni kan tahlili zamanı.';
    }
  }

  static String missingBloodTestsId(String day) => 'missingBloodTests_$day';

  static String missingBloodTestsTitle(int count) =>
      'Kan tahlili eksik danışanlar ($count)';

  static String missingBloodTestsBody(List<NotificationCustomer> customers) {
    return '${customers.length} danışanın kan tahlili sisteme girilmemiş: '
        '${customers.map((c) => c.name).join(', ')}';
  }
}

class MealPhotoNotification {
  final String chatId;
  final String messageId;

  final String? mealLabel;
  final DateTime sentAt;

  final String imageUrl;
  final bool imageIsOriginal;
  final bool isRead;

  const MealPhotoNotification({
    required this.chatId,
    required this.messageId,
    required this.mealLabel,
    required this.sentAt,
    required this.imageUrl,
    required this.imageIsOriginal,
    required this.isRead,
  });
}
