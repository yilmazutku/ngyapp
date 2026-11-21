import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/pages/chat_page_new.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/services/ios_app_on_mac.dart';
import 'package:ngy_app/services/meal_photo_loader.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';
import 'package:ngy_app/widgets/meal_thumbnail_image.dart';
import 'package:ngy_app/widgets/reaction_badge.dart';
import 'package:provider/provider.dart';

import 'paged_chat_fake.dart';

const String _clientUid = 'danisan-1';
const String _officeText = 'Bugün iki litre su içmeyi unutmayın';
const String _clientText = 'Tamamdır, öğlen fotoğraf atarım';
const List<String> _albumIds = <String>['p0', 'p1', 'p2', 'p3'];
const String _singlePhotoId = 'p9';

final String _officeUid = ChatManager.chatOfficeIds.first;
final DateTime _start = DateTime.now().subtract(const Duration(hours: 2));

Future<void> _seed(FakeFirebaseFirestore db) async {
  final CollectionReference<Map<String, dynamic>> messages =
      db.collection('chats').doc(_clientUid).collection('messages');

  Future<void> add(
    String id,
    int minute, {
    required String senderId,
    required String text,
    bool photo = false,
  }) {
    final Timestamp at =
        Timestamp.fromDate(_start.add(Duration(minutes: minute)));
    return messages.doc(id).set({
      'chatId': _clientUid,
      'senderId': senderId,
      'text': text,
      if (photo) 'imageUrl': 'https://x/$id.jpg',
      if (photo) 'thumbUrl': 'https://x/${id}_thumb.jpg',
      'createdAt': at,
      'clientCreatedAt': at,
    });
  }

  await add('o1', 0, senderId: _officeUid, text: _officeText);
  await add('c1', 1, senderId: _clientUid, text: _clientText);
  for (int i = 0; i < _albumIds.length; i++) {
    await add(_albumIds[i], 10 + i,
        senderId: _clientUid, text: 'Öğün: Öğle', photo: true);
  }
  await add(_singlePhotoId, 30,
      senderId: _clientUid, text: 'Öğün: Akşam', photo: true);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const MethodChannel platformInfo = MethodChannel('ngy_app/platform_info');

  Future<void> setIosAppOnMac(bool value) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        platformInfo, (MethodCall call) async => value);
    await loadIosAppOnMac();
    messenger.setMockMethodCallHandler(platformInfo, null);
  }

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<FakeFirebaseFirestore> pumpChat(
    WidgetTester tester, {
    required String viewerUid,
    bool onMac = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await setIosAppOnMac(onMac);
    addTearDown(() => setIosAppOnMac(false));

    MealPhotoLoader.instance
      ..client = MockClient((request) async => http.Response('', 404))
      ..cacheDirectory = null;

    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    await tester.runAsync(() => _seed(db));
    final PagedFakeChat chat = PagedFakeChat(db, currentUid: viewerUid);
    addTearDown(chat.dispose);

    final bool office = viewerUid != _clientUid;
    await tester.pumpWidget(ChangeNotifierProvider<ChatManager>.value(
      value: chat,
      child: MaterialApp(
        home: ChatPage(
          overrideChatId: office ? _clientUid : null,
          userDisplayName: office ? 'Ayşe Yılmaz' : null,
        ),
      ),
    ));
    await settle(tester);
    return db;
  }

  Future<Map<String, String>> reactionsOf(
    WidgetTester tester,
    FakeFirebaseFirestore db,
    String messageId,
  ) async {
    final DocumentSnapshot<Map<String, dynamic>>? doc = await tester.runAsync(
      () => db
          .collection('chats')
          .doc(_clientUid)
          .collection('messages')
          .doc(messageId)
          .get(),
    );
    final Object? reactions = doc?.data()?['reactions'];
    if (reactions is! Map) return <String, String>{};
    return reactions
        .map((key, value) => MapEntry(key as String, value as String));
  }

  Finder thumbnailOf(String messageId) => find.byWidgetPredicate((widget) =>
      widget is MealThumbnailImage &&
      widget.url == 'https://x/${messageId}_thumb.jpg');

  Finder popupItem(String label) =>
      find.widgetWithText(PopupMenuItem<Object>, label);

  final Finder anyPopupItem =
      find.byWidgetPredicate((widget) => widget is PopupMenuItem);

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    await tester.tapAt(
      tester.getCenter(target),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
  }

  Future<void> holdMouse(WidgetTester tester, Finder target) async {
    final TestGesture press = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await press.up();
    await settle(tester);
  }

  Future<void> pickEmoji(WidgetTester tester, String emoji) async {
    await tester.tap(find.text(emoji).last);
    await settle(tester);
  }

  List<String> popupLabels(WidgetTester tester) {
    final List<PopupMenuItem<Object>> items = tester
        .widgetList<PopupMenuItem<Object>>(
            find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object>))
        .toList();
    return <String>[
      for (final PopupMenuItem<Object> item in items)
        ((item.child as Text?)?.data) ?? '',
    ];
  }

  group('Mac\'teki iPad uygulaması', () {
    final TargetPlatformVariant ios =
        TargetPlatformVariant.only(TargetPlatform.iOS);

    testWidgets('danışan ofisin yazısına sağ tıklayıp ifade bırakır',
        (tester) async {
      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _clientUid, onMac: true);

      await rightClick(tester, find.text(_officeText));
      expect(popupLabels(tester),
          <String>['Yanıtla', kMessageReactLabel, 'Mesajı Kopyala']);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(popupItem(kMessageReactLabel));
      await settle(tester);
      expect(anyPopupItem, findsNothing);

      await pickEmoji(tester, '❤️');
      expect(await reactionsOf(tester, db, 'o1'),
          <String, String>{_clientUid: '❤️'});
      expect(find.byType(ReactionBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: ios);

    testWidgets('kendi yazısında "İfade Bırak" yok; "Mesajı Kopyala" panoya '
        'yazar', (tester) async {
      final List<String?> clipboard = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _clientUid, onMac: true);

      await rightClick(tester, find.text(_clientText));
      expect(popupLabels(tester), <String>['Yanıtla', 'Mesajı Kopyala']);

      await tester.tap(popupItem('Mesajı Kopyala'));
      await settle(tester);
      expect(clipboard, <String?>[_clientText]);
      expect(await reactionsOf(tester, db, 'c1'), isEmpty);
    }, variant: ios);

    testWidgets('"Yanıtla" mesajı yanıt şeridine alır', (tester) async {
      await pumpChat(tester, viewerUid: _clientUid, onMac: true);
      expect(find.text(_officeText), findsOneWidget);

      await rightClick(tester, find.text(_officeText));
      await tester.tap(popupItem('Yanıtla'));
      await settle(tester);

      expect(find.text(_officeText), findsNWidgets(2));
    }, variant: ios);

    testWidgets('ofis albümdeki tek bir fotoğrafa sağ tıklayıp ifade bırakır',
        (tester) async {
      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _officeUid, onMac: true);
      expect(thumbnailOf('p1'), findsOneWidget);

      await rightClick(tester, thumbnailOf('p1'));
      expect(popupLabels(tester), <String>[
        'Yanıtla',
        kMessageReactLabel,
        "Öğün Fotoğrafları'nda göster",
      ]);

      await tester.tap(popupItem(kMessageReactLabel));
      await settle(tester);
      await pickEmoji(tester, '👍');

      expect(await reactionsOf(tester, db, 'p1'),
          <String, String>{_officeUid: '👍'});
      for (final String id in _albumIds.where((id) => id != 'p1')) {
        expect(await reactionsOf(tester, db, id), isEmpty, reason: id);
      }
      expect(find.byType(ReactionBadge), findsOneWidget);
    }, variant: ios);

    testWidgets('tek fotoğrafa bırakılan ifade aynı ifade seçilince kalkar',
        (tester) async {
      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _officeUid, onMac: true);

      await rightClick(tester, thumbnailOf(_singlePhotoId));
      await tester.tap(popupItem(kMessageReactLabel));
      await settle(tester);
      await pickEmoji(tester, '😂');
      expect(await reactionsOf(tester, db, _singlePhotoId),
          <String, String>{_officeUid: '😂'});

      await rightClick(tester, thumbnailOf(_singlePhotoId));
      await tester.tap(popupItem(kMessageReactLabel));
      await settle(tester);
      await pickEmoji(tester, '😂');
      expect(await reactionsOf(tester, db, _singlePhotoId), isEmpty);
    }, variant: ios);

    testWidgets('"…" ile bütün ifadeler açılır, listeden seçilen kaydedilir',
        (tester) async {
      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _clientUid, onMac: true);

      await rightClick(tester, find.text(_officeText));
      await tester.tap(popupItem(kMessageReactLabel));
      await settle(tester);
      expect(find.text('🥗'), findsNothing);

      await tester.tap(find.byTooltip('Tüm ifadeler'));
      await settle(tester);
      await pickEmoji(tester, '🥗');
      expect(await reactionsOf(tester, db, 'o1'),
          <String, String>{_clientUid: '🥗'});
    }, variant: ios);

    testWidgets('fareyle basılı tutmak da menüyü açar', (tester) async {
      final FakeFirebaseFirestore db =
          await pumpChat(tester, viewerUid: _clientUid, onMac: true);

      await holdMouse(tester, find.text(_officeText));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(anyPopupItem, findsNothing);

      await pickEmoji(tester, '🙏');
      expect(await reactionsOf(tester, db, 'o1'),
          <String, String>{_clientUid: '🙏'});
    }, variant: ios);
  });

  testWidgets('iPhone, iPad ve Android\'de sağ tık menü açmaz; uzun basınca '
      'açılan menüden ifade bırakılır', (tester) async {
    final FakeFirebaseFirestore db =
        await pumpChat(tester, viewerUid: _clientUid);

    await rightClick(tester, find.text(_officeText));
    expect(anyPopupItem, findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await rightClick(tester, thumbnailOf(_singlePhotoId));
    expect(anyPopupItem, findsNothing);

    await tester.longPress(find.text(_officeText));
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await pickEmoji(tester, '😮');
    expect(await reactionsOf(tester, db, 'o1'),
        <String, String>{_clientUid: '😮'});
  }, variant: const TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.iOS,
    TargetPlatform.android,
  }));

  testWidgets('masaüstünde yazıya ve albüm fotoğrafına sağ tıklayıp ifade '
      'bırakılır', (tester) async {
    final FakeFirebaseFirestore db =
        await pumpChat(tester, viewerUid: _officeUid);

    await rightClick(tester, find.text(_clientText));
    expect(find.text(kMessageReactLabel), findsOneWidget);
    await tester.tap(find.text(kMessageReactLabel));
    await settle(tester);
    await pickEmoji(tester, '😢');
    expect(await reactionsOf(tester, db, 'c1'),
        <String, String>{_officeUid: '😢'});

    await rightClick(tester, thumbnailOf('p2'));
    expect(popupLabels(tester), contains(kMessageReactLabel));
    await tester.tap(popupItem(kMessageReactLabel));
    await settle(tester);
    await pickEmoji(tester, '🙏');
    expect(await reactionsOf(tester, db, 'p2'),
        <String, String>{_officeUid: '🙏'});
  }, variant: TargetPlatformVariant.desktop());
}
