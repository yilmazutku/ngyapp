import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/pages/feature_test_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const String prefsKey = 'featureTestChecklist.v1';

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: FeatureTestPage()));
    await tester.pumpAndSettle();
  }

  Future<List<String>> saved() async =>
      (await SharedPreferences.getInstance()).getStringList(prefsKey) ??
      const [];

  testWidgets('işaretlenen adım sayılır, cihazda kalır ve sıfırlanabilir',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    expect(find.textContaining('0 / '), findsOneWidget);
    expect(find.text('Sıfırla'), findsNothing);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / '), findsOneWidget);
    expect(await saved(), ['kilo.ekle']);

    await pumpPage(tester);
    expect(find.textContaining('1 / '), findsOneWidget);

    await tester.tap(find.text('Sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Sıfırla'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 / '), findsOneWidget);
    expect(await saved(), isEmpty);
  });
}
