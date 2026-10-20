import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/dialog_utils.dart';

void main() {
  Future<Completer<void>> open(WidgetTester tester) async {
    final Completer<void> task = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => DialogUtils.openLoadingUntilDone(
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
}
