import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/pages/user_media_gallery_page.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/services/meal_photo_loader.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:provider/provider.dart';

import 'paged_chat_fake.dart';

const String _uid = 'danisan-1';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  UserMediaGalleryGrid gridOf(WidgetTester tester) =>
      tester.widget<UserMediaGalleryGrid>(find.byType(UserMediaGalleryGrid));

  Future<FakeFirebaseFirestore> seeded(
    WidgetTester tester,
    int count, {
    ChatSeedKind Function(int index) kindOf = alternatingChatKind,
  }) async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    await tester.runAsync(() => seedChatMessages(db, _uid, count, kindOf));
    return db;
  }

  Future<PagedFakeChat> pumpGallery(
    WidgetTester tester,
    FakeFirebaseFirestore db, {
    Future<void> Function(MessageData message)? onDeletePhoto,
  }) async {
    MealPhotoLoader.instance
      ..client = MockClient((request) async => http.Response('', 404))
      ..cacheDirectory = null;
    final PagedFakeChat chat = PagedFakeChat(db, currentUid: _uid);
    addTearDown(chat.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<ChatManager>.value(
      value: chat,
      child: MaterialApp(
        home: UserMediaGalleryPage(userId: _uid, onDeletePhoto: onDeletePhoto),
      ),
    ));
    await settle(tester);
    return chat;
  }

  testWidgets('kısa sohbette bütün fotoğraflar ve toplam sayı görünür',
      (tester) async {
    final PagedFakeChat chat = await pumpGallery(tester, await seeded(tester, 12));

    expect(tester.takeException(), isNull);
    expect(find.text('Fotoğraflarım'), findsOneWidget);
    expect(find.text('6 fotoğraf'), findsOneWidget);
    expect(find.byType(MealImageCard), findsNWidgets(6));
    expect(chat.olderPageCalls, 0);
    expect(gridOf(tester).complete, isTrue);
  });

  testWidgets('ekrana sığan galeri, eski sayfalar okunduktan sonra da sol '
      'üstten başlar', (tester) async {
    final PagedFakeChat chat = await pumpGallery(
      tester,
      await seeded(
        tester,
        45,
        kindOf: (index) =>
            index % 7 == 0 ? ChatSeedKind.photo : ChatSeedKind.officeText,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('7 fotoğraf'), findsOneWidget);
    expect(find.byType(MealImageCard), findsNWidgets(7));
    expect(chat.olderPageCalls, 1);
    expect(gridOf(tester).complete, isTrue);
  });

  testWidgets('uzun sohbette toplam sayı görünür; yalnızca ekranı dolduracak '
      'kadar eski sayfa okunur', (tester) async {
    final PagedFakeChat chat =
        await pumpGallery(tester, await seeded(tester, 400));

    expect(tester.takeException(), isNull);
    expect(find.text('200 fotoğraf'), findsOneWidget);
    expect(chat.olderPageCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(gridOf(tester).complete, isFalse);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await settle(tester);

    expect(chat.olderPageCalls, greaterThan(1));
    expect(find.text('200 fotoğraf'), findsOneWidget);
  });

  testWidgets('fotoğraf yoksa boş olduğu söylenir', (tester) async {
    await pumpGallery(
      tester,
      await seeded(tester, 8, kindOf: (index) => ChatSeedKind.text),
    );

    expect(find.text('Sohbette henüz fotoğraf yüklemediniz.'), findsOneWidget);
    expect(find.byType(MealImageCard), findsNothing);
  });

  testWidgets('sayım okunamazsa yüklenen sayı artı işaretiyle yazılır',
      (tester) async {
    final FakeFirebaseFirestore db = await seeded(tester, 400);
    MealPhotoLoader.instance
      ..client = MockClient((request) async => http.Response('', 404))
      ..cacheDirectory = null;
    final PagedFakeChat chat = PagedFakeChat(db, currentUid: _uid)
      ..countFails = true;
    addTearDown(chat.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<ChatManager>.value(
      value: chat,
      child: const MaterialApp(home: UserMediaGalleryPage(userId: _uid)),
    ));
    await settle(tester);

    expect(find.text('75+ fotoğraf'), findsOneWidget);
  });

  testWidgets('eski sayfa okunamazsa üstte "Tekrar dene" görünür ve '
      'yeniden denenir', (tester) async {
    final FakeFirebaseFirestore db = await seeded(tester, 400);
    MealPhotoLoader.instance
      ..client = MockClient((request) async => http.Response('', 404))
      ..cacheDirectory = null;
    final PagedFakeChat chat = PagedFakeChat(db, currentUid: _uid)
      ..olderPageFailures = 1;
    addTearDown(chat.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<ChatManager>.value(
      value: chat,
      child: const MaterialApp(home: UserMediaGalleryPage(userId: _uid)),
    ));
    await settle(tester);

    final Finder retry = find.textContaining('Tekrar dene');
    expect(retry, findsOneWidget);
    expect(chat.olderPageCalls, 1);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await settle(tester);
    expect(chat.olderPageCalls, 1);

    await tester.tap(retry);
    await settle(tester);

    expect(find.textContaining('Tekrar dene'), findsNothing);
    expect(chat.olderPageCalls, 2);
  });

  testWidgets('silinen fotoğraf ızgaradan kalkar ve toplam sayı azalır',
      (tester) async {
    final FakeFirebaseFirestore db = await seeded(tester, 12);
    final List<String> deleted = [];
    await pumpGallery(
      tester,
      db,
      onDeletePhoto: (message) async {
        deleted.add(message.id);
        await markChatPhotoDeleted(db, _uid, message.id);
      },
    );
    expect(find.text('6 fotoğraf'), findsOneWidget);

    await tester.longPress(find.byType(MealImageCard).first);
    await settle(tester);
    await tester.tap(find.text('Fotoğrafı Sil'));
    await settle(tester);

    expect(deleted, hasLength(1));
    expect(find.text('5 fotoğraf'), findsOneWidget);
    expect(find.byType(MealImageCard), findsNWidgets(5));
  });
}
