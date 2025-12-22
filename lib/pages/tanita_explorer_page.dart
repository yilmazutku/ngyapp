import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/meas_provider.dart';
import '../models/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/dialog_utils.dart';
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
      );
    }).toList();
  }

  Future<void> _pickAndUploadPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) {
        log.info('No PDF selected.');
        return;
      }

      final file = result.files.single;
      final fileBytes = file.bytes;
      final filePath = file.path;
      final fileName = file.name;

      if (fileBytes != null) {
        await _uploadToProvider(fileName, fileBytes);
      } else if (filePath != null) {
        final f = File(filePath);
        if (await f.exists()) {
          final readBytes = await f.readAsBytes();
          await _uploadToProvider(fileName, readBytes);
        } else {
          if (!mounted) return;
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Dosya bulunamadı.',
          );
        }
      } else {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Dosya okunamadı.',
        );
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

  Future<void> _uploadToProvider(String fileName, List<int> fileBytes) async {
    final provider = Provider.of<MeasProvider>(context, listen: false);

    // Show blocking loading (do NOT await)
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'PDF yükleniyor...');
      loadingOpen = true;
    }

    try {
      await provider.uploadTanitaPdfFile(
        userId: widget.userId,
        fileName: fileName,
        fileBytes: fileBytes,
      );

      // Close loading BEFORE success dialog
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'PDF yüklendi.',
        );
        setState(() {
          _pdfListFuture = _fetchTanitaPdfs();
        });
      }
    } catch (e) {
      log.err('Error uploading PDF: {}', [e]);

      // Close loading BEFORE error dialog
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
            onPressed: _pickAndUploadPdf,
            icon: const Icon(Icons.add),
            label: const Text('Yeni PDF ekle'),
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

  TanitaPdfModel({
    required this.docId,
    required this.pdfUrl,
    required this.fileName,
    required this.uploadTime,
  });
}
