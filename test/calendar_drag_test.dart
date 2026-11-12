import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/calendar_drag.dart';

const double _timeColumnWidth = 50;
const double _headerHeight = 54;
const double _pixelsPerMinute = 2.4;
const int _gridStart = 8 * 60 + 30;
const int _gridEnd = 20 * 60;

CalendarGridGeometry _geometry({int dayCount = 6, int snapMinutes = 10}) =>
    CalendarGridGeometry(
      contentWidth: _timeColumnWidth + dayCount * 200,
      timeColumnWidth: _timeColumnWidth,
      headerHeight: _headerHeight,
      dayCount: dayCount,
      gridStartMinutes: _gridStart,
      gridEndMinutes: _gridEnd,
      pixelsPerMinute: _pixelsPerMinute,
      snapMinutes: snapMinutes,
    );

int _minutes(int hour, int minute) => hour * 60 + minute;

void main() {
  group('gün sütunu', () {
    test('işaretçinin altındaki günü verir', () {
      final CalendarGridGeometry geometry = _geometry();
      expect(geometry.dayWidth, 200);
      expect(geometry.dayIndexAt(_timeColumnWidth), 0);
      expect(geometry.dayIndexAt(_timeColumnWidth + 199.9), 0);
      expect(geometry.dayIndexAt(_timeColumnWidth + 200), 1);
      expect(geometry.dayIndexAt(_timeColumnWidth + 5 * 200 + 1), 5);
    });

    test(
        'saat sütununun üstünde ilk güne, sağ kenarın dışında son güne '
        'sabitlenir', () {
      final CalendarGridGeometry geometry = _geometry();
      expect(geometry.dayIndexAt(0), 0);
      expect(geometry.dayIndexAt(-300), 0);
      expect(geometry.dayIndexAt(5000), 5);
    });

    test('tek günlük görünümde yatay hareket günü değiştirmez', () {
      final CalendarGridGeometry geometry = _geometry(dayCount: 1);
      expect(geometry.dayIndexAt(-50), 0);
      expect(geometry.dayIndexAt(120), 0);
      expect(geometry.dayIndexAt(900), 0);
    });
  });

  group('saat adımı', () {
    final CalendarGridGeometry geometry = _geometry();

    int snap(double raw, int original, {int duration = 30}) =>
        geometry.snapStart(
          rawMinutes: raw,
          originalMinutes: original,
          durationMinutes: duration,
        );

    test('10 dakikalık adımlara oturur', () {
      final int original = _minutes(10, 0);
      expect(snap(_minutes(10, 0) + 4.9, original), _minutes(10, 0));
      expect(snap(_minutes(10, 0) + 5.1, original), _minutes(10, 10));
      expect(snap(_minutes(10, 0) + 14.9, original), _minutes(10, 10));
      expect(snap(_minutes(10, 0) + 15.1, original), _minutes(10, 20));
      expect(snap(_minutes(10, 0) - 5.1, original), _minutes(9, 50));
      expect(snap(_minutes(10, 0) + 83, original), _minutes(11, 20));
    });

    test('adım boyu değiştirilebilir (15 dk)', () {
      final CalendarGridGeometry quarter = _geometry(snapMinutes: 15);
      expect(
        quarter.snapStart(
          rawMinutes: _minutes(10, 0) + 8,
          originalMinutes: _minutes(10, 0),
          durationMinutes: 30,
        ),
        _minutes(10, 15),
      );
    });

    test(
        'ızgara dışındaki bir saatte başlayan randevu yerinden oynamadıkça '
        'kendi saatinde kalır', () {
      final int original = _minutes(10, 5);
      expect(snap(original.toDouble(), original), original);
      expect(snap(original + 2.0, original), original);
      expect(snap(original - 2.0, original), original);
      expect(snap(original + 3.0, original), _minutes(10, 10));
      expect(snap(original - 3.0, original), _minutes(10, 0));
      expect(snap(original + 12.0, original), _minutes(10, 20));
    });

    test('ızgaranın başından önceye taşınamaz', () {
      expect(snap(_gridStart - 200.0, _minutes(9, 0)), _gridStart);
    });

    test('randevunun bitişi ızgaranın sonunu aşmaz', () {
      expect(snap(_gridEnd + 300.0, _minutes(18, 0)), _minutes(19, 30));
      expect(snap(_gridEnd + 300.0, _minutes(18, 0), duration: 45),
          _minutes(19, 10));
      expect(snap(_gridEnd + 300.0, _minutes(18, 0), duration: 5),
          _minutes(19, 50));
    });

    test('zaten ızgaranın sonunu aşan randevu yatay taşınırken saatini korur',
        () {
      final int original = _minutes(19, 45);
      expect(snap(original.toDouble(), original), original);
      expect(snap(original + 40.0, original), original);
      expect(snap(original - 6.0, original), _minutes(19, 40));
    });
  });

  group('bırakma hedefi', () {
    final CalendarGridGeometry geometry = _geometry();
    final int original = _minutes(10, 0);
    final double cardTop = geometry.topOf(original);
    const double grabDy = 17;

    CalendarDropTarget target(Offset pointer) => geometry.dropTarget(
          pointer: pointer,
          grabDy: grabDy,
          originalMinutes: original,
          durationMinutes: 30,
        );

    test(
        'kart tutulduğu noktadan taşınır: işaretçi oynamadıkça hedef '
        'değişmez', () {
      expect(
        target(Offset(_timeColumnWidth + 30, cardTop + grabDy)),
        CalendarDropTarget(dayIndex: 0, startMinutes: original),
      );
    });

    test('yalnızca yatay hareket saati değiştirmez, günü değiştirir', () {
      expect(
        target(Offset(_timeColumnWidth + 3 * 200 + 30, cardTop + grabDy)),
        CalendarDropTarget(dayIndex: 3, startMinutes: original),
      );
    });

    test('dikey hareket piksel karşılığı kadar dakika kaydırır', () {
      expect(
        target(Offset(
            _timeColumnWidth + 30, cardTop + grabDy + 60 * _pixelsPerMinute)),
        CalendarDropTarget(dayIndex: 0, startMinutes: _minutes(11, 0)),
      );
      expect(
        target(Offset(
            _timeColumnWidth + 430, cardTop + grabDy - 30 * _pixelsPerMinute)),
        CalendarDropTarget(dayIndex: 2, startMinutes: _minutes(9, 30)),
      );
    });

    test('bir adımın yarısından az hareket hedefi değiştirmez', () {
      final double halfStep = 5 * _pixelsPerMinute;
      expect(
        target(Offset(_timeColumnWidth + 30, cardTop + grabDy + halfStep - 1)),
        CalendarDropTarget(dayIndex: 0, startMinutes: original),
      );
      expect(
        target(Offset(_timeColumnWidth + 30, cardTop + grabDy + halfStep + 1)),
        CalendarDropTarget(dayIndex: 0, startMinutes: _minutes(10, 10)),
      );
    });

    test('hedef, günün tarihine ve saatine çevrilir', () {
      expect(
        const CalendarDropTarget(dayIndex: 2, startMinutes: 14 * 60 + 40)
            .onDay(DateTime(2026, 11, 12)),
        DateTime(2026, 11, 12, 14, 40),
      );
    });
  });

  test('ızgara konumları: gün sütununun solu ve saatin üst kenarı', () {
    final CalendarGridGeometry geometry = _geometry();
    expect(geometry.dayLeft(0), _timeColumnWidth);
    expect(geometry.dayLeft(4), _timeColumnWidth + 800);
    expect(geometry.topOf(_gridStart), _headerHeight);
    expect(geometry.topOf(_minutes(9, 30)),
        closeTo(_headerHeight + 60 * _pixelsPerMinute, 1e-9));
  });
}
