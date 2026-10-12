import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ngy_app/models/subs_model.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const SubsPackageType flexible = SubsPackageType.oneMonthFlexible;

  test('"1 Aylık (Esnek)" 1 Aylık ile aynı görüşme ve erteleme hakkını verir', () {
    expect(flexible.label, '1 Aylık (Esnek)');
    expect(flexible.defaultMeetings, 4);
    expect(flexible.defaultMeetings, SubsPackageType.oneMonth.defaultMeetings);
    expect(
      SubscriptionModel.calculateAllowedPostponements(flexible.defaultMeetings),
      1,
    );
  });

  test('Firestore\'daki etiketten geri okunur, 1 Aylık ile karışmaz', () {
    expect(SubsPackageType.fromLabel('1 Aylık (Esnek)'), flexible);
    expect(SubsPackageType.fromLabel('1 Aylık'), SubsPackageType.oneMonth);
  });

  test('Kilo Takip dışındaki durumlarda seçilebilir, 1 Aylık\'ın hemen ardından gelir', () {
    for (final SubActiveStatus status in SubActiveStatus.values) {
      final List<SubsPackageType> options =
          SubsPackageType.availableFor(status);
      if (status == SubActiveStatus.activeWeightTracking) {
        expect(options, [SubsPackageType.sixMonth], reason: status.label);
      } else {
        expect(
          options,
          [
            SubsPackageType.oneMonth,
            SubsPackageType.oneMonthFlexible,
            SubsPackageType.threeMonth,
          ],
          reason: status.label,
        );
      }
    }
  });

  test('paket adı paket süresinden üretilir', () {
    expect(
      SubscriptionModel.buildPackageName(
        packageType: flexible,
        startDate: DateTime(2026, 10, 12),
      ),
      '1Aylık(Esnek)_12EkimBaşlangıç',
    );
  });
}
