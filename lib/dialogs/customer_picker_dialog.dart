import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../utils/dialog_utils.dart';
import '../utils/search_text.dart';
import '../widgets/search_field.dart';
import '../widgets/status_note.dart';

Future<UserModel?> showCustomerPickerDialog(
  BuildContext context, {
  required List<UserModel> customers,
  String title = 'Danışan Seç',
}) {
  return showDialog<UserModel>(
    context: context,
    builder: (_) => _CustomerPickerDialog(customers: customers, title: title),
  );
}

class _CustomerPickerDialog extends StatefulWidget {
  final List<UserModel> customers;
  final String title;

  const _CustomerPickerDialog({required this.customers, required this.title});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  static const String _searchLabel = 'Danışan ara (ad soyad / e-posta)';
  static const String _emptyText = 'Aramaya uyan danışan yok.';
  static const String _cancelLabel = 'Vazgeç';
  static const double _maxWidth = 480;
  static const double _maxHeight = 520;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final List<UserModel> _sorted = List<UserModel>.of(widget.customers)
    ..sort((a, b) => compareSearchText(_nameOf(a), _nameOf(b)));
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static String _nameOf(UserModel user) =>
      user.fullName.isEmpty ? user.email : user.fullName;

  List<UserModel> get _visible {
    final List<String> queryWords = searchWordsOf(_query);
    if (queryWords.isEmpty) return _sorted;
    return _sorted
        .where((user) => matchesSearchWords(
            queryWords, searchWordsOf('${user.fullName} ${user.email}')))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final List<UserModel> visible = _visible;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: math.min(_maxWidth, screen.width * 0.9),
        height: math.min(_maxHeight, screen.height * 0.6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              controller: _searchController,
              label: _searchLabel,
              maxWidth: double.infinity,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? const StatusNote(
                      icon: Icons.person_search_outlined,
                      text: _emptyText,
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final UserModel user = visible[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              child: Text(
                                user.initials,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            title: Text(_nameOf(user)),
                            subtitle: user.fullName.isEmpty
                                ? null
                                : Text(user.email),
                            onTap: () =>
                                DialogUtils.closeOwnRoute(context, user),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => DialogUtils.closeOwnRoute(context),
          child: const Text(_cancelLabel),
        ),
      ],
    );
  }
}
