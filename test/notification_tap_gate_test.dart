import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/notification_tap_gate.dart';

/// Ana sayfanın [NotificationTapGate] ile ilgili davranışının kopyası: ilk
/// karesinden sonra açıldığını bildirir, kapanınca kaydını siler (bkz.
/// `HomePage`).
class _FakeHome extends StatefulWidget {
  final NotificationTapGate gate;

  const _FakeHome({required this.gate});

  @override
  State<_FakeHome> createState() => _FakeHomeState();
}

class _FakeHomeState extends State<_FakeHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.gate.homeShown(this);
    });
  }

  @override
  void dispose() {
    widget.gate.homeGone(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ana sayfa');
}

void main() {
  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> opened;
  late NotificationTapGate gate;

  /// KVKK onayı geçerli mi (`AuthWrapper` ana sayfayı ancak o zaman
  /// gösterir).
  late ValueNotifier<bool> hasConsent;

  NavigatorState navigator() => navigatorKey.currentState!;

  Map<String, dynamic> chatTap(String chatId) =>
      {'type': 'chat', 'chatId': chatId};

  /// İlk sayfa: onay yoksa KVKK onayı, varsa ana sayfa. Bildirim, kök
  /// navigator'a sohbet açar.
  Future<void> pumpApp(WidgetTester tester, {required bool consent}) async {
    navigatorKey = GlobalKey<NavigatorState>();
    opened = [];
    hasConsent = ValueNotifier<bool>(consent);
    gate = NotificationTapGate(onOpen: (data) {
      final String chatId = data['chatId'] as String;
      opened.add(chatId);
      navigator().push(MaterialPageRoute<void>(
        builder: (_) => Text('sohbet $chatId'),
      ));
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: ValueListenableBuilder<bool>(
        valueListenable: hasConsent,
        builder: (context, consent, _) =>
            consent ? _FakeHome(gate: gate) : const Text('KVKK onayı'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ana sayfa açıkken bildirim hemen açılır', (tester) async {
    await pumpApp(tester, consent: true);

    gate.open(chatTap('c1'));
    await tester.pumpAndSettle();

    expect(opened, ['c1']);
    expect(find.text('sohbet c1'), findsOneWidget);
  });

  testWidgets('KVKK onayı ekranındayken basılan bildirim bekler, onaydan '
      'sonra ana sayfa açılınca bir kez açılır', (tester) async {
    await pumpApp(tester, consent: false);

    gate.open(chatTap('c1'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('KVKK onayı'), findsOneWidget);

    hasConsent.value = true;
    await tester.pumpAndSettle();
    expect(opened, ['c1']);
    expect(find.text('sohbet c1'), findsOneWidget);

    // Ana sayfa yeniden kurulsa da aynı bildirim ikinci kez açılmaz.
    navigator().pop();
    hasConsent.value = false;
    await tester.pumpAndSettle();
    hasConsent.value = true;
    await tester.pumpAndSettle();
    expect(opened, ['c1']);
  });

  testWidgets('sürüm denetimi bitmeden ya da zorunlu güncelleme ekranı '
      'varken bildirim açılmaz; engel kalkınca açılır', (tester) async {
    await pumpApp(tester, consent: false);
    // Uygulama bildirimle açıldı; güncelleme ekranı ilk denetimi bekliyor.
    gate.setUpdateBlocking(true);
    gate.open(chatTap('c1'));

    hasConsent.value = true;
    await tester.pumpAndSettle();
    expect(find.text('ana sayfa'), findsOneWidget);
    expect(opened, isEmpty);

    gate.setUpdateBlocking(false);
    await tester.pumpAndSettle();
    expect(opened, ['c1']);
    expect(find.text('sohbet c1'), findsOneWidget);

    // Ana sayfa açıkken engel gelirse sonraki bildirim de bekler.
    gate.setUpdateBlocking(true);
    gate.open(chatTap('c2'));
    await tester.pumpAndSettle();
    expect(opened, ['c1']);

    gate.setUpdateBlocking(false);
    await tester.pumpAndSettle();
    expect(opened, ['c1', 'c2']);
  });

  testWidgets('oturum kapanınca bekleyen bildirim atılır', (tester) async {
    await pumpApp(tester, consent: false);

    gate.open(chatTap('c1'));
    gate.clearPending();
    hasConsent.value = true;
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.text('ana sayfa'), findsOneWidget);
  });

  testWidgets('hazır olmadan basılan bildirimlerden yalnızca sonuncusu '
      'açılır', (tester) async {
    await pumpApp(tester, consent: false);

    gate.open(chatTap('c1'));
    gate.open(chatTap('c2'));
    hasConsent.value = true;
    await tester.pumpAndSettle();

    expect(opened, ['c2']);
  });

  testWidgets('ana sayfa yeni rotayla değişirken hazır kalır; ana sayfa '
      'kapanınca bildirim bekler', (tester) async {
    await pumpApp(tester, consent: true);

    // Girişten sonraki gibi: eski ana sayfa geçiş bitene kadar durur, sonra
    // kapanır; yenisi açık kaldıkça bildirim açılır.
    navigator().pushReplacement(MaterialPageRoute<void>(
      builder: (_) => _FakeHome(gate: gate),
    ));
    await tester.pumpAndSettle();
    gate.open(chatTap('c1'));
    await tester.pumpAndSettle();
    expect(opened, ['c1']);

    // Çıkış: ana sayfa giriş sayfasıyla değişir.
    navigator().pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const Text('giriş')),
      (route) => false,
    );
    await tester.pumpAndSettle();
    gate.open(chatTap('c2'));
    await tester.pumpAndSettle();
    expect(opened, ['c1']);
    expect(find.text('giriş'), findsOneWidget);
  });
}
