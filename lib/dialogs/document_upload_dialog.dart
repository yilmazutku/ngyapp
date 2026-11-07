import 'package:flutter/material.dart';

import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/blood_test_reminder_preview.dart';

class DocumentUploadOptions {
  final DateTime? bloodTestDate;
  final bool wantsReminder;

  const DocumentUploadOptions({this.bloodTestDate, this.wantsReminder = false});

  bool get isBloodTest => bloodTestDate != null;
}

Future<DocumentUploadOptions?> showDocumentUploadDialog(
  BuildContext context, {
  required List<String> fileNames,
}) {
  return showDialog<DocumentUploadOptions>(
    context: context,
    builder: (_) => _DocumentUploadDialog(fileNames: fileNames),
  );
}

class _DocumentUploadDialog extends StatefulWidget {
  final List<String> fileNames;

  const _DocumentUploadDialog({required this.fileNames});

  @override
  State<_DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<_DocumentUploadDialog> {
  static const String _title = 'Doküman Yükle';
  static const String _bloodTestLabel = 'Bu bir kan tahlili mi?';
  static const String _testDateLabel = 'Tahlilin Yapıldığı Tarih';
  static const String _reminderLabel =
      '3 ay sonra hatırlatıcı istiyor musunuz?';
  static const String _uploadLabel = 'Yükle';
  static const String _cancelLabel = 'İptal';

  static const int _maxListedFiles = 4;

  bool _isBloodTest = false;
  DateTime _testDate = DateUtils.dateOnly(DateTime.now());
  bool _wantsReminder = true;

  Future<void> _pickTestDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _testDate,
      firstDate: DateTime(2015),
      lastDate: now,
      helpText: _testDateLabel,
    );
    if (picked != null && mounted) setState(() => _testDate = picked);
  }

  void _submit() {
    DialogUtils.closeOwnRoute(
      context,
      DocumentUploadOptions(
        bloodTestDate: _isBloodTest ? _testDate : null,
        wantsReminder: _isBloodTest && _wantsReminder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text(_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFileList(theme),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _isBloodTest,
                title: const Text(_bloodTestLabel),
                secondary: Icon(
                  Icons.bloodtype_rounded,
                  color: _isBloodTest ? Colors.red.shade600 : Colors.grey,
                ),
                onChanged: (value) =>
                    setState(() => _isBloodTest = value ?? false),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _isBloodTest
                    ? _buildBloodTestSection(theme)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => DialogUtils.closeOwnRoute(context),
          child: const Text(_cancelLabel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text(_uploadLabel),
        ),
      ],
    );
  }

  Widget _buildFileList(ThemeData theme) {
    final List<String> files = widget.fileNames;
    final int hidden = files.length - _maxListedFiles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            files.length == 1 ? '1 dosya seçildi' : '${files.length} dosya seçildi',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          for (final String name in files.take(_maxListedFiles))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    name.toLowerCase().endsWith('.pdf')
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    size: 18,
                    color: name.toLowerCase().endsWith('.pdf')
                        ? Colors.red.shade400
                        : Colors.blue.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (hidden > 0)
            Text(
              '+$hidden dosya daha',
              style: TextStyle(color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  Widget _buildBloodTestSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(_testDateLabel),
            subtitle: Text(
              DateFormatter.formatLongDate(_testDate),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickTestDate,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _wantsReminder,
            title: const Text(_reminderLabel),
            secondary: Icon(
              Icons.alarm_rounded,
              color: _wantsReminder ? theme.colorScheme.primary : Colors.grey,
            ),
            onChanged: (value) =>
                setState(() => _wantsReminder = value ?? false),
          ),
          if (_wantsReminder) BloodTestReminderPreview(testDate: _testDate),
        ],
      ),
    );
  }
}
