import 'dart:math' as math;
import 'dart:ui';

class CalendarDropTarget {
  const CalendarDropTarget(
      {required this.dayIndex, required this.startMinutes});

  final int dayIndex;
  final int startMinutes;

  DateTime onDay(DateTime day) => DateTime(
      day.year, day.month, day.day, startMinutes ~/ 60, startMinutes % 60);

  @override
  bool operator ==(Object other) =>
      other is CalendarDropTarget &&
      other.dayIndex == dayIndex &&
      other.startMinutes == startMinutes;

  @override
  int get hashCode => Object.hash(dayIndex, startMinutes);

  @override
  String toString() =>
      'CalendarDropTarget(dayIndex: $dayIndex, startMinutes: $startMinutes)';
}

class CalendarGridGeometry {
  const CalendarGridGeometry({
    required this.contentWidth,
    required this.timeColumnWidth,
    required this.headerHeight,
    required this.dayCount,
    required this.gridStartMinutes,
    required this.gridEndMinutes,
    required this.pixelsPerMinute,
    required this.snapMinutes,
  })  : assert(dayCount > 0),
        assert(snapMinutes > 0),
        assert(pixelsPerMinute > 0),
        assert(gridEndMinutes > gridStartMinutes);

  final double contentWidth;
  final double timeColumnWidth;
  final double headerHeight;
  final int dayCount;
  final int gridStartMinutes;
  final int gridEndMinutes;
  final double pixelsPerMinute;
  final int snapMinutes;

  double get dayWidth => (contentWidth - timeColumnWidth) / dayCount;

  double dayLeft(int dayIndex) => timeColumnWidth + dayIndex * dayWidth;

  double topOf(int minutes) =>
      headerHeight + (minutes - gridStartMinutes) * pixelsPerMinute;

  int dayIndexAt(double dx) {
    final double width = dayWidth;
    if (width <= 0) return 0;
    return ((dx - timeColumnWidth) / width).floor().clamp(0, dayCount - 1);
  }

  int latestStart(int durationMinutes, int originalMinutes) {
    final int footprint = math.max(durationMinutes, snapMinutes);
    final int onGrid =
        ((gridEndMinutes - footprint) ~/ snapMinutes) * snapMinutes;
    return math.max(math.max(onGrid, originalMinutes), gridStartMinutes);
  }

  int snapStart({
    required double rawMinutes,
    required int originalMinutes,
    required int durationMinutes,
  }) {
    final int onGrid = (rawMinutes / snapMinutes).round() * snapMinutes;
    final bool staysPut =
        (rawMinutes - originalMinutes).abs() <= (rawMinutes - onGrid).abs();
    final int snapped = staysPut ? originalMinutes : onGrid;
    return snapped.clamp(
        gridStartMinutes, latestStart(durationMinutes, originalMinutes));
  }

  CalendarDropTarget dropTarget({
    required Offset pointer,
    required double grabDy,
    required int originalMinutes,
    required int durationMinutes,
  }) {
    final double cardTop = pointer.dy - grabDy - headerHeight;
    return CalendarDropTarget(
      dayIndex: dayIndexAt(pointer.dx),
      startMinutes: snapStart(
        rawMinutes: gridStartMinutes + cardTop / pixelsPerMinute,
        originalMinutes: originalMinutes,
        durationMinutes: durationMinutes,
      ),
    );
  }
}
