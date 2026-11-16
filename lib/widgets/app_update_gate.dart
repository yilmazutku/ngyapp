import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/app_update_info.dart';
import '../providers/app_update_provider.dart';
import '../services/fcm_service.dart';
import '../utils/dialog_utils.dart';

/// Runs the "is there a newer version?" check once the first frame is on
/// screen and, when there is one, sends the user to the App Store or Google
/// Play.
///
/// [child] is built straight away and stays in the tree the whole time, even
/// while a mandatory update is blocking the screen. That is what keeps the
/// check clear of the login flow: Firebase restores the saved session
/// underneath at its usual speed, so the user is never asked to sign in again
/// because of the version check, and the check never has to be skipped to keep
/// a session alive. The two are simply independent.
///
/// The check itself runs on every launch regardless of who is signed in, or
/// whether anyone is.
///
/// **Mobile only.** On Windows and macOS this widget is a plain pass-through:
/// it returns [child] untouched, registers no lifecycle observer and schedules
/// no check. Those builds are installed by hand and have no store listing, so
/// there is nowhere to send the user. The guard lives here as well as in
/// [AppUpdateProvider.checkForUpdate] so that no desktop code path can reach
/// a prompt even if the widget is reused elsewhere.
class AppUpdateGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  /// Set while a mandatory update is pending; painted over [widget.child].
  AppUpdateInfo? _blockingUpdate;

  bool _storeOpenFailed = false;

  /// True between opening and closing the optional-update dialog, so a second
  /// check cannot stack another one on top of it.
  bool _promptOpen = false;

  /// True while a check is in flight, so repeated resumes don't pile up reads.
  bool _checkRunning = false;

  @override
  void initState() {
    super.initState();
    // Desktop: nothing to observe and nothing to check.
    if (!AppUpdateProvider.isSupported) return;
    // İlk denetim bitene ve zorunlu güncelleme ekranı kalkana kadar bildirim
    // sayfa açmaz: açsaydı sayfa güncelleme ekranının üstünde kalırdı.
    FcmService().setUpdateBlocking(true);
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: the app is already on screen and the auth stream
    // is already running, so nothing waits on this.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    // removeObserver is a no-op when it was never added, but keeping the guard
    // symmetric with initState makes the desktop path obvious.
    if (AppUpdateProvider.isSupported) {
      WidgetsBinding.instance.removeObserver(this);
      // Engel bu ekranla birlikte kalkar. Bekleyen bildirim ağaç kilitliyken
      // (dispose sırasında) sayfa açmasın diye kareden sonra.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => FcmService().setUpdateBlocking(false));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Only while the user is being held on the blocking screen. Coming back
    // from the store, or from an admin correcting the configuration, should
    // release them without needing a restart.
    if (state == AppLifecycleState.resumed && _blockingUpdate != null) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checkRunning || !mounted) return;
    _checkRunning = true;
    try {
      final provider = Provider.of<AppUpdateProvider>(context, listen: false);
      final info = await provider.checkForUpdate();
      if (!mounted) return;

      if (info != null && info.isForced) {
        setState(() => _blockingUpdate = info);
        return;
      }

      // Nothing mandatory any more: let a previously blocked user through.
      if (_blockingUpdate != null) {
        setState(() {
          _blockingUpdate = null;
          _storeOpenFailed = false;
        });
      }
      try {
        if (info != null) {
          await _promptOptionalUpdate(info);
        }
      } finally {
        if (mounted) FcmService().setUpdateBlocking(false);
      }
    } finally {
      _checkRunning = false;
    }
  }

  /// Offers the update but lets the user carry on with the current version.
  Future<void> _promptOptionalUpdate(AppUpdateInfo info) async {
    final BuildContext? navigatorContext = widget.navigatorKey.currentContext;
    if (_promptOpen || navigatorContext == null) return;
    _promptOpen = true;
    try {
      final bool accepted = await DialogUtils.openConfirm(
        navigatorContext,
        title: AppUpdateConstants.optionalTitle,
        message: info.userMessage,
        confirmText: AppUpdateConstants.updateButton,
        cancelText: AppUpdateConstants.laterButton,
      );
      if (!accepted) return;
      final bool opened = await _openStore(info);
      if (opened || !navigatorContext.mounted) return;
      await DialogUtils.openError(
        navigatorContext,
        title: AppUpdateConstants.storeErrorTitle,
        message: AppUpdateConstants.storeErrorMessage,
      );
    } finally {
      _promptOpen = false;
    }
  }

  Future<void> _openStoreFromBlockingScreen(AppUpdateInfo info) async {
    final bool opened = await _openStore(info);
    if (!mounted) return;
    setState(() => _storeOpenFailed = !opened);
  }

  Future<bool> _openStore(AppUpdateInfo info) =>
      _launchFirstReachable([info.storeUri, info.webStoreUri]);

  /// Tries each address in turn: the native store scheme opens the store app
  /// directly, the https listing covers devices that cannot handle it.
  Future<bool> _launchFirstReachable(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // This address is unusable on this device; fall through to the next.
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppUpdateProvider.isSupported) return widget.child;

    final blocking = _blockingUpdate;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(excluding: blocking != null, child: widget.child),
        if (blocking != null) ...[
          // Swallows taps aimed at the app underneath, which keeps running so
          // the session finishes restoring while the user updates.
          const ModalBarrier(dismissible: false),
          _ForcedUpdateView(
            info: blocking,
            storeOpenFailed: _storeOpenFailed,
            onUpdate: () => _openStoreFromBlockingScreen(blocking),
          ),
        ],
      ],
    );
  }
}

/// Full-screen notice shown when the running version is no longer supported.
class _ForcedUpdateView extends StatelessWidget {
  /// Widest the content grows to, so the text keeps a readable line length on
  /// tablets and desktop-sized windows.
  static const double _maxContentWidth = 420;

  /// Size of the decorative header icon.
  static const double _iconSize = 64;

  final AppUpdateInfo info;
  final bool storeOpenFailed;
  final VoidCallback onUpdate;

  const _ForcedUpdateView({
    required this.info,
    required this.storeOpenFailed,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: _maxContentWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update,
                    size: _iconSize,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppUpdateConstants.forcedTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    info.userMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onUpdate,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(AppUpdateConstants.updateButton),
                    ),
                  ),
                  if (storeOpenFailed) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppUpdateConstants.storeErrorMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
