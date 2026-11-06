import '../models/user_model.dart';
import 'search_text.dart';

class BirthdayIndex {
  BirthdayIndex(Iterable<UserModel> users) : _byMonthDay = _group(users);

  const BirthdayIndex.empty() : _byMonthDay = const {};

  final Map<int, List<UserModel>> _byMonthDay;

  static Map<int, List<UserModel>> _group(Iterable<UserModel> users) {
    final Map<int, List<UserModel>> byMonthDay = {};
    for (final UserModel user in users) {
      final DateTime? birthDate = user.birthDate;
      if (birthDate == null || user.isExcludedFromActiveCustomers) continue;
      (byMonthDay[_key(birthDate.month, birthDate.day)] ??= []).add(user);
    }
    for (final List<UserModel> group in byMonthDay.values) {
      group.sort((a, b) => compareSearchText(a.fullName, b.fullName));
    }
    return byMonthDay;
  }

  static int _key(int month, int day) => month * 100 + day;

  static bool _isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  List<UserModel> on(DateTime day) {
    final List<UserModel> born = _byMonthDay[_key(day.month, day.day)] ?? const [];
    final bool showsLeapDay =
        day.month == 2 && day.day == 28 && !_isLeapYear(day.year);
    final List<UserModel>? leapDay = showsLeapDay ? _byMonthDay[_key(2, 29)] : null;
    if (leapDay == null || leapDay.isEmpty) return born;
    return [...born, ...leapDay]
      ..sort((a, b) => compareSearchText(a.fullName, b.fullName));
  }

  static int ageOn(DateTime birthDate, DateTime day) =>
      day.year - birthDate.year;
}
