import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/document_dialogs.dart';
import '../models/admin_notification.dart';
import '../models/test_attachment.dart';
import '../providers/blood_test_provider.dart';
import '../providers/test_provider.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../utils/storage_upload.dart';
import '../widgets/full_screen_image_page.dart';
import '../widgets/inline_note.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/status_note.dart';

/// Tests tab behaves like Tanita explorer: header + list + upload in-place
/// Accepts PDFs and images (jpg/jpeg/png/webp/heic)
class TestsTab extends StatefulWidget {
  final String userId;

  final String userName;

  const TestsTab({super.key, required this.userId, required this.userName});

  @override
  State<TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends State<TestsTab>
    with SingleTickerProviderStateMixin {
  static const List<String> _allowedExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  ];
  static const String _bloodTestUploadLabel = 'Kan Tahlili Yükle';
  static const String _otherUploadLabel = 'Doküman Yükle';
  static const String _bloodTestHint =
      '3 aylık takip, tahlilin yapıldığı tarihe göre hesaplanır.';
  static const String _otherHint =
      'Kan tahlili olmayan dokümanlar. Kan tahlili olanı kalem simgesiyle '
      'Kan Tahlili sekmesine taşıyabilirsiniz.';
  static const String _editTooltip = 'Düzenle';
  static const String _deleteLabel = 'Sil';
  static const String _noBloodTests = 'Henüz kan tahlili yüklenmedi.';
  static const String _noOtherDocuments = 'Başka doküman yok.';
  static const String _goToOtherLabel = 'Diğer sekmesine git';

  late final TabController _tabController =
      TabController(length: DocumentCategory.values.length, vsync: this);
  final Map<DocumentCategory, ScrollController> _scrollControllers = {
    for (final DocumentCategory category in DocumentCategory.values)
      category: ScrollController(),
  };

