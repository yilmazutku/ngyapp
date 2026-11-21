import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:ngy_app/widgets/reaction_picker.dart';

import 'admin_meal_photos_fakes.dart';
import 'meal_image_details_dialog_probe.dart';

const String _clientA = 'danisan-a';
const String _clientAName = 'Buket Tekkeli';
const String _clientB = 'danisan-b';
const String _clientBName = 'Aslı Aydaş';
const String _noMessageText =
    'Bu fotoğrafın sohbette mesajı yok; ifade bırakılamaz.';

class _Shot {
  const _Shot(this.id, this.meal, this.hour, this.minute);

  final String id;
  final Meals meal;
  final int hour;
  final int minute;

  String get url => 'https://ornek.com/$id.jpg';
  String get thumbUrl => 'https://ornek.com/$id-kucuk.png';
  DateTime at(DateTime day) => day.add(Duration(hours: hour, minutes: minute));
}

const List<_Shot> _stripA = [
  _Shot('a0', Meals.br, 8, 10),
  _Shot('a1', Meals.firstmid, 10, 30),
  _Shot('a2', Meals.lunch, 12, 40),
  _Shot('a3', Meals.lunch, 13, 5),
  _Shot('a4', Meals.secondmid, 16, 20),
  _Shot('a5', Meals.dinner, 19, 45),
  _Shot('a6', Meals.none, 21, 30),
];

const List<_Shot> _stripB = [
  _Shot('b0', Meals.br, 9, 0),
  _Shot('b1', Meals.lunch, 14, 0),
  _Shot('b2', Meals.dinner, 22, 0),
];

MealModel _single(_Shot shot, DateTime day) => MealModel(
      mealId: 'ogun-${shot.id}',
      mealType: shot.meal,
      imageUrls: [shot.url],
      thumbUrls: [shot.thumbUrl],
      imageTimes: [shot.at(day)],
      timestamp: shot.at(day),
      isChecked: false,
    );

Map<String, List<MealModel>> _mealsByUser(DateTime day) => {
      _clientA: [
        _single(_stripA[6], day),
        _single(_stripA[5], day),
        _single(_stripA[4], day),
        MealModel(
          mealId: 'ogun-ogle',
          mealType: Meals.lunch,
          imageUrls: [_stripA[2].url, _stripA[3].url],
          thumbUrls: [_stripA[2].thumbUrl, _stripA[3].thumbUrl],
          imageTimes: [_stripA[2].at(day), _stripA[3].at(day)],
          timestamp: _stripA[3].at(day),
          isChecked: false,
        ),
        _single(_stripA[1], day),
        _single(_stripA[0], day),
      ],
      _clientB: [for (final _Shot shot in _stripB.reversed) _single(shot, day)],
    };

MessageData _message(String chatId, _Shot shot, [Map<String, String>? r]) =>
    MessageData(
      id: 'mesaj-${shot.id}',
      chatId: chatId,
      senderId: chatId,
      imageUrl: shot.url,
      thumbUrl: shot.thumbUrl,
      reactions: r ?? const {},
    );

Map<String, MessageData> _messages() => {
      for (final _Shot shot in _stripA.take(6))
        shot.url: _message(
          _clientA,
          shot,
          shot.id == 'a1' ? {FakeChatManager.adminUid: '❤️'} : null,
        ),
      for (final _Shot shot in _stripB) shot.url: _message(_clientB, shot),
    };

String _titleOf(_Shot shot, DateTime day) => '${shot.meal.displayLabel} - '
    '${DateFormat('d MMMM y, HH:mm', 'tr_TR').format(shot.at(day))}';

Finder _section(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

Finder _cards(String name) =>
    find.descendant(of: _section(name), matching: find.byType(MealImageCard));

Finder _cardOf(_Shot shot) => find.byWidgetPredicate(
      (widget) => widget is MealImageCard && widget.meal.imageUrl == shot.url,
    );

Finder _scrollableIn(Finder within, AxisDirection direction) => find
    .descendant(
      of: within,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axisDirection == direction,
      ),
    )
    .first;

