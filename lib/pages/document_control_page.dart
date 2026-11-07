import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/blood_test_status.dart';
import '../providers/blood_test_provider.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../utils/search_text.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/home_button.dart';
import '../widgets/search_field.dart';
import '../widgets/status_note.dart';
import 'customer_sum.dart';

Color _groupColor(BloodTestStatusGroup group) {
  switch (group) {
    case BloodTestStatusGroup.overdue:
      return const Color(0xFFC62828);
    case BloodTestStatusGroup.upcoming:
      return const Color(0xFFEF6C00);
    case BloodTestStatusGroup.undated:
      return const Color(0xFF546E7A);
    case BloodTestStatusGroup.upToDate:
      return const Color(0xFF2E7D32);
  }
}

IconData _groupIcon(BloodTestStatusGroup group) {
  switch (group) {
    case BloodTestStatusGroup.overdue:
      return Icons.error_rounded;
    case BloodTestStatusGroup.upcoming:
      return Icons.schedule_rounded;
    case BloodTestStatusGroup.undated:
      return Icons.help_rounded;
    case BloodTestStatusGroup.upToDate:
      return Icons.check_circle_rounded;
  }
}

class DocumentControlPage extends StatefulWidget {
  const DocumentControlPage({super.key});

  static const String title = 'Doküman Kontrol';

  @override
  State<DocumentControlPage> createState() => _DocumentControlPageState();
}

class _DocumentControlPageState extends State<DocumentControlPage> {
  static const String _searchLabel = 'Danışan ara (ad soyad)';
  static const String _noMatchText = 'Bu seçimde danışan yok.';
  static const String _notCheckedText =
      'Henüz kontrol yapılmadı. "Kan tahlillerini kontrol et"e basınca bütün '
      'danışanlar tahlil tarihleriyle listelenir.';

  late final BloodTestProvider _bloodTests =
      Provider.of<BloodTestProvider>(context, listen: false);
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<(int, int)> _progress = ValueNotifier<(int, int)>((0, 0));
  bool _checking = false;
  BloodTestStatusGroup? _group;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    _progress.value = (0, 0);
    try {
      await _bloodTests.checkAllCustomers(
        now: DateTime.now(),
        onProgress: (done, total) {
          if (mounted) _progress.value = (done, total);
        },
      );
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Kan tahlilleri kontrol edilemedi: $e',
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openCustomer(BloodTestStatus status) async {
    await openCustomerSummaryById(
      context,
      userId: status.customer.userId,
      displayName: status.customer.name,
    );
  }

  List<BloodTestStatus> _visible(BloodTestReport report) {
    final List<String> queryWords = searchWordsOf(_query);
    return [
      for (final BloodTestStatus status in report.statuses)
        if ((_group == null || status.kind.group == _group) &&
            (queryWords.isEmpty ||
                matchesSearchWords(
                    queryWords, searchWordsOf(status.customer.name))))
          status,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(DocumentControlPage.title),
        actions: const [HomeButton()],
      ),
      body: ListenableBuilder(
        listenable: _bloodTests,
        builder: (context, _) {
          final BloodTestReport? report = _bloodTests.lastReport;
          final List<BloodTestStatus> visible =
              report == null ? const [] : _visible(report);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _CheckCard(
                    checking: _checking,
                    progress: _progress,
                    report: report,
                    onCheck: _check,
                  ),
                  const SizedBox(height: 16),
                  if (report == null)
                    const StatusNote(
                      icon: Icons.fact_check_outlined,
                      text: _notCheckedText,
                    )
                  else ...[
                    FilterChipGroup<BloodTestStatusGroup>(
                      title: 'Durum',
                      titleIcon: Icons.filter_list_rounded,
                      options: {
                        for (final BloodTestStatusGroup group
                            in BloodTestStatusGroup.values)
                          group: '${group.label} (${report.countOf(group)})',
                      },
                      selectedValue: _group,
                      allLabel: 'Tümü (${report.statuses.length})',
                      horizontalScroll: false,
                      onSelected: (group) => setState(() => _group = group),
                    ),
                    const SizedBox(height: 14),
                    SearchField(
                      controller: _searchController,
                      label: _searchLabel,
                      maxWidth: double.infinity,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty)
                      const StatusNote(
                        icon: Icons.search_off_rounded,
                        text: _noMatchText,
                      )
                    else
                      for (final BloodTestStatusGroup group
                          in BloodTestStatusGroup.values)
                        if (visible.any((s) => s.kind.group == group))
                          _GroupSection(
                            group: group,
                            statuses: [
                              for (final BloodTestStatus status in visible)
                                if (status.kind.group == group) status,
                            ],
                            now: report.checkedAt,
                            onOpen: _openCustomer,
                          ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.checking,
    required this.progress,
    required this.report,
    required this.onCheck,
  });

  static const String _checkLabel = 'Kan tahlillerini kontrol et';

  final bool checking;
  final ValueNotifier<(int, int)> progress;
  final BloodTestReport? report;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final BloodTestReport? report = this.report;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bloodtype_rounded,
                      color: Colors.red.shade700, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kan Tahlili Kontrolü',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Bütün danışanların kan tahlili tarihlerini kontrol '
                        'eder. Üzerinden 3 ay geçen tahliller ve eklenmesinin '
                        'üzerinden 1 hafta geçtiği hâlde ilk tahlili '
                        'yüklenmeyen danışanlar en üstte listelenir.',
                        style: TextStyle(fontSize: 13.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: checking ? null : onCheck,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text(_checkLabel),
            ),
            const SizedBox(height: 10),
            if (checking)
              ValueListenableBuilder<(int, int)>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final (int done, int total) = value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: total == 0 ? null : done / total,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        total == 0
                            ? 'Danışanlar okunuyor...'
                            : '$done / $total danışan kontrol edildi',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                    ],
                  );
                },
              )
            else if (report != null) ...[
              Text(
                'Son kontrol: '
                '${DateFormatter.formatNumericDateTime(report.checkedAt)} · '
                '${report.statuses.length} danışan',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              if (!DateFormatter.isSameDay(report.checkedAt, DateTime.now()))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Bu sonuçlar o güne göre hesaplandı; güncel durum için '
                    'yeniden kontrol edin.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.statuses,
    required this.now,
    required this.onOpen,
  });

