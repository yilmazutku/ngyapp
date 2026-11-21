import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/mock_test_run.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/providers/mock_test_data_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/services/meal_photo_loader.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

class _FakeUserProvider extends UserProvider {
  _FakeUserProvider(this.customers);

  final List<UserModel> customers;

  @override
  Future<List<UserModel>> fetchAllCustomers({bool forceRefresh = false}) =>
      Future<List<UserModel>>.value(customers);
}

class _FakeSubProvider extends SubProvider {
  @override
  Future<Map<String, SubscriptionModel>> fetchSubscriptionsOfUsersByStatus(
    List<String> userIds,
    SubActiveStatus status,
  ) =>
      Future<Map<String, SubscriptionModel>>.value({
        for (final String userId in userIds)
          userId: SubscriptionModel(
            subscriptionId: 'paket-$userId',
            userId: userId,
            packageName: 'Paket',
            startDate: DateTime(2026, 11, 1),
            totalMeetings: 4,
            allowedPostponements: 1,
            totalAmount: 0,
            meetingType: SubsMeetingType.online,
          ),
      });
}

class _FakeMealManager extends MealManager {
  _FakeMealManager(this.mealsByUser);

  final Map<String, List<MealModel>> mealsByUser;

  @override
  Future<Map<String, List<MealModel>>> fetchMealsOfUsersForDate({
    required List<String> userIds,
    required DateTime date,
    void Function(Map<String, List<MealModel>> batchResult)? onBatch,
  }) async {
    onBatch?.call(mealsByUser);
    return mealsByUser;
  }
}

class _FakeMockTestDataProvider extends MockTestDataProvider {
  @override
  Future<List<MockTestRun>> fetchRuns() =>
      Future<List<MockTestRun>>.value(const []);
}

class _FakeChatManager extends ChatManager {
  _FakeChatManager()
      : super(
          db: FakeFirebaseFirestore(),
          auth: _FakeAuth(),
          storage: _FakeStorage(),
        );

  @override
  Future<Map<String, MessageData>> fetchImageMessages(
    String chatId,
    List<String> imageUrls,
  ) =>
      Future<Map<String, MessageData>>.value(const {});
}

class _Screen {
  const _Screen(
    this.name,
    this.platform,
    this.size,
    this.devicePixelRatio,
    this.padding,
  );

  final String name;
  final TargetPlatform platform;
  final Size size;
  final double devicePixelRatio;
  final EdgeInsets padding;
}

const List<_Screen> _screens = [
  _Screen('iPhone (alt home çubuğu)', TargetPlatform.iOS, Size(393, 852), 3,
      EdgeInsets.only(top: 59, bottom: 34)),
  _Screen('iPhone SE (alt boşluk yok)', TargetPlatform.iOS, Size(375, 667), 2,
      EdgeInsets.only(top: 20)),
  _Screen('iPhone yatay (yan çentik)', TargetPlatform.iOS, Size(852, 393), 3,
      EdgeInsets.only(left: 59, right: 59, bottom: 21)),
  _Screen('iPad', TargetPlatform.iOS, Size(1024, 1366), 2,
      EdgeInsets.only(top: 24, bottom: 20)),
  _Screen('Android (hareket çubuğu)', TargetPlatform.android, Size(412, 915),
      2.625, EdgeInsets.only(top: 24, bottom: 24)),
  _Screen('macOS', TargetPlatform.macOS, Size(1280, 800), 2, EdgeInsets.zero),
  _Screen('Windows', TargetPlatform.windows, Size(1280, 800), 1,
      EdgeInsets.zero),
];

const String _photoClientId = 'danisan-foto';
const String _emptyClientId = 'danisan-bos';
const int _photoCount = 12;
const List<Meals> _mealCycle = [
  Meals.br,
  Meals.firstmid,
  Meals.lunch,
  Meals.secondmid,
  Meals.dinner,
  Meals.thirdmid,
];

UserModel _customer(String userId, String name, String surname) => UserModel(
      userId: userId,
      name: name,
      surname: surname,
      email: '$userId@ornek.com',
      password: '',
      role: 'customer',
    );

String _thumbUrl(int index) => 'https://ornek.com/kucuk-$index.png';

List<MealModel> _meals(DateTime day) => [
      for (int i = 0; i < _photoCount; i++)
        MealModel(
          mealId: 'ogun-$i',
          mealType: _mealCycle[i % _mealCycle.length],
          imageUrls: ['https://ornek.com/foto-$i.jpg'],
          thumbUrls: [_thumbUrl(i)],
          timestamp: day.add(Duration(hours: 8, minutes: 20 * i)),
          isChecked: false,
        ),
    ];

