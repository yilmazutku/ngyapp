import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/constants/app_constants.dart';
import 'package:ngy_app/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo.compareVersions', () {
    test('sürümler metin gibi değil sayı sayı karşılaştırılır', () {
      expect(AppUpdateInfo.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(AppUpdateInfo.compareVersions('1.0.9', '1.0.10'), lessThan(0));
      expect(AppUpdateInfo.compareVersions('1.1', '1.0.9'), greaterThan(0));
      expect(AppUpdateInfo.compareVersions('1.0', '1.0.0'), 0);
    });

    test('build numarası ve ek yok sayılır', () {
      expect(AppUpdateInfo.compareVersions('1.0.5+15', '1.0.5'), 0);
      expect(AppUpdateInfo.compareVersions('1.0.5-beta', '1.0.5'), 0);
    });

    test('sayı olmayan sürüm karşılaştırılmaz', () {
      expect(AppUpdateInfo.compareVersions('1.0.x', '1.0.5'), isNull);
      expect(AppUpdateInfo.compareVersions('v1.0.5', '1.0.5'), isNull);
      expect(AppUpdateInfo.compareVersions('', '1.0.5'), isNull);
    });
  });

  for (final bool isIos in <bool>[true, false]) {
    group(isIos ? 'iOS' : 'Android', () {
      AppUpdateInfo? resolve(Map<String, dynamic>? data, String installed) =>
          AppUpdateInfo.resolve(
            data: data,
            currentVersion: installed,
            isIos: isIos,
          );

      test('döküman yoksa ya da isCheckVersion false ise hiçbir şey '
          'gösterilmez', () {
        expect(resolve(null, '1.0.0'), isNull);
        expect(
          resolve({
            'isCheckVersion': false,
            'minSupportedVersion': '9.0.0',
            'latestVersion': '9.0.0',
          }, '1.0.0'),
          isNull,
        );
      });

      test('isCheckVersion alanı yoksa denetim açık sayılır', () {
        expect(resolve({'minSupportedVersion': '1.0.5'}, '1.0.3')?.isForced,
            isTrue);
      });

      test('en düşük sürümün altı zorunlu güncellemeye düşer ve varsa en yeni '
          'sürüme yönlendirilir', () {
        final AppUpdateInfo? info = resolve(
          {'minSupportedVersion': '1.0.5', 'latestVersion': '1.0.6'},
          '1.0.4',
        );
        expect(info?.action, AppUpdateAction.forced);
        expect(info?.targetVersion, '1.0.6');
        expect(
          resolve({'minSupportedVersion': '1.0.5'}, '1.0.4')?.targetVersion,
          '1.0.5',
        );
      });

      test('en düşük sürüm ve üstü, en yeni sürümün altındaysa kapatılabilir '
          'uyarı alır', () {
        final AppUpdateInfo? info = resolve(
          {'minSupportedVersion': '1.0.5', 'latestVersion': '1.0.6'},
          '1.0.5',
        );
        expect(info?.action, AppUpdateAction.optional);
        expect(info?.targetVersion, '1.0.6');
      });

      test('güncel ya da daha yeni sürümde hiçbir şey gösterilmez', () {
        final Map<String, dynamic> document = {
          'minSupportedVersion': '1.0.5',
          'latestVersion': '1.0.5',
        };
        expect(resolve(document, '1.0.5'), isNull);
        expect(resolve(document, '1.0.5+15'), isNull);
        expect(resolve(document, '1.0.10'), isNull);
      });

      test('boş, sayı tipinde ya da bozuk sürüm alanı kimseyi engellemez', () {
        expect(
          resolve({'minSupportedVersion': '', 'latestVersion': ''}, '1.0.3'),
          isNull,
        );
        expect(resolve({'minSupportedVersion': 1.1}, '1.0.3'), isNull);
        expect(resolve({'minSupportedVersion': '1.0.x'}, '1.0.3'), isNull);
      });

      test("1.0.5 öncesi build'ler kendini 1.0.2 bildirir: en düşük sürüm "
          '1.0.5 olunca engellenir, 1.0.5 kurulunca engel kalkar', () {
        final Map<String, dynamic> document = {
          'minSupportedVersion': '1.0.5',
          'iosAppId': AppUpdateConstants.iosAppId,
        };
        expect(resolve(document, '1.0.2')?.isForced, isTrue);
        expect(resolve(document, '1.0.5'), isNull);
      });

      test('yöneticinin yazdığı metin varsayılan metnin yerine geçer', () {
        expect(
          resolve(
            {'minSupportedVersion': '1.0.5', 'message': 'Lütfen güncelleyin.'},
            '1.0.3',
          )?.userMessage,
          'Lütfen güncelleyin.',
        );
      });
    });
  }

  group('mağazaya özel alanlar', () {
    test('yalnızca iOS alanları yazılırsa Android etkilenmez', () {
      final Map<String, dynamic> document = {
        'iosMinSupportedVersion': '1.0.5',
        'iosLatestVersion': '1.0.5',
      };
      expect(
        AppUpdateInfo.resolve(
                data: document, currentVersion: '1.0.2', isIos: true)
            ?.isForced,
        isTrue,
      );
      expect(
        AppUpdateInfo.resolve(
            data: document, currentVersion: '1.0.2', isIos: false),
        isNull,
      );
    });

    test('mağazaya özel alan ortak alanı ezer', () {
      final Map<String, dynamic> document = {
        'minSupportedVersion': '1.0.5',
        'androidMinSupportedVersion': '1.0.0',
      };
      expect(
        AppUpdateInfo.resolve(
            data: document, currentVersion: '1.0.2', isIos: false),
        isNull,
      );
      expect(
        AppUpdateInfo.resolve(
                data: document, currentVersion: '1.0.2', isIos: true)
            ?.isForced,
        isTrue,
      );
    });
  });

  group('mağaza adresi', () {
    test('iOS: App Store numarası dökümanda yoksa ya da boşsa uygulamadaki '
        'numara kullanılır', () {
      for (final Map<String, dynamic> document in <Map<String, dynamic>>[
        {'minSupportedVersion': '1.0.5'},
        {'minSupportedVersion': '1.0.5', 'iosAppId': ''},
      ]) {
        final AppUpdateInfo? info = AppUpdateInfo.resolve(
            data: document, currentVersion: '1.0.3', isIos: true);
        expect(info?.storeName, AppUpdateConstants.iosStoreName);
        expect(info?.storeUri.toString(),
            'itms-apps://itunes.apple.com/app/id6756973059');
        expect(info?.webStoreUri.toString(),
            'https://apps.apple.com/app/id6756973059');
      }
    });

    test('iOS: dökümandaki App Store numarası uygulamadakinin yerine geçer',
        () {
      final AppUpdateInfo? info = AppUpdateInfo.resolve(
        data: {'minSupportedVersion': '1.0.5', 'iosAppId': '123'},
        currentVersion: '1.0.3',
        isIos: true,
      );
      expect(info?.storeUri.toString(), 'itms-apps://itunes.apple.com/app/id123');
    });

    test('Android: Play adresi paket adından kurulur', () {
      final AppUpdateInfo? info = AppUpdateInfo.resolve(
        data: {'minSupportedVersion': '1.0.5'},
        currentVersion: '1.0.3',
        isIos: false,
      );
      expect(info?.storeName, AppUpdateConstants.androidStoreName);
      expect(info?.storeUri.toString(),
          'market://details?id=com.utkuyilmaz.ngy_app');
      expect(info?.webStoreUri.toString(),
          'https://play.google.com/store/apps/details?id=com.utkuyilmaz.ngy_app');
    });
  });
}
