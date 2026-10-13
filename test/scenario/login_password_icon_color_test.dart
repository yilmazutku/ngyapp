import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/pages/login_page.dart';
import 'package:ngy_app/providers/login_manager.dart';
import 'package:provider/provider.dart';

const Color _primaryColorOfAppThemeInMainDart = Color(0xFFA16AEC);

Widget _loginApp(LoginProvider provider) =>
    ChangeNotifierProvider<LoginProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.purple,
          primaryColor: _primaryColorOfAppThemeInMainDart,
          splashFactory: InkRipple.splashFactory,
        ),
        home: const LoginPage(),
      ),
    );

Color _iconColor(WidgetTester tester, IconData icon) =>
    IconTheme.of(tester.element(find.byIcon(icon))).color!;

bool _isGray(Color color) {
  final int argb = color.toARGB32();
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return r == g && g == b && r > 0x40 && r < 0xE0;
}

bool _isPurple(Color color) {
  final HSVColor hsv = HSVColor.fromColor(color);
  return hsv.hue >= 250 && hsv.hue <= 320 && hsv.saturation > 0.3;
}

void main() {
  testWidgets(
      '1.1: şifre gizliyken göz ikonu gri ve üstü çizili, gösterilince temanın mor ana rengiyle açık göz, gizleyince yine gri',
      (tester) async {
    await tester.pumpWidget(_loginApp(LoginProvider()));

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);
    final Color hidden = _iconColor(tester, Icons.visibility_off);
    expect(_isGray(hidden), isTrue, reason: 'gizliyken ikon rengi $hidden');

    await tester.tap(find.byTooltip('Şifreyi göster'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    final Color shown = _iconColor(tester, Icons.visibility);
    expect(shown, _primaryColorOfAppThemeInMainDart);
    expect(_isPurple(shown), isTrue, reason: 'görünürken ikon rengi $shown');

    await tester.tap(find.byTooltip('Şifreyi gizle'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(_iconColor(tester, Icons.visibility_off), hidden);
  });
}
