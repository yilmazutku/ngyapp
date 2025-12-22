# Announcements and news page configuration
_Exported on 12/18/2025 at 17:25:33 GMT+3 from Cursor (2.2.29)_

---

**User**

I'd like to configure a page dedicated for announcements & news. Maybe they may include images. The flow is, admin uploads an image & title for an announcement, with a body text too. When the news page is clicked, user sees the news published by the admin. if clicks, then another page opens with the image of that news, with the body text (explanation of the news) for that news.  the body text may also include links (videos in the future too, if not too complicated?). Admin needs to control the news from the app aswell. Crate a new directory under libs/news for all relevant files u will create. 

---

**Cursor**

I'll help you create a news/announcements feature. Let me first explore the project structure to understand the existing patterns and conventions.

Now I have a clear understanding of the project patterns. Let me create the news/announcements feature.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a news/announcement item
class NewsModel {
  final String newsId;
  final String title;
  final String bodyText;
  final String? imageUrl;
  final List<String> links; // URLs that can be embedded in the body
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final bool isPublished;
  final int orderIndex; // For manual ordering if needed

  NewsModel({
    required this.newsId,
    required this.title,
    required this.bodyText,
    this.imageUrl,
    this.links = const [],
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.isPublished = true,
    this.orderIndex = 0,
  });

  factory NewsModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NewsModel(
      newsId: doc.id,
      title: data['title'] ?? '',
      bodyText: data['bodyText'] ?? '',
      imageUrl: data['imageUrl'],
      links: List<String>.from(data['links'] ?? []),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      createdBy: data['createdBy'],
      isPublished: data['isPublished'] ?? true,
      orderIndex: data['orderIndex'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'bodyText': bodyText,
      'imageUrl': imageUrl,
      'links': links,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'createdBy': createdBy,
      'isPublished': isPublished,
      'orderIndex': orderIndex,
    };
  }

