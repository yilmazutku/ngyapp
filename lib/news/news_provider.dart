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
  List<NewsModel> _blogList = [];
  bool _isLoading = false;

  List<NewsModel> get newsList => _newsList;
  List<NewsModel> get blogList => _blogList;
  bool get isLoading => _isLoading;

  /// Fetches published news for the announcements page (sorted by createdAt
  /// desc). Items marked as blog-only (showInAnnouncements == false) are
  /// filtered out; legacy items without the flag are treated as visible here.
  Future<List<NewsModel>> fetchPublishedNews() async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      _newsList = snapshot.docs
          .map((doc) => NewsModel.fromDocument(doc))
          .where((news) => news.isVisibleInAnnouncements)
          .toList();
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

  /// Fetches published news marked for the public blog page (showInBlog ==
  /// true). Uses equality-only filters and sorts client-side so no composite
  /// Firestore index is required; legacy items (null flag) never match.
  Future<List<NewsModel>> fetchBlogNews() async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('isPublished', isEqualTo: true)
          .where('showInBlog', isEqualTo: true)
          .get();

      _blogList = snapshot.docs.map((doc) => NewsModel.fromDocument(doc)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _logger.info('Fetched {} blog news items', [_blogList.length]);

      return _blogList;
    } catch (e) {
      _logger.err('Error fetching blog news: $e');
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
    bool showInAnnouncements = true,
    bool showInBlog = false,
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
        showInAnnouncements: showInAnnouncements,
        showInBlog: showInBlog,
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
    bool showInAnnouncements = true,
    bool showInBlog = false,
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
        'showInAnnouncements': showInAnnouncements,
        'showInBlog': showInBlog,
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

