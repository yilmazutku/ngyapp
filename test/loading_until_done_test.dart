import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/dialog_utils.dart';

void main() {
  const String topPage = 'Bildirimden açılan sayfa';

  /// Son açılan diyaloğun [DialogUtils.openLoadingUntilDone] çağrısı.
  late Future<void> closed;

  Future<Completer<void>> open(WidgetTester tester) async {
    final Completer<void> task = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => closed = DialogUtils.openLoadingUntilDone(
              context,
              message: 'Görsel siliniyor...',
              doneMessage: 'Silindi!',
              task: task.future,
            ),
            child: const Text('sil'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sil'));
    await tester.pump();
    expect(find.text('Görsel siliniyor...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    return task;
  }

  /// Diyalog açıkken üstüne bir sayfa açar (ör. bildirime basılıp sohbet
  /// açılması).
  Future<void> pushPageAbove(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text(topPage)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(topPage), findsOneWidget);
  }

  /// Üstteki sayfa açık kalmış, diyalog kaldırılmış ve çağrı dönmüş olmalı;
  /// sayfadan geri dönünce de diyalog görünmez.
  Future<void> expectOnlyDialogRemoved(
    WidgetTester tester, {
    required bool Function() returned,
  }) async {
    expect(find.text(topPage), findsOneWidget);
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(returned(), isTrue);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('sil'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  }

  testWidgets('iş bitince "Silindi!" görünür, 1 sn sonra kapanır',
      (tester) async {
    final Completer<void> task = await open(tester);

    task.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Silindi!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('iş hata verince hemen kapanır', (tester) async {
    final Completer<void> task = await open(tester);

    task.completeError(StateError('silinemedi'));
    task.future.catchError((Object e) {});
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Silindi!'), findsNothing);
  });

  testWidgets('üstüne sayfa açıldıysa iş bitince yalnızca diyalog kalkar',
      (tester) async {
    final Completer<void> task = await open(tester);
    bool returned = false;
    closed.then((_) => returned = true);
    await pushPageAbove(tester);

    task.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await expectOnlyDialogRemoved(tester, returned: () => returned);
  });

  testWidgets('üstüne sayfa açıldıysa iş hata verince yalnızca diyalog kalkar',
      (tester) async {
    final Completer<void> task = await open(tester);
    bool returned = false;
    closed.then((_) => returned = true);
    await pushPageAbove(tester);

    task.completeError(StateError('silinemedi'));
    task.future.catchError((Object e) {});
    await tester.pump();
    await tester.pumpAndSettle();
    await expectOnlyDialogRemoved(tester, returned: () => returned);
  });
}
