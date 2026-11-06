import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/chat/chat_input_keys.dart';

void main() {
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

  Future<({List<String> sent, ValueNotifier<String?> reply})> pumpInput(
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
          body: Focus(
            onKeyEvent: (node, event) {
              switch (chatInputKeyAction(
                event,
                platform: defaultTargetPlatform,
                isShiftPressed: HardwareKeyboard.instance.isShiftPressed,
                isComposing: controller.value.composing.isValid,
                hasReply: reply.value != null,
              )) {
                case ChatInputKeyAction.send:
                  sent.add(controller.text);
                  return KeyEventResult.handled;
                case ChatInputKeyAction.cancelReply:
                  reply.value = null;
                  return KeyEventResult.handled;
                case ChatInputKeyAction.none:
                  return KeyEventResult.ignored;
              }
            },
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    return (sent: sent, reply: reply);
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
}
