import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'meal_model.dart';

enum ChatLoadTestStatus {
  preparing('preparing', 'Hazırlanıyor'),
  creatingUsers('creatingUsers', 'Kullanıcılar oluşturuluyor'),
  running('running', 'Sürüyor'),
  completed('completed', 'Tamamlandı'),
  cancelled('cancelled', 'Durduruldu'),
  failed('failed', 'Başarısız'),
  unknown('unknown', 'Bilinmiyor');

  const ChatLoadTestStatus(this.value, this.label);

  final String value;
  final String label;

  static ChatLoadTestStatus fromValue(Object? value) {
    for (final ChatLoadTestStatus status in values) {
      if (status.value == value) return status;
    }
    return unknown;
  }

  bool get isActive =>
      this == preparing || this == creatingUsers || this == running;
}

enum ChatLoadTestOrder {
  roundRobin('roundRobin', 'Sırayla', 'Her turda herkes birer fotoğraf'),
  perUser('perUser', 'Kişi kişi', 'Her kişi fotoğraflarını art arda');

  const ChatLoadTestOrder(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  static ChatLoadTestOrder fromValue(Object? value) {
    for (final ChatLoadTestOrder order in values) {
      if (order.value == value) return order;
    }
    return roundRobin;
  }
}

class ChatLoadTestLimits {
  ChatLoadTestLimits._();

  static const int maxUsers = 100;
  static const int maxPhotosPerUser = 10;
  static const int maxSourcePhotos = 5;
  static const double maxGapSeconds = 600;
  static const int maxStartDelaySeconds = 600;
  static const Duration maxDuration = Duration(hours: 2);
  static const Duration stalledAfter = Duration(minutes: 6);
}

class ChatLoadTestUsers {
  ChatLoadTestUsers._();

  static const String uidPrefix = 'loadtest_';
  static final RegExp _uidPattern =
      RegExp(r'^loadtest_[A-Za-z0-9]{8,40}_\d{3}$');

  static bool isTestUserUid(String uid) => _uidPattern.hasMatch(uid);

  static String uidOf(String runId, int index) =>
      '$uidPrefix${runId}_${(index + 1).toString().padLeft(3, '0')}';
}

class ChatLoadTestSlot {
  final int photoIndex;
  final Meals meal;

  const ChatLoadTestSlot({required this.photoIndex, required this.meal});

  Map<String, dynamic> toMap() => {
        'photo': photoIndex,
        'meal': meal.name,
        'caption': meal.chatCaption,
        'summary': meal.chatSummary,
      };
}

class ChatLoadTestConfig {
  final int userCount;
  final int photosPerUser;
  final double gapSeconds;
  final int startDelaySeconds;
  final ChatLoadTestOrder order;

  const ChatLoadTestConfig({
    required this.userCount,
    required this.photosPerUser,
    required this.gapSeconds,
    required this.startDelaySeconds,
    required this.order,
  });

  int get totalMessages => userCount * photosPerUser;

  Duration get sendDuration => Duration(
      milliseconds: ((totalMessages - 1) * gapSeconds * 1000).round());

  Duration get totalDuration =>
      sendDuration + Duration(seconds: startDelaySeconds);

  String? validate(int photoCount) {
    if (photoCount < 1 || photoCount > ChatLoadTestLimits.maxSourcePhotos) {
      return 'En az 1, en fazla ${ChatLoadTestLimits.maxSourcePhotos} '
          'fotoğraf seçin.';
    }
    if (userCount < 1 || userCount > ChatLoadTestLimits.maxUsers) {
      return 'Kullanıcı sayısı 1-${ChatLoadTestLimits.maxUsers} arasında '
          'olmalı.';
    }
    if (photosPerUser < 1 ||
        photosPerUser > ChatLoadTestLimits.maxPhotosPerUser) {
      return 'Kişi başı fotoğraf 1-${ChatLoadTestLimits.maxPhotosPerUser} '
          'arasında olmalı.';
    }
    if (!gapSeconds.isFinite ||
        gapSeconds < 0 ||
        gapSeconds > ChatLoadTestLimits.maxGapSeconds) {
      return 'Mesajlar arası süre 0-'
          '${ChatLoadTestLimits.maxGapSeconds.round()} sn arasında olmalı.';
    }
    if (startDelaySeconds < 0 ||
        startDelaySeconds > ChatLoadTestLimits.maxStartDelaySeconds) {
      return 'Başlama gecikmesi 0-${ChatLoadTestLimits.maxStartDelaySeconds} '
          'sn arasında olmalı.';
    }
    if (totalDuration > ChatLoadTestLimits.maxDuration) {
      return 'Test en fazla ${ChatLoadTestLimits.maxDuration.inHours} saat '
          'sürebilir; kullanıcı, fotoğraf ya da süreyi azaltın.';
    }
    return null;
  }

  List<ChatLoadTestSlot> slotsFor(int photoCount) {
    final List<Meals> meals = Meals.dietValues;
    return [
      for (int i = 0; i < photosPerUser; i++)
        ChatLoadTestSlot(
          photoIndex: i % photoCount,
          meal: meals[i % meals.length],
        ),
    ];
  }

