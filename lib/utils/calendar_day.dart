import 'package:cloud_firestore/cloud_firestore.dart';

const Duration _halfDay = Duration(hours: 12);

DateTime calendarDayFromTimestamp(Timestamp stored) {
  final DateTime nearestUtcDay = stored.toDate().toUtc().add(_halfDay);
  return DateTime(nearestUtcDay.year, nearestUtcDay.month, nearestUtcDay.day);
}

Timestamp calendarDayToTimestamp(DateTime day) =>
    Timestamp.fromDate(DateTime.utc(day.year, day.month, day.day));
