import 'package:flutter/services.dart';

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
