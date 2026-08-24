import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DialogUtils {
  /// Blank lines prefixed to an attention notice so its text does not start
  /// where the eye expects an ordinary dialog body.
  static const String _attentionLeadIn = '\n\n\n';

  /// Turkish-aware upper case: the default mapping turns "i" into "I" and
  /// leaves "ı" alone, which reads wrong in Turkish.
  static String _upperTr(String text) =>
      text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// Shows a notice the admin must not skim past: the whole message in red,
  /// bold, upper case, and pushed down by a few blank lines.
  ///
  /// Used for the package-side consequences of an action (e.g. a postponement
  /// right that was not given back), where quietly logging the change would
  /// leave the admin with wrong figures and no idea why.
  static Future<void> openAttentionInfo(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Anladım',
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _upperTr(title),
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            '$_attentionLeadIn${_upperTr(message)}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog with a message and an OK button
  /// Closes the current route, then shows an info dialog on a context that
  /// survives that pop.
  ///
  /// Calling [openInfo] with the popped route's own context looks up an
  /// ancestor of a deactivated element. In debug that throws; in both modes the
  /// dialog that was supposed to confirm the save simply never appeared. The
  /// navigator's own context outlives the route, so the message still lands.
  static Future<void> popThenInfo(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    navigator.pop();
    await openInfo(hostContext, title: title, message: message);
  }

  static Future<void> openInfo(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Tamam',
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog with a message and returns the result (true/false)
  static Future<bool> openConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Evet',
    String cancelText = 'Hayır',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result == true;
  }

  /// Shows an error dialog with a message and an OK button
  static Future<void> openError(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Tamam',
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Shows a loading dialog with a message
  /// Prevents user interaction during loading operations
  static Future<void> openLoading(
    BuildContext context, {
    required String message,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  /// Shows a non-dismissible loading dialog whose message updates live via
  /// [messageListenable]. Useful for multi-step / bulk operations that want to
  /// surface progress (e.g. "Yükleniyor (2/5)...").
  static Future<void> openLoadingProgress(
    BuildContext context, {
    required ValueListenable<String> messageListenable,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: messageListenable,
                  builder: (_, message, __) => Text(message),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
