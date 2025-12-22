import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/logger.dart';
import '../providers/test_provider.dart';
import '../utils/dialog_utils.dart';

final Logger log = Logger.forClass(TestsTab);

/// Tests tab behaves like Tanita explorer: header + list + upload in-place
/// Accepts PDFs and images (jpg/jpeg/png/webp/heic)
class TestsTab extends StatefulWidget {
  final String userId;
  const TestsTab({super.key, required this.userId});

  @override
  State<TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends State<TestsTab> {
  late Future<List<_TestAttachmentModel>> _filesFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _filesFuture = _fetchFiles();
  }

  Future<List<_TestAttachmentModel>> _fetchFiles() async {
    final provider = Provider.of<TestProvider>(context, listen: false);
    final raw = await provider.fetchTestAttachmentMetadata(widget.userId);
    return raw.map((m) {
      final ts = m['uploadTime'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      final contentType = (m['contentType'] ?? '') as String;
      final isImage = (m['isImage'] as bool?) ?? contentType.startsWith('image/');
      return _TestAttachmentModel(
        docId: (m['docId'] ?? '') as String,
        url: (m['pdfUrl'] ?? '') as String,
        fileName: (m['fileName'] ?? '') as String,
        uploadTime: dt,
        storagePath: (m['storagePath'] ?? '') as String,
        contentType: contentType,
        isImage: isImage,
      );
    }).toList();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _filesFuture = _fetchFiles(); });
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
      );
      if (result == null || result.files.isEmpty) return;

      if (mounted) setState(() { _busy = true; });

      final file = result.files.single;
      final name = file.name;

      List<int> bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw Exception('Dosya okunamadı.');
      }

      // --- SHOW LOADING (do not await) ---
      bool loadingOpen = false;
      if (mounted) {
        DialogUtils.openLoading(context, message: 'Dosya yükleniyor...');
        loadingOpen = true;
      }

      try {
        final provider = Provider.of<TestProvider>(context, listen: false);
        await provider.uploadTestAttachmentFile(
          userId: widget.userId,
          fileName: name,
          fileBytes: bytes,
        );

        // Close loading BEFORE showing info
        if (mounted && loadingOpen) {
          Navigator.of(context, rootNavigator: true).pop(); // close loading dialog
          loadingOpen = false;
        }

        if (mounted) {
          await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Dosya yüklendi.');
          setState(() { _filesFuture = _fetchFiles(); });
        }
      } catch (e) {
        if (mounted && loadingOpen) {
          Navigator.of(context, rootNavigator: true).pop(); // close loading dialog
          loadingOpen = false;
        }
        if (mounted) {
          await DialogUtils.openError(context, title: 'Hata', message: 'Dosya yükleme hatası: $e');
        }
      } finally {
        if (mounted) setState(() { _busy = false; });
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Dosya seçme hatası: $e');
    }
  }

  Future<void> _deleteFile(_TestAttachmentModel f) async {
    final ok = await DialogUtils.openConfirm(
      context,
      title: 'Dosyayı Sil',
      message: '"${f.fileName}" dosyasını silmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (ok != true || !mounted) return;

    try {
      final provider = Provider.of<TestProvider>(context, listen: false);
      await provider.deleteTestAttachment(
        userId: widget.userId,
        docId: f.docId,
        storagePath: f.storagePath,
      );
      if (!mounted) return;
      await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Dosya silindi.');
      setState(() { _filesFuture = _fetchFiles(); });
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Dosya silinemedi: $e');
    }
  }

  void _openFile(_TestAttachmentModel f) async {
    if (f.isImage) {
      _showImagePreview(f.url, f.fileName);
      return;
    }
    // PDF or other ⇒ open externally
    final uri = Uri.parse(f.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Açılamadı: ${f.url}');
    }
  }

  void _showImagePreview(String url, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Görüntü yüklenemedi'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text('Test Dosyaları', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _busy ? null : _pickAndUploadFile,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add),
            label: const Text('Yeni Test Dosyası'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here (it’s a tab). Layout mirrors TanitaExplorerPage body.
    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<_TestAttachmentModel>>(
              future: _filesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Hata: ${snap.error}'),
                      ),
                    ],
                  );
                }

                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 60),
                      Center(child: Text('Hiç dosya yok.')),
                    ],
                  );
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = list[i];
                    final dtStr = f.uploadTime != null
                        ? DateFormat('d MMMM y, HH:mm', 'tr_TR').format(f.uploadTime!.toLocal())
                        : '-';

                    Widget leading;
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
                      leading: leading,
                      title: Text(f.fileName),
                      subtitle: Text(dtStr),
                      onTap: () => _openFile(f),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Sil',
                        onPressed: () => _deleteFile(f),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TestAttachmentModel {
  final String docId;
  final String url;
  final String fileName;
  final DateTime? uploadTime;
  final String storagePath;
  final String contentType;
  final bool isImage;

  _TestAttachmentModel({
    required this.docId,
    required this.url,
    required this.fileName,
    required this.uploadTime,
    required this.storagePath,
    required this.contentType,
    required this.isImage,
  });
}
