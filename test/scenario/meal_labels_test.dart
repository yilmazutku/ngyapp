import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';

MealModel _mealWithPhotos(int count) => MealModel(
      mealId: 'lunch',
      mealType: Meals.lunch,
      imageUrls: List<String>.generate(count, (i) => 'https://x/$i.jpg'),
      timestamp: DateTime(2026, 10, 13, 12, 30),
      isChecked: true,
    );

void main() {
  group('Öğün adları (F, 3.1, 5.1)', () {
    test('ara öğünler her yerde numarasız "Ara" görünür', () {
      expect(Meals.firstmid.displayLabel, 'Ara');
      expect(Meals.secondmid.displayLabel, 'Ara');
      expect(Meals.thirdmid.displayLabel, 'Ara');
    });

    test('diğer öğünler kendi adıyla, "Hiçbiri" yerine "Diğer" görünür', () {
      expect(Meals.br.displayLabel, 'Sabah');
      expect(Meals.lunch.displayLabel, 'Öğle');
      expect(Meals.dinner.displayLabel, 'Akşam');
      expect(Meals.none.displayLabel, 'Diğer');
      expect(Meals.none.label, 'Diğer');
    });

    test('hiçbir öğünün kullanıcıya görünen adında "Ara Öğün" ya da "Hiçbiri" yok',
        () {
      for (final Meals meal in Meals.values) {
        expect(meal.displayLabel, isNot(contains('Ara Öğün')),
            reason: meal.name);
        expect(meal.displayLabel, isNot(contains('Hiçbiri')),
            reason: meal.name);
        expect(meal.chatCaption, isNot(contains('Ara Öğün')),
            reason: meal.name);
        expect(meal.chatSummary, isNot(contains('Ara Öğün')),
            reason: meal.name);
      }
    });
  });

  group('Sohbetteki öğün metinleri (3.3, 4.2, 8.2)', () {
    test('öğün fotoğrafı mesajının açıklaması "Öğün: Ara" / "Öğün: Öğle"', () {
      expect(Meals.secondmid.chatCaption, 'Öğün: Ara');
      expect(Meals.lunch.chatCaption, 'Öğün: Öğle');
      expect(Meals.none.chatCaption, 'Öğün: Diğer');
    });

    test('sohbet listesindeki özet "Öğün Fotoğrafı (Ara)"', () {
      expect(Meals.firstmid.chatSummary, 'Öğün Fotoğrafı (Ara)');
      expect(Meals.thirdmid.chatSummary, 'Öğün Fotoğrafı (Ara)');
      expect(Meals.dinner.chatSummary, 'Öğün Fotoğrafı (Akşam)');
    });

    test('eski mesajlardaki numaralı ara öğün ve "Hiçbiri" bugünkü adlarla gösterilir',
        () {
      expect(Meals.chatTextForDisplay('Öğün: Ara Öğün 2'), 'Öğün: Ara');
      expect(Meals.chatTextForDisplay('Öğün: Ara Öğün 1'), 'Öğün: Ara');
      expect(Meals.chatTextForDisplay('Öğün: Ara Öğün 3'), 'Öğün: Ara');
      expect(Meals.chatTextForDisplay('Öğün: Ara Öğün'), 'Öğün: Ara');
      expect(Meals.chatTextForDisplay('Öğün: Hiçbiri'), 'Öğün: Diğer');
      expect(Meals.chatTextForDisplay('Öğün Fotoğrafı (Ara Öğün 2)'),
          'Öğün Fotoğrafı (Ara)');
      expect(Meals.chatTextForDisplay('Öğün Fotoğrafı (Hiçbiri)'),
          'Öğün Fotoğrafı (Diğer)');
      expect(Meals.chatTextForDisplay('Öğün: Ara Öğün 2 (fotoğraf silindi)'),
          'Öğün: Ara (fotoğraf silindi)');
    });

    test('bugünkü adlarla yazılmış öğün metni değişmez', () {
      expect(Meals.chatTextForDisplay('Öğün: Ara'), 'Öğün: Ara');
      expect(Meals.chatTextForDisplay('Öğün: Öğle'), 'Öğün: Öğle');
      expect(Meals.chatTextForDisplay('Öğün: Diğer'), 'Öğün: Diğer');
    });

    test('kullanıcının kendi yazdığı metne dokunulmaz', () {
      const List<String> userTexts = <String>[
        'Ara Öğün 2 ne zaman?',
        'Hiçbiri olmadı bugün',
        'Merhaba',
        'öğün: Ara Öğün 2',
        '',
      ];
      for (final String text in userTexts) {
        expect(Meals.chatTextForDisplay(text), text);
      }
    });
  });

  group('Silinen fotoğrafın sohbetteki notu (D, 7.1, 7.3)', () {
    test('"Öğün: Öğle" -> "Öğün: Öğle (fotoğraf silindi)"', () {
      expect(Meals.deletedPhotoChatText('Öğün: Öğle'),
          'Öğün: Öğle (fotoğraf silindi)');
      expect(Meals.deletedPhotoChatText('Öğün: Akşam'),
          'Öğün: Akşam (fotoğraf silindi)');
    });

    test('eski numaralı ara öğün mesajı silinince not "Ara" ile yazılır', () {
      expect(Meals.deletedPhotoChatText('Öğün: Ara Öğün 2'),
          'Öğün: Ara (fotoğraf silindi)');
    });

    test('açıklaması olmayan fotoğraf silinince "Fotoğraf silindi"', () {
      expect(Meals.deletedPhotoChatText(null), 'Fotoğraf silindi');
      expect(Meals.deletedPhotoChatText(''), 'Fotoğraf silindi');
      expect(Meals.deletedPhotoChatText('   '), 'Fotoğraf silindi');
    });
  });

  group('Öğün başına fotoğraf sınırı (B, 3.8, 7.10)', () {
    test('sınır 10 ve uyarı metni senaryodaki gibi', () {
      expect(MealModel.maxImages, 10);
      expect(MealModel.maxImagesReachedTitle, 'Fotoğraf Sınırı');
      expect(MealModel.maxImagesReachedMessage,
          'Bir öğün için en fazla 10 fotoğraf yüklenmesine izin verilmektedir.');
    });

    test('9 fotoğrafta bir tane daha eklenebilir, 10\'da eklenemez', () {
      expect(_mealWithPhotos(3).canAddMoreImages, isTrue);
      expect(_mealWithPhotos(9).canAddMoreImages, isTrue);
      expect(_mealWithPhotos(10).canAddMoreImages, isFalse);
    });
  });
}
