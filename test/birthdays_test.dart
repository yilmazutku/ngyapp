import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

  group('doğum tarihi kaydedildiği cihazın saat diliminden bağımsız', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    Future<UserModel> readBack(Timestamp birthDate) async {
      final DocumentReference<Map<String, dynamic>> doc =
          db.collection('users').doc();
      await doc.set({
        'name': 'Zeynep',
        'surname': 'Kaya',
        'role': 'customer',
        'birthDate': birthDate,
      });
      return UserModel.fromDocument(await doc.get());
    }

    test('10 Kasım 1990 her cihazda 10 Kasım, takvimde de o gün', () async {
      final Map<String, DateTime> savedAs = {
        'Windows (geçmiş tarihe de UTC+3)': DateTime.utc(1990, 11, 9, 21),
        'iOS / Android / macOS (1990 kışı UTC+2)':
            DateTime.utc(1990, 11, 9, 22),
        'yeni biçim (UTC gün başı)': DateTime.utc(1990, 11, 10),
      };
      for (final MapEntry<String, DateTime> saved in savedAs.entries) {
        final UserModel user = await readBack(Timestamp.fromDate(saved.value));
        expect(user.birthDate, DateTime(1990, 11, 10), reason: saved.key);
        expect(BirthdayIndex([user]).on(DateTime(2026, 11, 10)), [user],
            reason: saved.key);
        expect(BirthdayIndex([user]).on(DateTime(2026, 11, 9)), isEmpty,
            reason: saved.key);
      }
    });

    test('UTC+4\'lü dönemde (Ağustos 1983) kaydedilen tarih de kaymaz',
        () async {
      final UserModel user =
          await readBack(Timestamp.fromDate(DateTime.utc(1983, 8, 19, 20)));
      expect(user.birthDate, DateTime(1983, 8, 20));
    });

    test('UTC gün başı olarak yazılır, geri okununca aynı gün', () async {
      final UserModel user = UserModel(
        userId: 'u',
        name: 'Zeynep',
        surname: 'Kaya',
        email: 'u@x.com',
        password: '',
        role: 'customer',
        birthDate: DateTime(1990, 11, 10),
      );
      final Timestamp written = user.toMap()['birthDate'] as Timestamp;
      expect(written, Timestamp.fromDate(DateTime.utc(1990, 11, 10)));
      expect((await readBack(written)).birthDate, DateTime(1990, 11, 10));
    });
  });
}
