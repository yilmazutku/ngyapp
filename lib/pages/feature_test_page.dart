import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feature_test_checklist.dart';
import '../models/feature_test_plan.dart';
import '../services/notification_service.dart';
import '../tabs/admin_images_page.dart';
import '../utils/dialog_utils.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/home_button.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/status_note.dart';
import 'admin_appointments_page.dart';
import 'admin_chat_page.dart';
import 'admin_notifications_page.dart';
import 'danisanlar_ozet_page.dart';
import 'feature_test_tools.dart';

const Color _passedColor = Color(0xFF2E7D32);
const Color _failedColor = Color(0xFFC62828);
const Color _skippedColor = Color(0xFF607D8B);

IconData _resultIcon(FeatureTestResult? result) {
  switch (result) {
    case FeatureTestResult.passed:
      return Icons.check_circle_rounded;
    case FeatureTestResult.failed:
      return Icons.cancel_rounded;
    case FeatureTestResult.skipped:
      return Icons.remove_circle_rounded;
    case null:
      return Icons.radio_button_unchecked_rounded;
  }
}

Color _resultColor(FeatureTestResult? result) {
  switch (result) {
    case FeatureTestResult.passed:
      return _passedColor;
    case FeatureTestResult.failed:
      return _failedColor;
    case FeatureTestResult.skipped:
      return _skippedColor;
    case null:
      return Colors.grey.shade500;
  }
}

class FeatureTestPage extends StatefulWidget {
  const FeatureTestPage({super.key});

  static const String title = 'Yeni Özellik Testleri';

  @override
  State<FeatureTestPage> createState() => _FeatureTestPageState();
}

class _FeatureTestPageState extends State<FeatureTestPage> {
  static const String _resetLabel = 'Sıfırla';
  static const String _cancelLabel = 'Vazgeç';
  static const String _saveLabel = 'Kaydet';
  static const String _deleteLabel = 'Sil';
  static const String _actionLabel = 'Yapılacak';
  static const String _expectedLabel = 'Beklenen sonuç';
  static const String _noteLabel = 'Not';

  late final FeatureTestChecklist _checklist =
      FeatureTestChecklist(platform: defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _checklist.load();
  }

  @override
  void dispose() {
    _checklist.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Sonuçları Sıfırla',
      message: 'Bütün sonuçlar ve notlar silinecek; eklediğiniz adımlar ve '
          'araç ayarları kalır. Devam etmek istiyor musunuz?',
      confirmText: _resetLabel,
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;
    _checklist.resetResults();
  }

