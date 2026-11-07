import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ChatInputKeyAction {
  send,

  cancelReply,

  none,
}

bool chatEnterSendsOn(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return false;
  }
}

ChatInputKeyAction chatInputKeyAction(
  KeyEvent event, {
  required TargetPlatform platform,
  required bool isShiftPressed,
  required bool isComposing,
  required bool hasReply,
}) {
  if (!chatEnterSendsOn(platform) || event is! KeyDownEvent) {
    return ChatInputKeyAction.none;
  }
  if (event.logicalKey == LogicalKeyboardKey.escape && hasReply) {
    return ChatInputKeyAction.cancelReply;
  }
  final bool isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
  if (!isEnter || isShiftPressed || isComposing) {
    return ChatInputKeyAction.none;
  }
  return ChatInputKeyAction.send;
}

class ChatInputKeyHandler extends StatelessWidget {
  const ChatInputKeyHandler({
    super.key,
    required this.controller,
    required this.hasReply,
    required this.onSend,
    required this.onCancelReply,
    required this.child,
  });

  final TextEditingController controller;
  final bool Function() hasReply;
  final VoidCallback onSend;
  final VoidCallback onCancelReply;
  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final ChatInputKeyAction action = chatInputKeyAction(
      event,
      platform: defaultTargetPlatform,
      isShiftPressed: HardwareKeyboard.instance.isShiftPressed,
      isComposing: controller.value.composing.isValid,
      hasReply: hasReply(),
    );
    switch (action) {
      case ChatInputKeyAction.send:
        onSend();
        return KeyEventResult.handled;
      case ChatInputKeyAction.cancelReply:
        onCancelReply();
        return KeyEventResult.handled;
      case ChatInputKeyAction.none:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(onKeyEvent: _onKeyEvent, child: child);
  }
}
