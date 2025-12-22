// filter_params.dart
// Model for passing filter parameters from UI to providers for Firebase-side filtering
//
// OPTIMIZATION: This class enables Firebase-side filtering instead of client-side filtering
// Benefits:
// - Reduces data transfer (only filtered results are fetched)
// - Improves performance for large datasets
// - Scalable architecture
//
// Architecture:
// 1. UI layer (tabs) builds FilterParams based on user selections
// 2. FilterParams passed to providers via getDataList()
// 3. Providers apply filters in Firebase queries (WHERE clauses, date ranges)
// 4. Only matching data is transferred to client
// 5. Complex filters (full-text search) still done client-side where Firebase doesn't support them
//
// Usage pattern:
// - Status filters, enum filters → Firebase WHERE clauses
// - Date range filters → Firebase timestamp comparisons
// - Text search in complex fields → Client-side (Firebase doesn't support full-text search efficiently)

import 'package:flutter/material.dart';

/// Base class for filter parameters that can be passed to providers
/// for server-side (Firebase) filtering
abstract class FilterParams {
  final DateTimeRange? dateRange;
  final String? searchQuery;

  const FilterParams({
    this.dateRange,
    this.searchQuery,
  });

  /// Returns true if any filters are active
  bool get hasFilters => dateRange != null || (searchQuery != null && searchQuery!.isNotEmpty);

  /// Returns a map representation for debugging
  Map<String, dynamic> toDebugMap() => {
        'dateRange': dateRange != null
            ? '${dateRange!.start.toIso8601String()} - ${dateRange!.end.toIso8601String()}'
            : null,
        'searchQuery': searchQuery,
      };
}

/// Filter parameters for appointments
class AppointmentFilterParams extends FilterParams {
  final String? status; // AppointmentStatus label
  final String? meetingType; // MeetingType label
  final String? sortOption; // AppointmentSortOption label

  const AppointmentFilterParams({
    super.dateRange,
    super.searchQuery,
    this.status,
    this.meetingType,
    this.sortOption,
  });

  @override
  bool get hasFilters =>
      super.hasFilters || status != null || meetingType != null || sortOption != null;

  @override
  Map<String, dynamic> toDebugMap() => {
        ...super.toDebugMap(),
        'status': status,
        'meetingType': meetingType,
        'sortOption': sortOption,
      };
}

/// Filter parameters for diets
class DietFilterParams extends FilterParams {
  const DietFilterParams({
    super.dateRange,
    super.searchQuery,
  });
}

/// Filter parameters for meal images
class MealFilterParams extends FilterParams {
  final String? mealType; // Meals enum value
  final bool showOnlyThisWeek;
  final DateTime? specificDate;

  const MealFilterParams({
    super.dateRange,
    super.searchQuery,
    this.mealType,
    this.showOnlyThisWeek = false,
    this.specificDate,
  });

  @override
  bool get hasFilters =>
      super.hasFilters || mealType != null || showOnlyThisWeek || specificDate != null;

  @override
  Map<String, dynamic> toDebugMap() => {
        ...super.toDebugMap(),
        'mealType': mealType,
        'showOnlyThisWeek': showOnlyThisWeek,
        'specificDate': specificDate?.toIso8601String(),
      };
}

/// Filter parameters for measurements
class MeasurementFilterParams extends FilterParams {
  const MeasurementFilterParams({
    super.dateRange,
    super.searchQuery,
  });
}

/// Filter parameters for payments
class PaymentFilterParams extends FilterParams {
  final String? status; // PaymentStatus label

  const PaymentFilterParams({
    super.dateRange,
    super.searchQuery,
    this.status,
  });

  @override
  bool get hasFilters => super.hasFilters || status != null;

  @override
  Map<String, dynamic> toDebugMap() => {
        ...super.toDebugMap(),
        'status': status,
      };
}

/// Filter parameters for subscriptions
class SubscriptionFilterParams extends FilterParams {
  final String? status; // SubActiveStatus label

  const SubscriptionFilterParams({
    super.dateRange,
    super.searchQuery,
    this.status,
  });

  @override
  bool get hasFilters => super.hasFilters || status != null;

  @override
  Map<String, dynamic> toDebugMap() => {
        ...super.toDebugMap(),
        'status': status,
      };
}