  final BloodTestStatusGroup group;
  final List<BloodTestStatus> statuses;
  final DateTime now;
  final ValueChanged<BloodTestStatus> onOpen;

  @override
  Widget build(BuildContext context) {
    final Color color = _groupColor(group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Icon(_groupIcon(group), size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  '${toUpperTr(group.label)} (${statuses.length})',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < statuses.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  _StatusRow(
                    status: statuses[i],
                    now: now,
                    onTap: () => onOpen(statuses[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.now,
    required this.onTap,
  });

  final BloodTestStatus status;
  final DateTime now;
  final VoidCallback onTap;

  static String _date(DateTime? date) =>
      date == null ? '-' : DateFormatter.formatNumericDate(date);

  String get _detail {
    switch (status.kind) {
      case BloodTestStatusKind.missingFirst:
        return status.createdAt == null
            ? 'Eklenme tarihi bilinmiyor'
            : 'Eklenme ${_date(status.createdAt)} · 1 hafta doldu: '
                '${_date(status.deadline)}';
      case BloodTestStatusKind.waitingFirst:
        return 'Eklenme ${_date(status.createdAt)} · Son gün: '
            '${_date(status.deadline)}';
      case BloodTestStatusKind.expired:
      case BloodTestStatusKind.expiringSoon:
      case BloodTestStatusKind.upToDate:
        return 'Son tahlil ${_date(status.lastTestDate)} · 3 ay: '
            '${_date(status.deadline)}';
      case BloodTestStatusKind.undated:
        return 'Detay sekmesinde "Evet" seçili; tahlil tarihiyle '
            'yüklenince 3 ay takibi başlar.';
    }
  }

  String? get _badge {
    final int? days = status.daysUntilDeadline(now);
    if (days == null) return null;
    if (status.kind.group == BloodTestStatusGroup.overdue) {
      return days >= 0 ? 'Bugün doldu' : '${-days} gün geçti';
    }
    return days <= 0 ? 'Bugün doluyor' : '$days gün kaldı';
  }

  @override
  Widget build(BuildContext context) {
    final BloodTestStatusGroup group = status.kind.group;
    final Color color = _groupColor(group);
    final String? badge = _badge;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(_groupIcon(group), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.customer.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.kind.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    _detail,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