  Map<String, dynamic> toRequest({
    required String runId,
    required List<Map<String, dynamic>> photos,
    required int utcOffsetMinutes,
  }) =>
      {
        'runId': runId,
        'userCount': userCount,
        'photosPerUser': photosPerUser,
        'gapSeconds': gapSeconds,
        'startDelaySeconds': startDelaySeconds,
        'order': order.value,
        'utcOffsetMinutes': utcOffsetMinutes,
        'photos': photos,
        'slots': [
          for (final ChatLoadTestSlot slot in slotsFor(photos.length))
            slot.toMap(),
        ],
      };
}

class ChatLoadTestRun {
  final String id;
  final ChatLoadTestStatus status;
  final DateTime? createdAt;
  final DateTime? startAt;
  final DateTime? finishedAt;
  final DateTime? heartbeatAt;
  final int userCount;
  final int requestedUserCount;
  final int photosPerUser;
  final int totalSteps;
  final int sentCount;
  final int failedCount;
  final double gapSeconds;
  final int startDelaySeconds;
  final ChatLoadTestOrder order;
  final String? lastError;
  final List<String> listedUserIds;

  const ChatLoadTestRun({
    required this.id,
    required this.status,
    this.createdAt,
    this.startAt,
    this.finishedAt,
    this.heartbeatAt,
    this.userCount = 0,
    this.requestedUserCount = 0,
    this.photosPerUser = 0,
    this.totalSteps = 0,
    this.sentCount = 0,
    this.failedCount = 0,
    this.gapSeconds = 0,
    this.startDelaySeconds = 0,
    this.order = ChatLoadTestOrder.roundRobin,
    this.lastError,
    this.listedUserIds = const [],
  });

  factory ChatLoadTestRun.fromMap(String id, Map<String, dynamic> data) {
    DateTime? time(String field) {
      final Object? value = data[field];
      return value is Timestamp ? value.toDate() : null;
    }

    int count(String field) {
      final Object? value = data[field];
      return value is num ? value.toInt() : 0;
    }

    final Object? gap = data['gapSeconds'];
    final Object? error = data['lastError'];
    final Object? users = data['users'];
    return ChatLoadTestRun(
      id: id,
      status: ChatLoadTestStatus.fromValue(data['status']),
      createdAt: time('createdAt'),
      startAt: time('startAt'),
      finishedAt: time('finishedAt'),
      heartbeatAt: time('heartbeatAt'),
      userCount: count('userCount'),
      requestedUserCount: count('requestedUserCount'),
      photosPerUser: count('photosPerUser'),
      totalSteps: count('totalSteps'),
      sentCount: count('sentCount'),
      failedCount: count('failedCount'),
      gapSeconds: gap is num ? gap.toDouble() : 0,
      startDelaySeconds: count('startDelaySeconds'),
      order: ChatLoadTestOrder.fromValue(data['order']),
      lastError: error is String && error.isNotEmpty ? error : null,
      listedUserIds: [
        if (users is List)
          for (final Object? user in users)
            if (user is Map && user['uid'] is String) user['uid'] as String,
      ],
    );
  }

  int get displayUserCount => userCount > 0 ? userCount : requestedUserCount;

  List<String> get testUserIds {
    final List<String> listed = [
      for (final String uid in listedUserIds)
        if (ChatLoadTestUsers.isTestUserUid(uid)) uid,
    ];
    if (listed.isNotEmpty) return listed;
    final int count = userCount.clamp(0, ChatLoadTestLimits.maxUsers).toInt();
    return [for (int i = 0; i < count; i++) ChatLoadTestUsers.uidOf(id, i)];
  }

  int get processedCount => sentCount + failedCount;

  double get progress =>
      totalSteps <= 0 ? 0 : (processedCount / totalSteps).clamp(0.0, 1.0);

  DateTime? get estimatedEndAt => startAt?.add(Duration(
      milliseconds: ((totalSteps - 1).clamp(0, totalSteps) * gapSeconds * 1000)
          .round()));

  bool isStalled(DateTime now) {
    final DateTime? heartbeat = heartbeatAt;
    return status == ChatLoadTestStatus.running &&
        heartbeat != null &&
        now.difference(heartbeat) > ChatLoadTestLimits.stalledAfter;
  }
}

class ChatLoadTestPhoto {
  final Uint8List bytes;
  final String name;
  final String? mimeType;

  const ChatLoadTestPhoto({
    required this.bytes,
    required this.name,
    this.mimeType,
  });
}

class ChatLoadTestCleanupResult {
  final int deletedUsers;
  final int failedUsers;
  final int deletedRuns;
  final String? error;

  const ChatLoadTestCleanupResult({
    required this.deletedUsers,
    required this.failedUsers,
    required this.deletedRuns,
    this.error,
  });

  bool get isComplete => failedUsers == 0 && error == null;
}

class ChatLoadTestStartResult {
  final String runId;
  final int userCount;
  final int totalSteps;
  final DateTime? startAt;

  const ChatLoadTestStartResult({
    required this.runId,
    required this.userCount,
    required this.totalSteps,
    this.startAt,
  });

  factory ChatLoadTestStartResult.fromResult(String runId, Object? result) {
    final Map<Object?, Object?> data =
        result is Map ? Map<Object?, Object?>.from(result) : const {};
    final Object? users = data['userCount'];
    final Object? steps = data['totalSteps'];
    final Object? startAtMs = data['startAtMs'];
    return ChatLoadTestStartResult(
      runId: runId,
      userCount: users is num ? users.toInt() : 0,
      totalSteps: steps is num ? steps.toInt() : 0,
      startAt: startAtMs is num
          ? DateTime.fromMillisecondsSinceEpoch(startAtMs.toInt())
          : null,
    );
  }
}
