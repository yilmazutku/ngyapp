import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/test_attachment.dart';
import '../providers/test_provider.dart';
import '../utils/date_formatter.dart';
import 'inline_note.dart';

class BloodTestStatusCard extends StatefulWidget {
  const BloodTestStatusCard({super.key, required this.userId});

  final String userId;

  @override
  State<BloodTestStatusCard> createState() => _BloodTestStatusCardState();
}

class _BloodTestStatusCardState extends State<BloodTestStatusCard> {
  static const String _title = 'Kan tahlili';
  static const String _uploadedLabel = 'Yüklü';
  static const String _missingLabel = 'Yüklü değil';
  static const String _checkingLabel = 'Kontrol ediliyor';
  static const String _uploadedAtLabel = 'Yüklenme';
  static const String _testDateLabel = 'Tahlil tarihi';
  static const String _unknownValue = 'Girilmedi';
  static const String _missingNote = 'Kan tahlili, Dokümanlar sekmesindeki '
      'Kan Tahlili bölümünden yüklenir. Yüklenmezse danışan, eklendiği '
      'günden 1 hafta sonra günlük kan tahlili taramasında listelenir.';
  static const String _loadError = 'Kan tahlili bilgisi okunamadı.';
  static const String _retryTooltip = 'Yenile';
  static const double _contentIndent = 52;

  late final TestProvider _tests =
      Provider.of<TestProvider>(context, listen: false);
  late Future<List<TestAttachment>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _tests.fetchTestAttachments(widget.userId);
    _tests.addListener(_reload);
  }

  @override
  void dispose() {
    _tests.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _filesFuture = _tests.fetchTestAttachments(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TestAttachment>>(
      future: _filesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _card(
            color: Colors.grey.shade600,
            status: null,
            details: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _loadError,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: _retryTooltip,
                    onPressed: _reload,
                  ),
                ],
              ),
            ],
          );
        }
        final List<TestAttachment>? files = snapshot.data;
        if (files == null) {
          return _card(
            color: Colors.grey.shade600,
            status: _StatusPill(
              label: _checkingLabel,
              color: Colors.grey.shade700,
              leading: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            details: const [],
          );
        }
        final TestAttachment? latest = TestAttachment.latestBloodTest(files);
        if (latest != null) return _uploadedCard(latest);
        return _missingCard(
          files.where((TestAttachment file) => file.isUnclassified).length,
        );
      },
    );
  }

  Widget _uploadedCard(TestAttachment latest) {
    final Color color = Colors.green.shade700;
    final DateTime? uploadedAt = latest.uploadTime;
    final DateTime? testDate = latest.bloodTestDate;
    return _card(
      color: color,
      status: _StatusPill(
        label: _uploadedLabel,
        color: color,
        leading: Icon(Icons.check_circle_rounded, size: 16, color: color),
      ),
      details: [
        _detailLine(
          icon: Icons.cloud_upload_outlined,
          label: _uploadedAtLabel,
          value: uploadedAt == null
              ? _unknownValue
              : DateFormatter.formatLongDateTime(uploadedAt),
        ),
        const SizedBox(height: 4),
        _detailLine(
          icon: Icons.event_outlined,
          label: _testDateLabel,
          value: testDate == null
              ? _unknownValue
              : DateFormatter.formatLongDate(testDate),
          valueColor: testDate == null ? Colors.orange.shade800 : null,
        ),
      ],
    );
  }

  Widget _missingCard(int unclassified) {
    final Color color = Colors.red.shade600;
    return _card(
      color: color,
      status: _StatusPill(
        label: _missingLabel,
        color: color,
        leading: Icon(Icons.cancel_rounded, size: 16, color: color),
      ),
      details: [
        Text(
          _missingNote,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        if (unclassified > 0) ...[
          const SizedBox(height: 8),
          InlineNote(
            icon: Icons.info_outline_rounded,
            color: Colors.blueGrey.shade700,
            text: 'Dokümanlar sekmesinin Diğer bölümünde türü belirtilmemiş '
                '$unclassified doküman var. Kan tahliliyse kalem simgesine '
                'basıp "Kan Tahlili sekmesine taşı"yı seçin.',
          ),
        ],
      ],
    );
  }

  Widget _detailLine({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _card({
    required Color color,
    required Widget? status,
    required List<Widget> details,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bloodtype_rounded, color: color),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    _title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (status != null) status,
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: _contentIndent, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: details,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.leading,
  });

  final String label;
  final Color color;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
