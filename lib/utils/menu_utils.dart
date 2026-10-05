// lib/utils/menu_utils.dart
import 'package:flutter/material.dart';

Future<T?> showMenuAt<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) async {
  final RenderObject? overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return null;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}
