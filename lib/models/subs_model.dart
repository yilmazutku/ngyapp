import 'package:cloud_firestore/cloud_firestore.dart';

enum SubsMeetingType {
  online('online'),
  faceToFace('face_to_face'),
  hybrid('hybrid');

  const SubsMeetingType(this.label);

  final String label;

  static SubsMeetingType fromLabel(String label) {
    return SubsMeetingType.values.firstWhere((e) => e.label == label);
  }
}

/// Package duration type. Selecting one auto-fills the suggested meeting count
/// ([defaultMeetings]) in the add/edit dialogs, but the admin can still adjust
/// the meeting count afterwards.
enum SubsPackageType {
  oneMonth('1 Aylık', 4),
  threeMonth('3 Aylık', 12);

  const SubsPackageType(this.label, this.defaultMeetings);

  /// Human-readable label, also the value stored in Firestore.
  final String label;

  /// Suggested number of meetings pre-filled when this type is selected.
  final int defaultMeetings;

  /// Parses the stored [label] back into a [SubsPackageType]; returns null when
  /// the subscription has no recorded type (e.g. legacy data).
  static SubsPackageType? fromLabel(String? label) {
    if (label == null) return null;
    for (final type in SubsPackageType.values) {
      if (type.label == label) return type;
    }
    return null;
  }
}

class SubscriptionModel {
  final String subscriptionId;
  final String userId;
  final String packageName;

  /// Package duration type (e.g. 1 Aylık / 3 Aylık). Nullable for legacy
  /// subscriptions created before this field existed.
  final SubsPackageType? packageType;
  final String? notes;
  final DateTime startDate;
  final int totalMeetings;
  int meetingsCompleted;
  int meetingsBurned;

  /// Number of postponement rights the customer has consumed. Only
  /// user-originated postponements increment this; admin-initiated
  /// postponements never do, so it always reflects the customer's own usage.
  int postponementsUsed;
  final int allowedPostponements;
  final double totalAmount;
  double amountPaid;
  SubActiveStatus status;
  final SubsMeetingType meetingType;
  final int? onlineMeetings;
  final int? faceToFaceMeetings;

  /// Date the package was frozen. Only meaningful when [status] is
  /// [SubActiveStatus.frozen]; null for every other status.
  DateTime? freezeDate;
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  SubscriptionModel({
    required this.subscriptionId,
    required this.userId,
    required this.packageName,
    this.packageType,
    this.notes,
    required this.startDate,
    required this.totalMeetings,
    this.meetingsCompleted = 0,
    this.meetingsBurned = 0,
    this.postponementsUsed = 0,
    required this.allowedPostponements,
    required this.totalAmount,
    this.amountPaid = 0.0,
    this.status = SubActiveStatus.activeWeekly,
    required this.meetingType,
    this.onlineMeetings,
    this.faceToFaceMeetings,
    this.freezeDate,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
  }) : createDate = createDate ?? DateTime.now();

  factory SubscriptionModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionModel(
      subscriptionId: doc.id,
      userId: data['userId'],
      packageName: data['packageName'],
      packageType: SubsPackageType.fromLabel(data['packageType']),
      notes: data['notes'],
      startDate: (data['startDate'] as Timestamp).toDate(),
      totalMeetings: data['totalMeetings'],
      meetingsCompleted: data['meetingsCompleted'] ?? 0,
      meetingsBurned: data['meetingsBurned'] ?? 0,
      postponementsUsed: data['postponementsUsed'] ?? 0,
      allowedPostponements: data['allowedPostponements'],
      totalAmount: data['totalAmount'].toDouble(),
      amountPaid: data['amountPaid'].toDouble(),
      status: SubActiveStatus.fromLabel(data['status']),
      meetingType: data['meetingType'] != null 
          ? SubsMeetingType.fromLabel(data['meetingType'])
          : SubsMeetingType.faceToFace,
      onlineMeetings: data['onlineMeetings'],
      faceToFaceMeetings: data['faceToFaceMeetings'],
      freezeDate: data['freezeDate'] != null ? (data['freezeDate'] as Timestamp).toDate() : null,
      createDate: data['createDate'] != null ? (data['createDate'] as Timestamp).toDate() : DateTime.now(),
      createUser: data['createUser'],
      updateDate: data['updateDate'] != null ? (data['updateDate'] as Timestamp).toDate() : null,
      updateUser: data['updateUser'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'subscriptionId': subscriptionId,
      'userId': userId,
      'packageName': packageName,
      if (packageType != null) 'packageType': packageType!.label,
      if (notes != null) 'notes': notes,
      'startDate': Timestamp.fromDate(startDate),
      'totalMeetings': totalMeetings,
      'meetingsCompleted': meetingsCompleted,
      'meetingsBurned': meetingsBurned,
      'postponementsUsed': postponementsUsed,
      'allowedPostponements': allowedPostponements,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'status': status.label,
      'meetingType': meetingType.label,
      if (freezeDate != null) 'freezeDate': Timestamp.fromDate(freezeDate!),
      'createDate': Timestamp.fromDate(createDate),
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
    };
    
    if (meetingType == SubsMeetingType.hybrid) {
      if (onlineMeetings != null) {
        map['onlineMeetings'] = onlineMeetings as Object;
      }
      if (faceToFaceMeetings != null) {
        map['faceToFaceMeetings'] = faceToFaceMeetings as Object;
      }
    }
    
    return map;
  }