Finder get _pageList => find
    .ancestor(
      of: find.byType(Card).first,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<Finder> _revealCard(
  WidgetTester tester,
  String name,
  _Shot shot,
) async {
  await tester.scrollUntilVisible(find.text(name), 200, scrollable: _pageList);
  await tester.pumpAndSettle();
  final Finder strip = _scrollableIn(_section(name), AxisDirection.right);
  await tester.ensureVisible(strip);
  tester.state<ScrollableState>(strip).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_cardOf(shot), 120, scrollable: strip);
  await tester.ensureVisible(_cardOf(shot));
  await tester.pumpAndSettle();
  return _cardOf(shot);
}

Future<FakeChatManager> _pumpPage(
  WidgetTester tester, {
  Widget? home,
}) async {
  await rememberSolidImages(tester, [
    for (final _Shot shot in [..._stripA, ..._stripB]) ...[
      shot.thumbUrl,
      shot.url,
    ],
  ]);
  final FakeChatManager chatManager =
      FakeChatManager(messagesByImageUrl: _messages());
  await tester.pumpWidget(
    adminMealPhotosApp(
      customers: [
        testCustomer(_clientA, 'Buket', 'Tekkeli'),
        testCustomer(_clientB, 'Aslı', 'Aydaş'),
      ],
      mealsByUser: _mealsByUser(testToday()),
      chatManager: chatManager,
      home: home ?? const AdminMealPhotosPage(),
    ),
  );
  await settleAdminMealPhotos(tester);
  return chatManager;
}

Future<void> _openPhoto(WidgetTester tester, String name, _Shot shot) async {
  await tester.tap(await _revealCard(tester, name, shot));
  await tester.pumpAndSettle();
}

