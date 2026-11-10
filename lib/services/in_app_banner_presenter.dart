import 'dart:async';

import 'package:flutter/widgets.dart';

class InAppBannerPresenter {
  InAppBannerPresenter({required this.displayDuration});

  final Duration displayDuration;

  OverlayEntry? _entry;
  Timer? _timer;

  void show(OverlayState overlay, WidgetBuilder builder) {
    dismiss();
    final OverlayEntry entry = OverlayEntry(builder: builder);
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(displayDuration, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