  NewsModel copyWith({
    String? newsId,
    String? title,
    String? bodyText,
    String? imageUrl,
    List<String>? links,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    bool? isPublished,
    int? orderIndex,
  }) {
    return NewsModel(
      newsId: newsId ?? this.newsId,
      title: title ?? this.title,
      bodyText: bodyText ?? this.bodyText,
      imageUrl: imageUrl ?? this.imageUrl,
      links: links ?? this.links,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      isPublished: isPublished ?? this.isPublished,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  String toString() {
    return 'NewsModel{newsId: $newsId, title: $title, isPublished: $isPublished, createdAt: $createdAt}';
  }
}

```

```dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/logger.dart';
import 'news_model.dart';

/// Provider for managing news/announcements CRUD operations
class NewsProvider extends ChangeNotifier {
  final Logger _logger = Logger.forClass(NewsProvider);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const String _collectionPath = 'news';

  List<NewsModel> _newsList = [];
  bool _isLoading = false;

  List<NewsModel> get newsList => _newsList;
  bool get isLoading => _isLoading;

  /// Fetches all published news for user view (sorted by createdAt desc)
  Future<List<NewsModel>> fetchPublishedNews() async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      _newsList = snapshot.docs.map((doc) => NewsModel.fromDocument(doc)).toList();
      _logger.info('Fetched {} published news items', [_newsList.length]);

      return _newsList;
    } catch (e) {
      _logger.err('Error fetching published news: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches all news (published and unpublished) for admin view
  Future<List<NewsModel>> fetchAllNews() async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .get();

      _newsList = snapshot.docs.map((doc) => NewsModel.fromDocument(doc)).toList();
      _logger.info('Fetched {} total news items', [_newsList.length]);

      return _newsList;
    } catch (e) {
      _logger.err('Error fetching all news: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new news item
  Future<void> addNews({
    required String title,
    required String bodyText,
    File? imageFile,
    Uint8List? imageBytes, // For web support
    String? imageName,
    List<String> links = const [],
    bool isPublished = true,
    String? createdBy,
  }) async {
    try {
      String? imageUrl;

      // Upload image if provided
      if (imageFile != null) {
        imageUrl = await _uploadImage(imageFile: imageFile);
      } else if (imageBytes != null && imageName != null) {
        imageUrl = await _uploadImage(imageBytes: imageBytes, imageName: imageName);
      }

      final docRef = _firestore.collection(_collectionPath).doc();

      final news = NewsModel(
        newsId: docRef.id,
        title: title,
        bodyText: bodyText,
        imageUrl: imageUrl,
        links: links,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        isPublished: isPublished,
      );

      await docRef.set(news.toMap());
      _logger.info('News added successfully: ${news.title}');

      // Refresh the list
      await fetchAllNews();
    } catch (e) {
      _logger.err('Error adding news: $e');
      rethrow;
    }
  }

  /// Updates an existing news item
  Future<void> updateNews({
    required String newsId,
    required String title,
    required String bodyText,
    File? newImageFile,
    Uint8List? newImageBytes,
    String? newImageName,
    String? existingImageUrl,
    List<String> links = const [],
    bool isPublished = true,
  }) async {
    try {
      String? imageUrl = existingImageUrl;

      // Upload new image if provided
      if (newImageFile != null) {
        imageUrl = await _uploadImage(imageFile: newImageFile);
      } else if (newImageBytes != null && newImageName != null) {
        imageUrl = await _uploadImage(imageBytes: newImageBytes, imageName: newImageName);
      }

      await _firestore.collection(_collectionPath).doc(newsId).update({
        'title': title,
        'bodyText': bodyText,
        'imageUrl': imageUrl,
        'links': links,
        'isPublished': isPublished,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      _logger.info('News updated successfully: $newsId');

      // Refresh the list
      await fetchAllNews();
    } catch (e) {
      _logger.err('Error updating news: $e');
      rethrow;
    }
  }

  /// Deletes a news item
  Future<void> deleteNews(String newsId) async {
    try {
      // Get the news to check for image
      final doc = await _firestore.collection(_collectionPath).doc(newsId).get();
      if (doc.exists) {
        final news = NewsModel.fromDocument(doc);
        
        // Delete image from storage if exists
        if (news.imageUrl != null && news.imageUrl!.isNotEmpty) {
          try {
            final ref = _storage.refFromURL(news.imageUrl!);
            await ref.delete();
            _logger.info('Deleted image for news: $newsId');
          } catch (e) {
            _logger.warn('Could not delete image for news $newsId: $e');
          }
        }
      }

      await _firestore.collection(_collectionPath).doc(newsId).delete();
      _logger.info('News deleted successfully: $newsId');

      // Refresh the list
      await fetchAllNews();
    } catch (e) {
      _logger.err('Error deleting news: $e');
      rethrow;
    }
  }

  /// Toggles the published status of a news item
  Future<void> togglePublished(String newsId, bool isPublished) async {
    try {
      await _firestore.collection(_collectionPath).doc(newsId).update({
        'isPublished': isPublished,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      _logger.info('News $newsId published status changed to: $isPublished');

      // Refresh the list
      await fetchAllNews();
    } catch (e) {
      _logger.err('Error toggling published status: $e');
      rethrow;
    }
  }

  /// Uploads an image to Firebase Storage
  Future<String> _uploadImage({
    File? imageFile,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageName ?? 'news_image.jpg'}';
      final ref = _storage.ref().child('news/$fileName');

      UploadTask uploadTask;
      if (imageFile != null) {
        uploadTask = ref.putFile(imageFile);
      } else if (imageBytes != null) {
        uploadTask = ref.putData(imageBytes);
      } else {
        throw Exception('No image data provided');
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      _logger.info('Image uploaded to: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      _logger.err('Error uploading image: $e');
      rethrow;
    }
  }
}

```

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'news_detail_page.dart';
import 'news_model.dart';
import 'news_provider.dart';

/// User-facing page that displays a list of published news/announcements
class NewsListPage extends StatefulWidget {
  const NewsListPage({super.key});

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  List<NewsModel> _newsList = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = Provider.of<NewsProvider>(context, listen: false);
      final news = await provider.fetchPublishedNews();
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

  void _openNewsDetail(NewsModel news) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(news: news),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duyurular'),
        centerTitle: true,
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
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsList.length,
      itemBuilder: (context, index) {
        return _NewsCard(
          news: _newsList[index],
          onTap: () => _openNewsDetail(_newsList[index]),
        );
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsModel news;
  final VoidCallback onTap;

  const _NewsCard({
    required this.news,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMMM yyyy', 'tr_TR');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section
            if (news.imageUrl != null && news.imageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  news.imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
            // Content section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    news.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    news.bodyText,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateFormat.format(news.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Devamını oku',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'news_model.dart';

/// Detail page showing full news content with image and clickable links
class NewsDetailPage extends StatelessWidget {
  final NewsModel news;

  const NewsDetailPage({super.key, required this.news});

  // Regex pattern to detect URLs in text
  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s\)\]\}]+)',
    caseSensitive: false,
  );

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with image
          SliverAppBar(
            expandedHeight: news.imageUrl != null && news.imageUrl!.isNotEmpty
                ? 250
                : 0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                news.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 10,
                      color: Colors.black54,
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              background: news.imageUrl != null && news.imageUrl!.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          news.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 64),
                              ),
                            );
                          },
                        ),
                        // Gradient overlay for better text visibility
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date info
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        dateFormat.format(news.createdAt),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (news.updatedAt != null) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.update, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Güncellendi: ${dateFormat.format(news.updatedAt!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Title (shown if no image or for accessibility)
                  if (news.imageUrl == null || news.imageUrl!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        news.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  // Body text with clickable links
                  _buildRichText(context, news.bodyText),
                  // Explicit links section
                  if (news.links.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Bağlantılar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...news.links.map((link) => _buildLinkItem(context, link)),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds rich text with clickable URLs
  Widget _buildRichText(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _urlRegex.allMatches(text)) {
      // Add text before URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: Colors.grey[800],
          ),
        ));
      }

      // Add clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          fontSize: 16,
          height: 1.6,
          color: Theme.of(context).primaryColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
      ));

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          fontSize: 16,
          height: 1.6,
          color: Colors.grey[800],
        ),
      ));
    }

    // If no URLs found, just return plain text
    if (spans.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.6,
          color: Colors.grey[800],
        ),
      );
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  Widget _buildLinkItem(BuildContext context, String link) {
    // Try to extract a readable name from URL
    String displayName = link;
    try {
      final uri = Uri.parse(link);
      displayName = uri.host + uri.path;
      if (displayName.length > 40) {
        displayName = '${displayName.substring(0, 40)}...';
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _launchUrl(link),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.link, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.open_in_new,
                color: Theme.of(context).primaryColor,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```

```dart
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
    _loadNews();
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

```

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../utils/dialog_utils.dart';
import 'news_model.dart';
import 'news_provider.dart';

/// Dialog for adding or editing a news/announcement
class AddNewsDialog extends StatefulWidget {
  final NewsModel? news; // If provided, we're editing
  final VoidCallback? onSaved;

  const AddNewsDialog({
    super.key,
    this.news,
    this.onSaved,
  });

  @override
  State<AddNewsDialog> createState() => _AddNewsDialogState();
}

class _AddNewsDialogState extends State<AddNewsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _linkController = TextEditingController();

  final List<String> _links = [];
  bool _isPublished = true;
  bool _isSaving = false;

  // Image handling
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _existingImageUrl;

  bool get _isEditing => widget.news != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.news!.title;
      _bodyController.text = widget.news!.bodyText;
      _links.addAll(widget.news!.links);
      _isPublished = widget.news!.isPublished;
      _existingImageUrl = widget.news!.imageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = pickedFile.name;
          _selectedImageFile = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _selectedImageFile = File(pickedFile.path);
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _existingImageUrl = null;
    });
  }

  void _addLink() {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;

    // Basic URL validation
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı http:// veya https:// ile başlamalıdır')),
      );
      return;
    }

    setState(() {
      _links.add(link);
      _linkController.clear();
    });
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(
          context,
          message: _isEditing ? 'Duyuru güncelleniyor...' : 'Duyuru ekleniyor...',
        );
        loadingOpen = true;
      }

      final provider = Provider.of<NewsProvider>(context, listen: false);

      if (_isEditing) {
        await provider.updateNews(
          newsId: widget.news!.newsId,
          title: _titleController.text.trim(),
          bodyText: _bodyController.text.trim(),
          newImageFile: _selectedImageFile,
          newImageBytes: _selectedImageBytes,
          newImageName: _selectedImageName,
          existingImageUrl: _existingImageUrl,
          links: _links,
          isPublished: _isPublished,
        );
      } else {
        await provider.addNews(
          title: _titleController.text.trim(),
          bodyText: _bodyController.text.trim(),
          imageFile: _selectedImageFile,
          imageBytes: _selectedImageBytes,
          imageName: _selectedImageName,
          links: _links,
          isPublished: _isPublished,
        );
      }

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved?.call();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Duyuru güncellendi' : 'Duyuru eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: _isEditing
              ? 'Duyuru güncellenirken bir hata oluştu.'
              : 'Duyuru eklenirken bir hata oluştu.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 600.0 : screenWidth * 0.95;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditing ? Icons.edit : Icons.add,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Duyuru Düzenle' : 'Yeni Duyuru',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Başlık *',
                          hintText: 'Duyuru başlığını girin',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Başlık zorunludur';
                          }
                          return null;
                        },
                        maxLength: 150,
                      ),
                      const SizedBox(height: 16),