String? _selectedEmoji(WidgetTester tester) =>
    tester.widget<QuickReactionRow>(find.byType(QuickReactionRow)).currentEmoji;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  final ScreenVariant screens = ScreenVariant(ignoreTestFontOverflow: true);
  final ScreenVariant phoneAndDesktop = ScreenVariant(
    screens: [kTestScreens[0], kTestScreens[5]],
    ignoreTestFontOverflow: true,
  );

  testWidgets(
      'şeritteki fotoğrafa dokununca oklar o danışanın şeridinde, şeritteki '
      'sırayla gezer; uçlarda o yöndeki ok çıkmaz', (tester) async {
    await _pumpPage(tester);
    final DateTime day = testToday();
    await _openPhoto(tester, _clientAName, _stripA[2]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    expect(probe.counterText, '3 / ${_stripA.length}');
    expect(probe.title, _titleOf(_stripA[2], day));

    await probe.showPrevious();
    await probe.showPrevious();
    expect(probe.counterText, '1 / ${_stripA.length}');
    expect(probe.title, _titleOf(_stripA[0], day));
    probe.expectArrows(previousShown: false, nextShown: true);

    for (int i = 1; i < _stripA.length; i++) {
      await probe.showNext();
      expect(probe.counterText, '${i + 1} / ${_stripA.length}');
      expect(probe.title, _titleOf(_stripA[i], day));
      probe.expectArrows(
        previousShown: true,
        nextShown: i < _stripA.length - 1,
      );
    }
    for (final _Shot other in _stripB) {
      expect(probe.title, isNot(_titleOf(other, day)));
    }
  }, variant: phoneAndDesktop);

  testWidgets(
      'başka danışanın şeridinden açılınca yalnızca onun fotoğrafları '
      'gezilir', (tester) async {
    await _pumpPage(tester);
    final DateTime day = testToday();

    await _openPhoto(tester, _clientBName, _stripB[0]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    expect(probe.counterText, '1 / ${_stripB.length}');
    for (int i = 0; i < _stripB.length; i++) {
      expect(probe.title, _titleOf(_stripB[i], day));
      if (i < _stripB.length - 1) await probe.showNext();
    }
    probe.expectArrows(previousShown: true, nextShown: false);
  }, variant: phoneAndDesktop);

  testWidgets(
      'öğün filtresi açıkken yalnızca şeritte görünen fotoğraflar '
      'arasında gezilir', (tester) async {
    await _pumpPage(tester);
    final DateTime day = testToday();

    await tester.tap(find.text(MealPhotoFiltersLayout.filtersLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, Meals.snackLabel));
    await tester.pumpAndSettle();
    expect(_cards(_clientAName), findsNWidgets(2));

    await _openPhoto(tester, _clientAName, _stripA[1]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    expect(probe.counterText, '1 / 2');
    expect(probe.title, _titleOf(_stripA[1], day));
    probe.expectArrows(previousShown: false, nextShown: true);

    await probe.showNext();
    expect(probe.counterText, '2 / 2');
    expect(probe.title, _titleOf(_stripA[4], day));
    probe.expectArrows(previousShown: true, nextShown: false);
  }, variant: phoneAndDesktop);

  testWidgets(
      'alttaki ifade satırı o an gösterilen fotoğrafın mesajına ait; '
      'bırakılan ifade o fotoğrafa gider ve kartında görünür', (tester) async {
    final FakeChatManager chat = await _pumpPage(tester);

    await _openPhoto(tester, _clientAName, _stripA[0]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    expect(_selectedEmoji(tester), isNull);

    await probe.showNext();
    expect(_selectedEmoji(tester), '❤️',
        reason: '2. fotoğrafa önceden bırakılan ifade işaretli gelmeli');

    await probe.showNext();
    expect(_selectedEmoji(tester), isNull);
    await tester.ensureVisible(find.text('👍'));
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(chat.reactions, hasLength(1));
    expect(chat.reactions.single.chatId, _clientA);
    expect(chat.reactions.single.messageId, 'mesaj-a2');
    expect(chat.reactions.single.emoji, '👍');
    expect(_selectedEmoji(tester), '👍');

    await probe.showNext();
    expect(_selectedEmoji(tester), isNull);
    await probe.showPrevious();
    expect(_selectedEmoji(tester), '👍',
        reason: 'geri dönünce bırakılan ifade işaretli kalmalı');

    for (int i = 3; i < _stripA.length; i++) {
      await probe.showNext();
    }
    expect(find.byType(QuickReactionRow), findsNothing);
    expect(find.text(_noMessageText), findsOneWidget);

    await tester.tap(find.text(kCloseLabel));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: await _revealCard(tester, _clientAName, _stripA[2]),
        matching: find.text('👍'),
      ),
      findsOneWidget,
      reason: 'ifade, bırakıldığı fotoğrafın kartında görünmeli',
    );
    expect(
      find.descendant(
        of: await _revealCard(tester, _clientAName, _stripA[0]),
        matching: find.text('👍'),
      ),
      findsNothing,
    );
  }, variant: phoneAndDesktop);

  testWidgets('"Sohbette göster" gezilen fotoğrafın mesajıyla sohbete döner',
      (tester) async {
    String? openedMessageId;
    await _pumpPage(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                openedMessageId = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const AdminMealPhotosPage(
                      returnToChatUserId: _clientA,
                    ),
                  ),
                );
              },
              child: const Text('sohbet'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sohbet'));
    await settleAdminMealPhotos(tester);
    await tester.pumpAndSettle();

    await _openPhoto(tester, _clientAName, _stripA[0]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    await probe.showNext();
    await probe.showNext();
    await probe.showNext();
    await tester.ensureVisible(find.text('Sohbette göster'));
    await tester.tap(find.text('Sohbette göster'));
    await tester.pumpAndSettle();

    expect(openedMessageId, 'mesaj-a3');
    expect(find.byType(AdminMealPhotosPage), findsNothing);
  }, variant: phoneAndDesktop);

  testWidgets(
      'gerçek sayfada oklar fotoğrafın altında, ortada ve kaydırmadan '
      'görünür; gezerken yerinden oynamaz', (tester) async {
    await _pumpPage(tester);
    final String at = screens.current.name;

    await _openPhoto(tester, _clientAName, _stripA[0]);
    final PhotoDialogProbe probe = PhotoDialogProbe(tester);
    probe.expectPlacement(at);
    probe.expectCentered(at);
    final Map<String, Rect> first = probe.layout();

    for (int i = 1; i < _stripA.length; i++) {
      await probe.showNext();
      probe.expectSameLayout(first, '$at, ${i + 1}. fotoğraf');
      probe.expectPlacement('$at, ${i + 1}. fotoğraf');
    }
    await disposeAdminMealPhotos(tester);
  }, variant: screens);
}