  late Future<List<TestAttachment>> _filesFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _filesFuture = _fetchFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final ScrollController controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<List<TestAttachment>> _fetchFiles() =>
      Provider.of<TestProvider>(context, listen: false)
          .fetchTestAttachments(widget.userId);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _filesFuture = _fetchFiles();
    });
  }

  void _finishWork() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _filesFuture = _fetchFiles();
    });
  }

  Future<void> _refresh() async {
    _reload();
    await _filesFuture.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _pickAndUpload(
    DocumentCategory category,
    List<TestAttachment> files,
  ) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: true,
        // Keep only the file paths (not the bytes) so the picker never loads
        // every selected file into memory at once; each file is streamed
        // straight from disk at upload time.
        withData: false,
      );
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Dosya seçme hatası: $e');
      return;
    }
    if (result == null || result.files.isEmpty || !mounted) return;

    BloodTestInfo? bloodTest;
    if (category == DocumentCategory.bloodTest) {
      bloodTest = await showBloodTestUploadDialog(
        context,
        fileNames: [for (final PlatformFile file in result.files) file.name],
        knownTestDates: TestAttachment.testDatesOf(files),
      );
      if (bloodTest == null || !mounted) return;
    }
    await _uploadFiles(result.files, bloodTest);
  }

  /// Uploads the picked files in sequence. A single failing file does not
  /// abort the batch; a summary reports how many succeeded and which (if any)
  /// failed.
  Future<void> _uploadFiles(
    List<PlatformFile> files,
    BloodTestInfo? bloodTest,
  ) async {
    final TestProvider tests =
        Provider.of<TestProvider>(context, listen: false);
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    final int total = files.length;
    final ValueNotifier<String> progress =
        ValueNotifier<String>('Dosyalar yükleniyor (1/$total)...');
    setState(() => _busy = true);
    LoadingDialog? loading;
    if (mounted) {
      loading = DialogUtils.openLoadingProgress(context, messageListenable: progress);
    }

    int success = 0;
    final List<String> failed = [];
    try {
      for (int i = 0; i < total; i++) {
        final PlatformFile file = files[i];
        progress.value = 'Dosyalar yükleniyor (${i + 1}/$total)...';
        // Guard against pathologically large files that would otherwise make
        // the upload very slow and risk crashing the app on Windows desktop.
        if (file.size > kMaxUploadBytes) {
          failed.add('${file.name} (çok büyük, en fazla $kMaxUploadSizeLabel)');
          continue;
        }
        final String? path = file.path;
        if (path == null) {
          failed.add('${file.name} (dosya okunamadı)');
          continue;
        }
        try {
          await tests.uploadTestAttachmentFile(
            userId: widget.userId,
            fileName: file.name,
            filePath: path,
            bloodTest: bloodTest,
          );
          success++;
        } catch (e) {
          failed.add(e is UploadTimeoutException
              ? '${file.name} (${e.userMessage})'
              : file.name);
        }
      }

      final List<String> notes = [];
      String? reminderError;
      if (success > 0 && bloodTest != null) {
        progress.value = 'Kan tahlili kaydediliyor...';
        try {
          final BloodTestReminderSync sync = await bloodTests.syncReminders(
            userId: widget.userId,
            userName: widget.userName,
          );
          notes.add(
              '${DateFormatter.formatNumericDate(bloodTest.testDate)} tarihli '
              'kan tahlili kaydedildi.');
          notes.addAll(_reminderNotes(sync, edited: bloodTest));
        } catch (e) {
          reminderError =
              'Dosyalar yüklendi fakat 3 ay hatırlatması güncellenemedi: $e';
        }
      }

      loading?.close();
      if (!mounted) return;
      _finishWork();
      final String uploaded = '$success dosya yüklendi.';
      final String details = [
        if (failed.isNotEmpty)
          '${failed.length} dosya yüklenemedi:\n${failed.join('\n')}',
        if (notes.isNotEmpty) notes.join(' '),
        if (reminderError != null) reminderError,
      ].join('\n\n');
      if (failed.isEmpty && reminderError == null) {
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: details.isEmpty ? uploaded : '$uploaded\n\n$details',
        );
      } else {
        await DialogUtils.openError(
          context,
          title: success > 0 ? 'Kısmen Tamamlandı' : 'Hata',
          message: '$uploaded\n\n$details',
        );
      }
    } catch (e) {
      loading?.close();
      if (mounted) {
        await DialogUtils.openError(context, title: 'Hata', message: 'Dosya yükleme hatası: $e');
      }
    } finally {
      loading?.close();
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _reminderNotes(
    BloodTestReminderSync sync, {
    BloodTestInfo? edited,
  }) {
    final List<String> notes = [];
    final DateTime? latest = sync.latestTestDate;
    final DateTime? remindFor = sync.remindFor;
    final DateTime now = DateTime.now();
    if (edited != null && edited.wantsReminder) {
      if (latest != null && latest.isAfter(edited.testDate)) {
        notes.add('Danışanın daha yeni tarihli '
            '(${DateFormatter.formatNumericDate(latest)}) bir kan tahlili '
            'olduğu için bu tahlile 3 ay hatırlatması kurulmadı.');
      } else if (sync.written == 0) {
        notes.add('Bu tarihli tahlilin 3 ay hatırlatması zaten kurulu.');
      } else if (!BloodTestReminderSchedule.plan(edited.testDate, now)
          .containsKey(BloodTestReminderStage.dayBefore)) {
        notes.add('Tahlilin üzerinden 3 ay geçtiği için hatırlatma Sistem '
            'bildirimlerine düştü.');
      } else {
        notes.add('3 ay hatırlatması '
            '${DateFormatter.formatLongDate(BloodTestReminderSchedule.dueDay(edited.testDate))} '
            've bir gün öncesi için kuruldu.');
      }
    }
    if (remindFor != null &&
        remindFor != edited?.testDate &&
        sync.written > 0) {
      notes.add('Danışanın en yeni kan tahlili artık '
          '${DateFormatter.formatNumericDate(remindFor)} tarihli; 3 ay '
          'hatırlatması bu tahlile göre kuruldu.');
    }
    return notes;
  }

  Future<void> _editFile(TestAttachment file, List<TestAttachment> files) async {
    final DateTime? originalDate = file.bloodTestDate;
    final List<TestAttachment> sameDate = [
      for (final TestAttachment other in files)
        if (originalDate != null &&
            other.docId != file.docId &&
            other.bloodTestDate == originalDate)
          other,
    ];
    final DocumentEdit? edit = await showDocumentEditDialog(
      context,
      file: file,
      sameDateCount: sameDate.length,
      knownTestDates: TestAttachment.testDatesOf(files),
    );
    if (edit == null || !mounted) return;

    final BloodTestInfo? bloodTest = edit.bloodTest;
    final List<String> docIds = [
      file.docId,
      if (edit.applyToSameDate)
        for (final TestAttachment other in sameDate) other.docId,
    ];
    final TestProvider tests =
        Provider.of<TestProvider>(context, listen: false);
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    setState(() => _busy = true);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: 'Kaydediliyor...');
    try {
      try {
        await tests.updateDocumentCategory(
          userId: widget.userId,
          docIds: docIds,
          bloodTest: bloodTest,
        );
      } catch (e) {
        loading.close();
        if (!mounted) return;
        await DialogUtils.openError(context, title: 'Hata', message: 'Doküman güncellenemedi: $e');
        return;
      }

      final String count =
          docIds.length == 1 ? 'Dosya' : '${docIds.length} dosya';
      final List<String> notes = [
        if (bloodTest == null && file.isBloodTest)
          '$count Diğer sekmesine taşındı.'
        else if (bloodTest == null)
          'Doküman "Diğer" olarak kaydedildi.'
        else if (!file.isBloodTest)
          '$count ${DateFormatter.formatNumericDate(bloodTest.testDate)} '
              'tarihli kan tahlili olarak Kan Tahlili sekmesine taşındı.'
        else
          '$count ${DateFormatter.formatNumericDate(bloodTest.testDate)} '
              'tarihli kan tahlili olarak güncellendi.',
      ];
      BloodTestReminderSync? sync;
      String? reminderError;
      if (file.isBloodTest || bloodTest != null) {
        try {
          sync = await bloodTests.syncReminders(
            userId: widget.userId,
            userName: widget.userName,
          );
          if (bloodTest == null && sync.removed > 0) {
            notes.add('Taşınan tahlilin 3 ay hatırlatması kaldırıldı.');
          } else if (bloodTest != null &&
              !bloodTest.wantsReminder &&
              sync.removed > 0) {
            notes.add('Bekleyen 3 ay hatırlatması kaldırıldı.');
          }
          notes.addAll(_reminderNotes(sync, edited: bloodTest));
        } catch (e) {
          reminderError = 'Doküman güncellendi fakat 3 ay hatırlatması '
              'güncellenemedi: $e';
        }
      }

      loading.close();
      if (!mounted) return;
      _finishWork();
      if (reminderError != null) {
        await DialogUtils.openError(context, title: 'Uyarı', message: reminderError);
      } else {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: notes.join(' '));
      }
      if (sync != null && !sync.hasBloodTests && file.isBloodTest) {
        await _offerPresenceReset(bloodTests);
      }
    } finally {
      loading.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFile(TestAttachment f, List<TestAttachment> files) async {
    final DateTime? testDate = f.bloodTestDate;
    final bool lastOfItsDate = testDate != null &&
        !files.any((TestAttachment other) =>
            other.docId != f.docId && other.bloodTestDate == testDate);
    final bool ok = await DialogUtils.openConfirm(
      context,
      title: 'Dosyayı Sil',
      message: lastOfItsDate && f.bloodTestReminder
          ? '"${f.fileName}" dosyasını silmek istiyor musunuz?\n\nBu tarihli '
              'tahlilin başka dosyası olmadığı için 3 ay hatırlatması da '
              'kaldırılır.'
          : '"${f.fileName}" dosyasını silmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (!ok || !mounted) return;

    final TestProvider provider =
        Provider.of<TestProvider>(context, listen: false);
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    setState(() => _busy = true);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: 'Siliniyor...');
    try {
      try {
        await provider.deleteTestAttachment(
          userId: widget.userId,
          docId: f.docId,
          storagePath: f.storagePath,
        );
      } catch (e) {
        loading.close();
        if (!mounted) return;
        await DialogUtils.openError(context, title: 'Hata', message: 'Dosya silinemedi: $e');
        return;
      }

      final List<String> notes = ['Dosya silindi.'];
      BloodTestReminderSync? sync;
      String? reminderError;
      if (f.isBloodTest) {
        try {
          sync = await bloodTests.syncReminders(
            userId: widget.userId,
            userName: widget.userName,
          );
          if (sync.removed > 0) {
            notes.add('Bu tahlilin 3 ay hatırlatması kaldırıldı.');
          }
          notes.addAll(_reminderNotes(sync));
        } catch (e) {
          reminderError =
              'Dosya silindi fakat 3 ay hatırlatması güncellenemedi: $e';
        }
      }

      loading.close();
      if (!mounted) return;
      _finishWork();
      if (reminderError != null) {
        await DialogUtils.openError(context, title: 'Uyarı', message: reminderError);
      } else {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: notes.join(' '));
      }
      if (sync != null && !sync.hasBloodTests) {
        await _offerPresenceReset(bloodTests);
      }
    } finally {
      loading.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerPresenceReset(BloodTestProvider bloodTests) async {
    final bool present;
    try {
      present = await bloodTests.fetchBloodTestPresent(widget.userId);
    } catch (e) {
      return;
    }
    if (!present || !mounted) return;
    final bool reset = await DialogUtils.openConfirm(
      context,
      title: 'Kan Tahlili Kalmadı',
      message: 'Danışanın Kan Tahlili sekmesinde dosya kalmadı.\n\nDetay '
          'sekmesindeki "Danışanın kan değerleri dokümanı mevcut mu?" sorusu '
          '"Hayır" olarak işaretlensin mi? "Hayır" olursa danışan, eklendiği '
          'günden 1 hafta geçtiyse günlük taramada kan tahlili eksik '
          'danışanlar listesine girer.',
      confirmText: '"Hayır" olarak işaretle',
      cancelText: '"Evet" kalsın',
    );
    if (!reset || !mounted) return;
    try {
      await bloodTests.setBloodTestPresent(userId: widget.userId, present: false);
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Seçim kaydedilemedi: $e');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Kan değerleri dokümanı "mevcut değil" olarak kaydedildi.'),
      duration: Duration(seconds: 2),
    ));
  }

  void _openFile(TestAttachment f) async {
    if (f.isImage) {
      _showImagePreview(f.url, f.fileName);
      return;
    }
    // PDF or other ⇒ open externally
    final Uri uri = Uri.parse(f.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Açılamadı: ${f.url}');
    }
  }

  /// Görseli ortak tam ekran görüntüleyicide açar (yakınlaştırma,
  /// kaydırarak kapatma, Esc).
  void _showImagePreview(String url, String title) {
    showFullScreenImage<void>(context, imageUrl: url, title: title);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TestAttachment>>(
      future: _filesFuture,
      builder: (context, snapshot) {
        final List<TestAttachment>? files =
            snapshot.hasError ? null : snapshot.data;
        final Map<DocumentCategory, List<TestAttachment>>? byCategory =
            files == null
                ? null
                : {
                    for (final DocumentCategory category
                        in DocumentCategory.values)
                      category: TestAttachment.ofCategory(files, category),
                  };
        final bool refreshing =
            snapshot.connectionState == ConnectionState.waiting &&
                files != null;
        return Column(
          children: [
            TabBar.secondary(
              controller: _tabController,
              tabs: [
                for (final DocumentCategory category in DocumentCategory.values)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          category == DocumentCategory.bloodTest
                              ? Icons.bloodtype_outlined
                              : Icons.folder_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(byCategory == null
                            ? category.label
                            : '${category.label} '
                                '(${byCategory[category]!.length})'),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 2,
              child: refreshing ? const LinearProgressIndicator() : null,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final DocumentCategory category
                      in DocumentCategory.values)
                    Column(
                      children: [
                        _buildHeader(category, files ?? const []),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: _buildList(
                              category,
                              snapshot,
                              files,
                              byCategory?[category],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(DocumentCategory category, List<TestAttachment> files) {
    final double horizontal = MediaQuery.of(context).size.width * 0.04;
    final bool bloodTest = category == DocumentCategory.bloodTest;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bloodTest ? _bloodTestHint : _otherHint,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _busy ? null : () => _pickAndUpload(category, files),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add),
            label: Text(bloodTest ? _bloodTestUploadLabel : _otherUploadLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    DocumentCategory category,
    AsyncSnapshot<List<TestAttachment>> snapshot,
    List<TestAttachment>? files,
    List<TestAttachment>? shown,
  ) {
    if (snapshot.hasError) {
      return ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          StatusNote(
            icon: Icons.error_outline,
            text: 'Dokümanlar yüklenemedi: ${snapshot.error}',
            isError: true,
            action: TextButton(onPressed: _reload, child: const Text('Yenile')),
          ),
        ],
      );
    }
    if (files == null || shown == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final int unclassified = [
      for (final TestAttachment file in files)
        if (file.isUnclassified) file,
    ].length;
    if (shown.isEmpty) {
      final bool hintOther =
          category == DocumentCategory.bloodTest && unclassified > 0;
      return ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 32),
          StatusNote(
            icon: category == DocumentCategory.bloodTest
                ? Icons.bloodtype_outlined
                : Icons.folder_open_outlined,
            text: category == DocumentCategory.bloodTest
                ? hintOther
                    ? '$_noBloodTests\n\nDiğer sekmesinde türü belirtilmemiş '
                        '$unclassified doküman var. Kan tahlili olanları '
                        'kalem simgesine basıp "Evet" diyerek buraya '
                        'taşıyabilirsiniz.'
                    : _noBloodTests
                : _noOtherDocuments,
            action: hintOther
                ? OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(
                        DocumentCategory.other.index),
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text(_goToOtherLabel),
                  )
                : null,
          ),
        ],
      );
    }

    final DateTime? latestTestDate = TestAttachment.latestTestDate(files);
    final bool showUnclassifiedNote =
        category == DocumentCategory.other && unclassified > 0;
    final int offset = showUnclassifiedNote ? 1 : 0;
    final double horizontal = MediaQuery.of(context).size.width * 0.04;
    return ListView.separated(
      controller: _scrollControllers[category],
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: shown.length + offset,
      separatorBuilder: (_, int i) => i < offset
          ? const SizedBox(height: 4)
          : const Divider(height: 1),
      itemBuilder: (_, int i) {
        if (i < offset) {
          return Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 8),
            child: InlineNote(
              icon: Icons.info_outline_rounded,
              color: Colors.blueGrey.shade700,
              text: '$unclassified dokümanın türü belirtilmemiş (kan tahlili '
                  'sorusundan önce yüklendi). Kan tahlili olanları kalem '
                  'simgesine basıp "Evet" diyerek taşıyın; 3 aylık takip '
                  'tahlil tarihi girilince başlar.',
            ),
          );
        }
        return _buildTile(shown[i - offset], files, latestTestDate);
      },
    );
  }

  Widget _buildTile(
    TestAttachment f,
    List<TestAttachment> files,
    DateTime? latestTestDate,
  ) {
    final DateTime? uploadTime = f.uploadTime;
    final String uploaded = uploadTime == null
        ? 'Yüklenme: -'
        : 'Yüklenme: ${DateFormatter.formatLongDateTime(uploadTime)}';

    final Widget leading;
    if (f.isImage) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          f.url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.orange),
        ),
      );
    } else {
      leading = const Icon(Icons.picture_as_pdf, color: Colors.red);
    }

    return ListTile(
      key: ValueKey<String>(f.docId),
      leading: leading,
      title: Text(f.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: f.isBloodTest
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(uploaded),
                const SizedBox(height: 4),
                _BloodTestBadges(
                  file: f,
                  isLatest: f.bloodTestDate != null &&
                      f.bloodTestDate == latestTestDate,
                ),
              ],
            )
          : Text(uploaded),
      onTap: () => _openFile(f),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledActionButton(
            dense: true,
            icon: Icons.delete,
            label: _deleteLabel,
            foregroundColor: Colors.red,
            onPressed: _busy ? null : () => _deleteFile(f, files),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: _editTooltip,
            onPressed: _busy ? null : () => _editFile(f, files),
          ),
        ],
      ),
    );
  }
}

