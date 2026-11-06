import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/utils/birthdays.dart';

void main() {
  UserModel user(String id, String name, String surname, DateTime? birthDate) =>
      UserModel(
        userId: id,
        name: name,
        surname: surname,
        email: '$id@x.com',
        password: '',
        role: 'customer',
        birthDate: birthDate,
      );

  final BirthdayIndex index = BirthdayIndex([
    user('1', 'Zeynep', 'Kaya', DateTime(1990, 11, 6)),
    user('2', 'Ayşe', 'Demir', DateTime(1985, 11, 6)),
    user('3', 'Mehmet', 'Öz', DateTime(1992, 2, 29)),
    user('4', 'Can', 'Ak', null),
    user('5', 'Simge', 'Erdoğan', DateTime(1995, 11, 6)),
    user('6', 'Ece', 'Su', DateTime(2000, 2, 28)),
  ]);

  List<String> namesOn(DateTime day) =>
      index.on(day).map((u) => u.fullName).toList();

  test('doğum günü olanlar ada göre, çalışanlar hariç', () {
    expect(namesOn(DateTime(2026, 11, 6)), ['Ayşe Demir', 'Zeynep Kaya']);
    expect(namesOn(DateTime(2026, 11, 7)), isEmpty);
  });

  test('29 Şubat doğumlu artık yıl olmayan yılda 28 Şubat\'ta görünür', () {
    expect(namesOn(DateTime(2026, 2, 28)), ['Ece Su', 'Mehmet Öz']);
    expect(namesOn(DateTime(2028, 2, 28)), ['Ece Su']);
    expect(namesOn(DateTime(2028, 2, 29)), ['Mehmet Öz']);
  });

  test('girdiği yaş', () {
    expect(BirthdayIndex.ageOn(DateTime(1990, 11, 6), DateTime(2026, 11, 6)),
        36);
  });

  test('boş dizin', () {
    expect(const BirthdayIndex.empty().on(DateTime(2026, 11, 6)), isEmpty);
  });
}
