import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/app_update_info.dart';
import '../models/logger.dart';
import '../providers/app_update_provider.dart';
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
class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  final Logger _logger = Logger.forClass(AppUpdateGate);

  /// Set while a mandatory update is pending; painted over [widget.child].
  AppUpdateInfo? _blockingUpdate;

  /// True between opening and closing the optional-update dialog, so a second
  /// check cannot stack another one on top of it.
  bool _promptOpen = false;

  /// True while a check is in flight, so repeated resumes don't pile up reads.
  bool _checkRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: the app is already on screen and the auth stream
    // is already running, so nothing waits on this.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        setState(() => _blockingUpdate = null);
      }
      if (info != null) {
        await _promptOptionalUpdate(info);
      }
    } finally {
      _checkRunning = false;
    }
  }

  /// Offers the update but lets the user carry on with the current version.
  Future<void> _promptOptionalUpdate(AppUpdateInfo info) async {
    if (_promptOpen || !mounted) return;
    _promptOpen = true;
    try {
      final accepted = await DialogUtils.openConfirm(
        context,
        title: AppUpdateConstants.optionalTitle,
        message: info.userMessage,
        confirmText: AppUpdateConstants.updateButton,
        cancelText: AppUpdateConstants.laterButton,
      );
      if (!mounted) return;
      if (!accepted) return;
      await _openStore(info);
    } finally {
      _promptOpen = false;
    }
  }

  Future<void> _openStore(AppUpdateInfo info) async {
    final opened =
        await _launchFirstReachable([info.storeUri, info.webStoreUri]);
    if (!mounted) return;
    if (opened) return;
    await DialogUtils.openError(
      context,
      title: AppUpdateConstants.storeErrorTitle,
      message: AppUpdateConstants.storeErrorMessage,
    );
  }

  /// Tries each address in turn: the native store scheme opens the store app
  /// directly, the https listing covers devices that cannot handle it.
  Future<bool> _launchFirstReachable(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        _logger.warn('Could not open store address {}: {}', [uri, e]);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _blockingUpdate;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (blocking != null) ...[
          // Swallows taps aimed at the app underneath, which keeps running so
          // the session finishes restoring while the user updates.
          const ModalBarrier(dismissible: false),
          _ForcedUpdateView(
            info: blocking,
            onUpdate: () => _openStore(blocking),
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
  final VoidCallback onUpdate;

  const _ForcedUpdateView({required this.info, required this.onUpdate});

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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
