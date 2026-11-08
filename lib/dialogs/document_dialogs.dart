import 'package:flutter/material.dart';

import '../models/test_attachment.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/blood_test_reminder_preview.dart';
import '../widgets/inline_note.dart';

class DocumentEdit {
  const DocumentEdit({required this.bloodTest, required this.applyToSameDate});

  final BloodTestInfo? bloodTest;
  final bool applyToSameDate;
}

Future<BloodTestInfo?> showBloodTestUploadDialog(
  BuildContext context, {
  required List<String> fileNames,
  List<DateTime> knownTestDates = const [],
}) {
  return showDialog<BloodTestInfo>(
    context: context,
    builder: (_) => _BloodTestUploadDialog(
      fileNames: fileNames,
      knownTestDates: knownTestDates,
    ),
  );
}

Future<DocumentEdit?> showDocumentEditDialog(
  BuildContext context, {
  required TestAttachment file,
  int sameDateCount = 0,
  List<DateTime> knownTestDates = const [],
}) {
  return showDialog<DocumentEdit>(
    context: context,
    builder: (_) => _DocumentEditDialog(
      file: file,
      sameDateCount: sameDateCount,
      knownTestDates: knownTestDates,
    ),
  );
}

class _BloodTestUploadDialog extends StatefulWidget {
  const _BloodTestUploadDialog({
    required this.fileNames,
    required this.knownTestDates,
  });

  final List<String> fileNames;
  final List<DateTime> knownTestDates;

  @override
  State<_BloodTestUploadDialog> createState() => _BloodTestUploadDialogState();
}

class _BloodTestUploadDialogState extends State<_BloodTestUploadDialog> {
  static const String _title = 'Kan Tahlili Yükle';
  static const String _uploadLabel = 'Yükle';
  static const String _cancelLabel = 'İptal';

  DateTime? _testDate;
  bool _wantsReminder = true;

  @override
  Widget build(BuildContext context) {
    final DateTime? testDate = _testDate;
    return _DocumentDialogFrame(
      title: _title,
      actions: [
        TextButton(
          onPressed: () => DialogUtils.closeOwnRoute(context),
          child: const Text(_cancelLabel),
        ),
        FilledButton.icon(
          onPressed: testDate == null
              ? null
              : () => DialogUtils.closeOwnRoute(
                    context,
                    BloodTestInfo(
                      testDate: testDate,
                      wantsReminder: _wantsReminder,
                    ),
                  ),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text(_uploadLabel),
        ),
      ],
      children: [
        _FileSummary(fileNames: widget.fileNames),
        const SizedBox(height: 8),
        _BloodTestFields(
          testDate: testDate,
          wantsReminder: _wantsReminder,
          knownTestDates: widget.knownTestDates,
          onDateChanged: (DateTime date) => setState(() => _testDate = date),
          onReminderChanged: (bool value) =>
              setState(() => _wantsReminder = value),
        ),
      ],
    );
  }
}

class _DocumentEditDialog extends StatefulWidget {
  const _DocumentEditDialog({
    required this.file,
    required this.sameDateCount,
    required this.knownTestDates,
  });

  final TestAttachment file;
  final int sameDateCount;
  final List<DateTime> knownTestDates;

  @override
  State<_DocumentEditDialog> createState() => _DocumentEditDialogState();
}

class _DocumentEditDialogState extends State<_DocumentEditDialog> {
  static const String _title = 'Dokümanı Düzenle';
  static const String _question = 'Bu bir kan tahlili mi?';
  static const String _yesLabel = 'Evet';
  static const String _noLabel = 'Hayır';
  static const String _saveLabel = 'Kaydet';
  static const String _toBloodTestLabel = 'Kan Tahlili\'ne Taşı';
  static const String _toOtherLabel = 'Diğer\'e Taşı';
  static const String _cancelLabel = 'İptal';
  static const String _unclassifiedNote = 'Bu doküman, türü sorulmadan '
      'yüklendiği için Diğer sekmesinde duruyor. Kan tahliliyse "Evet" deyip '
      'tahlilin yapıldığı tarihi girin; 3 aylık takip o zaman başlar.';
  static const String _toOtherNote = 'Dosya Diğer sekmesine taşınır ve tahlil '
      'tarihi silinir. Bu tarihin başka kan tahlili dosyası kalmazsa 3 ay '
      'hatırlatması da kaldırılır.';

