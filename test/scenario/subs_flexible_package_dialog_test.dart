import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/dialogs/add_sub_dialog.dart';
import 'package:ngy_app/dialogs/edit_sub_dialog.dart';
import 'package:ngy_app/models/filter_params.dart';
import 'package:ngy_app/models/payment_model.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/providers/payment_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:provider/provider.dart';

const String _oneMonth = '1 Aylık (4 görüşme)';
const String _flexible = '1 Aylık (Esnek) (2 görüşme)';
const String _threeMonth = '3 Aylık (12 görüşme)';
const String _sixMonth = '6 Aylık (6 görüşme)';

const String _meetingsLabel = 'Toplam Görüşme Sayısı';
const String _postponementsLabel = 'Toplam İzin Verilen Erteleme Sayısı';
const String _packageNameLabel = 'Paket Adı (otomatik oluşturulur)';

const List<String> _trMonths = <String>[
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _expectedName(String duration, DateTime start) =>
    '${duration}_${start.day}${_trMonths[start.month - 1]}Başlangıç';

class _FakePaymentProvider extends PaymentProvider {
  _FakePaymentProvider() : super(subProvider: SubProvider());

  int fetchCalls = 0;

  @override
  Future<List<PaymentModel>> fetchPayments(
    String? selectedSubscriptionId, {
    required String userId,
    required bool showAllPayments,
    PaymentFilterParams? filterParams,
  }) async {
    fetchCalls++;
    return <PaymentModel>[];
  }
}

const String _realFontFamily = 'Roboto';

File _robotoFile() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  final List<String> candidates = <String>[
    if (root != null)
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/Roboto-Regular.ttf',
  ];
  return candidates.map(File.new).firstWhere(
        (file) => file.existsSync(),
        orElse: () => throw StateError(
            'Roboto-Regular.ttf bulunamadı: ${candidates.join(', ')}'),
      );
}

Future<void> _loadRealFont() async {
  final Uint8List bytes = _robotoFile().readAsBytesSync();
  final FontLoader loader = FontLoader(_realFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Widget _launcher(WidgetBuilder dialogBuilder,
    {Widget Function(Widget)? wrap, bool realFont = false}) {
  final Widget app = MaterialApp(
    theme: ThemeData(
      splashFactory: InkRipple.splashFactory,
      fontFamily: realFont ? _realFontFamily : null,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: dialogBuilder),
            child: const Text('Diyaloğu aç'),
          ),
        ),
      ),
    ),
  );
  return wrap == null ? app : wrap(app);
}

Future<void> _open(WidgetTester tester, WidgetBuilder dialogBuilder,
    {Widget Function(Widget)? wrap, bool realFont = false}) async {
  await tester
      .pumpWidget(_launcher(dialogBuilder, wrap: wrap, realFont: realFont));
  await tester.tap(find.text('Diyaloğu aç'));
  await tester.pumpAndSettle();
}

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<List<String>> _layoutErrorsWhile(Future<void> Function() body) async {
  final List<String> errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final Match? source =
        RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(details.toString());
    errors.add('${details.exceptionAsString().split('\n').first} '
        '(${source?.group(0) ?? 'kaynak bilinmiyor'})');
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

DropdownButton<T> _dropdown<T>(WidgetTester tester) =>
    tester.widget<DropdownButton<T>>(find.byType(DropdownButton<T>));

List<String> _packageOptionTexts(WidgetTester tester) =>
    _dropdown<SubsPackageType>(tester)
        .items!
        .map((item) => (item.child as Text).data!)
        .toList();

String _fieldText(WidgetTester tester, String label) => tester
    .widget<EditableText>(find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(EditableText),
    ))
    .controller
    .text;

Finder _shownPackage(String optionText) => find
    .descendant(
      of: find.byType(DropdownButtonFormField<SubsPackageType>),
      matching: find.text(optionText),
    )
    .hitTestable();

Future<void> _pickPackage(WidgetTester tester, String optionText) async {
  await tester.tap(find.byType(DropdownButtonFormField<SubsPackageType>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionText).last);
  await tester.pumpAndSettle();
}

