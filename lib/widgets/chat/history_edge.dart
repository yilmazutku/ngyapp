// lib/widgets/chat/history_edge.dart
import 'package:flutter/material.dart';

class HistoryEdge extends StatelessWidget {
  final bool _loading;
  final String? _retryText;
  final VoidCallback? _onRetry;
  final String? _note;

  const HistoryEdge.loading({super.key})
      : _loading = true,
        _retryText = null,
        _onRetry = null,
        _note = null;

  const HistoryEdge.retry({
    super.key,
    required String text,
    required VoidCallback onRetry,
  })  : _loading = false,
        _retryText = text,
        _onRetry = onRetry,
        _note = null;

  const HistoryEdge.note(String text, {super.key})
      : _loading = false,
        _retryText = null,
        _onRetry = null,
        _note = text;

  @override
  Widget build(BuildContext context) {
    final String? retryText = _retryText;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (retryText != null) {
      return Center(
        child: TextButton.icon(
          onPressed: _onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(retryText, textAlign: TextAlign.center),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          _note ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