  @override
  String toString() {
    return 'SubscriptionModel{subscriptionId: $subscriptionId, userId: $userId, packageName: $packageName, packageType: $packageType, notes: $notes, startDate: $startDate, totalMeetings: $totalMeetings, meetingsCompleted: $meetingsCompleted, meetingsBurned: $meetingsBurned, postponementsUsed: $postponementsUsed, allowedPostponements: $allowedPostponements, totalAmount: $totalAmount, amountPaid: $amountPaid, status: $status, meetingType: $meetingType, onlineMeetings: $onlineMeetings, faceToFaceMeetings: $faceToFaceMeetings, freezeDate: $freezeDate, createDate: $createDate, createUser: $createUser, updateDate: $updateDate, updateUser: $updateUser}';
  }

  /// Auto-calculates the suggested allowed postponements for a package
  /// (one per month, i.e. one for every 4 meetings, rounded up).
  static int calculateAllowedPostponements(int totalMeetings) {
    if (totalMeetings <= 0) return 0;
    return (totalMeetings / 4).ceil();
  }

  /// Remaining postponement rights ("kalan erteleme hakkı"), i.e.
  /// [allowedPostponements] minus the postponements already used. Because
  /// [postponementsUsed] only tracks user-originated postponements, this never
  /// counts admin-initiated ones. Clamped so it is never negative. This is the
  /// single source of truth used everywhere the remaining right is shown.
  int get remainingPostponements {
    final remaining = allowedPostponements - postponementsUsed;
    return remaining < 0 ? 0 : remaining;
  }

  /// Whether the customer still has any postponement rights left.
  bool get hasPostponementsLeft => remainingPostponements > 0;

  /// Remaining meeting rights ("kalan görüşme hakkı"), i.e. [totalMeetings]
  /// minus the meetings already completed and burned. Clamped so it is never
  /// negative and never exceeds [totalMeetings]. This is the single source of
  /// truth used everywhere the remaining meeting count is shown/checked.
  int get remainingMeetings {
    final remaining = totalMeetings - meetingsCompleted - meetingsBurned;
    return remaining.clamp(0, totalMeetings);
  }

  /// Whether the customer still has any meeting rights left.
  bool get hasMeetingsLeft => remainingMeetings > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SubscriptionModel &&
              runtimeType == other.runtimeType &&
              subscriptionId == other.subscriptionId;

  @override
  int get hashCode => subscriptionId.hashCode;
}

enum SubActiveStatus {
  activeWeekly('active', 'Aktif/Haftalık'),
  activeWeightTracking('active_kt', 'Aktif/Kilo Takip'),
  completed('completed', 'Tamamlandı'),
  frozen('frozen', 'Donduruldu');

  const SubActiveStatus(this.label, this.displayName);

  final String label;
  final String displayName;

  /// Whether this status represents a live/active package (weekly or weight
  /// tracking). Business rule: only one active package may exist per customer
  /// at a time.
  bool get isActive =>
      this == SubActiveStatus.activeWeekly ||
      this == SubActiveStatus.activeWeightTracking;

  static SubActiveStatus fromLabel(String label) {
    return SubActiveStatus.values.firstWhere((e) => e.label == label);
  }
}