class _BloodTestBadges extends StatelessWidget {
  final TestAttachment file;
  final bool isLatest;

  const _BloodTestBadges({required this.file, required this.isLatest});

  @override
  Widget build(BuildContext context) {
    final DateTime? testDate = file.bloodTestDate;
    final DateTime? dueDay = file.reminderDueDay;
    if (testDate == null || dueDay == null) {
      return _badge(
        icon: Icons.warning_amber_rounded,
        text: 'Tahlil tarihi girilmedi',
        color: Colors.orange.shade800,
      );
    }
    final bool expired = !BloodTestReminderSchedule.fireTime(
            testDate, BloodTestReminderStage.dueDay)
        .isAfter(DateTime.now());
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _badge(
          icon: Icons.bloodtype_rounded,
          text: 'Tahlil tarihi: ${DateFormatter.formatNumericDate(testDate)}',
          color: Colors.red.shade700,
        ),
        if (isLatest && expired)
          _badge(
            icon: Icons.event_busy_rounded,
            text: '3 ay doldu: ${DateFormatter.formatNumericDate(dueDay)}',
            color: Colors.orange.shade800,
          )
        else if (isLatest && file.bloodTestReminder)
          _badge(
            icon: Icons.alarm_rounded,
            text: 'Hatırlatma: ${DateFormatter.formatNumericDate(dueDay)}',
            color: Colors.deepPurple,
          ),
      ],
    );
  }

  Widget _badge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