  late bool? _isBloodTest =
      widget.file.isUnclassified ? null : widget.file.isBloodTest;
  late DateTime? _testDate = widget.file.bloodTestDate;
  late bool _wantsReminder =
      widget.file.isBloodTest ? widget.file.bloodTestReminder : true;
  bool _applyToSameDate = true;

  bool get _canSubmit {
    final TestAttachment file = widget.file;
    final bool? isBloodTest = _isBloodTest;
    if (isBloodTest == null) return false;
    if (!isBloodTest) return file.isBloodTest || file.isUnclassified;
    if (_testDate == null) return false;
    return !file.isBloodTest ||
        _testDate != file.bloodTestDate ||
        _wantsReminder != file.bloodTestReminder;
  }

  String get _submitLabel {
    if (_isBloodTest == true && !widget.file.isBloodTest) {
      return _toBloodTestLabel;
    }
    if (_isBloodTest == false && widget.file.isBloodTest) return _toOtherLabel;
    return _saveLabel;
  }

  String _sameDateLabel(DateTime? originalDate) {
    final String date =
        originalDate == null ? '' : ' (${DateFormatter.formatNumericDate(originalDate)})';
    return _isBloodTest == true
        ? 'Aynı tarihli$date diğer ${widget.sameDateCount} dosyaya da uygula'
        : 'Aynı tarihli$date diğer ${widget.sameDateCount} dosyayı da taşı';
  }

  void _submit() {
    final DateTime? testDate = _testDate;
    DialogUtils.closeOwnRoute(
      context,
      DocumentEdit(
        bloodTest: _isBloodTest == true && testDate != null
            ? BloodTestInfo(testDate: testDate, wantsReminder: _wantsReminder)
            : null,
        applyToSameDate: widget.sameDateCount > 0 && _applyToSameDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TestAttachment file = widget.file;
    final DateTime? uploadTime = file.uploadTime;
    final bool? isBloodTest = _isBloodTest;
    return _DocumentDialogFrame(
      title: _title,
      actions: [
        TextButton(
          onPressed: () => DialogUtils.closeOwnRoute(context),
          child: const Text(_cancelLabel),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_submitLabel),
        ),
      ],
      children: [
        _FileSummary(
          fileNames: [file.fileName],
          caption: uploadTime == null
              ? null
              : 'Yüklenme: ${DateFormatter.formatLongDateTime(uploadTime)}',
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: file.isUnclassified && isBloodTest == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InlineNote(
                    icon: Icons.info_outline_rounded,
                    text: _unclassifiedNote,
                    color: Colors.blueGrey.shade700,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 16),
        Text(_question, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              label: Text(_yesLabel),
              icon: Icon(Icons.bloodtype_rounded),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text(_noLabel),
              icon: Icon(Icons.folder_outlined),
            ),
          ],
          selected: {if (isBloodTest != null) isBloodTest},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: (Set<bool> selection) {
            if (selection.isEmpty) return;
            setState(() => _isBloodTest = selection.first);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _buildDetails(),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final TestAttachment file = widget.file;
    final Widget? sameDate = widget.sameDateCount > 0
        ? CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _applyToSameDate,
            title: Text(_sameDateLabel(file.bloodTestDate)),
            onChanged: (bool? value) =>
                setState(() => _applyToSameDate = value ?? false),
          )
        : null;
    if (_isBloodTest == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BloodTestFields(
              testDate: _testDate,
              wantsReminder: _wantsReminder,
              knownTestDates: widget.knownTestDates,
              onDateChanged: (DateTime date) =>
                  setState(() => _testDate = date),
              onReminderChanged: (bool value) =>
                  setState(() => _wantsReminder = value),
            ),
            if (sameDate != null) sameDate,
          ],
        ),
      );
    }
    if (_isBloodTest == false && file.isBloodTest) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InlineNote(
              icon: Icons.drive_file_move_outline,
              text: _toOtherNote,
              color: Colors.orange.shade800,
            ),
            if (sameDate != null) sameDate,
          ],
        ),
      );
    }
    return const SizedBox(width: double.infinity);
  }
}

