import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/pages/chat_page_new.dart';
import 'package:ngy_app/services/fcm_service.dart';

/// Danışanın sohbeti açıkken bildirime basılınca [FcmService] sohbetin
/// üstündeki rotaları [FcmService.isClientChatPopBoundary]'ye kadar kapatır.
void main() {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpWithChat(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Text('ana sayfa'),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: ChatPage.routeName),
      builder: (_) => const Text('sohbet'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sohbetin üstündeki sıradan sayfa kapanır', (tester) async {
    await pumpWithChat(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Text('galeri'),
    ));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.popUntil(FcmService.isClientChatPopBoundary);
    await tester.pumpAndSettle();
    expect(find.text('galeri'), findsNothing);
    expect(find.text('sohbet'), findsOneWidget);
  });

  testWidgets('kapanmadan soru soran sayfa (fotoğraf düzenleme) kapanmaz',
      (tester) async {
    await pumpWithChat(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const PopScope<void>(
        canPop: false,
        child: Text('düzenleme'),
      ),
    ));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.popUntil(FcmService.isClientChatPopBoundary);
    await tester.pumpAndSettle();
    expect(find.text('düzenleme'), findsOneWidget);
  });

  testWidgets('diyalog kapanmaz', (tester) async {
    await pumpWithChat(tester);
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('siliniyor')),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.popUntil(FcmService.isClientChatPopBoundary);
    await tester.pumpAndSettle();
    expect(find.text('siliniyor'), findsOneWidget);
  });
}
