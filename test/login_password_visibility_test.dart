import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/pages/login_page.dart';
import 'package:ngy_app/providers/login_manager.dart';
import 'package:provider/provider.dart';

Widget _loginApp(LoginProvider provider, {Key? key}) =>
    ChangeNotifierProvider<LoginProvider>.value(
      value: provider,
      child: MaterialApp(home: LoginPage(key: key)),
    );

bool _isPasswordObscured(WidgetTester tester) => tester
    .widget<EditableText>(find.descendant(
      of: find.widgetWithText(TextField, 'Şifre'),
      matching: find.byType(EditableText),
    ))
    .obscureText;

Color? _iconColor(WidgetTester tester, IconData icon) =>
    IconTheme.of(tester.element(find.byIcon(icon))).color;

void main() {
  testWidgets('password eye icon toggles visibility and resets on reopen',
      (tester) async {
    final provider = LoginProvider();
    await tester.pumpWidget(_loginApp(provider, key: const ValueKey(1)));

    expect(_isPasswordObscured(tester), isTrue);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    final Color? hiddenColor = _iconColor(tester, Icons.visibility_off);

    await tester.tap(find.byTooltip('Şifreyi göster'));
    await tester.pumpAndSettle();
    expect(_isPasswordObscured(tester), isFalse);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(_iconColor(tester, Icons.visibility), isNot(hiddenColor));

    await tester.tap(find.byTooltip('Şifreyi gizle'));
    await tester.pumpAndSettle();
    expect(_isPasswordObscured(tester), isTrue);

    await tester.tap(find.byTooltip('Şifreyi göster'));
    await tester.pumpAndSettle();
    expect(_isPasswordObscured(tester), isFalse);

    provider.passwordController.text = 'x';
    provider.clearError();
    await tester.pumpAndSettle();
    expect(_isPasswordObscured(tester), isFalse);

    await tester.pumpWidget(_loginApp(provider, key: const ValueKey(2)));
    expect(_isPasswordObscured(tester), isTrue);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(_iconColor(tester, Icons.visibility_off), hiddenColor);
  });
}
