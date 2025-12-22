import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/logger.dart';

/// Model class for daily user data (water intake and steps)
class DailyData {
  final double waterIntake; // in liters
  final int steps;

  DailyData({this.waterIntake = 0.0, this.steps = 0});
}

class DailyDataProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(DailyDataProvider);
  final DateFormat df=DateFormat('yyyy-MM-dd');

  /// Fetches daily data for a specific date as a DailyData object
  Future<DailyData> fetchDailyDataForDate(String userId, {DateTime? date}) async {
    final effectiveDate = date ?? DateTime.now();
    final currentDate = df.format(effectiveDate);
    
    try {
      final dailyDataDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyData')
          .doc(currentDate)
          .get();
          
      if (dailyDataDoc.exists) {
        final data = dailyDataDoc.data();
        if (data != null) {
          return DailyData(
            waterIntake: (data['waterIntake'] as num?)?.toDouble() ?? 0.0,
            steps: (data['steps'] as num?)?.toInt() ?? 0,
          );
        }
      }
    } catch (e) {
      logger.err('Error fetching daily data for {}: {}', [currentDate, e]);
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
      
      logger.info('Fetched daily data for {} days in range {}-{}', 
        [days, df.format(start), df.format(end)]);

      // throw Exception('asd');
      return resultMap;
    } catch (e) {
      logger.err('Error fetching date range daily data, daterange={}, err={}', [dateRange,e]);
      rethrow;
    }
  }

  /// Saves water intake (in liters) for a specific user and date.
  Future<void> saveWaterIntake(
      String userId, DateTime date, double liters) async {
    final dateStr = df.format(date);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyData')
          .doc(dateStr);

      await docRef.set({
        'waterIntake': liters,
      }, SetOptions(merge: true));

      logger.info(
          'Water intake updated to {} liters for date {}', [liters, dateStr]);
    } catch (e) {
      logger.err(
          'Error saving water intake for date {}: {}', [dateStr, e]);
      rethrow;
    }
  }

  /// Saves steps count for a specific user and date.
  Future<void> saveSteps(String userId, DateTime date, int steps) async {
    final dateStr = df.format(date);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyData')
          .doc(dateStr);

      await docRef.set({
        'steps': steps,
      }, SetOptions(merge: true));

      logger.info('Steps updated to {} for date {}', [steps, dateStr]);
    } catch (e) {
      logger.err('Error saving steps for date {}: {}', [dateStr, e]);
      rethrow;
    }
  }
}