Future<void> _pickStatus(WidgetTester tester, String statusText) async {
  await tester.tap(find.byType(DropdownButtonFormField<SubActiveStatus>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(statusText).last);
  await tester.pumpAndSettle();
}

Set<String> _visibleFieldLabels(WidgetTester tester) => tester
    .widgetList<InputDecorator>(find.byType(InputDecorator))
    .map((decorator) => decorator.decoration.labelText ?? '')
    .toSet();

WidgetBuilder _addDialog() => (_) => AddSubscriptionDialog(
      userId: 'u1',
      onSubscriptionAdded: () {},
    );

SubscriptionModel _subscription({
  required SubsPackageType packageType,
  required int totalMeetings,
  required int allowedPostponements,
}) =>
    SubscriptionModel(
      subscriptionId: 's1',
      userId: 'u1',
      packageName: SubscriptionModel.buildPackageName(
        packageType: packageType,
        startDate: DateTime(2026, 10, 12),
      ),
      packageType: packageType,
      startDate: DateTime(2026, 10, 12),
      totalMeetings: totalMeetings,
      allowedPostponements: allowedPostponements,
      totalAmount: 5000,
      meetingType: SubsMeetingType.faceToFace,
    );

Widget Function(Widget) _withFakePayments(_FakePaymentProvider provider) =>
    (app) => ChangeNotifierProvider<PaymentProvider>.value(
          value: provider,
          child: app,
        );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await _loadRealFont();
  });

  group('Yeni Paket Ekle: "1 Aylık (Esnek)"', () {
    testWidgets(
        'diyalog ağaçta hiçbir provider yokken açılır (provider yalnızca kaydederken gerekir)',
        (tester) async {
      await _open(tester, _addDialog());
      expect(find.text('Yeni Paket Ekle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'varsayılan Aktif/Haftalık durumunda Paket Süresi seçenekleri sırasıyla 1 Aylık, 1 Aylık (Esnek), 3 Aylık; 6 Aylık yok',
        (tester) async {
      await _open(tester, _addDialog());

      expect(_dropdown<SubActiveStatus>(tester).value,
          SubActiveStatus.activeWeekly);
      expect(find.text('Aktif/Haftalık'), findsWidgets);
      expect(_packageOptionTexts(tester),
          <String>[_oneMonth, _flexible, _threeMonth]);

      await tester.tap(find.byType(DropdownButtonFormField<SubsPackageType>));
      await tester.pumpAndSettle();
      expect(find.text(_oneMonth), findsWidgets);
      expect(find.text(_flexible), findsWidgets);
      expect(find.text(_threeMonth), findsWidgets);
      expect(find.text(_sixMonth), findsNothing);
      expect(
        tester.getTopLeft(find.text(_oneMonth).last).dy,
        lessThan(tester.getTopLeft(find.text(_flexible).last).dy),
      );
      expect(
        tester.getTopLeft(find.text(_flexible).last).dy,
        lessThan(tester.getTopLeft(find.text(_threeMonth).last).dy),
      );
    });

    testWidgets(
        '"1 Aylık (Esnek)" seçilince görüşme 2, erteleme 1 ve paket adı 1Aylık(Esnek)_<gün><Ay>Başlangıç olur',
        (tester) async {
      final DateTime today = DateTime.now();
      await _open(tester, _addDialog());

      await _pickPackage(tester, _flexible);

      expect(_dropdown<SubsPackageType>(tester).value,
          SubsPackageType.oneMonthFlexible);
      expect(_shownPackage(_flexible), findsOneWidget);
      expect(_shownPackage(_oneMonth), findsNothing);
      expect(_fieldText(tester, _meetingsLabel), '2');
      expect(_fieldText(tester, _postponementsLabel), '1');
      expect(_fieldText(tester, _packageNameLabel),
          _expectedName('1Aylık(Esnek)', today));
      expect(tester.takeException(), isNull);
    });

    testWidgets('"1 Aylık (Esnek)" formu "1 Aylık" ile aynı alanları gösterir',
        (tester) async {
      await _open(tester, _addDialog());

      await _pickPackage(tester, _oneMonth);
      final Set<String> oneMonthLabels = _visibleFieldLabels(tester);
      expect(_fieldText(tester, _meetingsLabel), '4');
      expect(_fieldText(tester, _postponementsLabel), '1');

      await _pickPackage(tester, _flexible);
      final Set<String> flexibleLabels = _visibleFieldLabels(tester);

      expect(flexibleLabels, oneMonthLabels);
      expect(flexibleLabels, contains('Toplam Ücret (TL)'));
      expect(find.text('Ödeme Alındı mı?'), findsOneWidget);
      expect(find.text('Ödeme Alınacak mı?'), findsOneWidget);
    });

    testWidgets(
        'durum Aktif/Kilo Takip yapılınca seçenek yalnızca "6 Aylık", otomatik seçili ve görüşme 6',
        (tester) async {
      final DateTime today = DateTime.now();
      await _open(tester, _addDialog());
      await _pickPackage(tester, _flexible);

      await _pickStatus(tester, 'Aktif/Kilo Takip');

      expect(_packageOptionTexts(tester), <String>[_sixMonth]);
      expect(_dropdown<SubsPackageType>(tester).value,
          SubsPackageType.sixMonth);
      expect(_shownPackage(_sixMonth), findsOneWidget);
      expect(_fieldText(tester, _meetingsLabel), '6');
      expect(_fieldText(tester, _packageNameLabel),
          _expectedName('6Aylık', today));
      expect(tester.takeException(), isNull);
    });

    for (final bool realFont in <bool>[false, true]) {
      testWidgets(
          'telefon genişliğinde (360x740, ${realFont ? 'Roboto' : 'tema yazı tipi verilmeden'}) açılıp Esnek ve Kilo Takip seçilince taşma hatası yok',
          (tester) async {
        _usePhoneScreen(tester);
        final List<String> errors = await _layoutErrorsWhile(() async {
          await _open(tester, _addDialog(), realFont: realFont);
          await _pickPackage(tester, _flexible);
          await tester.dragUntilVisible(
            find.text('Ödeme Alınacak mı?'),
            find.byType(SingleChildScrollView).first,
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          await tester.dragUntilVisible(
            find.byType(DropdownButtonFormField<SubActiveStatus>),
            find.byType(SingleChildScrollView).first,
            const Offset(0, 200),
          );
          await tester.pumpAndSettle();
          await _pickStatus(tester, 'Aktif/Kilo Takip');
        });
        expect(errors, isEmpty);
      }, variant: TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
      }));
    }
  });

  group('Paket Düzenle: "1 Aylık (Esnek)"', () {
    testWidgets(
        'packageType = oneMonthFlexible olan paket açılınca Paket Süresi\'nde "1 Aylık (Esnek) (2 görüşme)" seçili görünür',
        (tester) async {
      final _FakePaymentProvider payments = _FakePaymentProvider();
      await _open(
        tester,
        (_) => EditSubscriptionDialog(
          subscription: _subscription(
            packageType: SubsPackageType.oneMonthFlexible,
            totalMeetings: 2,
            allowedPostponements: 1,
          ),
          onSubscriptionUpdated: () {},
        ),
        wrap: _withFakePayments(payments),
      );

      expect(payments.fetchCalls, 1);
      expect(_dropdown<SubsPackageType>(tester).value,
          SubsPackageType.oneMonthFlexible);
      expect(_shownPackage(_flexible), findsOneWidget);
      expect(_shownPackage(_oneMonth), findsNothing);
      expect(_shownPackage(_threeMonth), findsNothing);
      expect(_packageOptionTexts(tester),
          <String>[_oneMonth, _flexible, _threeMonth]);
      expect(_fieldText(tester, _meetingsLabel), '2');
      expect(_fieldText(tester, _postponementsLabel), '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '"1 Aylık" paket "1 Aylık (Esnek)"e çevrilince görüşme 2, erteleme 1 ve paket adı 1Aylık(Esnek)_12EkimBaşlangıç olur',
        (tester) async {
      await _open(
        tester,
        (_) => EditSubscriptionDialog(
          subscription: _subscription(
            packageType: SubsPackageType.oneMonth,
            totalMeetings: 4,
            allowedPostponements: 1,
          ),
          onSubscriptionUpdated: () {},
        ),
        wrap: _withFakePayments(_FakePaymentProvider()),
      );

      await _pickPackage(tester, _flexible);

      expect(_dropdown<SubsPackageType>(tester).value,
          SubsPackageType.oneMonthFlexible);
      expect(_fieldText(tester, _meetingsLabel), '2');
      expect(_fieldText(tester, _postponementsLabel), '1');
      expect(_fieldText(tester, 'Paket İsmi'), '1Aylık(Esnek)_12EkimBaşlangıç');
    });

    for (final bool realFont in <bool>[false, true]) {
      testWidgets(
          'telefon genişliğinde (360x740, ${realFont ? 'Roboto' : 'tema yazı tipi verilmeden'}) Esnek paket düzenlenirken taşma hatası yok',
          (tester) async {
        _usePhoneScreen(tester);
        final List<String> errors = await _layoutErrorsWhile(() async {
          await _open(
            tester,
            (_) => EditSubscriptionDialog(
              subscription: _subscription(
                packageType: SubsPackageType.oneMonthFlexible,
                totalMeetings: 2,
                allowedPostponements: 1,
              ),
              onSubscriptionUpdated: () {},
            ),
            wrap: _withFakePayments(_FakePaymentProvider()),
            realFont: realFont,
          );
        });
        expect(find.text('Paket Düzenle'), findsOneWidget);
        expect(errors, isEmpty);
      }, variant: TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
      }));
    }
  });
}
