import 'package:flutter/material.dart';

/// A widget that handles different loading states and error states with consistent styling
class LoadingErrorWidget extends StatelessWidget {
  /// Whether the content is currently loading
  final bool isLoading;

  /// Optional error message to display
  final String? errorMessage;

  /// Optional icon to show with the error message
  final IconData errorIcon;

  /// Optional retry callback when an error occurs
  final VoidCallback? onRetry;

  /// Optional custom widget to show when loading
  final Widget? loadingWidget;

  /// Creates a widget that shows appropriate UI for loading and error states
  const LoadingErrorWidget({
    super.key,
    this.isLoading = false,
    this.errorMessage,
    this.errorIcon = Icons.error_outline,
    this.onRetry,
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingWidget ??
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Yükleniyor...',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              errorIcon,
              size: 48,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // If not loading and no error, return an empty widget
    return const SizedBox.shrink();
  }
}
