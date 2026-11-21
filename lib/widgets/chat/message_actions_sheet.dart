// lib/widgets/chat/message_actions_sheet.dart
import 'package:flutter/material.dart';

import '../../utils/menu_utils.dart';
import '../reaction_picker.dart';

const String kMessageReactLabel = 'İfade Bırak';

final Object _reactMenuValue = Object();

bool messageMenuOnRightClick(
  TargetPlatform platform, {
  required bool iosAppOnMac,
}) {
  switch (platform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.iOS:
      return iosAppOnMac;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Bir mesaj üzerindeki işlemler. Dokunmatikte uzun basınca açılan menü
/// ([showMessageActionsSheet]) ve sağ tık menüsü ([showMessageMenuAt]) aynı
/// adları kullanır.
enum MessageAction {
  reply('Yanıtla', Icons.reply),
  copy('Mesajı Kopyala', Icons.copy),
  showInMealPhotos("Öğün Fotoğrafları'nda göster", Icons.photo_library_outlined),
  deletePhoto('Fotoğrafı Sil', Icons.delete_outline);

  const MessageAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Mesaj menüsünde seçilen: bir ifade ya da bir işlem.
class MessageActionChoice {
  final String? emoji;
  final MessageAction? action;

  const MessageActionChoice.emoji(String this.emoji) : action = null;
  const MessageActionChoice.action(MessageAction this.action) : emoji = null;
}

/// Uzun basınca açılan mesaj menüsü: [canReact] ise üstte hızlı ifadeler
/// (bırakanın mevcut ifadesi işaretli, "…" tüm ifadeleri açar), altında
/// [actions]. Seçilen ifade ya da işlem döner; kapatılırsa null.
Future<MessageActionChoice?> showMessageActionsSheet(
  BuildContext context, {
  required bool canReact,
  required List<MessageAction> actions,
  String? currentEmoji,
}) async {
  bool showAllReactions = false;

  final MessageActionChoice? choice =
      await showModalBottomSheet<MessageActionChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canReact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Center(
                child: QuickReactionRow(
                  currentEmoji: currentEmoji,
                  onSelected: (emoji) => Navigator.of(sheetContext)
                      .pop(MessageActionChoice.emoji(emoji)),
                  onShowAll: () {
                    showAllReactions = true;
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ),
            ),
          if (canReact && actions.isNotEmpty) const Divider(height: 1),
          for (final MessageAction action in actions)
            ListTile(
              leading: Icon(
                action.icon,
                color: action == MessageAction.deletePhoto
                    ? Theme.of(sheetContext).colorScheme.error
                    : null,
              ),
              title: Text(
                action.label,
                style: action == MessageAction.deletePhoto
                    ? TextStyle(color: Theme.of(sheetContext).colorScheme.error)
                    : null,
              ),
              onTap: () => Navigator.of(sheetContext)
                  .pop(MessageActionChoice.action(action)),
            ),
        ],
      ),
    ),
  );

  if (!showAllReactions) return choice;
  if (!context.mounted) return null;
  final String? emoji =
      await showAllReactionsSheet(context, currentEmoji: currentEmoji);
  return emoji == null ? null : MessageActionChoice.emoji(emoji);
}

Future<MessageActionChoice?> showMessageMenuAt(
  BuildContext context, {
  required Offset globalPosition,
  required bool canReact,
  required List<MessageAction> actions,
  String? currentEmoji,
}) async {
  final Object? choice = await showMenuAt<Object>(
    context,
    globalPosition: globalPosition,
    items: [
      for (final MessageAction action in actions)
        if (action == MessageAction.reply)
          PopupMenuItem<Object>(value: action, child: Text(action.label)),
      if (canReact)
        PopupMenuItem<Object>(
          value: _reactMenuValue,
          child: const Text(kMessageReactLabel),
        ),
      for (final MessageAction action in actions)
        if (action != MessageAction.reply)
          PopupMenuItem<Object>(value: action, child: Text(action.label)),
    ],
  );
  if (choice is MessageAction) return MessageActionChoice.action(choice);
  if (choice != _reactMenuValue || !context.mounted) return null;

  final String? emoji = await showReactionPicker(
    context,
    globalPosition: globalPosition,
    currentEmoji: currentEmoji,
  );
  return emoji == null ? null : MessageActionChoice.emoji(emoji);
}
