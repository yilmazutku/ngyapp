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

