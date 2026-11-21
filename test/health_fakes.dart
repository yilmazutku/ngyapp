import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:health/health.dart';
import 'package:ngy_app/providers/daily_data_provider.dart';
import 'package:ngy_app/services/health_steps_service.dart';

class FakeHealth extends Health {
  FakeHealth({this.iosLike = false});

  final bool iosLike;
  bool available = true;
  bool permitted = false;
  bool grantOnRequest = true;
  int? steps = 1234;
  Object? stepsError;
  Object? permissionError;
  Completer<void>? requestGate;
  int availabilityChecks = 0;
  int permissionChecks = 0;
  int requests = 0;
  final List<(DateTime, DateTime)> intervals = <(DateTime, DateTime)>[];

  int get calls =>
      availabilityChecks + permissionChecks + requests + intervals.length;

  @override
  Future<bool> isHealthConnectAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    permissionChecks++;
    if (permissionError != null) throw permissionError!;
    if (iosLike) return null;
    return permitted;
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requests++;
    if (requestGate != null) await requestGate!.future;
    if (grantOnRequest) permitted = true;
    return grantOnRequest;
  }

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    intervals.add((startTime, endTime));
    if (stepsError != null) throw stepsError!;
    return steps;
  }
}

class FakeHealthSteps extends HealthStepsService {
  FakeHealthSteps([Map<DateTime, FutureOr<int?>>? steps])
      : steps = steps ?? <DateTime, FutureOr<int?>>{};

  final Map<DateTime, FutureOr<int?>> steps;
  final List<DateTime> asked = <DateTime>[];
  bool supported = true;

  @override
  bool get isSupported => supported;

  @override
  Future<int?> stepsForDay(DateTime day) async {
    asked.add(day);
    return steps[day];
  }
}

class ScriptedDailyDataProvider extends DailyDataProvider {
  ScriptedDailyDataProvider(FakeFirebaseFirestore db) : super(firestore: db);

  int fetchFailures = 0;
  int saveFailures = 0;
  int stepsSyncFailures = 0;
  final List<DateTime> stepsSyncDays = <DateTime>[];
  final Map<DateTime, Completer<void>> fetchGates =
      <DateTime, Completer<void>>{};

  @override
  Future<DailyData> fetchDailyDataForDate(String userId,
      {DateTime? date}) async {
    final Completer<void>? gate = fetchGates[date];
    if (gate != null) await gate.future;
    if (fetchFailures > 0) {
      fetchFailures--;
      throw Exception('offline');
    }
    return super.fetchDailyDataForDate(userId, date: date);
  }

  @override
  Future<void> saveDailyData(
    String userId,
    DateTime date, {
    required double waterIntake,
    required int steps,
  }) async {
    if (saveFailures > 0) {
      saveFailures--;
      throw Exception('offline');
    }
    return super.saveDailyData(userId, date,
        waterIntake: waterIntake, steps: steps);
  }

  @override
  Future<int> saveStepsIfHigher(
      String userId, DateTime date, int steps) async {
    stepsSyncDays.add(date);
    if (stepsSyncFailures > 0) {
      stepsSyncFailures--;
      throw Exception('offline');
    }
    return super.saveStepsIfHigher(userId, date, steps);
  }
}