Future<Uint8List> _solidPng(Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = color,
  );
  final ui.Image image = await recorder.endRecording().toImage(8, 8);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Rect _thumbRect(Finder scrollbar) {
  final List<Rect> drawn = [];
  expect(
    scrollbar,
    paints
      ..everything((Symbol method, List<dynamic> arguments) {
        if (method == #drawRRect) {
          drawn.add((arguments.first as RRect).outerRect);
        } else if (method == #drawRect) {
          drawn.add(arguments.first as Rect);
        }
        return true;
      }),
  );
  expect(drawn, isNotEmpty);
  return drawn.last;
}

bool _isTestFontOverflow(FlutterErrorDetails details) =>
    details.exception is FlutterError &&
    details.exceptionAsString().contains('A RenderFlex overflowed by');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  for (final _Screen screen in _screens) {
    testWidgets(
        '${screen.name}: şeridin kaydırma çubuğu kartların altında, '
        'şeridin en altında', (tester) async {
      debugDefaultTargetPlatformOverride = screen.platform;
      tester.view.devicePixelRatio = screen.devicePixelRatio;
      tester.view.physicalSize = screen.size * screen.devicePixelRatio;
      final FakeViewPadding padding = FakeViewPadding(
        left: screen.padding.left * screen.devicePixelRatio,
        top: screen.padding.top * screen.devicePixelRatio,
        right: screen.padding.right * screen.devicePixelRatio,
        bottom: screen.padding.bottom * screen.devicePixelRatio,
      );
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      addTearDown(tester.view.reset);
      final FlutterExceptionHandler? reportError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (_isTestFontOverflow(details)) return;
        reportError?.call(details);
      };

      await tester.runAsync(() async {
        for (int i = 0; i < _photoCount; i++) {
          MealPhotoLoader.instance.remember(
            _thumbUrl(i),
            await _solidPng(Colors.primaries[i % Colors.primaries.length]),
          );
        }
      });

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final _FakeChatManager chatManager = _FakeChatManager();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(
              create: (_) => _FakeUserProvider([
                _customer(_photoClientId, 'Buket', 'Tekkeli'),
                _customer(_emptyClientId, 'Aslı', 'Aydaş'),
              ]),
            ),
            ChangeNotifierProvider<SubProvider>(
                create: (_) => _FakeSubProvider()),
            ChangeNotifierProvider<MealManager>(
              create: (_) =>
                  _FakeMealManager({_photoClientId: _meals(today)}),
            ),
            ChangeNotifierProvider<MockTestDataProvider>(
                create: (_) => _FakeMockTestDataProvider()),
            ChangeNotifierProvider<ChatManager>.value(value: chatManager),
          ],
          child: const MaterialApp(
            locale: Locale('tr', 'TR'),
            supportedLocales: [Locale('tr', 'TR')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: AdminMealPhotosPage(),
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(
              const Duration(milliseconds: 20),
            ));
        await tester.pump(const Duration(milliseconds: 100));
      }

      final Finder cards = find.byType(MealImageCard);
      expect(cards, findsWidgets);
      final Finder strip = find
          .ancestor(
            of: cards.first,
            matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
          )
          .first;
      await tester.ensureVisible(strip);
      await tester.pump(const Duration(milliseconds: 300));

      final Rect stripRect = tester.getRect(strip);
      final double cardsBottom = tester
          .widgetList<MealImageCard>(cards)
          .map((card) => tester.getRect(find.byWidget(card)).bottom)
          .reduce(math.max);
      final Rect thumb = _thumbRect(strip).shift(stripRect.topLeft);

      expect(thumb.width, greaterThan(thumb.height),
          reason: 'yatay şeridin çubuğu bulunmalı');
      expect(thumb.top, greaterThanOrEqualTo(cardsBottom),
          reason: 'çubuk kartların (öğün/saat satırının) altında olmalı');
      expect(thumb.bottom, lessThanOrEqualTo(stripRect.bottom + 0.01),
          reason: 'çubuk şeridin içinde kalmalı');
      expect(stripRect.bottom - thumb.bottom, lessThan(8),
          reason: 'çubuk şeridin en altına yakın olmalı');
      expect(thumb.left - stripRect.left, lessThan(8),
          reason: 'çubuk ekranın yan boşluğu kadar içeri itilmemeli');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      FlutterError.onError = reportError;
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
