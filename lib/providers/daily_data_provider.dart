import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Model class for daily user data (water intake and steps)
class DailyData {
  final double waterIntake; // in liters
  final int steps;
  final bool isSaved;

  DailyData({this.waterIntake = 0.0, this.steps = 0, this.isSaved = false});
}

class DailyDataProvider extends ChangeNotifier {
  DailyDataProvider({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String waterIntakeField = 'waterIntake';
  static const String stepsField = 'steps';

  final FirebaseFirestore _firestore;
  final DateFormat df=DateFormat('yyyy-MM-dd');

  DocumentReference<Map<String, dynamic>> _dayDoc(
          String userId, DateTime date) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('dailyData')
          .doc(df.format(date));

  /// Fetches daily data for a specific date as a DailyData object
  Future<DailyData> fetchDailyDataForDate(String userId, {DateTime? date}) async {
    final effectiveDate = date ?? DateTime.now();

    try {
      final dailyDataDoc = await _dayDoc(userId, effectiveDate).get();

      if (dailyDataDoc.exists) {
        final data = dailyDataDoc.data();
        if (data != null) {
          return DailyData(
            waterIntake: (data[waterIntakeField] as num?)?.toDouble() ?? 0.0,
            steps: (data[stepsField] as num?)?.toInt() ?? 0,
            isSaved: true,
          );
        }
      }
    } catch (e) {
      rethrow;
    }

    return DailyData(); // Return default values if no data found
  }

  /// Fetches daily data for a date range and returns a map of DateTime to DailyData
  Future<Map<DateTime, DailyData>> fetchDailyDataForDateRange(
    String userId,
    DateTimeRange dateRange,
  ) async {
    try {
      final start = dateRange.start;
      final end = dateRange.end;
      final days = end.difference(start).inDays + 1;

      final dates = List.generate(days, (index) {
        final date = start.add(Duration(days: index));
        return DateTime(date.year, date.month, date.day); // normalized date
      });

      final Map<DateTime, DailyData> resultMap = {};

      // Fetch all dates in parallel for better performance
      final futures = dates.map((date) async {
        final dailyData = await fetchDailyDataForDate(userId, date: date);
        return MapEntry(date, dailyData);
      });

      final results = await Future.wait(futures);

      for (final entry in results) {
        resultMap[entry.key] = entry.value;
      }

      // throw Exception('asd');
      return resultMap;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveDailyData(
    String userId,
    DateTime date, {
    required double waterIntake,
    required int steps,
  }) async {
    await _dayDoc(userId, date).set({
      waterIntakeField: waterIntake,
      stepsField: steps,
    }, SetOptions(merge: true));
  }
}