                      // Body text field
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          labelText: 'İçerik *',
                          hintText: 'Duyuru içeriğini girin (URL\'ler otomatik olarak tıklanabilir olacaktır)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'İçerik zorunludur';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Image section
                      _buildImageSection(),
                      const SizedBox(height: 16),

                      // Links section
                      _buildLinksSection(),
                      const SizedBox(height: 16),

                      // Publish status
                      SwitchListTile(
                        title: const Text('Yayınla'),
                        subtitle: Text(
                          _isPublished
                              ? 'Duyuru kullanıcılara görünür olacak'
                              : 'Duyuru taslak olarak kaydedilecek',
                        ),
                        value: _isPublished,
                        onChanged: (value) {
                          setState(() {
                            _isPublished = value;
                          });
                        },
                        secondary: Icon(
                          _isPublished ? Icons.visibility : Icons.visibility_off,
                          color: _isPublished ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveNews,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isEditing ? Icons.save : Icons.add),
                    label: Text(_isEditing ? 'Kaydet' : 'Ekle'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Görsel',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        if (_selectedImageFile != null ||
            _selectedImageBytes != null ||
            (_existingImageUrl != null && _existingImageUrl!.isNotEmpty))
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _selectedImageBytes != null
                    ? Image.memory(
                        _selectedImageBytes!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      )
                    : _selectedImageFile != null
                        ? Image.file(
                            _selectedImageFile!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            _existingImageUrl!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                ),
                              );
                            },
                          ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blue,
                      child: IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.white),
                        onPressed: _pickImage,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.white),
                        onPressed: _removeImage,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          InkWell(
            onTap: _pickImage,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey[500]),
                    const SizedBox(height: 8),
                    Text(
                      'Görsel seçmek için tıklayın',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLinksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bağlantılar (Opsiyonel)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addLink(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).primaryColor,
              onPressed: _addLink,
              tooltip: 'Bağlantı Ekle',
            ),
          ],
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _links.asMap().entries.map((entry) {
              final index = entry.key;
              final link = entry.value;
              // Show shortened URL
              String shortLink = link;
              try {
                final uri = Uri.parse(link);
                shortLink = uri.host;
                if (shortLink.length > 25) {
                  shortLink = '${shortLink.substring(0, 25)}...';
                }
              } catch (_) {}

              return Chip(
                label: Text(shortLink, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeLink(index),
                backgroundColor: Colors.blue.withOpacity(0.1),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Not: İçerik alanındaki URL\'ler otomatik olarak tıklanabilir olur. Buraya eklenen bağlantılar ayrı bir bölümde gösterilir.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

```

Now let me update `main.dart` to register the provider and add navigation, and also check if the required packages are in the project:

Good, the required packages (`image_picker` and `url_launcher`) are already in the project. Now let me update `main.dart`:

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

Now let me add the navigation methods and grid items for the news pages:

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  void _navigateToNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewsListPage(),
      ),
    );
  }

  void _navigateToAdminNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminNewsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  void _navigateToNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewsListPage(),
      ),
    );
  }

  void _navigateToAdminNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminNewsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
          {
            'icon': Icons.newspaper,
            'label': 'Duyurular',
            'onTap': () => _navigateToNews(context),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  void _navigateToNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewsListPage(),
      ),
    );
  }

  void _navigateToAdminNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminNewsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
          {
            'icon': Icons.newspaper,
            'label': 'Duyurular',
            'onTap': () => _navigateToNews(context),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
            {
              'icon': Icons.campaign,
              'label': 'Duyuru Yönetimi',
              'onTap': () => _navigateToAdminNews(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

Now let me check for linter errors in the created files:

I've successfully created the news/announcements feature. Here's a summary of what was created:

## Created Files in `lib/news/`

### 1. `news_model.dart`
The data model for news items with:
- `newsId`, `title`, `bodyText`, `imageUrl`
- `links` - array of URLs to display as separate clickable links
- `createdAt`, `updatedAt`, `createdBy`
- `isPublished` - for draft/publish toggle
- `orderIndex` - for manual ordering if needed

### 2. `news_provider.dart`
ChangeNotifier provider with all CRUD operations:
- `fetchPublishedNews()` - for user view (only published items)
- `fetchAllNews()` - for admin view (all items)
- `addNews()` - with image upload support (File or Uint8List for web)
- `updateNews()` - edit existing news
- `deleteNews()` - deletes news and associated image from storage
- `togglePublished()` - quick publish/unpublish toggle

### 3. `news_list_page.dart`
User-facing news list page:
- Displays published news in attractive cards with image thumbnails
- Pull-to-refresh support
- Shows title, preview of body text, and date
- Tapping opens the detail page

### 4. `news_detail_page.dart`
Full news detail view:
- Large hero image with gradient overlay
- Full body text with **automatic URL detection** - any URL in the text becomes clickable
- Separate "Links" section for explicitly added links
- Uses `url_launcher` to open links externally

### 5. `admin_news_page.dart`
Admin management page:
- Lists all news (published & drafts)
- Visual indicators for published status (badge + border color)
- Quick actions via popup menu: Edit, Toggle Publish, Delete
- FAB to add new news
- Confirmation dialogs for destructive actions

### 6. `add_news_dialog.dart`
Add/Edit dialog:
- Title and body text fields
- Image picker (gallery) with preview
- Links management (add/remove URLs)
- Publish toggle switch
- Works for both add and edit modes

## Navigation Added to `main.dart`
- **NewsProvider** registered in the providers list
- **"Duyurular"** item added to user grid (newspaper icon)
- **"Duyuru Yönetimi"** item added to admin grid (campaign icon)

## Features
✅ Admin uploads news with image, title, body text, and optional links  
✅ Users see published news in a list  
✅ Clicking news opens detail page with full content  
✅ URLs in body text are automatically clickable  
✅ Explicit links section at the bottom  
✅ Draft/publish status control  
✅ Full CRUD for admin  
✅ Images stored in Firebase Storage under `news/` folder  
✅ Responsive design for mobile & desktop

---

**User**

how can we send notifications to users when a new news is published? a new .js file is required to do so? If so plz do. Make sure firebase handles the notification sendings. Be thorough

---

**Cursor**

I'll help you set up push notifications for new news publications using Firebase Cloud Functions. Let me first examine the existing Cloud Functions setup:

I can see the existing pattern. I'll add a Cloud Function that triggers when a news is published, and update the FCM service to handle navigation when users tap the notification. Let me update the files:

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif(must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif channels (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif channels (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

/**
 * Build Android notification config for news/announcements.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfigForNews(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: NEWS_CHANNEL_ID,
      icon: 'ic_notification',
      color: '#1976D2', // Blue color for news
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_HIGH',
    },
  };
}

/**
 * Collects all FCM tokens from all users (excluding admins).
 * @return {Promise<string[]>} Array of FCM tokens.
 */
async function getAllUserTokens() {
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const allTokens = [];

  usersSnapshot.docs.forEach((doc) => {
    const userId = doc.id;
    // Skip admins - they see news in admin panel anyway
    if (ADMIN_UIDS.has(userId)) return;

    const userData = doc.data();
    if (userData && Array.isArray(userData.tokens)) {
      allTokens.push(...userData.tokens);
    }
  });

  // Deduplicate tokens
  return Array.from(new Set(allTokens));
}

/**
 * Removes invalid FCM tokens from all user documents.
 * @param {string[]} invalidTokens Array of invalid tokens to remove.
 */
async function removeInvalidTokensFromAllUsers(invalidTokens) {
  if (!invalidTokens.length) return;

  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const batch = admin.firestore().batch();
  let batchCount = 0;

  for (const doc of usersSnapshot.docs) {
    const userData = doc.data();
    if (!userData || !Array.isArray(userData.tokens)) continue;

    // Check if this user has any of the invalid tokens
    const hasInvalid = userData.tokens.some((t) => invalidTokens.includes(t));
    if (!hasInvalid) continue;

    batch.update(doc.ref, {
      tokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
    });
    batchCount++;

    // Firestore batches have a limit of 500 operations
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  logger.info(`Removed ${invalidTokens.length} invalid tokens from users`);
}

/**
 * Sends push notifications to all users when a new news is published.
 * Triggers on news document creation.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsCreated = onDocumentCreated(
    'news/{newsId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newsData = snap.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news is published
      if (!newsData.isPublished) {
        logger.info(`News ${newsId} is not published, skipping notification`);
        return;
      }

      const title = newsData.title || 'Yeni Duyuru';
      const body = truncate(newsData.bodyText || '', 100);

      logger.info(`Sending notification for new news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches (FCM limit is 500 per request)
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfig(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News notification sent for: ${newsId}`);
    },
);

/**
 * Sends push notifications when a news is updated to published state.
 * Only triggers if news was previously unpublished and is now published.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsPublished = onDocumentUpdated(
    'news/{newsId}',
    async (event) => {
      const beforeData = event.data?.before?.data() || {};
      const afterData = event.data?.after?.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news just became published
      // (was not published before, is published now)
      const wasDraft = !beforeData.isPublished;
      const isNowPublished = afterData.isPublished === true;

      if (!wasDraft || !isNowPublished) {
        logger.info(`News ${newsId} publish state unchanged, skipping`);
        return;
      }

      const title = afterData.title || 'Yeni Duyuru';
      const body = truncate(afterData.bodyText || '', 100);

      logger.info(`Sending notification for newly published news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfig(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News publish notification sent for: ${newsId}`);
    },
);

```

Now let me update the FCM service to handle the 'news' notification type for navigation:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54), // WhatsApp dark green
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366), // WhatsApp green
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54), // WhatsApp dark green
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366), // WhatsApp green
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

Now let me update the in-app notification banner to show the appropriate icon for news:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    // Determine notification type for icon/color
    final type = (data['type'] ?? '').toString();
    final isNews = type == 'news';

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        icon: isNews ? Icons.campaign : Icons.chat,
        backgroundColor: isNews ? const Color(0xFF1976D2) : const Color(0xFF075E54),
        accentColor: isNews ? const Color(0xFF64B5F6) : const Color(0xFF25D366),
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54), // WhatsApp dark green
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366), // WhatsApp green
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    // Determine notification type for icon/color
    final type = (data['type'] ?? '').toString();
    final isNews = type == 'news';

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        icon: isNews ? Icons.campaign : Icons.chat,
        backgroundColor: isNews ? const Color(0xFF1976D2) : const Color(0xFF075E54),
        accentColor: isNews ? const Color(0xFF64B5F6) : const Color(0xFF25D366),
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final IconData icon;
  final Color backgroundColor;
  final Color accentColor;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
    this.icon = Icons.chat,
    this.backgroundColor = const Color(0xFF075E54),
    this.accentColor = const Color(0xFF25D366),
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54), // WhatsApp dark green
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366), // WhatsApp green
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    // Determine notification type for icon/color
    final type = (data['type'] ?? '').toString();
    final isNews = type == 'news';

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        icon: isNews ? Icons.campaign : Icons.chat,
        backgroundColor: isNews ? const Color(0xFF1976D2) : const Color(0xFF075E54),
        accentColor: isNews ? const Color(0xFF64B5F6) : const Color(0xFF25D366),
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final IconData icon;
  final Color backgroundColor;
  final Color accentColor;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
    this.icon = Icons.chat,
    this.backgroundColor = const Color(0xFF075E54),
    this.accentColor = const Color(0xFF25D366),
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: widget.accentColor,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                widget.icon,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    // Determine notification type for icon/color
    final type = (data['type'] ?? '').toString();
    final isNews = type == 'news';

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        icon: isNews ? Icons.campaign : Icons.chat,
        backgroundColor: isNews ? const Color(0xFF1976D2) : const Color(0xFF075E54),
        accentColor: isNews ? const Color(0xFF64B5F6) : const Color(0xFF25D366),
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    _pendingMessage = message;
    _tryOpenPendingMessage();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final IconData icon;
  final Color backgroundColor;
  final Color accentColor;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
    this.icon = Icons.chat,
    this.backgroundColor = const Color(0xFF075E54),
    this.accentColor = const Color(0xFF25D366),
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: widget.accentColor,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                widget.icon,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


