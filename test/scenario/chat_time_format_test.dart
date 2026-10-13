import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/utils/date_formatter.dart';

List<DateTime> _dstSwitchDays(int year) {
  final List<DateTime> days = <DateTime>[];
  for (DateTime day = DateTime(year);
      day.year == year;
      day = DateTime(day.year, day.month, day.day + 1)) {
    final DateTime next = DateTime(day.year, day.month, day.day + 1);
    if (day.timeZoneOffset != next.timeZoneOffset) days.add(day);
  }
  return days;
}

String _numericDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('Tüm Sohbetler zaman biçimi (8.1, E)', () {
    final DateTime now = DateTime(2026, 10, 13, 18, 0);

    String format(DateTime date) =>
        DateFormatter.formatChatListTime(date, now: now);

    test('bugünkü mesaj saatle yazılır: "14:05"', () {
      expect(format(DateTime(2026, 10, 13, 14, 5)), '14:05');
      expect(format(DateTime(2026, 10, 13, 0, 1)), '00:01');
    });

    test('dünkü mesaj "Dün" yazılır (24 saat değil, takvim günü)', () {
      expect(format(DateTime(2026, 10, 12, 23, 59)), 'Dün');
      expect(format(DateTime(2026, 10, 12, 0, 1)), 'Dün');
      expect(
        DateFormatter.formatChatListTime(DateTime(2026, 10, 12, 23, 50),
            now: DateTime(2026, 10, 13, 0, 5)),
        'Dün',
      );
    });

    test('son bir haftadaki mesaj Türkçe gün adıyla yazılır', () {
      expect(format(DateTime(2026, 10, 11, 9, 0)), 'Pazar');
      expect(format(DateTime(2026, 10, 10, 9, 0)), 'Cumartesi');
      expect(format(DateTime(2026, 10, 8, 9, 0)), 'Perşembe');
      expect(format(DateTime(2026, 10, 7, 9, 0)), 'Çarşamba');
      expect(
        DateFormatter.formatChatListTime(DateTime(2026, 10, 13, 9, 0),
            now: DateTime(2026, 10, 16, 12, 0)),
        'Salı',
      );
    });

    test('daha eski mesaj "12.09.2026" biçiminde yazılır', () {
      expect(format(DateTime(2026, 9, 12, 10, 30)), '12.09.2026');
      expect(format(DateTime(2025, 12, 31, 23, 0)), '31.12.2025');
    });

    test('bir hafta önceki aynı gün adı gün adıyla değil tarihle yazılır', () {
      expect(format(DateTime(2026, 10, 6, 9, 0)), '06.10.2026');
    });

    test('cihaz saati geride kaldığı için "gelecekte" görünen zaman bugün sayılır',
        () {
      expect(format(DateTime(2026, 10, 13, 18, 4)), '18:04');
      expect(
        DateFormatter.formatChatListTime(DateTime(2026, 10, 14, 0, 2),
            now: DateTime(2026, 10, 13, 23, 58)),
        '00:02',
      );
    });

    final List<DateTime> switchDays = _dstSwitchDays(2026);
    test('yaz saati geçişi günü kaydırmaz (geçiş gününden ertesi sabaha "Dün", 7 gün önce tarih)',
        () {
      for (final DateTime day in switchDays) {
        final DateTime switchNoon = DateTime(day.year, day.month, day.day, 12);
        final DateTime nextMorning =
            DateTime(day.year, day.month, day.day + 1, 9);
        final DateTime weekBefore =
            DateTime(day.year, day.month, day.day - 6, 9);
        expect(DateFormatter.formatChatListTime(switchNoon, now: nextMorning),
            'Dün',
            reason: 'geçiş günü $day');
        expect(DateFormatter.formatChatDayLabel(switchNoon, now: nextMorning),
            'Dün',
            reason: 'geçiş günü $day');
        expect(DateFormatter.formatChatListTime(weekBefore, now: nextMorning),
            _numericDate(weekBefore),
            reason: 'geçiş günü $day');
      }
    },
        skip: switchDays.isEmpty
            ? 'Bu makinenin saat diliminde 2026 yılında yaz saati geçişi yok; '
                'denemek için TZ=Europe/Berlin flutter test ile çalıştırın'
            : false);
  });

  group('Sohbet gün ayırıcısı (A: "Bugün / Dün / 12 Eylül")', () {
    final DateTime now = DateTime(2026, 10, 13, 18, 0);

    String label(DateTime date) =>
        DateFormatter.formatChatDayLabel(date, now: now);

    test('bugün "Bugün", dün "Dün"', () {
      expect(label(DateTime(2026, 10, 13, 8, 0)), 'Bugün');
      expect(label(DateTime(2026, 10, 12, 23, 59)), 'Dün');
    });

    test('daha eski gün "12 Eylül" biçiminde, gün adıyla değil', () {
      expect(label(DateTime(2026, 9, 12, 10, 0)), '12 Eylül');
      expect(label(DateTime(2026, 10, 10, 10, 0)), '10 Ekim');
    });

    test('başka yıldaki gün yılıyla yazılır', () {
      expect(label(DateTime(2025, 9, 12, 10, 0)), '12 Eylül 2025');
    });

    test('cihaz saati geride kalınca "gelecekte" görünen mesaj "Bugün" altında',
        () {
      expect(
        DateFormatter.formatChatDayLabel(DateTime(2026, 10, 14, 0, 2),
            now: DateTime(2026, 10, 13, 23, 58)),
        'Bugün',
      );
    });
  });
}
