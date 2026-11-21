import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/mock_test_run.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/providers/mock_test_data_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/services/meal_photo_loader.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

class FakeUserProvider extends UserProvider {
  FakeUserProvider(this.customers);

  final List<UserModel> customers;

  @override
  Future<List<UserModel>> fetchAllCustomers({bool forceRefresh = false}) =>
      Future<List<UserModel>>.value(customers);
}

class FakeSubProvider extends SubProvider {
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

class FakeMealManager extends MealManager {
  FakeMealManager(this.mealsByUser);

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

class FakeMockTestDataProvider extends MockTestDataProvider {
  @override
  Future<List<MockTestRun>> fetchRuns() =>
      Future<List<MockTestRun>>.value(const []);
}

class FakeReaction {
  const FakeReaction(this.chatId, this.messageId, this.emoji);

  final String chatId;
  final String messageId;
  final String emoji;
}

class FakeChatManager extends ChatManager {
  FakeChatManager({this.messagesByImageUrl = const {}})
      : super(
          db: FakeFirebaseFirestore(),
          auth: _FakeAuth(),
          storage: _FakeStorage(),
        );

  static const String adminUid = 'admin';

  final Map<String, MessageData> messagesByImageUrl;
  final List<FakeReaction> reactions = [];

  @override
  String get userId => adminUid;

  MessageData? _messageOf(String chatId, String imageUrl) {
    final MessageData? message = messagesByImageUrl[imageUrl];
    return message != null && message.chatId == chatId ? message : null;
  }

  @override
  Future<Map<String, MessageData>> fetchImageMessages(
    String chatId,
    List<String> imageUrls,
  ) =>
      Future<Map<String, MessageData>>.value({
        for (final String url in imageUrls)
          if (_messageOf(chatId, url) != null) url: _messageOf(chatId, url)!,
      });

  @override
  Future<MessageData?> findImageMessage(String chatId, String imageUrl) =>
      Future<MessageData?>.value(_messageOf(chatId, imageUrl));

  @override
  Future<void> toggleReaction(
    String chatId,
    String messageId,
    String emoji, {
    String? currentEmoji,
  }) async {
    reactions.add(FakeReaction(chatId, messageId, emoji));
  }
}

class TestScreen {
  const TestScreen(
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

const List<TestScreen> kTestScreens = [
  TestScreen('iPhone (alt home çubuğu)', TargetPlatform.iOS, Size(393, 852), 3,
      EdgeInsets.only(top: 59, bottom: 34)),
  TestScreen('iPhone SE (alt boşluk yok)', TargetPlatform.iOS, Size(375, 667),
      2, EdgeInsets.only(top: 20)),
  TestScreen('iPhone yatay (yan çentik)', TargetPlatform.iOS, Size(852, 393), 3,
      EdgeInsets.only(left: 59, right: 59, bottom: 21)),
  TestScreen('iPad', TargetPlatform.iOS, Size(1024, 1366), 2,
      EdgeInsets.only(top: 24, bottom: 20)),
  TestScreen('Android (hareket çubuğu)', TargetPlatform.android, Size(412, 915),
      2.625, EdgeInsets.only(top: 24, bottom: 24)),
  TestScreen(
      'macOS', TargetPlatform.macOS, Size(1280, 800), 2, EdgeInsets.zero),
  TestScreen(
      'Windows', TargetPlatform.windows, Size(1280, 800), 1, EdgeInsets.zero),
];

bool isTestFontOverflow(FlutterErrorDetails details) =>
    details.exception is FlutterError &&
    details.exceptionAsString().contains('A RenderFlex overflowed by');

void applyTestScreen(TestFlutterView view, TestScreen screen) {
  view.devicePixelRatio = screen.devicePixelRatio;
  view.physicalSize = screen.size * screen.devicePixelRatio;
  final FakeViewPadding padding = FakeViewPadding(
    left: screen.padding.left * screen.devicePixelRatio,
    top: screen.padding.top * screen.devicePixelRatio,
    right: screen.padding.right * screen.devicePixelRatio,
    bottom: screen.padding.bottom * screen.devicePixelRatio,
  );
  view.padding = padding;
  view.viewPadding = padding;
}

class ScreenVariant extends TestVariant<TestScreen> {
  ScreenVariant({
    this.screens = kTestScreens,
    this.ignoreTestFontOverflow = false,
  });

  final List<TestScreen> screens;
  final bool ignoreTestFontOverflow;

  TestScreen? _current;
  FlutterExceptionHandler? _reportError;

  TestScreen get current => _current!;

  TestFlutterView get _view =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;

  @override
  Iterable<TestScreen> get values => screens;

  @override
  String describeValue(TestScreen value) => value.name;

  @override
  Future<Object?> setUp(TestScreen value) async {
    _current = value;
    debugDefaultTargetPlatformOverride = value.platform;
    applyTestScreen(_view, value);
    if (ignoreTestFontOverflow) {
      final FlutterExceptionHandler? reportError = FlutterError.onError;
      _reportError = reportError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (isTestFontOverflow(details)) return;
        reportError?.call(details);
      };
    }
    return null;
  }

  @override
  Future<void> tearDown(TestScreen value, Object? memento) async {
    if (ignoreTestFontOverflow) FlutterError.onError = _reportError;
    _view.reset();
    debugDefaultTargetPlatformOverride = null;
    _current = null;
  }
}

UserModel testCustomer(String userId, String name, String surname) => UserModel(
      userId: userId,
      name: name,
      surname: surname,
      email: '$userId@ornek.com',
      password: '',
      role: 'customer',
    );

DateTime testToday() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

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

Future<void> rememberSolidImages(
  WidgetTester tester,
  List<String> urls,
) async {
  await tester.runAsync(() async {
    for (int i = 0; i < urls.length; i++) {
      MealPhotoLoader.instance.remember(
        urls[i],
        await _solidPng(Colors.primaries[i % Colors.primaries.length]),
      );
    }
  });
}

Widget adminMealPhotosApp({
  required List<UserModel> customers,
  required Map<String, List<MealModel>> mealsByUser,
  required ChatManager chatManager,
  required Widget home,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(
        create: (_) => FakeUserProvider(customers),
      ),
      ChangeNotifierProvider<SubProvider>(create: (_) => FakeSubProvider()),
      ChangeNotifierProvider<MealManager>(
        create: (_) => FakeMealManager(mealsByUser),
      ),
      ChangeNotifierProvider<MockTestDataProvider>(
          create: (_) => FakeMockTestDataProvider()),
      ChangeNotifierProvider<ChatManager>.value(value: chatManager),
    ],
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<void> settleAdminMealPhotos(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 20),
        ));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> disposeAdminMealPhotos(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