```

Now let me update the Android `string.xml` to add the news notification channel:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Default FCM notification channel -->
    <string name="notification_channel_id" translatable="false">chat_messages_v2</string>
    
    <!-- Chat notifications channel settings -->
    <string name="chat_channel_name">Sohbet Mesajları</string>
    <string name="chat_channel_description">Yeni sohbet mesajı bildirimleri</string>
    
    <!-- News/Announcements notification channel -->
    <string name="news_channel_id" translatable="false">news_announcements</string>
    <string name="news_channel_name">Duyurular</string>
    <string name="news_channel_description">Yeni duyuru bildirimleri</string>
</resources>
```

Let me check if there's a custom MainActivity or Application file that creates notification channels:

Let me update the MyApplication.kt to add the news notification channel:

```plaintext
package com.example.untitled

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.multidex.MultiDexApplication

class MyApplication : MultiDexApplication() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            // Chat messages channel - high importance for instant notifications
            val chatChannel = NotificationChannel(
                getString(R.string.notification_channel_id),
                getString(R.string.chat_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.chat_channel_description)
                enableLights(true)
                lightColor = 0xFF075E54.toInt() // WhatsApp green
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                setShowBadge(true)
            }

            // News/Announcements channel - high importance for timely announcements
            val newsChannel = NotificationChannel(
                getString(R.string.news_channel_id),
                getString(R.string.news_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.news_channel_description)
                enableLights(true)
                lightColor = 0xFF1976D2.toInt() // Blue color
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200, 100, 200)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannel(chatChannel)
            notificationManager.createNotificationChannel(newsChannel)
        }
    }
} 
```

