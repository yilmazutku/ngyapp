import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';

final DateTime _morning = DateTime(2026, 10, 21, 9);
final DateTime _noon = DateTime(2026, 10, 21, 12);
final DateTime _evening = DateTime(2026, 10, 21, 19);

/// `imageUrls` listesinden önceki tek adresli (`imageUrl`) eski kayıt,
/// [MealModel.fromDocument]'in okuduğu hâliyle: küçük görsel ve saat listesi
/// yok.
MealModel _legacySinglePhoto() => MealModel(
      mealId: Meals.lunch.name,
      mealType: Meals.lunch,
      imageUrls: const ['eski'],
      subscriptionId: 'abonelik',
      description: 'açıklama',
      calories: 450,
      notes: 'not',
      timestamp: _morning,
      isChecked: true,
    );

MealModel? _add(MealModel? current, String url,
        {String? thumb, required DateTime time}) =>
    MealManager.mealWithImageAdded(
      current,
      meal: Meals.lunch,
      subscriptionId: 'abonelik',
      imageUrl: url,
      thumbUrl: thumb,
      time: time,
    );

MealModel? _remove(MealModel current, String url) =>
    MealManager.mealWithImageRemovedAt(current, current.imageUrls.indexOf(url));

void main() {
  group('MealManager.mealWithImageAdded', () {
    test('kayıt yoksa tek fotoğraflı yeni kayıt olur', () {
      final MealModel added = _add(null, 'a', thumb: 'a_t', time: _noon)!;

      expect(added.mealId, Meals.lunch.name);
      expect(added.mealType, Meals.lunch);
      expect(added.imageUrls, ['a']);
      expect(added.thumbUrls, ['a_t']);
      expect(added.imageTimes, [_noon]);
      expect(added.timestamp, _noon);
      expect(added.subscriptionId, 'abonelik');
      expect(added.isChecked, isTrue);
    });

    test('tek adresli eski kayda eklenir; eski fotoğraf ve alanlar korunur',
        () {
      final MealModel added =
          _add(_legacySinglePhoto(), 'yeni', thumb: 'yeni_t', time: _noon)!;

      expect(added.imageUrls, ['eski', 'yeni']);
      expect(added.thumbUrls, ['', 'yeni_t']);
      // Eski fotoğrafın saati kaydedilmemişti: öğünün saatine düşer.
      expect(added.imageTimes, [_morning, _noon]);
      expect(added.timestamp, _noon);
      expect(added.description, 'açıklama');
      expect(added.calories, 450);
      expect(added.notes, 'not');

      final Map<String, dynamic> written = added.toMap();
      expect(written['imageUrls'], ['eski', 'yeni']);
      expect(written['imageUrl'], 'eski');
      expect(written['thumbUrls'], ['', 'yeni_t']);
    });

    test('eksik küçük görsel ve saatler eklemeden önce hizalanır', () {
      final MealModel current = MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: const ['a', 'b', 'c'],
        thumbUrls: const ['a_t'],
        imageTimes: [_morning],
        timestamp: _noon,
        isChecked: true,
      );

      final MealModel added = _add(current, 'd', time: _evening)!;

      expect(added.imageUrls, ['a', 'b', 'c', 'd']);
      // Küçük görseli olmayan yeni fotoğrafın yerinde de boş dize durur.
      expect(added.thumbUrls, ['a_t', '', '', '']);
      expect(added.imageTimes, [_morning, _noon, _noon, _evening]);
    });

    test('sınır doluysa null döner', () {
      final MealModel full = MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: [
          for (int i = 0; i < MealModel.maxImages; i++) 'u$i',
        ],
        timestamp: _noon,
        isChecked: true,
      );

      expect(_add(full, 'fazla', time: _evening), isNull);
    });
  });

  group('MealManager.mealWithImageRemovedAt', () {
    test('aradaki fotoğraf üç listeden aynı sırayla çıkar', () {
      final MealModel current = MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: const ['a', 'b', 'c'],
        thumbUrls: const ['a_t', 'b_t', 'c_t'],
        imageTimes: [_morning, _noon, _evening],
        subscriptionId: 'abonelik',
        description: 'açıklama',
        timestamp: _evening,
        isChecked: true,
      );

      final MealModel remaining = _remove(current, 'b')!;

      expect(remaining.imageUrls, ['a', 'c']);
      expect(remaining.thumbUrls, ['a_t', 'c_t']);
      expect(remaining.imageTimes, [_morning, _evening]);
      expect(remaining.subscriptionId, 'abonelik');
      expect(remaining.description, 'açıklama');
    });

    test('öğünün saati kalan fotoğrafların en son yükleneni olur', () {
      final MealModel current = MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: const ['a', 'b', 'c'],
        imageTimes: [_noon, _evening, _morning],
        timestamp: _evening,
        isChecked: true,
      );

      expect(_remove(current, 'b')!.timestamp, _noon);
    });

    test('eksik küçük görsel ve saatler çıkarmadan önce hizalanır', () {
      final MealModel current = MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: const ['a', 'b', 'c'],
        thumbUrls: const ['a_t'],
        timestamp: _noon,
        isChecked: true,
      );

      final MealModel remaining = _remove(current, 'a')!;

      expect(remaining.imageUrls, ['b', 'c']);
      expect(remaining.thumbUrls, ['', '']);
      expect(remaining.imageTimes, [_noon, _noon]);
      expect(remaining.toMap()['imageUrl'], 'b');
    });

    test('tek adresli eski kaydın tek fotoğrafı çıkınca kayıt kalmaz', () {
      expect(_remove(_legacySinglePhoto(), 'eski'), isNull);
    });
  });
}
