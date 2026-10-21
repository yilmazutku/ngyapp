import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/open_chats.dart';

/// Sohbet sayfasının [OpenChats] ile ilgili davranışının kopyası: açılınca
/// rotasıyla kaydolur, kapanınca kaydını siler; bildirime basılınca gelen
/// mesaj kimliğini [notifications]'a yazar.
class _FakeChat extends StatefulWidget {
  final OpenChats openChats;
  final String chatId;
  final List<String?> notifications;

  const _FakeChat({
    required this.openChats,
    required this.chatId,
    required this.notifications,
  });

  @override
  State<_FakeChat> createState() => _FakeChatState();
}

class _FakeChatState extends State<_FakeChat> {
  bool _registered = false;

  void _onNotification(String? messageId) =>
      widget.notifications.add(messageId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registered) return;
    _registered = true;
    widget.openChats.open(
      widget.chatId,
      route: ModalRoute.of(context),
      onNotificationOpen: _onNotification,
    );
  }

  @override
  void dispose() {
    widget.openChats.close(widget.chatId, onNotificationOpen: _onNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('sohbet ${widget.chatId}');
}

void main() {
  late OpenChats openChats;
  late GlobalKey<NavigatorState> navigatorKey;
  late List<String?> notifications;

  NavigatorState navigator() => navigatorKey.currentState!;

  Route<void> chatRoute(String chatId) => MaterialPageRoute<void>(
        builder: (_) => _FakeChat(
          openChats: openChats,
          chatId: chatId,
          notifications: notifications,
        ),
      );

  /// Ana sayfa > sohbet listesi.
  Future<void> pumpChatList(WidgetTester tester) async {
    openChats = OpenChats();
    navigatorKey = GlobalKey<NavigatorState>();
    notifications = [];
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Text('ana sayfa'),
    ));
    navigator().push(MaterialPageRoute<void>(
      builder: (_) => const Text('sohbet listesi'),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openFromList(WidgetTester tester, String chatId) async {
    navigator().push(chatRoute(chatId));
    await tester.pumpAndSettle();
  }

  Future<void> adminNotification(
    WidgetTester tester,
    String chatId, {
    String? messageId,
  }) async {
    openChats.showAdminChat(
      navigator(),
      chatId,
      messageId,
      () => chatRoute(chatId),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    navigator().pop();
    await tester.pumpAndSettle();
  }

  void expectShowing(String text) {
    expect(find.text(text), findsOneWidget);
  }

  group('admin', () {
    testWidgets('bildirimdeki sohbet açık sohbetin üstüne açılır; geri önceki '
        'sohbete, oradan sohbet listesine döner', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');

      await adminNotification(tester, 'b');
      expectShowing('sohbet b');
      expect(openChats.length, 2);

      await back(tester);
      expectShowing('sohbet a');
      await back(tester);
      expectShowing('sohbet listesi');
      expect(openChats.length, 0);
    });

    testWidgets('üst üste en fazla iki sohbet kalır', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');
      await adminNotification(tester, 'b');
      await adminNotification(tester, 'c');
      await adminNotification(tester, 'd');

      expectShowing('sohbet d');
      expect(openChats.length, 2);
      await back(tester);
      expectShowing('sohbet c');
      await back(tester);
      expectShowing('sohbet listesi');
    });

    testWidgets('alttaki sohbetin bildirimi o sohbeti en üste getirir; geri '
        'şu an görünen sohbete döner', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');
      await adminNotification(tester, 'b');

      await adminNotification(tester, 'a');
      expectShowing('sohbet a');
      expect(openChats.length, 2);
      expect(openChats.topChatId, 'a');

      await back(tester);
      expectShowing('sohbet b');
      await back(tester);
      expectShowing('sohbet listesi');
    });

    testWidgets('kapatılan sohbetin açtığı sayfalar da kalkar', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');
      // a'dan Öğün Fotoğrafları, oradan başka bir danışanın sohbeti.
      navigator().push(MaterialPageRoute<void>(
        builder: (_) => const Text('öğün fotoğrafları'),
      ));
      await tester.pumpAndSettle();
      await openFromList(tester, 'x');

      await adminNotification(tester, 'b');
      expectShowing('sohbet b');
      expect(openChats.length, 2);
      await back(tester);
      expectShowing('sohbet x');
      await back(tester);
      expectShowing('sohbet listesi');
      expect(find.text('öğün fotoğrafları'), findsNothing);
    });

    testWidgets('üstte yükleme diyaloğu varken bildirim sohbet açmaz',
        (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');
      showDialog<void>(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('siliniyor')),
      );
      await tester.pumpAndSettle();

      await adminNotification(tester, 'b');
      expectShowing('siliniyor');
      expect(find.text('sohbet b'), findsNothing);
      expect(openChats.length, 1);
    });

    testWidgets('görünen sohbetin bildirimi yeni sayfa açmaz, mesaja gider',
        (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'a');
      navigator().push(MaterialPageRoute<void>(
        builder: (_) => const Text('tam ekran fotoğraf'),
      ));
      await tester.pumpAndSettle();

      await adminNotification(tester, 'a', messageId: 'm1');
      expectShowing('sohbet a');
      expect(openChats.length, 1);
      expect(notifications, ['m1']);

      await back(tester);
      expectShowing('sohbet listesi');
    });
  });

  group('danışan', () {
    Future<void> clientNotification(
      WidgetTester tester, {
      String? messageId,
    }) async {
      openChats.showClientChat(
        navigator(),
        'me',
        messageId,
        () => chatRoute('me'),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sohbet kapalıysa açılır', (tester) async {
      await pumpChatList(tester);
      await clientNotification(tester);
      expectShowing('sohbet me');
      expect(openChats.length, 1);
    });

    testWidgets('sohbet kapanma geçişindeyken bildirime basılırsa sohbet '
        'yeniden açılır', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'me');
      navigator().pop();
      await tester.pump();

      await clientNotification(tester);
      expectShowing('sohbet me');
      expect(openChats.length, 1);
      expect(notifications, isEmpty);
    });

    testWidgets('sohbet açıksa ikinci kopya açılmaz; üstündeki sayfa kapanır, '
        'yeni mesaj bildirimi en yeniye gider', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'me');
      navigator().push(MaterialPageRoute<void>(
        builder: (_) => const Text('galeri'),
      ));
      await tester.pumpAndSettle();

      await clientNotification(tester);
      expectShowing('sohbet me');
      expect(openChats.length, 1);
      expect(notifications, [null]);
    });

    testWidgets('kapanmadan soru soran sayfa (fotoğraf düzenleme) ve diyalog '
        'kapanmaz', (tester) async {
      await pumpChatList(tester);
      await openFromList(tester, 'me');
      navigator().push(MaterialPageRoute<void>(
        builder: (_) => const PopScope<void>(
          canPop: false,
          child: Text('düzenleme'),
        ),
      ));
      await tester.pumpAndSettle();

      await clientNotification(tester, messageId: 'm2');
      expectShowing('düzenleme');
      expect(notifications, ['m2']);

      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('siliniyor')),
      );
      await tester.pumpAndSettle();
      await clientNotification(tester);
      expectShowing('siliniyor');
    });
  });

  test('kayıt, sayfanın işleviyle silinir: aynı sohbetin eski sayfası '
      'kapanınca yenisinin kaydı kalır', () {
    final OpenChats chats = OpenChats();
    void oldPage(String? _) {}
    void newPage(String? _) {}
    chats.open('a', onNotificationOpen: oldPage);
    chats.open('a', onNotificationOpen: newPage);

    chats.close('a', onNotificationOpen: oldPage);
    expect(chats.length, 1);
    expect(chats.topChatId, 'a');
    chats.close('a', onNotificationOpen: oldPage);
    expect(chats.length, 1);
    chats.close('a', onNotificationOpen: newPage);
    expect(chats.length, 0);
  });
}