class _DocumentDialogFrame extends StatelessWidget {
  const _DocumentDialogFrame({
    required this.title,
    required this.children,
    required this.actions,
  });

  static const double _maxWidth = 520;

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
      actions: actions,
    );
  }
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.fileNames, this.caption});

  static const int _maxListedFiles = 4;

  final List<String> fileNames;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final int hidden = fileNames.length - _maxListedFiles;
    final String? caption = this.caption;
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
          if (caption == null) ...[
            Text(
              fileNames.length == 1
                  ? '1 dosya seçildi'
                  : '${fileNames.length} dosya seçildi',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
          ],
          for (final String name in fileNames.take(_maxListedFiles))
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
          if (caption != null)
            Text(
              caption,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
        ],
      ),
    );
  }
}

class _BloodTestFields extends StatelessWidget {
  const _BloodTestFields({
    required this.testDate,
    required this.wantsReminder,
    required this.knownTestDates,
    required this.onDateChanged,
    required this.onReminderChanged,
  });

  static const String _testDateLabel = 'Tahlilin Yapıldığı Tarih';
  static const String _pickDateLabel = 'Tarih seçin';
  static const String _dateHint = '3 aylık takip bu tarihe göre hesaplanır; '
      'dosyanın yüklendiği gün kullanılmaz.';
  static const String _knownDatesLabel = 'Bu danışanın kayıtlı tahlil tarihleri';
  static const String _reminderLabel =
      '3 ay sonra hatırlatıcı istiyor musunuz?';
  static const int _maxKnownDates = 4;

  final DateTime? testDate;
  final bool wantsReminder;
  final List<DateTime> knownTestDates;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<bool> onReminderChanged;

  static final DateTime _firstDate = DateTime(2015);

  Future<void> _pickDate(BuildContext context) async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime? current = testDate;
    final DateTime firstDate =
        current != null && current.isBefore(_firstDate) ? current : _firstDate;
    final DateTime initialDate = current == null || current.isAfter(today)
        ? today
        : current;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: today,
      helpText: _testDateLabel,
    );
    if (picked != null && context.mounted) onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? testDate = this.testDate;
    final Color dateColor =
        testDate == null ? theme.colorScheme.error : theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.event_outlined, color: dateColor),
          title: const Text(_testDateLabel),
          subtitle: Text(
            testDate == null
                ? _pickDateLabel
                : DateFormatter.formatLongDate(testDate),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: testDate == null ? theme.colorScheme.error : null,
            ),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(context),
        ),
        Text(
          _dateHint,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        if (knownTestDates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_knownDatesLabel, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final DateTime date in knownTestDates.take(_maxKnownDates))
                ChoiceChip(
                  label: Text(DateFormatter.formatNumericDate(date)),
                  selected: date == testDate,
                  onSelected: (_) => onDateChanged(date),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: wantsReminder,
          title: const Text(_reminderLabel),
          secondary: Icon(
            Icons.alarm_rounded,
            color: wantsReminder ? theme.colorScheme.primary : Colors.grey,
          ),
          onChanged: (bool? value) => onReminderChanged(value ?? false),
        ),
        if (wantsReminder && testDate != null)
          BloodTestReminderPreview(testDate: testDate),
      ],
    );
  }
}