Let me check for linter errors:

Now let me verify the Cloud Functions file is complete:

I've implemented the complete notification system for news/announcements. Here's a comprehensive summary:

## What Was Added

### 1. Firebase Cloud Functions (`functions/index.js`)

**Two new Cloud Functions:**

1. **`notifyUsersOnNewsCreated`** - Triggers when a new news document is created in the `news` collection
   - Only sends notifications if `isPublished: true`
   - Sends to all users (excluding admins)

2. **`notifyUsersOnNewsPublished`** - Triggers when a news document is updated
   - Only sends notifications when a draft becomes published (`isPublished: false → true`)
   - Prevents duplicate notifications for regular edits

**Helper functions added:**
- `getAllUserTokens()` - Collects FCM tokens from all non-admin users
- `removeInvalidTokensFromAllUsers()` - Cleans up expired/invalid tokens in batches
- `buildAndroidConfigForNews()` - Android notification config with blue color theme

**Features:**
- ✅ Batch processing (handles 500+ devices efficiently)
- ✅ Invalid token cleanup (automatic removal of expired tokens)
- ✅ Admin exclusion (admins don't receive notifications - they see news in admin panel)
- ✅ Emoji prefix in title (`📢`)

### 2. Flutter FCM Service (`lib/services/fcm_service.dart`)

**Updates:**
- Added `'news'` case to notification tap handler → navigates to `NewsListPage`
- Updated in-app banner to support different icons/colors:
  - News notifications: Blue theme with campaign icon
  - Chat notifications: Green theme with chat icon

### 3. Android Configuration

**`string.xml`** - Added news channel strings:
```xml
<string name="news_channel_id">news_announcements</string>
<string name="news_channel_name">Duyurular</string>
<string name="news_channel_description">Yeni duyuru bildirimleri</string>
```

**`MyApplication.kt`** - Added news notification channel:
- Blue LED color (`#1976D2`)
- High importance (heads-up notifications)
- Custom vibration pattern

---

## Deployment Steps

To deploy the Cloud Functions, run:

```bash
cd functions
npm install
firebase deploy --only functions
```

Or deploy specific functions:
```bash
firebase deploy --only functions:notifyUsersOnNewsCreated,functions:notifyUsersOnNewsPublished
```

---

## How It Works

1. **Admin creates/publishes news** via the app
2. **Cloud Function triggers** when Firestore document is created/updated
3. **Function fetches all user FCM tokens** from `users` collection
4. **FCM sends notifications** to all devices in batches of 500
5. **User taps notification** → App opens `NewsListPage`
6. **Invalid tokens are cleaned up** automatically

The notification will appear as:
- **Title:** `📢 [News Title]`
- **Body:** First 100 characters of news content
- **Channel:** "Duyurular" (Android only)

```xml
<string name="news_channel_id">news_announcements</string>
<string name="news_channel_name">Duyurular</string>
<string name="news_channel_description">Yeni duyuru bildirimleri</string>
```

```shellscript
cd functions
npm install
firebase deploy --only functions
```

```shellscript
firebase deploy --only functions:notifyUsersOnNewsCreated,functions:notifyUsersOnNewsPublished
```

---

**User**

does it apply to ios users as well? if not please make sure it does.

---

**Cursor**

Good question! The Cloud Functions already send notifications to iOS via APNs (Apple Push Notification service) using the `buildApnsConfig()` function. However, let me verify the iOS setup is complete:

```javascript
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}
```

Good news! Your iOS setup is already **fully configured**. Looking at your files:

**`AppDelegate.swift`** ✅ Already has:
- Firebase Messaging delegate
- APNs token registration
- Foreground notification handling
- Notification tap handling

**`Info.plist`** ✅ Already has:
- `remote-notification` background mode
- `FirebaseMessagingAutoInitEnabled`

**Cloud Functions** ✅ Already uses `buildApnsConfig()` which sends proper APNs notifications.

The news notifications **will work on iOS** because the same FCM infrastructure is used. However, let me enhance the APNs config to be more specific for news notifications:

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif channels (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @param {string} category Optional notification category for action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfig(category = null) {
  const apsPayload = {
    'sound': 'default',
    'badge': 1,
    'mutable-content': 1,
    'content-available': 1,
  };

  // Add category if provided (for actionable notifications)
  if (category) {
    apsPayload['category'] = category;
  }

  return {
    payload: {
      aps: apsPayload,
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Build iOS (APNs) notification config for news/announcements.
 * Uses 'news' category for potential future action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfigForNews() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
        'category': 'NEWS_CATEGORY', // For future actionable notifications
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

/**
 * Build Android notification config for news/announcements.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfigForNews(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: NEWS_CHANNEL_ID,
      icon: 'ic_notification',
      color: '#1976D2', // Blue color for news
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_HIGH',
    },
  };
}

/**
 * Collects all FCM tokens from all users (excluding admins).
 * @return {Promise<string[]>} Array of FCM tokens.
 */
async function getAllUserTokens() {
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const allTokens = [];

  usersSnapshot.docs.forEach((doc) => {
    const userId = doc.id;
    // Skip admins - they see news in admin panel anyway
    if (ADMIN_UIDS.has(userId)) return;

    const userData = doc.data();
    if (userData && Array.isArray(userData.tokens)) {
      allTokens.push(...userData.tokens);
    }
  });

  // Deduplicate tokens
  return Array.from(new Set(allTokens));
}

/**
 * Removes invalid FCM tokens from all user documents.
 * @param {string[]} invalidTokens Array of invalid tokens to remove.
 */
async function removeInvalidTokensFromAllUsers(invalidTokens) {
  if (!invalidTokens.length) return;

  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const batch = admin.firestore().batch();
  let batchCount = 0;

  for (const doc of usersSnapshot.docs) {
    const userData = doc.data();
    if (!userData || !Array.isArray(userData.tokens)) continue;

    // Check if this user has any of the invalid tokens
    const hasInvalid = userData.tokens.some((t) => invalidTokens.includes(t));
    if (!hasInvalid) continue;

    batch.update(doc.ref, {
      tokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
    });
    batchCount++;

    // Firestore batches have a limit of 500 operations
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  logger.info(`Removed ${invalidTokens.length} invalid tokens from users`);
}

/**
 * Sends push notifications to all users when a new news is published.
 * Triggers on news document creation.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsCreated = onDocumentCreated(
    'news/{newsId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newsData = snap.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news is published
      if (!newsData.isPublished) {
        logger.info(`News ${newsId} is not published, skipping notification`);
        return;
      }

      const title = newsData.title || 'Yeni Duyuru';
      const body = truncate(newsData.bodyText || '', 100);

      logger.info(`Sending notification for new news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches (FCM limit is 500 per request)
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfig(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News notification sent for: ${newsId}`);
    },
);

/**
 * Sends push notifications when a news is updated to published state.
 * Only triggers if news was previously unpublished and is now published.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsPublished = onDocumentUpdated(
    'news/{newsId}',
    async (event) => {
      const beforeData = event.data?.before?.data() || {};
      const afterData = event.data?.after?.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news just became published
      // (was not published before, is published now)
      const wasDraft = !beforeData.isPublished;
      const isNowPublished = afterData.isPublished === true;

      if (!wasDraft || !isNowPublished) {
        logger.info(`News ${newsId} publish state unchanged, skipping`);
        return;
      }

      const title = afterData.title || 'Yeni Duyuru';
      const body = truncate(afterData.bodyText || '', 100);

      logger.info(`Sending notification for newly published news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfig(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News publish notification sent for: ${newsId}`);
    },
);

```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif channels (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @param {string} category Optional notification category for action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfig(category = null) {
  const apsPayload = {
    'sound': 'default',
    'badge': 1,
    'mutable-content': 1,
    'content-available': 1,
  };

  // Add category if provided (for actionable notifications)
  if (category) {
    apsPayload['category'] = category;
  }

  return {
    payload: {
      aps: apsPayload,
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Build iOS (APNs) notification config for news/announcements.
 * Uses 'news' category for potential future action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfigForNews() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
        'category': 'NEWS_CATEGORY', // For future actionable notifications
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

/**
 * Build Android notification config for news/announcements.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfigForNews(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: NEWS_CHANNEL_ID,
      icon: 'ic_notification',
      color: '#1976D2', // Blue color for news
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_HIGH',
    },
  };
}

/**
 * Collects all FCM tokens from all users (excluding admins).
 * @return {Promise<string[]>} Array of FCM tokens.
 */
async function getAllUserTokens() {
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const allTokens = [];

  usersSnapshot.docs.forEach((doc) => {
    const userId = doc.id;
    // Skip admins - they see news in admin panel anyway
    if (ADMIN_UIDS.has(userId)) return;

    const userData = doc.data();
    if (userData && Array.isArray(userData.tokens)) {
      allTokens.push(...userData.tokens);
    }
  });

  // Deduplicate tokens
  return Array.from(new Set(allTokens));
}

/**
 * Removes invalid FCM tokens from all user documents.
 * @param {string[]} invalidTokens Array of invalid tokens to remove.
 */
async function removeInvalidTokensFromAllUsers(invalidTokens) {
  if (!invalidTokens.length) return;

  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const batch = admin.firestore().batch();
  let batchCount = 0;

  for (const doc of usersSnapshot.docs) {
    const userData = doc.data();
    if (!userData || !Array.isArray(userData.tokens)) continue;

    // Check if this user has any of the invalid tokens
    const hasInvalid = userData.tokens.some((t) => invalidTokens.includes(t));
    if (!hasInvalid) continue;

    batch.update(doc.ref, {
      tokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
    });
    batchCount++;

    // Firestore batches have a limit of 500 operations
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  logger.info(`Removed ${invalidTokens.length} invalid tokens from users`);
}

/**
 * Sends push notifications to all users when a new news is published.
 * Triggers on news document creation.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsCreated = onDocumentCreated(
    'news/{newsId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newsData = snap.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news is published
      if (!newsData.isPublished) {
        logger.info(`News ${newsId} is not published, skipping notification`);
        return;
      }

      const title = newsData.title || 'Yeni Duyuru';
      const body = truncate(newsData.bodyText || '', 100);

      logger.info(`Sending notification for new news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches (FCM limit is 500 per request)
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News notification sent for: ${newsId}`);
    },
);

/**
 * Sends push notifications when a news is updated to published state.
 * Only triggers if news was previously unpublished and is now published.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsPublished = onDocumentUpdated(
    'news/{newsId}',
    async (event) => {
      const beforeData = event.data?.before?.data() || {};
      const afterData = event.data?.after?.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news just became published
      // (was not published before, is published now)
      const wasDraft = !beforeData.isPublished;
      const isNowPublished = afterData.isPublished === true;

      if (!wasDraft || !isNowPublished) {
        logger.info(`News ${newsId} publish state unchanged, skipping`);
        return;
      }

      const title = afterData.title || 'Yeni Duyuru';
      const body = truncate(afterData.bodyText || '', 100);

      logger.info(`Sending notification for newly published news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News publish notification sent for: ${newsId}`);
    },
);

```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif channels (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @param {string} category Optional notification category for action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfig(category = null) {
  const apsPayload = {
    'sound': 'default',
    'badge': 1,
    'mutable-content': 1,
    'content-available': 1,
  };

  // Add category if provided (for actionable notifications)
  if (category) {
    apsPayload['category'] = category;
  }

  return {
    payload: {
      aps: apsPayload,
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Build iOS (APNs) notification config for news/announcements.
 * Uses 'news' category for potential future action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfigForNews() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
        'category': 'NEWS_CATEGORY', // For future actionable notifications
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

/**
 * Build Android notification config for news/announcements.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfigForNews(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: NEWS_CHANNEL_ID,
      icon: 'ic_notification',
      color: '#1976D2', // Blue color for news
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_HIGH',
    },
  };
}

/**
 * Collects all FCM tokens from all users (excluding admins).
 * @return {Promise<string[]>} Array of FCM tokens.
 */
async function getAllUserTokens() {
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const allTokens = [];

  usersSnapshot.docs.forEach((doc) => {
    const userId = doc.id;
    // Skip admins - they see news in admin panel anyway
    if (ADMIN_UIDS.has(userId)) return;

    const userData = doc.data();
    if (userData && Array.isArray(userData.tokens)) {
      allTokens.push(...userData.tokens);
    }
  });

  // Deduplicate tokens
  return Array.from(new Set(allTokens));
}

/**
 * Removes invalid FCM tokens from all user documents.
 * @param {string[]} invalidTokens Array of invalid tokens to remove.
 */
async function removeInvalidTokensFromAllUsers(invalidTokens) {
  if (!invalidTokens.length) return;

  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const batch = admin.firestore().batch();
  let batchCount = 0;

  for (const doc of usersSnapshot.docs) {
    const userData = doc.data();
    if (!userData || !Array.isArray(userData.tokens)) continue;

    // Check if this user has any of the invalid tokens
    const hasInvalid = userData.tokens.some((t) => invalidTokens.includes(t));
    if (!hasInvalid) continue;

    batch.update(doc.ref, {
      tokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
    });
    batchCount++;

    // Firestore batches have a limit of 500 operations
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  logger.info(`Removed ${invalidTokens.length} invalid tokens from users`);
}

/**
 * Sends push notifications to all users when a new news is published.
 * Triggers on news document creation.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsCreated = onDocumentCreated(
    'news/{newsId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newsData = snap.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news is published
      if (!newsData.isPublished) {
        logger.info(`News ${newsId} is not published, skipping notification`);
        return;
      }

      const title = newsData.title || 'Yeni Duyuru';
      const body = truncate(newsData.bodyText || '', 100);

      logger.info(`Sending notification for new news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches (FCM limit is 500 per request)
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News notification sent for: ${newsId}`);
    },
);

/**
 * Sends push notifications when a news is updated to published state.
 * Only triggers if news was previously unpublished and is now published.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsPublished = onDocumentUpdated(
    'news/{newsId}',
    async (event) => {
      const beforeData = event.data?.before?.data() || {};
      const afterData = event.data?.after?.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news just became published
      // (was not published before, is published now)
      const wasDraft = !beforeData.isPublished;
      const isNowPublished = afterData.isPublished === true;

      if (!wasDraft || !isNowPublished) {
        logger.info(`News ${newsId} publish state unchanged, skipping`);
        return;
      }

      const title = afterData.title || 'Yeni Duyuru';
      const body = truncate(afterData.bodyText || '', 100);

      logger.info(`Sending notification for newly published news: ${title}`);

      // Get all user tokens
      const tokens = await getAllUserTokens();
      if (tokens.length === 0) {
        logger.info('No user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices`);

      // Send notification in batches
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: '📢 ' + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news publish', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News publish notification sent for: ${newsId}`);
    },
);

```

**Yes, iOS users are fully supported!** Here's the confirmation:

## ✅ iOS Notification Setup (Already Complete)

### AppDelegate.swift
- Firebase Messaging delegate ✓
- APNs token registration ✓
- Foreground notification display ✓
- Notification tap handling ✓

### Info.plist
- `remote-notification` background mode ✓
- `FirebaseMessagingAutoInitEnabled` ✓

### Cloud Functions (Enhanced)
I added a dedicated `buildApnsConfigForNews()` function that:
- Sets proper APNs payload with sound and badge
- Includes `NEWS_CATEGORY` for future action buttons
- Uses priority 10 for immediate delivery

## How Notifications Work on iOS

| Feature | iOS Behavior |
|---------|-------------|
| **Notification Sound** | Default iOS sound |
| **Badge** | App icon shows badge count |
| **Banner** | Appears at top when app in background |
| **Foreground** | Shows banner even when app is open |
| **Tap Action** | Opens NewsListPage |

## Important iOS Prerequisites

Make sure you have:

1. ✅ **Apple Developer Account** with Push Notifications capability
2. ✅ **APNs Authentication Key** uploaded to Firebase Console:
   - Go to Firebase Console → Project Settings → Cloud Messaging
   - Under "Apple app configuration", upload your APNs key (.p8 file)

If you haven't done step 2, notifications won't reach iOS devices. You can generate the key in Apple Developer Portal → Certificates, Identifiers & Profiles → Keys → Create a new key with "Apple Push Notifications service (APNs)" enabled.

---

**After deploying the Cloud Functions, both Android and iOS users will receive:**
- 📢 **Push notification** when new news is published
- **Tap to open** the news list page
- **Sound and badge** on both platforms

---

**User**

you said "If you haven't done step 2, notifications won't reach iOS devices. You can generate the key in Apple Developer Portal → Certificates, Identifiers & Profiles → Keys → Create a new key with "Apple Push Notifications service (APNs)" enabled." is this only for news announcement notifications or is it applicable for chat notifications as well?

---

**Cursor**

Great question! The APNs key requirement applies to **ALL push notifications on iOS**, including:

- ✉️ Chat notifications
- 📢 News/announcement notifications
- 🔔 Any future notifications you add

## Quick Check

**If your chat notifications are already working on iOS devices**, then your APNs key is already configured in Firebase Console, and you're all set! The news notifications will work automatically.

**If chat notifications are NOT working on iOS** (only on Android), then you need to upload the APNs key - and once you do, BOTH chat and news notifications will start working on iOS.

## Why?

Firebase Cloud Messaging (FCM) needs the APNs key to communicate with Apple's servers. It's a one-time setup that enables all iOS push notifications for your app:

```
Your App → Cloud Functions → FCM → APNs (Apple) → iOS Device
                                    ↑
                            Requires APNs Key
```

---

**TL;DR:** If iOS users are already receiving chat messages as push notifications, you don't need to do anything extra for news notifications - they'll just work! 🎉

```plaintext
Your App → Cloud Functions → FCM → APNs (Apple) → iOS Device
                                    ↑
                            Requires APNs Key
```

---

**User**

apn key creation asks me for environment and key restriction. environment has: " Sandbox, Production, Sandbox & Production" as 3 options. the other one has  "Team Scoped (All Topics), Topic Specific" as 2 options. what do i choose?

---

**Cursor**

For Firebase Cloud Messaging, choose these options:

## Environment
**→ Select: `Sandbox & Production`**

This ensures notifications work for:
- Development builds (when testing on your device via Xcode)
- Production builds (App Store / TestFlight releases)

## Key Restriction
**→ Select: `Team Scoped (All Topics)`**

This is simpler and allows the key to work for all your apps under your Apple Developer team. No need to restrict it to specific topics.

---

## Summary

| Setting | Choose |
|---------|--------|
| Environment | **Sandbox & Production** |
| Key Restriction | **Team Scoped (All Topics)** |

After creating the key:
1. Download the `.p8` file (you can only download it once!)
2. Note the **Key ID** shown
3. Go to **Firebase Console → Project Settings → Cloud Messaging**
4. Under "Apple app configuration", click **Upload** and provide:
   - The `.p8` file
   - Key ID
   - Your Team ID (found in Apple Developer Portal → Membership)

That's it! iOS push notifications will work for both chat and news. 🎉

---

**User**

do i add devicecheck to enabled stuff list?

---

**Cursor**

**No, you don't need DeviceCheck for push notifications.**

## What to Enable

Only enable:
- ✅ **Apple Push Notifications service (APNs)** - Required for push notifications

## What NOT to Enable (unless you need them)

- ❌ **DeviceCheck** - Used for fraud prevention, tracking device state (e.g., "has this device used a free trial before?"). Not related to push notifications.
- ❌ Other services - Only add what you specifically need

---

**Just enable APNs, and you're good to go!** 🔔

---

**User**

u said "nder "Apple app configuration", click Upload and provide:
The .p8 file
Key ID
Your Team ID (found in Apple Developer Portal → Membership)" but under APNs Authentication Key, it asks for  " No development APNs auth key
No production APNs auth key" and under certificates it has 2 places too: No development APNs certificate
No production APNs certificate


---

**Cursor**

Since you created a `.p8` **Authentication Key** (not a certificate), use the **APNs Authentication Key** section, not the certificates section.

## What to Do

1. **Click "Upload"** next to either the development or production APNs auth key row
   - With your `.p8` key (Sandbox & Production), **one upload covers both**

2. **Provide:**
   - **APNs auth key** → Upload your `.p8` file
   - **Key ID** → The 10-character ID shown when you created the key (e.g., `ABC123DEFG`)
   - **Team ID** → Found in Apple Developer Portal → Membership (e.g., `XYZ789`)

## Key vs Certificate

| Method | File Type | Recommendation |
|--------|-----------|----------------|
| **APNs Authentication Key** | `.p8` | ✅ **Use this** (newer, simpler, one key for both environments) |
| APNs Certificate | `.p12` | ❌ Older method, requires separate certs for dev/prod |

---

After uploading, Firebase will show your key ID and both "development" and "production" status should update since your key supports both environments.

**You're on the right track - just upload the `.p8` file in the Authentication Key section!** 🔑

---

**User**

when i uploaded for dev auth, it didnt auto update production auth but i uploaded the same .p8 file with same key, it seems to have worked. would it warn me if it was not ok to upload the same stuff for both of them?

---

**Cursor**

**Yes, that's perfectly fine!** ✅

## Why It's OK

Since you created your key with **"Sandbox & Production"** environment, the same `.p8` file works for both:

- ✅ **Development (Sandbox)** - For testing via Xcode
- ✅ **Production** - For App Store / TestFlight builds

Firebase doesn't auto-fill both slots from one upload, but uploading the same key to both is exactly the right thing to do.

## Would It Warn You?

Firebase would show an error if:
- ❌ The key file was invalid or corrupted
- ❌ The Key ID didn't match the file
- ❌ The Team ID was wrong

**No error = You're all set!** 🎉

---

Your iOS push notifications should now work for both development and production builds. Test it by:
1. Publishing a news item from the admin panel
2. Checking if your iOS device receives the notification

---

**User**

do the devices need to be running the app in background to receive notifications or do they receive it even if the app was terminated? asking for both ios and android.

---

**Cursor**

Great question! **Notifications work even when the app is completely closed/terminated** on both platforms.

## How It Works

| App State | Android | iOS |
|-----------|---------|-----|
| **Foreground** (app open) | ✅ Received (shows in-app banner) | ✅ Received (shows in-app banner) |
| **Background** (app minimized) | ✅ Received (system notification) | ✅ Received (system notification) |
| **Terminated** (app killed/closed) | ✅ Received (system notification) | ✅ Received (system notification) |
| **Device restarted** | ✅ Received (after boot) | ✅ Received (after boot) |

## Why?

Push notifications are handled by the **operating system**, not your app:

```
Cloud Functions → FCM → Android System → Shows notification
                    ↘ APNs → iOS System → Shows notification
```

Your app doesn't need to be running because:
- **Android**: Google Play Services / FCM service runs in the background
- **iOS**: APNs daemon runs at the system level

## Requirements

The only requirements are:
1. ✅ User opened the app **at least once** (to register FCM token)
2. ✅ User granted notification permissions
3. ✅ Device has internet connection
4. ✅ App is not "Force Stopped" (Android Settings → Apps → Force Stop)

## When User Taps the Notification

| App State | What Happens |
|-----------|--------------|
| Foreground | In-app banner tap handler runs |
| Background | App comes to foreground, navigates to NewsListPage |
| Terminated | App launches fresh, then navigates to NewsListPage |

---

**TL;DR:** Users will receive news notifications even if they've completely closed the app! 📱🔔

```plaintext
Cloud Functions → FCM → Android System → Shows notification
                    ↘ APNs → iOS System → Shows notification
```

