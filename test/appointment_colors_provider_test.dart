import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/appointment_color_palette.dart';
import 'package:ngy_app/providers/appointment_colors_provider.dart';

void main() {
  tearDown(() => AppointmentColorsRegistry.setOverrides(const {}));

  test('varsayılana döndürülen renk kayıttan da silinir', () async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    final AppointmentColorsProvider provider =
        AppointmentColorsProvider(db: db);

    await provider.saveColors(const {
      AppointmentColorSlot.birthday: 'blue_400',
      AppointmentColorSlot.diger: 'pink_200',
    });
    await provider.saveColors(const {
      AppointmentColorSlot.diger: 'pink_200',
    });

    final Map<String, dynamic> stored =
        (await db.collection('admininput').doc('appointmentColors').get())
            .data()!;
    expect(
        stored[AppointmentColorsProvider.colorsField], {'diger': 'pink_200'});

    AppointmentColorsRegistry.setOverrides(const {});
    final Map<AppointmentColorSlot, String> loaded =
        await AppointmentColorsProvider(db: db).fetchColors();
    expect(loaded, {AppointmentColorSlot.diger: 'pink_200'});
    expect(AppointmentColorsRegistry.colorFor(AppointmentColorSlot.birthday),
        AppointmentColorSlot.birthday.defaultOption.color);
  });

  test('bütün renkler sıfırlanınca kayıtta renk kalmaz', () async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    final AppointmentColorsProvider provider =
        AppointmentColorsProvider(db: db);

    await provider.saveColors(const {
      AppointmentColorSlot.birthday: 'blue_400',
    });
    await provider.saveColors(const {});

    final Map<String, dynamic> stored =
        (await db.collection('admininput').doc('appointmentColors').get())
            .data()!;
    expect(stored[AppointmentColorsProvider.colorsField], isEmpty);
  });
}
