import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/services/meal_reminder_service.dart';

/// Firestore'un `set(..., SetOptions(merge: true))` davranışı: iç içe map'ler
/// alan alan birleşir, yazılmayan alanlar olduğu gibi kalır.
Map<String, dynamic> _merge(
    Map<String, dynamic> current, Map<String, dynamic> write) {
  final Map<String, dynamic> result = Map<String, dynamic>.from(current);
  write.forEach((key, value) {
    final Object? existing = result[key];
    result[key] = value is Map<String, dynamic> && existing is Map<String, dynamic>
        ? _merge(existing, value)
        : value;
  });
  return result;
}

void main() {
  group('MealReminderService.mealsWithoutReminder', () {
    test('gün dokümanı yoksa her öğüne hatırlatma kurulur', () {
      expect(MealReminderService.mealsWithoutReminder(null), isEmpty);
      expect(MealReminderService.mealsWithoutReminder({}), isEmpty);
    });

    test('işaretlenmiş öğün atlanır, işareti kalkmış öğün atlanmaz', () {
      final Set<Meals> skipped = MealReminderService.mealsWithoutReminder({
        'meals': {'br': true, 'lunch': false},
      });
      expect(skipped, {Meals.br});
    });

    test('tanınmayan öğün adları ve bool olmayan değerler yok sayılır', () {
      final Set<Meals> skipped = MealReminderService.mealsWithoutReminder({
        'meals': {'unknown': true, 'dinner': 'true'},
        MealReminderService.REMINDER_CANCELLED_FIELD: 'bozuk',
      });
      expect(skipped, isEmpty);
    });
  });

  // Gün dokümanına yazılan alanların (MealManager.mealStateFields) birleşince
  // hatırlatmayı nasıl etkilediği. Sohbetten yükleme photoUploaded: true ile,
  // silme photoUploaded vermeden yazar.
  group('mealStateFields ile mealsWithoutReminder birlikte', () {
    test('yükleme işareti, son fotoğrafın silinme yazımıyla geri alınmaz', () {
      // Sohbetten yükleme.
      Map<String, dynamic> day = _merge(
        {},
        MealManager.mealStateFields(Meals.lunch, true, photoUploaded: true),
      );
      expect(MealReminderService.mealsWithoutReminder(day), {Meals.lunch});

      // Öğünün son fotoğrafı silindi: öğün işaretsiz olur ama hatırlatma geri
      // gelmez.
      day = _merge(day, MealManager.mealStateFields(Meals.lunch, false));
      expect(day['meals'], {'lunch': false});
      expect(MealReminderService.mealsWithoutReminder(day), {Meals.lunch});
    });

    test('photoUploaded vermeyen yazım (elle işaretleme, test verisi) kalıcı '
        'işaret yazmaz', () {
      Map<String, dynamic> day =
          _merge({}, MealManager.mealStateFields(Meals.dinner, true));
      day = _merge(day, MealManager.mealStateFields(Meals.dinner, false));
      expect(MealReminderService.mealsWithoutReminder(day), isEmpty);
    });

    test('işaret yalnızca fotoğrafı yüklenen öğünü etkiler', () {
      Map<String, dynamic> day = _merge(
        {'meals': {'br': false}},
        MealManager.mealStateFields(Meals.secondmid, true, photoUploaded: true),
      );
      day = _merge(day, MealManager.mealStateFields(Meals.secondmid, false));
      expect(MealReminderService.mealsWithoutReminder(day), {Meals.secondmid});
    });
  });
}
