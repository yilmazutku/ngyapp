import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/dialog_utils.dart';

void main() {
  const String homePage = 'Ana sayfa';
  const String ownerPage = 'Diyaloğu açan sayfa';
  const String topPage = 'Bildirimden açılan sayfa';
  const String loadingText = 'Siliniyor...';

  /// Diyalog geçişinin bitmesi için beklenen süre.
  const Duration transition = Duration(milliseconds: 300);

  /// Son açılan yükleme diyaloğu.
  late LoadingDialog loading;

  NavigatorState navigatorOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));

  /// Ana sayfanın üstüne açılan bir sayfadan [open] ile yükleme diyaloğunu
  /// açar.
  Future<void> openOnOwnerPage(
    WidgetTester tester,
    LoadingDialog Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text(homePage))),
    );
    navigatorOf(tester).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => loading = open(context),
              child: const Text(ownerPage),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(ownerPage));
    await tester.pump();
    await tester.pump(transition);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(loading.isOpen, isTrue);
  }

  Future<void> openLoading(WidgetTester tester) => openOnOwnerPage(
        tester,
        (context) => DialogUtils.openLoading(context, message: loadingText),
      );

  /// Diyalog açıkken üstüne bir sayfa açar (ör. bildirime basılıp sohbet
  /// açılması).
  Future<void> pushPageAbove(WidgetTester tester) async {
    navigatorOf(tester).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text(topPage)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(topPage), findsOneWidget);
  }

  /// Üstteki sayfa açık ve en üstte kalmış, diyalog kaldırılmış olmalı;
  /// sayfadan geri dönünce [below] görünür, diyalog görünmez.
  Future<void> expectOnlyDialogRemoved(
    WidgetTester tester, {
    String below = ownerPage,
  }) async {
    expect(find.text(topPage), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text(topPage)))!.isCurrent,
        isTrue);
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(loading.isOpen, isFalse);

    navigatorOf(tester).pop();
    await tester.pumpAndSettle();
    expect(find.text(below), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  }

  testWidgets('close ile diyalog kapanır, açan sayfa yerinde kalır',
      (tester) async {
    await openLoading(tester);
    expect(find.text(loadingText), findsOneWidget);

    loading.close();
    expect(loading.isOpen, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(ownerPage), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text(ownerPage)))!.isCurrent,
        isTrue);
  });

  testWidgets('üstüne sayfa açıldıysa close yalnızca diyaloğu kaldırır',
      (tester) async {
    await openLoading(tester);
    await pushPageAbove(tester);

    loading.close();
    await tester.pumpAndSettle();
    await expectOnlyDialogRemoved(tester);
  });

  testWidgets('iki kez close hata vermez, başka sayfayı kapatmaz',
      (tester) async {
    await openLoading(tester);

    loading.close();
    loading.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(ownerPage), findsOneWidget);

    loading.close();
    await tester.pumpAndSettle();
    expect(find.text(ownerPage), findsOneWidget);
  });

  testWidgets('açan sayfa kapandıktan sonra da close diyaloğu kaldırır',
      (tester) async {
    await openLoading(tester);
    final Route<dynamic> owner = ModalRoute.of(
        tester.element(find.text(ownerPage, skipOffstage: false)))!;
    await pushPageAbove(tester);

    // Bildirim alttaki sayfayı kapatır; diyaloğun sahibi artık yok.
    navigatorOf(tester).removeRoute(owner);
    await tester.pumpAndSettle();
    expect(find.text(ownerPage, skipOffstage: false), findsNothing);

    loading.close();
    await tester.pumpAndSettle();
    await expectOnlyDialogRemoved(tester, below: homePage);
  });

  testWidgets('geri tuşu ve arka plana dokunmak diyaloğu kapatmaz',
      (tester) async {
    await openLoading(tester);

    await tester.binding.handlePopRoute();
    await tester.pump(transition);
    expect(find.text(loadingText), findsOneWidget);

    await navigatorOf(tester).maybePop();
    await tester.pump(transition);
    expect(find.text(loadingText), findsOneWidget);

    final Size screen = tester.getSize(find.byType(MaterialApp));
    await tester.tapAt(Offset(screen.width - 5, screen.height - 5));
    await tester.pump(transition);
    expect(find.text(loadingText), findsOneWidget);
    expect(loading.isOpen, isTrue);
    expect(find.text(ownerPage), findsOneWidget);

    loading.close();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(ownerPage), findsOneWidget);
  });

  testWidgets('openLoadingProgress yazısını günceller, aynı biçimde kapanır',
      (tester) async {
    final ValueNotifier<String> progress =
        ValueNotifier<String>('Yükleniyor (1/2)...');
    addTearDown(progress.dispose);
    await openOnOwnerPage(
      tester,
      (context) => DialogUtils.openLoadingProgress(
        context,
        messageListenable: progress,
      ),
    );
    expect(find.text('Yükleniyor (1/2)...'), findsOneWidget);

    progress.value = 'Yükleniyor (2/2)...';
    await tester.pump();
    expect(find.text('Yükleniyor (1/2)...'), findsNothing);
    expect(find.text('Yükleniyor (2/2)...'), findsOneWidget);

    await pushPageAbove(tester);
    loading.close();
    await tester.pumpAndSettle();
    await expectOnlyDialogRemoved(tester);
  });

  testWidgets(
      'closeOwnRoute: sayfa kendini sonucuyla kapatır; üstüne açılan sayfa kalır',
      (tester) async {
    late BuildContext ownerContext;
    late NavigatorState navigator;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        navigator = Navigator.of(context);
        return const Text(homePage);
      }),
    ));
    final Future<Object?> ownerResult = navigator.push<Object?>(
      MaterialPageRoute<Object?>(builder: (context) {
        ownerContext = context;
        return const Text(ownerPage);
      }),
    );
    await tester.pumpAndSettle();
    navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const Text(topPage)));
    await tester.pumpAndSettle();

    DialogUtils.closeOwnRoute(ownerContext, 'u1');
    await tester.pumpAndSettle();
    expect(find.text(topPage), findsOneWidget);
    expect(await ownerResult, 'u1');

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text(homePage), findsOneWidget);
    expect(find.text(ownerPage), findsNothing);
  });

  testWidgets('closeOwnRoute: sayfa en üstteyse pop gibi kapanır',
      (tester) async {
    late BuildContext ownerContext;
    late NavigatorState navigator;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        navigator = Navigator.of(context);
        return const Text(homePage);
      }),
    ));
    final Future<Object?> ownerResult = navigator.push<Object?>(
      MaterialPageRoute<Object?>(builder: (context) {
        ownerContext = context;
        return const Text(ownerPage);
      }),
    );
    await tester.pumpAndSettle();

    DialogUtils.closeOwnRoute(ownerContext);
    await tester.pumpAndSettle();
    expect(find.text(homePage), findsOneWidget);
    expect(await ownerResult, isNull);
  });

  testWidgets('diyalog başka yoldan kaldırıldıysa close hata vermez',
      (tester) async {
    late LoadingDialog loading;
    late NavigatorState navigator;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        navigator = Navigator.of(context);
        return TextButton(
          onPressed: () => loading =
              DialogUtils.openLoading(context, message: 'Çıkış yapılıyor...'),
          child: const Text('aç'),
        );
      }),
    ));
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Ör. bildirim akışı ya da çıkış tüm sayfaları kaldırır.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const Text('Giriş')),
      (_) => false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    loading.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Giriş'), findsOneWidget);
  });

  testWidgets('yükleme diyaloğu iç içe navigator\'da da kök navigator\'a '
      'açılır', (tester) async {
    late LoadingDialog loading;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => TextButton(
            onPressed: () => loading =
                DialogUtils.openLoading(context, message: 'Yükleniyor'),
            child: const Text('aç'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final NavigatorState root =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(ModalRoute.of(tester.element(find.byType(AlertDialog)))!.navigator,
        root);
    loading.close();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
