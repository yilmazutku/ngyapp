import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/meas_provider.dart';
import '../models/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/dialog_utils.dart';
import '../utils/storage_upload.dart';
import '../widgets/app_bar_with_back.dart';

final Logger log = Logger.forClass(TanitaExplorerPage);

class TanitaExplorerPage extends StatefulWidget {
  final String userId;
  const TanitaExplorerPage({super.key, required this.userId});

  @override
  State<TanitaExplorerPage> createState() => _TanitaExplorerPageState();
}

class _TanitaExplorerPageState extends State<TanitaExplorerPage> {
  late Future<List<TanitaPdfModel>> _pdfListFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pdfListFuture = _fetchTanitaPdfs();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _pdfListFuture = _fetchTanitaPdfs();
      });
    }
  }

  Future<List<TanitaPdfModel>> _fetchTanitaPdfs() async {
    final collectionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('measurements')
        .doc('tanita')
        .collection('pdfFiles');

    final snapshot = await collectionRef.get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return TanitaPdfModel(
        docId: doc.id,
        pdfUrl: data['pdfUrl'] ?? '',
        fileName: data['fileName'] ?? '',
        uploadTime: (data['uploadTime'] as Timestamp?)?.toDate(),
        storagePath: data['storagePath'] ?? '',
      );
    }).toList();
  }

  /// Picks one or more PDFs and uploads them in sequence. A single failing file
  /// does not abort the batch; a summary reports how many succeeded and which
  /// (if any) failed.
  Future<void> _pickAndUploadPdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        // Keep only the file paths (not the bytes) so the picker never loads
        // every selected PDF into memory at once; each file is streamed
        // straight from disk at upload time.
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        log.info('No PDF selected.');
        return;
      }

      if (mounted) setState(() { _busy = true; });

      final files = result.files;
      final total = files.length;
      final progress =
          ValueNotifier<String>('PDF yükleniyor (1/$total)...');

      // --- SHOW LOADING (do not await) ---
      bool loadingOpen = false;
      if (mounted) {
        DialogUtils.openLoadingProgress(context, messageListenable: progress);
        loadingOpen = true;
      }

      int success = 0;
      final List<String> failed = [];
      try {
        final provider = Provider.of<MeasProvider>(context, listen: false);
        for (int i = 0; i < total; i++) {
          final file = files[i];
          progress.value = 'PDF yükleniyor (${i + 1}/$total)...';
          // Guard against pathologically large files that would otherwise make
          // the upload very slow and risk crashing the app on Windows desktop.
          if (file.size > kMaxUploadBytes) {
            log.warn('Tanita PDF too large, skipping: {} ({} bytes)',
                [file.name, file.size]);
            failed.add('${file.name} (çok büyük, en fazla $kMaxUploadSizeLabel)');
            continue;
          }
          final path = file.path;
          if (path == null) {
            log.warn('No file path for Tanita PDF: {}', [file.name]);
            failed.add('${file.name} (dosya okunamadı)');
            continue;
          }
          try {
            await provider.uploadTanitaPdfFile(
              userId: widget.userId,
              fileName: file.name,
              filePath: path, // streamed from disk
            );
            success++;
          } catch (e) {
            log.err('Error uploading Tanita PDF {}: {}', [file.name, e]);
            failed.add(e is UploadTimeoutException
                ? '${file.name} (${e.userMessage})'
                : file.name);
          }
        }

        // Close loading BEFORE showing info/error
        if (mounted && loadingOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          loadingOpen = false;
        }

        if (mounted) {
          setState(() { _pdfListFuture = _fetchTanitaPdfs(); });
          if (failed.isEmpty) {
            await DialogUtils.openInfo(
              context,
              title: 'Başarılı',
              message: '$success PDF yüklendi.',
            );
          } else {
            await DialogUtils.openError(
              context,
              title: success > 0 ? 'Kısmen Tamamlandı' : 'Hata',
              message: '$success PDF yüklendi, ${failed.length} PDF '
                  'yüklenemedi:\n${failed.join('\n')}',
            );
          }
        }
      } catch (e) {
        if (mounted && loadingOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          loadingOpen = false;
        }
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'PDF yükleme hatası: $e',
          );
        }
      } finally {
        progress.dispose();
        if (mounted) setState(() { _busy = false; });
      }
    } catch (e) {
      log.err('File pick error: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Dosya seçme hatası: $e',
      );
    }
  }

  /// Confirms and deletes a Tanita PDF (both its Storage blob and Firestore
  /// metadata), then refreshes the list.
  Future<void> _deletePdf(TanitaPdfModel pdf) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Dosyayı Sil',
      message: '"${pdf.fileName}" dosyasını silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (confirmed != true || !mounted) return;

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Dosya siliniyor...');
      loadingOpen = true;
    }

    try {
      final provider = Provider.of<MeasProvider>(context, listen: false);
      await provider.deleteTanitaPdfFile(
        userId: widget.userId,
        docId: pdf.docId,
        storagePath: pdf.storagePath,
      );

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        setState(() { _pdfListFuture = _fetchTanitaPdfs(); });
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Dosya silindi.',
        );
      }
    } catch (e) {
      log.err('Error deleting Tanita PDF {}: {}', [pdf.docId, e]);
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Dosya silinemedi: $e',
        );
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.04,
        vertical: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tanita PDF Listesi',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _busy ? null : _pickAndUploadPdfs,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add),
            label: const Text('PDF Ekle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(title: 'Tanita PDF Listesi'),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<TanitaPdfModel>>(
                future: _pdfListFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Hata: ${snapshot.error}'),
                        ),
                      ],
                    );
                  }
                  final pdfList = snapshot.data ?? [];
                  if (pdfList.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 60),
                        Center(child: Text('Hiç PDF dosyası yok.')),
                      ],
                    );
                  }
                  return ListView.builder(
                    itemCount: pdfList.length,
                    itemBuilder: (context, index) {
                      final pdf = pdfList[index];
                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        title: Text(pdf.fileName),
                        subtitle: Text(pdf.uploadTime?.toLocal().toString() ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Sil',
                          onPressed: _busy ? null : () => _deletePdf(pdf),
                        ),
                        onTap: () async {
                          final uri = Uri.parse(pdf.pdfUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (mounted) {
                              await DialogUtils.openError(
                                context,
                                title: 'Hata',
                                message: 'PDF açılamadı: ${pdf.pdfUrl}',
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small model for a Tanita PDF
class TanitaPdfModel {
  final String docId;
  final String pdfUrl;
  final String fileName;
  final DateTime? uploadTime;
  final String storagePath;

  TanitaPdfModel({
    required this.docId,
    required this.pdfUrl,
    required this.fileName,
    required this.uploadTime,
    required this.storagePath,
  });
}
