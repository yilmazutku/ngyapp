import 'dart:async';
import 'package:flutter/material.dart';

/// Default timeout for loading operations (10 seconds)
const Duration kLoadingTimeout = Duration(seconds: 10);

/// A simple loading overlay widget that blocks user interaction
/// while showing a centered spinner with optional message.
/// 
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     YourContent(),
///     if (_isLoading) const LoadingOverlay(),
///   ],
/// )
/// ```
class LoadingOverlay extends StatelessWidget {
  final String? message;
  final Color? barrierColor;

  const LoadingOverlay({
    super.key,
    this.message,
    this.barrierColor,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: barrierColor ?? Colors.black38,
        child: Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      message!,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
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

/// Mixin to add loading state with automatic timeout to StatefulWidgets.
/// 
/// Usage:
/// ```dart
/// class _MyDialogState extends State<MyDialog> with LoadingStateMixin {
///   Future<void> _doSomething() async {
///     startLoading();
///     try {
///       await someAsyncOperation();
///     } finally {
///       stopLoading();
///     }
///   }
///   
///   @override
///   Widget build(BuildContext context) {
///     return Stack(
///       children: [
///         MyContent(),
///         if (isLoading) const LoadingOverlay(),
///       ],
///     );
///   }
/// }
/// ```
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  Timer? _loadingTimeoutTimer;

  bool get isLoading => _isLoading;

  /// Start loading state with automatic timeout.
  /// After [timeout] (default 10 seconds), loading will auto-stop.
  void startLoading({Duration timeout = kLoadingTimeout}) {
    _loadingTimeoutTimer?.cancel();
    setState(() => _isLoading = true);
    
    _loadingTimeoutTimer = Timer(timeout, () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  /// Stop loading state and cancel timeout timer.
  void stopLoading() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _loadingTimeoutTimer?.cancel();
    super.dispose();
  }
}

