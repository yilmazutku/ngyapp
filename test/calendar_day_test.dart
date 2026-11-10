import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/test_attachment.dart';
import 'package:ngy_app/utils/calendar_day.dart';

void main() {
  final DateTime day = DateTime(2015, 11, 10);
  final Map<String, Timestamp> savedOn = {
    'iOS / Android / macOS (2016 öncesi kış UTC+2)':
        Timestamp.fromDate(DateTime.utc(2015, 11, 9, 22)),
    'Windows (geçmiş tarihe de UTC+3)':
        Timestamp.fromDate(DateTime.utc(2015, 11, 9, 21)),
    'UTC+4\'lü dönem': Timestamp.fromDate(DateTime.utc(2015, 11, 9, 20)),
    'yeni biçim (UTC gün başı)': Timestamp.fromDate(DateTime.utc(2015, 11, 10)),
  };

  test('eski ve yeni kayıtlar aynı güne okunur', () {
    savedOn.forEach((String how, Timestamp stored) {
      expect(calendarDayFromTimestamp(stored), day, reason: how);
    });
  });

  test('gün, saati atılarak UTC gün başı olarak yazılır', () {
    expect(calendarDayToTimestamp(DateTime(2026, 8, 6, 15, 30)),
        Timestamp.fromDate(DateTime.utc(2026, 8, 6)));
    expect(
        calendarDayFromTimestamp(
            calendarDayToTimestamp(DateTime(2026, 8, 6, 23, 59))),
        DateTime(2026, 8, 6));
  });

  test('kan tahlili tarihi her cihazda aynı gün', () {
    savedOn.forEach((String how, Timestamp stored) {
      final TestAttachment file = TestAttachment.fromMap('a', {
        TestAttachment.isBloodTestField: true,
        TestAttachment.bloodTestDateField: stored,
      });
      expect(file.bloodTestDate, day, reason: how);
    });
  });

  group('Firestore belgeleri', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    test('hatırlatmanın tahlil tarihi her cihazda aynı gün', () async {
      for (final MapEntry<String, Timestamp> saved in savedOn.entries) {
        final DocumentReference<Map<String, dynamic>> doc =
            db.collection('adminNotifications').doc();
        await doc.set({
          AdminNotification.typeField:
              AdminNotificationType.bloodTestReminder.value,
          AdminNotification.fireAtField:
              Timestamp.fromDate(DateTime(2016, 2, 10, 10, 30)),
          AdminNotification.testDateField: saved.value,
        });
        expect(AdminNotification.fromDocument(await doc.get())!.testDate, day,
            reason: saved.key);
      }
    });

    test('kilo takibe geçiş tarihi gün olarak yazılır, her cihazda aynı gün',
        () async {
      final SubscriptionModel sub = SubscriptionModel(
        subscriptionId: 's',
        userId: 'u',
        packageName: 'Paket',
        startDate: DateTime(2026, 11, 1),
        totalMeetings: 4,
        allowedPostponements: 1,
        totalAmount: 1000,
        meetingType: SubsMeetingType.faceToFace,
        status: SubActiveStatus.activeWeightTracking,
        weightTrackingStartDate: DateTime(2026, 11, 10, 18, 45),
      );
      final Map<String, dynamic> written = sub.toMap();
      expect(written[SubscriptionModel.weightTrackingStartDateField],
          Timestamp.fromDate(DateTime.utc(2026, 11, 10)));

      Future<DateTime?> readBack(Timestamp stored) async {
        final DocumentReference<Map<String, dynamic>> doc =
            db.collection('subscriptions').doc();
        await doc.set({
          ...written,
          SubscriptionModel.weightTrackingStartDateField: stored,
        });
        return SubscriptionModel.fromDocument(await doc.get())
            .weightTrackingStartDate;
      }

      expect(
          await readBack(written[SubscriptionModel.weightTrackingStartDateField]
              as Timestamp),
          DateTime(2026, 11, 10));
      for (final MapEntry<String, Timestamp> saved in savedOn.entries) {
        expect(await readBack(saved.value), day, reason: saved.key);
      }
    });
  });
}