  Future<void> _copyReport() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
        ClipboardData(text: _checklist.buildReport(now: DateTime.now())));
    messenger.showSnackBar(const SnackBar(
      content: Text('Rapor panoya kopyalandı; mesaja ya da e-postaya '
          'yapıştırabilirsiniz.'),
    ));
  }

  Future<void> _openShortcut(FeatureTestShortcut shortcut) async {
    final NavigatorState navigator = Navigator.of(context);
    switch (shortcut) {
      case FeatureTestShortcut.openUsers:
        await navigator.push(
            MaterialPageRoute<void>(builder: (_) => const AdminUsersPage()));
      case FeatureTestShortcut.openSummary:
        await navigator.push(MaterialPageRoute<void>(
            builder: (_) => const DanisanlarOzetPage()));
      case FeatureTestShortcut.openAppointments:
        await navigator.push(MaterialPageRoute<void>(
            builder: (_) => const AdminAppointmentsPage()));
      case FeatureTestShortcut.openChats:
        await navigator.push(AdminChatListPage.route());
      case FeatureTestShortcut.openNotifications:
        await openAdminNotificationCenter(context);
    }
  }

  void _setResult(FeatureTestStep step, FeatureTestResult result) {
    final bool newlyFailed = result == FeatureTestResult.failed &&
        _checklist.resultOf(step.id) != FeatureTestResult.failed;
    _checklist.setResult(step.id, result);
    if (newlyFailed && _checklist.noteOf(step.id) == null) _editNote(step);
  }

  Future<void> _editNote(FeatureTestStep step) async {
    final String? current = _checklist.noteOf(step.id);
    final List<String>? values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TextFieldsDialog(
        title: current == null ? 'Not Ekle' : 'Notu Düzenle',
        subtitle: step.action,
        fields: [
          _FieldSpec(
            label: _noteLabel,
            hint: 'Ne oldu? Hangi cihazda, hangi danışanda?',
            initialValue: current ?? '',
            maxLines: 4,
          ),
        ],
        clearLabel: current == null ? null : _deleteLabel,
      ),
    );
    if (values == null || !mounted) return;
    _checklist.setNote(step.id, values.first);
  }

  Future<void> _addStep(FeatureTestSection section) async {
    final List<String>? values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TextFieldsDialog(
        title: 'Adım Ekle',
        subtitle: section.title,
        fields: const [
          _FieldSpec(label: _actionLabel, maxLines: 3, required: true),
          _FieldSpec(label: _expectedLabel, maxLines: 3),
        ],
      ),
    );
    if (values == null || !mounted) return;
    _checklist.addCustomStep(
      sectionId: section.id,
      action: values[0],
      expected: values[1],
    );
  }

  Future<void> _editStep(FeatureTestStep step) async {
    final List<String>? values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TextFieldsDialog(
        title: 'Adımı Düzenle',
        fields: [
          _FieldSpec(
            label: _actionLabel,
            initialValue: step.action,
            maxLines: 3,
            required: true,
          ),
          _FieldSpec(
            label: _expectedLabel,
            initialValue: step.expected,
            maxLines: 3,
          ),
        ],
      ),
    );
    if (values == null || !mounted) return;
    _checklist.updateCustomStep(
      stepId: step.id,
      action: values[0],
      expected: values[1],
    );
  }

  Future<void> _deleteStep(FeatureTestStep step) async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Adımı Sil',
      message: '"${step.action}" adımı, sonucu ve notuyla birlikte silinecek. '
          'Devam etmek istiyor musunuz?',
      confirmText: _deleteLabel,
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;
    _checklist.removeCustomStep(step.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(FeatureTestPage.title),
        actions: const [HomeButton()],
      ),
      body: ListenableBuilder(
        listenable: _checklist,
        builder: (context, _) {
          if (!_checklist.isLoaded) {
            return const StatusNote(showProgress: true, text: 'Yükleniyor...');
          }
          final FeatureTestSummary summary = _checklist.summary;
          final List<Widget> sectionCards = [
            for (final FeatureTestSection section in _checklist.sections)
              if (_checklist.filter == FeatureTestFilter.all ||
                  _checklist.visibleStepsOf(section).isNotEmpty) ...[
                _SectionCard(
                  key: ValueKey<String>(section.id),
                  section: section,
                  checklist: _checklist,
                  onResult: _setResult,
                  onNote: _editNote,
                  onAddStep: () => _addStep(section),
                  onEditStep: _editStep,
                  onDeleteStep: _deleteStep,
                  onShortcut: _openShortcut,
                ),
                const SizedBox(height: 14),
              ],
          ];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _ProgressHeader(
                    summary: summary,
                    onCopy: _copyReport,
                    onReset: summary.done == 0 ? null : _reset,
                  ),
                  const SizedBox(height: 12),
                  _ViewBar(checklist: _checklist, summary: summary),
                  const SizedBox(height: 14),
                  if (sectionCards.isEmpty)
                    StatusNote(
                      icon: Icons.task_alt_rounded,
                      text: _checklist.filter == FeatureTestFilter.failed
                          ? 'Hatalı adım yok.'
                          : 'Yapılmamış adım kalmadı.',
                    )
                  else
                    ...sectionCards,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.summary,
    required this.onCopy,
    required this.onReset,
  });

  final FeatureTestSummary summary;
  final VoidCallback onCopy;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final bool localNotifications = NotificationService().isSupported;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8E54E9), Color(0xFFA16AEC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8E54E9).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                summary.isComplete
                    ? Icons.verified_rounded
                    : Icons.fact_check_outlined,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  summary.isComplete
                      ? 'Bütün adımlar test edildi'
                      : 'Test Kontrol Listesi',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Her adımı uygulamada yapın ve sonucu "Geçti", "Hatalı" ya da '
            '"Atla" ile işaretleyin. Hatalı adımlara ne olduğunu not edin; '
            'bitince raporu kopyalayıp gönderin. İşaretler bu cihazda saklanır.',
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: summary.total == 0 ? 0 : summary.done / summary.total,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${summary.done} / ${summary.total} adım',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _HeaderChip(
                icon: _resultIcon(FeatureTestResult.passed),
                text: '${summary.passed} geçti',
              ),
              _HeaderChip(
                icon: _resultIcon(FeatureTestResult.failed),
                text: '${summary.failed} hatalı',
                highlighted: summary.failed > 0,
              ),
              _HeaderChip(
                icon: _resultIcon(FeatureTestResult.skipped),
                text: '${summary.skipped} atlandı',
              ),
              _HeaderChip(
                icon: Icons.devices_rounded,
                text: 'Bu cihaz: '
                    '${featureTestPlatformLabel(defaultTargetPlatform)}',
              ),
              _HeaderChip(
                icon: localNotifications
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined,
                text: localNotifications
                    ? 'Sistem bildirimi var'
                    : 'Yalnızca uygulama içi şerit',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LabeledActionButton(
                dense: true,
                icon: Icons.copy_all_rounded,
                label: 'Raporu kopyala',
                foregroundColor: Colors.white,
                onPressed: onCopy,
              ),
              if (onReset != null)
                LabeledActionButton(
                  dense: true,
                  icon: Icons.restart_alt_rounded,
                  label: _FeatureTestPageState._resetLabel,
                  foregroundColor: Colors.white,
                  onPressed: onReset,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.text,
    this.highlighted = false,
  });

  final IconData icon;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? _failedColor.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewBar extends StatelessWidget {
  const _ViewBar({required this.checklist, required this.summary});

  final FeatureTestChecklist checklist;
  final FeatureTestSummary summary;

  @override
  Widget build(BuildContext context) {
    final bool allCollapsed = checklist.allCollapsed;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipGroup<FeatureTestFilter>(
            title: 'Göster',
            titleIcon: Icons.filter_list_rounded,
            options: {
              FeatureTestFilter.all:
                  '${FeatureTestFilter.all.label} (${summary.total})',
              FeatureTestFilter.open:
                  '${FeatureTestFilter.open.label} (${summary.open})',
              FeatureTestFilter.failed:
                  '${FeatureTestFilter.failed.label} (${summary.failed})',
            },
            selectedValue: checklist.filter,
            showAllOption: false,
            horizontalScroll: false,
            onSelected: (filter) {
              if (filter == null) return;
              checklist.filter = filter;
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text('Yalnızca bu cihaza uygun adımlar '
                    '(${featureTestPlatformLabel(checklist.platform)})'),
                selected: checklist.onlyThisDevice,
                onSelected: (value) => checklist.onlyThisDevice = value,
              ),
              TextButton.icon(
                onPressed: () => checklist.setAllCollapsed(!allCollapsed),
                icon: Icon(allCollapsed
                    ? Icons.unfold_more_rounded
                    : Icons.unfold_less_rounded),
                label: Text(allCollapsed ? 'Bölümleri aç' : 'Bölümleri daralt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.section,
    required this.checklist,
    required this.onResult,
    required this.onNote,
    required this.onAddStep,
    required this.onEditStep,
    required this.onDeleteStep,
    required this.onShortcut,
  });

  final FeatureTestSection section;
  final FeatureTestChecklist checklist;
  final void Function(FeatureTestStep step, FeatureTestResult result) onResult;
  final ValueChanged<FeatureTestStep> onNote;
  final VoidCallback onAddStep;
  final ValueChanged<FeatureTestStep> onEditStep;
  final ValueChanged<FeatureTestStep> onDeleteStep;
  final ValueChanged<FeatureTestShortcut> onShortcut;

  @override
  Widget build(BuildContext context) {
    final Color color = section.color;
    final List<FeatureTestStep> allSteps = checklist.stepsOf(section);
    final FeatureTestSummary summary = checklist.summaryOf(allSteps);
    final Set<String> visibleIds = {
      for (final FeatureTestStep step in checklist.visibleStepsOf(section))
        step.id,
    };
    final bool collapsed = checklist.isCollapsed(section.id);
    final String? note = section.note;
    final FeatureTestTool? tool = section.tool;
    final Color pillColor = summary.failed > 0
        ? _failedColor
        : summary.isComplete
            ? _passedColor
            : color;

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: summary.failed > 0
              ? _failedColor.withValues(alpha: 0.4)
              : summary.isComplete
                  ? _passedColor.withValues(alpha: 0.4)
                  : color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: color.withValues(alpha: 0.07),
            child: InkWell(
              onTap: () => checklist.toggleCollapsed(section.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(section.icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${summary.done}/${summary.total}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      color: Colors.grey.shade700,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            if (note != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            for (int i = 0; i < allSteps.length; i++)
              if (visibleIds.contains(allSteps[i].id))
                _StepTile(
                  key: ValueKey<String>(allSteps[i].id),
                  number: i + 1,
                  step: allSteps[i],
                  color: color,
                  result: checklist.resultOf(allSteps[i].id),
                  note: checklist.noteOf(allSteps[i].id),
                  appliesHere: allSteps[i].appliesTo(checklist.platform),
                  onResult: (result) => onResult(allSteps[i], result),
                  onNote: () => onNote(allSteps[i]),
                  onEdit: () => onEditStep(allSteps[i]),
                  onDelete: () => onDeleteStep(allSteps[i]),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAddStep,
                  icon: const Icon(Icons.add_task_rounded, size: 18),
                  label: const Text('Adım ekle'),
                ),
              ),
            ),
            if (section.shortcuts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final FeatureTestShortcut shortcut
                        in section.shortcuts)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                        ),
                        onPressed: () => onShortcut(shortcut),
                        icon: Icon(shortcut.icon, size: 18),
                        label: Text(shortcut.label),
                      ),
                  ],
                ),
              ),
            if (tool != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: FeatureTestToolPanel(
                  tool: tool,
                  color: color,
                  checklist: checklist,
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.number,
    required this.step,
    required this.color,
    required this.result,
    required this.note,
    required this.appliesHere,
    required this.onResult,
    required this.onNote,
    required this.onEdit,
    required this.onDelete,
  });

  final int number;
  final FeatureTestStep step;
  final Color color;
  final FeatureTestResult? result;
  final String? note;
  final bool appliesHere;
  final ValueChanged<FeatureTestResult> onResult;
  final VoidCallback onNote;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final FeatureTestResult? result = this.result;
    final String? note = this.note;
    final bool settled = result == FeatureTestResult.passed ||
        result == FeatureTestResult.skipped;
    final Color textColor = settled ? Colors.grey.shade500 : Colors.black87;

    return Material(
      color: result == FeatureTestResult.failed
          ? _failedColor.withValues(alpha: 0.05)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: result == FeatureTestResult.passed
                  ? 'İşareti kaldır'
                  : 'Geçti olarak işaretle',
              onPressed: () => onResult(FeatureTestResult.passed),
              icon: Icon(_resultIcon(result), color: _resultColor(result)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. ${step.action}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: textColor,
                      ),
                    ),
                    if (step.expected.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Beklenen: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: settled ? Colors.grey.shade500 : color,
                              ),
                            ),
                            TextSpan(text: step.expected),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: settled
                              ? Colors.grey.shade500
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                    if (step.platforms.isNotEmpty || step.isCustom) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final TargetPlatform platform in step.platforms)
                            _Tag(
                              text: featureTestPlatformLabel(platform),
                              color: appliesHere ? color : Colors.grey,
                            ),
                          if (step.isCustom)
                            const _Tag(
                              text: 'Kendi adımınız',
                              color: Colors.blueGrey,
                            ),
                        ],
                      ),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Text(
                          'Not: $note',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.brown.shade700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final FeatureTestResult option
                            in FeatureTestResult.values)
                          ChoiceChip(
                            label: Text(option == FeatureTestResult.skipped
                                ? 'Atla'
                                : option.label),
                            avatar: Icon(
                              _resultIcon(option),
                              size: 16,
                              color: result == option
                                  ? Colors.white
                                  : _resultColor(option),
                            ),
                            selected: result == option,
                            showCheckmark: false,
                            selectedColor: _resultColor(option),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: result == option
                                  ? Colors.white
                                  : Colors.grey.shade800,
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (_) => onResult(option),
                          ),
                        TextButton.icon(
                          onPressed: onNote,
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label:
                              Text(note == null ? 'Not ekle' : 'Notu düzenle'),
                        ),
                        if (step.isCustom) ...[
                          IconButton(
                            tooltip: 'Adımı düzenle',
                            visualDensity: VisualDensity.compact,
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Adımı sil',
                            visualDensity: VisualDensity.compact,
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _FieldSpec {
  const _FieldSpec({
    required this.label,
    this.hint,
    this.initialValue = '',
    this.maxLines = 1,
    this.required = false,
  });

  final String label;
  final String? hint;
  final String initialValue;
  final int maxLines;
  final bool required;
}

class _TextFieldsDialog extends StatefulWidget {
  const _TextFieldsDialog({
    required this.title,
    required this.fields,
    this.subtitle,
    this.clearLabel,
  });

  final String title;
  final String? subtitle;
  final List<_FieldSpec> fields;
  final String? clearLabel;

  @override
  State<_TextFieldsDialog> createState() => _TextFieldsDialogState();
}

class _TextFieldsDialogState extends State<_TextFieldsDialog> {
  static const double _maxWidth = 480;

  late final List<TextEditingController> _controllers = [
    for (final _FieldSpec field in widget.fields)
      TextEditingController(text: field.initialValue),
  ];

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isValid {
    for (int i = 0; i < widget.fields.length; i++) {
      if (widget.fields[i].required && _controllers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _close(List<String>? values) =>
      DialogUtils.closeOwnRoute(context, values);

  @override
  Widget build(BuildContext context) {
    final String? subtitle = widget.subtitle;
    final String? clearLabel = widget.clearLabel;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: _maxWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
              ],
              for (int i = 0; i < widget.fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                TextField(
                  controller: _controllers[i],
                  autofocus: i == 0,
                  minLines: 1,
                  maxLines: widget.fields[i].maxLines,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label,
                    hintText: widget.fields[i].hint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (clearLabel != null)
          TextButton(
            onPressed: () =>
                _close([for (int i = 0; i < widget.fields.length; i++) '']),
            child: Text(clearLabel),
          ),
        TextButton(
          onPressed: () => _close(null),
          child: const Text(_FeatureTestPageState._cancelLabel),
        ),
        FilledButton(
          onPressed: _isValid
              ? () => _close([
                    for (final TextEditingController controller in _controllers)
                      controller.text,
                  ])
              : null,
          child: const Text(_FeatureTestPageState._saveLabel),
        ),
      ],
    );
  }
}
