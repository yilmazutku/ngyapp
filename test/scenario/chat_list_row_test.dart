import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/utils/search_text.dart';

UserModel _user(String name, String surname, {String email = 'x@y.z'}) =>
    UserModel(
      userId: 'u-$name-$surname',
      name: name,
      surname: surname,
      email: email,
      password: '',
      role: 'customer',
    );

bool _matches(String query, UserModel user) => matchesSearchWords(
      searchWordsOf(query),
      searchWordsOf('${user.fullName} ${user.email}'),
    );

void main() {
  group('Avatardaki baş harfler Türkçe büyük harfle (8.2)', () {
    test('"ilknur şahin" -> "İŞ"', () {
      expect(_user('ilknur', 'şahin').initials, 'İŞ');
    });

    test('noktasız ı "I", noktalı i "İ" olur', () {
      expect(_user('ışıl', 'ince').initials, 'Iİ');
      expect(_user('İnci', 'Işık').initials, 'İI');
    });

    test('ç, ğ, ö, ü, ş büyük harfe çevrilir', () {
      expect(_user('çağla', 'öztürk').initials, 'ÇÖ');
      expect(_user('ümran', 'şen').initials, 'ÜŞ');
    });

    test('baştaki/sondaki boşluklar yok sayılır', () {
      expect(_user('  ayşe ', ' yılmaz  ').initials, 'AY');
    });

    test('soyadı yoksa tek harf, ikisi de yoksa "?"', () {
      expect(_user('nilay', '').initials, 'N');
      expect(_user('', '').initials, '?');
      expect(_user('   ', '  ').initials, '?');
    });
  });

  group('Tüm Sohbetler araması Türkçe harf duyarsız (8.3)', () {
    final UserModel isil = _user('Işıl', 'Şahin', email: 'isil.sahin@mail.com');
    final UserModel ilknur =
        _user('İlknur', 'Çelik', email: 'ilknur@ornek.com');
    final UserModel oya = _user('Oya', 'Oytan', email: 'oya.oytan@mail.com');

    test('"ış" ve "IS" ile "Işıl Şahin" bulunur', () {
      expect(_matches('ış', isil), isTrue);
      expect(_matches('IS', isil), isTrue);
      expect(_matches('işil', isil), isTrue);
    });

    test('"şa" ve "SA" soyadından bulur', () {
      expect(_matches('şa', isil), isTrue);
      expect(_matches('SA', isil), isTrue);
    });

    test('"i" ve "İ" ile "İlknur" bulunur, "çel" ve "CEL" ile "Çelik"', () {
      expect(_matches('i', ilknur), isTrue);
      expect(_matches('İL', ilknur), isTrue);
      expect(_matches('çel', ilknur), isTrue);
      expect(_matches('CEL', ilknur), isTrue);
    });

    test('e-postayla aranabilir', () {
      expect(_matches('ilknur@ornek.com', ilknur), isTrue);
      expect(_matches('ornek', ilknur), isTrue);
      expect(_matches('oya.oytan', oya), isTrue);
    });

    test('alakasız danışan eşleşmez', () {
      expect(_matches('ış', oya), isFalse);
      expect(_matches('çel', isil), isFalse);
    });
  });
}
