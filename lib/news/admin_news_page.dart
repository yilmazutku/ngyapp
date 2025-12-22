import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/dialog_utils.dart';
import 'add_news_dialog.dart';
import 'news_detail_page.dart';
import 'news_model.dart';
import 'news_provider.dart';

/// Admin page for managing news/announcements
class AdminNewsPage extends StatefulWidget {
  const AdminNewsPage({super.key});

  @override
  State<AdminNewsPage> createState() => _AdminNewsPageState();
}

class _AdminNewsPageState extends State<AdminNewsPage> {
  List<NewsModel> _newsList = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Defer loading until after the build phase to avoid "setState during build" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNews();
    });
  }

  Future<void> _loadNews() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = Provider.of<NewsProvider>(context, listen: false);
      final news = await provider.fetchAllNews();
      if (!mounted) return;
      setState(() {
        _newsList = news;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Haberler yüklenirken bir hata oluştu.';
        _isLoading = false;
      });
    }
  }

  void _openAddNewsDialog() {
    showDialog(
      context: context,
      builder: (context) => AddNewsDialog(
        onSaved: _loadNews,
      ),
    );
  }

  void _openEditNewsDialog(NewsModel news) {
    showDialog(
      context: context,
      builder: (context) => AddNewsDialog(
        news: news,
        onSaved: _loadNews,
      ),
    );
  }

  void _openNewsDetail(NewsModel news) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(news: news),
      ),
    );
  }

  Future<void> _togglePublished(NewsModel news) async {
    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(context, message: 'Durum güncelleniyor...');
        loadingOpen = true;
      }

      final provider = Provider.of<NewsProvider>(context, listen: false);
      await provider.togglePublished(news.newsId, !news.isPublished);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      await _loadNews();
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Durum güncellenirken bir hata oluştu.',
        );
      }
    }
  }

  Future<void> _deleteNews(NewsModel news) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Duyuruyu Sil',
      message: '"${news.title}" duyurusunu silmek istediğinize emin misiniz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed || !mounted) return;

    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(context, message: 'Siliniyor...');
        loadingOpen = true;
      }

      final provider = Provider.of<NewsProvider>(context, listen: false);
      await provider.deleteNews(news.newsId);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Duyuru başarıyla silindi.',
        );
      }

      await _loadNews();
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Duyuru silinirken bir hata oluştu.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duyuru Yönetimi'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadNews,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddNewsDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Duyuru'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadNews,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNews,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_newsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.newspaper, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Henüz duyuru bulunmuyor.',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openAddNewsDialog,
              icon: const Icon(Icons.add),
              label: const Text('İlk Duyuruyu Ekle'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsList.length,
      itemBuilder: (context, index) {
        return _AdminNewsCard(
          news: _newsList[index],
          onTap: () => _openNewsDetail(_newsList[index]),
          onEdit: () => _openEditNewsDialog(_newsList[index]),
          onDelete: () => _deleteNews(_newsList[index]),
          onTogglePublished: () => _togglePublished(_newsList[index]),
        );
      },
    );
  }
}

class _AdminNewsCard extends StatelessWidget {
  final NewsModel news;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePublished;

  const _AdminNewsCard({
    required this.news,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePublished,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy HH:mm', 'tr_TR');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: news.isPublished ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: news.imageUrl != null && news.imageUrl!.isNotEmpty
                      ? Image.network(
                          news.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.newspaper, color: Colors.grey),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            news.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Published status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: news.isPublished
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            news.isPublished ? 'Yayında' : 'Taslak',
                            style: TextStyle(
                              fontSize: 11,
                              color: news.isPublished ? Colors.green[700] : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      news.bodyText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          dateFormat.format(news.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (news.links.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.link, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '${news.links.length} bağlantı',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18, color: Colors.blue[600]),
                            const SizedBox(width: 8),
                            const Text('Düzenle'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              news.isPublished ? Icons.visibility_off : Icons.visibility,
                              size: 18,
                              color: Colors.orange[600],
                            ),
                            const SizedBox(width: 8),
                            Text(news.isPublished ? 'Yayından Kaldır' : 'Yayınla'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red[600]),
                            const SizedBox(width: 8),
                            const Text('Sil'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'toggle':
                          onTogglePublished();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

