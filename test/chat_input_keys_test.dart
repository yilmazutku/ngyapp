import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/ios_app_on_mac.dart';
import 'package:ngy_app/widgets/chat/chat_input_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel platformInfo = MethodChannel('ngy_app/platform_info');

  void mockPlatformInfo(Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformInfo, handler);
  }

  Future<void> setIosAppOnMac(bool value) async {
    mockPlatformInfo((MethodCall call) async => value);
    await loadIosAppOnMac();
    mockPlatformInfo(null);
  }

  const Set<TargetPlatform> sendingPlatforms = {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.iOS,
  };

  test('Enter gönderen platformlar', () {
    for (final TargetPlatform platform in TargetPlatform.values) {
      expect(
        chatEnterSendsOn(platform),
        sendingPlatforms.contains(platform),
        reason: '$platform',
      );
    }
  });

  test('sayısal tuş takımındaki Enter da gönderir', () {
    const KeyDownEvent numpadEnter = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.numpadEnter,
      logicalKey: LogicalKeyboardKey.numpadEnter,
      timeStamp: Duration.zero,
    );
    for (final TargetPlatform platform in TargetPlatform.values) {
      expect(
        chatInputKeyAction(
          numpadEnter,
          platform: platform,
          isShiftPressed: false,
          isComposing: false,
          hasReply: false,
        ),
        sendingPlatforms.contains(platform)
            ? ChatInputKeyAction.send
            : ChatInputKeyAction.none,
        reason: '$platform',
      );
    }
  });

  test('harf birleştirme sürerken Enter göndermez', () {
    const KeyDownEvent enter = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    for (final TargetPlatform platform in sendingPlatforms) {
      expect(
        chatInputKeyAction(
          enter,
          platform: platform,
          isShiftPressed: false,
          isComposing: true,
          hasReply: false,
        ),
        ChatInputKeyAction.none,
        reason: '$platform',
      );
    }
  });

  Future<
      ({
        List<String> sent,
        ValueNotifier<String?> reply,
        TextEditingController controller,
        FocusNode focusNode,
      })> pumpInput(
    WidgetTester tester,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: 'merhaba');
    final FocusNode focusNode = FocusNode();
    final ValueNotifier<String?> reply = ValueNotifier<String?>('yanıt');
    final List<String> sent = [];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(reply.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputKeyHandler(
            controller: controller,
            hasReply: () => reply.value != null,
            onSend: () => sent.add(controller.text),
            onCancelReply: () => reply.value = null,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: isIosAppOnMac ? TextInputAction.send : null,
              onSubmitted:
                  isIosAppOnMac ? (_) => sent.add(controller.text) : null,
              onEditingComplete: isIosAppOnMac ? () {} : null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    return (
      sent: sent,
      reply: reply,
      controller: controller,
      focusNode: focusNode,
    );
  }

  testWidgets('Enter mesajı gönderir', (tester) async {
    final input = await pumpInput(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    final bool sends = sendingPlatforms.contains(defaultTargetPlatform);
    expect(input.sent, sends ? ['merhaba'] : isEmpty);
  }, variant: TargetPlatformVariant.all());

  testWidgets('Shift+Enter göndermez', (tester) async {
    final input = await pumpInput(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(input.sent, isEmpty);
  }, variant: TargetPlatformVariant.all());

  testWidgets('Esc yazılan yanıtı iptal eder', (tester) async {
    final input = await pumpInput(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    final bool handlesKeys = sendingPlatforms.contains(defaultTargetPlatform);
    expect(input.reply.value, handlesKeys ? isNull : 'yanıt');
    expect(input.sent, isEmpty);
  }, variant: TargetPlatformVariant.all());

  testWidgets('boş harf birleştirme aralığı Enter\'ı engellemez',
      (tester) async {
    final input = await pumpInput(tester);
    input.controller.value = const TextEditingValue(
      text: 'merhaba',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange.collapsed(7),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    final bool sends = sendingPlatforms.contains(defaultTargetPlatform);
    expect(input.sent, sends ? ['merhaba'] : isEmpty);
  }, variant: TargetPlatformVariant.all());

  testWidgets('kutuda harf birleştirilirken Enter göndermez', (tester) async {
    final input = await pumpInput(tester);
    input.controller.value = const TextEditingValue(
      text: 'merhaba',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 5, end: 7),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(input.sent, isEmpty);
  }, variant: TargetPlatformVariant.all());

  Future<FocusNode> pumpComposer(
    WidgetTester tester, {
    required bool sendInTapRegion,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: 'merhaba');
    final FocusNode focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final Widget send = IconButton(
      icon: const Icon(Icons.send_rounded),
      onPressed: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: TextField(controller: controller, focusNode: focusNode),
              ),
              if (sendInTapRegion) TextFieldTapRegion(child: send) else send,
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
    await tester.pump();
    return focusNode;
  }

  testWidgets('fareyle gönder düğmesine basınca kutu odakta kalır',
      (tester) async {
    final FocusNode focusNode =
        await pumpComposer(tester, sendInTapRegion: true);
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.send_rounded),
        kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.all());

  testWidgets('kutunun bölgesi dışındaki düğmeye fareyle basmak odağı alır',
      (tester) async {
    final FocusNode focusNode =
        await pumpComposer(tester, sendInTapRegion: false);
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.send_rounded),
        kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  }, variant: TargetPlatformVariant.all());

  group('Mac\'teki iOS uygulaması', () {
    tearDown(() {
      mockPlatformInfo(null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('yalnızca iOS\'ta ve yerel taraf öyle diyorsa Mac sayılır', () async {
      mockPlatformInfo((MethodCall call) async =>
          call.method == 'isIosAppOnMac' ? true : null);
      for (final TargetPlatform platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        await loadIosAppOnMac();
        expect(isIosAppOnMac, platform == TargetPlatform.iOS,
            reason: '$platform');
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockPlatformInfo((MethodCall call) async => false);
      await loadIosAppOnMac();
      expect(isIosAppOnMac, isFalse);
    });

    test('yerel taraf yanıt vermezse Mac sayılmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockPlatformInfo(
          (MethodCall call) async => throw PlatformException(code: 'hata'));
      await loadIosAppOnMac();
      expect(isIosAppOnMac, isFalse);

      mockPlatformInfo(null);
      await loadIosAppOnMac();
      expect(isIosAppOnMac, isFalse);
    });
  });

  testWidgets(
      'Mac\'teki iOS uygulamasında Return "gönder" eylemiyle gönderir, '
      'kutu odakta kalır', (tester) async {
    await setIosAppOnMac(true);
    addTearDown(() => setIosAppOnMac(false));
    final input = await pumpInput(tester);
    expect(tester.testTextInput.setClientArgs?['inputAction'],
        'TextInputAction.send');

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(input.sent, ['merhaba']);
    expect(input.focusNode.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Mac dışında Return yeni satır eylemi göndermez',
      (tester) async {
    final input = await pumpInput(tester);
    expect(tester.testTextInput.setClientArgs?['inputAction'],
        'TextInputAction.newline');

    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();

    expect(input.sent, isEmpty);
    expect(input.focusNode.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.all());
}
