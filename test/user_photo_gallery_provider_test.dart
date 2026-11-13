import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_photo_gallery_provider.dart';

import 'paged_chat_fake.dart';

const String _uid = 'danisan-1';

void main() {
  late FakeFirebaseFirestore db;
  late PagedFakeChat chat;
  late UserPhotoGalleryProvider gallery;

  Future<void> add(int index, ChatSeedKind kind) =>
      addChatMessage(db, _uid, index, kind);

  Future<void> seed(int count, ChatSeedKind Function(int index) kindOf) =>
      seedChatMessages(db, _uid, count, kindOf);

  List<String> ids() => [for (final MessageData photo in gallery.photos) photo.id];

  List<String> expectedIds(int count, ChatSeedKind Function(int index) kindOf) => [
        for (int index = count - 1; index >= 0; index--)
          if (kindOf(index) == ChatSeedKind.photo) 'm$index',
      ];

  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> loadUntilStart() async {
    for (int i = 0; i < 50 && !gallery.atStart; i++) {
      await gallery.loadOlder();
      await settle();
    }
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    chat = PagedFakeChat(db);
    gallery = UserPhotoGalleryProvider(chat: chat, userId: _uid);
  });

  tearDown(() {
    gallery.dispose();
    chat.dispose();
  });

  const ChatSeedKind Function(int index) alternating = alternatingChatKind;

  test('açılmadan önce yükleniyor; hiç mesaj yoksa boş ve baştadır', () async {
    expect(gallery.isLoading, isTrue);

    gallery.start();
    await settle();

    expect(gallery.isLoading, isFalse);
    expect(gallery.photos, isEmpty);
    expect(gallery.atStart, isTrue);
    expect(gallery.totalCount, 0);
    expect(chat.olderPageCalls, 0);
  });

  test('kısa sohbet: fotoğrafların hepsi ilk anda gelir, eski sayfa okunmaz',
      () async {
    await seed(12, alternating);
    gallery.start();
    await settle();

    expect(ids(), expectedIds(12, alternating));
    expect(gallery.atStart, isTrue);
    expect(gallery.totalCount, 6);

    await gallery.loadOlder();
    expect(chat.olderPageCalls, 0);
    expect(gallery.isLoadingOlder, isFalse);
  });

  test('uzun sohbet: önce son fotoğraflar, istendikçe eskiler; boşluk ve '
      'tekrar olmaz', () async {
    const int count = 400;
    await seed(count, alternating);
    final List<String> all = expectedIds(count, alternating);
    gallery.start();
    await settle();

    expect(ids(), all.take(15).toList());
    expect(gallery.atStart, isFalse);
    expect(gallery.totalCount, all.length);

    await gallery.loadOlder();
    await settle();
    expect(chat.olderPageCalls, 1);
    expect(ids(), all.take(75).toList());
    expect(gallery.totalCount, all.length);

    await loadUntilStart();
    expect(chat.olderPageCalls, 4);
    expect(
      chat.olderPageLimits,
      everyElement(UserPhotoGalleryProvider.olderPageSize),
    );
    expect(ids(), all);
    expect(ids().toSet(), hasLength(all.length));
    expect(gallery.atStart, isTrue);
    expect(gallery.totalCount, all.length);

    await gallery.loadOlder();
    expect(chat.olderPageCalls, 4);
  });

  test('fotoğrafsız uzun aralık: boş sayfalar geçilir, ilk fotoğrafa kadar '
      'kendiliğinden okunur', () async {
    ChatSeedKind onlyFirst(int index) => index == 0
        ? ChatSeedKind.photo
        : (index.isEven ? ChatSeedKind.text : ChatSeedKind.officeText);
    await seed(300, onlyFirst);
    gallery.start();
    for (int i = 0; i < 50 && gallery.photos.isEmpty; i++) {
      await settle();
    }

    expect(ids(), ['m0']);
    expect(gallery.atStart, isTrue);
    expect(gallery.isLoadingOlder, isFalse);
    expect(gallery.totalCount, 1);
    expect(chat.olderPageCalls, 3);
  });

  test('yeni fotoğraf canlı gelir; toplam sayı da artar', () async {
    await seed(200, alternating);
    final int total = expectedIds(200, alternating).length;
    gallery.start();
    await settle();
    await gallery.loadOlder();
    await settle();
    expect(gallery.totalCount, total);
    final int loaded = gallery.photos.length;

    await add(200, ChatSeedKind.photo);
    await settle();

    expect(ids().first, 'm200');
    expect(gallery.photos, hasLength(loaded + 1));
    expect(gallery.totalCount, total + 1);
  });

  test('sohbet uzadıkça canlı pencereden düşen fotoğraflar eski sayfayla '
      'geri gelir', () async {
    await seed(40, alternating);
    gallery.start();
    await settle();
    expect(ids(), expectedIds(40, alternating).take(15).toList());

    for (int index = 40; index < 60; index++) {
      await add(index, ChatSeedKind.text);
    }
    await settle();
    expect(ids(), expectedIds(40, alternating).take(5).toList());

    await loadUntilStart();
    expect(ids(), expectedIds(40, alternating));
    expect(gallery.totalCount, 20);
  });

  test('canlı penceredeki fotoğraf silinince kendiliğinden kalkar', () async {
    await seed(100, alternating);
    final List<String> all = expectedIds(100, alternating);
    gallery.start();
    await settle();
    expect(ids().first, 'm98');

    await markChatPhotoDeleted(db, _uid, 'm98');
    await settle();

    expect(ids(), all.skip(1).take(14).toList());
    expect(gallery.totalCount, all.length - 1);
  });

  test('eski sayfadaki fotoğraf silinip yenilenince kalkar', () async {
    await seed(200, alternating);
    final List<String> all = expectedIds(200, alternating);
    gallery.start();
    await settle();
    await gallery.loadOlder();
    await settle();
    expect(ids(), contains('m100'));

    await markChatPhotoDeleted(db, _uid, 'm100');
    await settle();
    expect(ids(), contains('m100'));

    await gallery.refreshMessage('m100');
    await settle();

    expect(ids(), isNot(contains('m100')));
    expect(ids(), all.where((id) => id != 'm100').take(74).toList());
    expect(gallery.totalCount, all.length - 1);
  });

  test('silinmeyen fotoğraf yenilenince yerinde kalır', () async {
    await seed(200, alternating);
    gallery.start();
    await settle();
    await gallery.loadOlder();
    await settle();
    final List<String> before = ids();

    await gallery.refreshMessage('m100');
    await settle();

    expect(ids(), before);
  });

  test('ofisin gönderdiği görseller galeriye girmez; toplam, eski sayfalar '
      'yüklendikçe tam sayıya iner', () async {
    ChatSeedKind withOfficePhotos(int index) => switch (index) {
          5 || 6 || 150 => ChatSeedKind.officePhoto,
          _ => alternating(index),
        };
    await seed(160, withOfficePhotos);
    final List<String> all = expectedIds(160, withOfficePhotos);
    gallery.start();
    await settle();

    expect(ids(), all.take(ids().length).toList());
    expect(gallery.totalCount, all.length + 2);

    await loadUntilStart();
    expect(ids(), all);
    expect(gallery.totalCount, all.length);
  });

  test('eski sayfa okunamazsa durur; yeniden denenince sürer', () async {
    await seed(200, alternating);
    final List<String> all = expectedIds(200, alternating);
    gallery.start();
    await settle();

    chat.olderPageFailures = 1;
    await gallery.loadOlder();
    expect(gallery.olderLoadFailed, isTrue);
    expect(gallery.isLoadingOlder, isFalse);
    expect(ids(), all.take(15).toList());

    await gallery.loadOlder();
    expect(chat.olderPageCalls, 1);

    gallery.retryOlder();
    await settle();
    expect(gallery.olderLoadFailed, isFalse);
    expect(ids(), all.take(75).toList());
  });

  test('sayım okunamazsa toplam bilinmez; galerinin tamamı yüklenince '
      'yüklenen sayıdır', () async {
    chat.countFails = true;
    await seed(200, alternating);
    gallery.start();
    await settle();

    expect(gallery.totalCount, isNull);
    expect(gallery.totalCountUnavailable, isTrue);

    await loadUntilStart();
    expect(gallery.totalCount, 100);
    expect(gallery.totalCountUnavailable, isFalse);
  });

  test('değişiklik olmadıkça sayım yeniden sorulmaz', () async {
    await seed(200, alternating);
    gallery.start();
    await settle();
    expect(chat.countCalls, 1);

    await loadUntilStart();
    expect(chat.countCalls, 1);

    await add(200, ChatSeedKind.officeText);
    await settle();
    expect(chat.countCalls, 1);

    await add(201, ChatSeedKind.photo);
    await settle();
    expect(chat.countCalls, 2);
  });

  test('kapatılan galeri süren yüklemeden sonra dinleyicilerine haber vermez',
      () async {
    await seed(200, alternating);
    gallery.start();
    await settle();

    int notifications = 0;
    gallery.addListener(() => notifications++);
    final Future<void> loading = gallery.loadOlder();
    final int whileLoading = notifications;
    gallery.dispose();
    await loading;
    await settle();

    expect(notifications, whileLoading);

    gallery = UserPhotoGalleryProvider(chat: chat, userId: _uid);
  });
}
