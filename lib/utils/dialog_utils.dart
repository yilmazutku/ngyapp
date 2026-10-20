import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DialogUtils {
  /// Blank lines prefixed to an attention notice so its text does not start
  /// where the eye expects an ordinary dialog body.
  static const String _attentionLeadIn = '\n\n\n';

  /// How much larger than the theme's own text an attention notice is drawn.
  static const double _attentionTitleScale = 1.25;
  static const double _attentionMessageScale = 1.45;

  /// Turkish-aware upper case: the default mapping turns "i" into "I" and
  /// leaves "ı" alone, which reads wrong in Turkish.
  static String _upperTr(String text) =>
      text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static TextStyle _attentionTitleStyle(BuildContext context) {
    final TextStyle base =
        Theme.of(context).textTheme.titleLarge ?? const TextStyle();
    return base.copyWith(
      color: Colors.red,
      fontWeight: FontWeight.bold,
      fontSize: (base.fontSize ?? 20) * _attentionTitleScale,
    );
  }

  static TextStyle _attentionMessageStyle(BuildContext context) {
    final TextStyle base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      color: Colors.red,
      fontWeight: FontWeight.bold,
      fontSize: (base.fontSize ?? 14) * _attentionMessageScale,
      height: 1.4,
    );
  }

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
          style: _attentionTitleStyle(context),
        ),
        content: SingleChildScrollView(
          child: Text(
            '$_attentionLeadIn${_upperTr(message)}',
            style: _attentionMessageStyle(context),
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

  /// Attention-styled counterpart of [openConfirm]: same red, bold, enlarged
  /// notice as [openAttentionInfo], but the admin has to answer it.
  static Future<bool> openAttentionConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Evet',
    String cancelText = 'Hayır',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _upperTr(title),
          style: _attentionTitleStyle(context),
        ),
        content: SingleChildScrollView(
          child: Text(
            '$_attentionLeadIn${_upperTr(message)}',
            style: _attentionMessageStyle(context),
          ),
        ),
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

  /// İş sürerken ilerleme çubuğu ve [message], iş bitince onay ikonu ve
  /// [doneMessage] gösteren, [doneDuration] sonra kendiliğinden kapanan
  /// diyalog. İş hata verirse diyalog hemen kapanır; hatayı çağıran,
  /// [task]'ı bekleyerek yakalar ve kendi hata diyaloğunu gösterir. Diyalog
  /// kapanınca döner.
  static Future<void> openLoadingUntilDone(
    BuildContext context, {
    required String message,
    required String doneMessage,
    required Future<void> task,
    Duration doneDuration = const Duration(seconds: 1),
  }) async {
    // Sonuç diyalog açılmadan önce dinlenir: iş hemen hata verse de hata
    // yakalanmamış sayılmaz.
    final ValueNotifier<bool?> succeeded = ValueNotifier<bool?>(null);
    bool closed = false;
    task.then<void>(
      (_) {
        if (!closed) succeeded.value = true;
      },
      onError: (Object e) {
        if (!closed) succeeded.value = false;
      },
    );
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => _LoadingUntilDoneDialog(
          message: message,
          doneMessage: doneMessage,
          succeeded: succeeded,
          doneDuration: doneDuration,
        ),
      );
    } finally {
      closed = true;
      succeeded.dispose();
    }
  }
}

class _LoadingUntilDoneDialog extends StatefulWidget {
  final String message;
  final String doneMessage;

  /// İş sürerken null, bitince true, hata verince false.
  final ValueListenable<bool?> succeeded;
  final Duration doneDuration;

  const _LoadingUntilDoneDialog({
    required this.message,
    required this.doneMessage,
    required this.succeeded,
    required this.doneDuration,
  });

  @override
  State<_LoadingUntilDoneDialog> createState() =>
      _LoadingUntilDoneDialogState();
}

class _LoadingUntilDoneDialogState extends State<_LoadingUntilDoneDialog> {
  static const double _doneIconSize = 40;
  static const Duration _switchDuration = Duration(milliseconds: 200);

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.succeeded.addListener(_onResult);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onResult());
  }

  @override
  void dispose() {
    widget.succeeded.removeListener(_onResult);
    super.dispose();
  }

  Future<void> _onResult() async {
    final bool? succeeded = widget.succeeded.value;
    if (!mounted || succeeded == null || _closing) return;
    _closing = true;
    final NavigatorState navigator = Navigator.of(context);
    if (succeeded) {
      setState(() {});
      await Future<void>.delayed(widget.doneDuration);
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool done = widget.succeeded.value == true;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: AnimatedSwitcher(
          duration: _switchDuration,
          child: done
              ? Column(
                  key: const ValueKey<bool>(true),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: _doneIconSize,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.doneMessage,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey<bool>(false),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.message),
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
