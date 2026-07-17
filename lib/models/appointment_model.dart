import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ngy_app/models/user_model.dart';

import 'appointment_color_palette.dart';
import 'appointment_duration_config.dart';

class AppointmentModel {
  final String appointmentId;
  final String userId;
  final String? subscriptionId;
  final MeetingType meetingType;
  final AppointmentType appointmentType;
  final DateTime appointmentDateTime;
  final AppointmentStatus status;
  final String? notes;
  final DateTime createDate;
  final int durationMinutes;
  DateTime? updateDate;
  final String? createUser;
  String? updateUser;
  String? canceledBy; // 'user' or 'admin'
  DateTime? canceledAt;
  DateTime? postponedDate; // New date when appointment is postponed
  PostponeSource? postponedBy; // Who initiated the postponement (see PostponeSource)
  UserModel?
      user; //sonradan eklendi, userid var ama user yok gosterirken hangi username e ait old icin
  bool? isDeleted = false;


  AppointmentModel({
    required this.appointmentId,
    required this.userId,
    this.subscriptionId,
    required this.meetingType,
    required this.appointmentType,
    required this.appointmentDateTime,
    required this.status,
    this.notes,
    required this.createDate,
    this.updateDate,
    this.createUser,
    this.updateUser,
    this.canceledBy,
    this.canceledAt,
    this.postponedDate,
    this.postponedBy,
    this.user,
    this.isDeleted,
    required this.durationMinutes,
  });

  factory AppointmentModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppointmentModel(
      appointmentId: doc.id,
      userId: data['userId'] ?? '',
      subscriptionId: data['subscriptionId'],
      meetingType: MeetingType.values.firstWhere(
            (e) => e.label == data['meetingType'],
        orElse: () => MeetingType.f2f,
      ),
      appointmentType: AppointmentType.values.firstWhere(
            (e) => e.lbl == data['appointmentType'],
        orElse: () => AppointmentType.diger,
      ),
      appointmentDateTime: (data['appointmentDateTime'] as Timestamp).toDate(),

      durationMinutes: data['durationMinutes'] == null
          ? 30 //default, eski modeller için
          : data['durationMinutes'],

      status: AppointmentStatus.values.firstWhere(
            (e) => e.label == data['status'],
        orElse: () => AppointmentStatus.scheduled,
      ),
      // ... rest stays same
      notes: data['notes'],
      createDate: data['createDate'] != null
          ? (data['createDate'] as Timestamp).toDate()
          : (data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now()),
      updateDate: data['updateDate'] != null
          ? (data['updateDate'] as Timestamp).toDate()
          : (data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null),
      createUser: data['createUser'] ?? data['createdBy'],
      updateUser: data['updateUser'],
      canceledBy: data['canceledBy'],
      canceledAt: data['canceledAt'] != null
          ? (data['canceledAt'] as Timestamp).toDate()
          : null,
      postponedDate: data['postponedDate'] != null
          ? (data['postponedDate'] as Timestamp).toDate()
          : null,
      postponedBy: PostponeSource.fromValue(data['postponedBy'] as String?),
      isDeleted: data['isDeleted'],
    );
  }



  @override
  String toString() {
    return 'AppointmentModel{appointmentId: $appointmentId, userId: $userId, subscriptionId: $subscriptionId, meetingType: $meetingType, appointmentType: $appointmentType, appointmentDateTime: $appointmentDateTime, status: $status, notes: $notes, createDate: $createDate, updateDate: $updateDate, createUser: $createUser, updateUser: $updateUser, canceledBy: $canceledBy, canceledAt: $canceledAt, postponedDate: $postponedDate, postponedBy: $postponedBy, duration: $durationMinutes}';
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'subscriptionId': subscriptionId,
      'meetingType': meetingType.label,
      'appointmentType': appointmentType.lbl,
      'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
      'durationMinutes': durationMinutes,
      'status': status.label,
      'notes': notes,
      'createDate': Timestamp.fromDate(createDate),
      'updateDate': updateDate != null ? Timestamp.fromDate(updateDate!) : null,
      'createUser': createUser,
      'updateUser': updateUser,
      'canceledBy': canceledBy,
      'canceledAt': canceledAt != null ? Timestamp.fromDate(canceledAt!) : null,
      'postponedDate': postponedDate != null ? Timestamp.fromDate(postponedDate!) : null,
      'postponedBy': postponedBy?.value,
      'isDeleted': isDeleted,
    };
  }


  // Common appointment card widget
  Widget buildAppointmentCard({
    required String userName,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    bool showEditButton = false,
    bool isAdmin = false,
  }) {
    final isOverdue = status == AppointmentStatus.scheduled &&
        appointmentDateTime.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isOverdue ? Colors.red[50] : null,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (showEditButton && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: onEdit,
                    tooltip: 'Düzenle',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd MMMM yyyy HH:mm', 'tr_TR')
                      .format(appointmentDateTime),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip(),
                const SizedBox(width: 8),
                _buildMeetingTypeChip(),
              ],
            ),
            if (canceledBy != null) ...[
              const SizedBox(height: 8),
              Text(
                'İptal Eden: $canceledBy',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildStatusChip() {
    Color chipColor;
    switch (status) {
      case AppointmentStatus.scheduled:
        chipColor = Colors.blue;
        break;
      case AppointmentStatus.completed:
        chipColor = Colors.green;
        break;
      case AppointmentStatus.canceled:
      case AppointmentStatus.postponed:
        chipColor = Colors.orange;
        break;
      case AppointmentStatus.burned:
        chipColor = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMeetingTypeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        meetingType.label,
        style: const TextStyle(
          color: Colors.purple,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

enum AppointmentStatus {
  completed('Yapıldı'),
  scheduled('Planlandı'),
  burned('Yakıldı'),
  canceled('Iptal edildi'),
  postponed('Ertelendi');

  const AppointmentStatus(this.label);

  final String label;

  static AppointmentStatus fromLabel(String label) {
    return AppointmentStatus.values.firstWhere((e) => e.label == label);
  }
}

/// Who initiated an appointment postponement.
///
/// Only [PostponeSource.user] postponements consume a customer's postponement
/// rights (see `SubscriptionModel.postponementsUsed`); [PostponeSource.admin]
/// postponements do not affect the remaining rights.
enum PostponeSource {
  user('user', 'Kullanıcı Kaynaklı'),
  admin('admin', 'Admin Kaynaklı');

  const PostponeSource(this.value, this.label);

  /// Stored value in Firestore.
  final String value;

  /// Human-readable label shown in the UI.
  final String label;

  /// Parses the stored [value] back into a [PostponeSource]; returns null when
  /// the appointment has no recorded source (e.g. legacy/non-postponed data).
  static PostponeSource? fromValue(String? value) {
    if (value == null) return null;
    for (final source in PostponeSource.values) {
      if (source.value == value) return source;
    }
    return null;
  }
}

enum MeetingType {
  online('Online'),
  f2f('Yüz yüze');
  const MeetingType(this.label);

  final String label;
  
  static MeetingType fromLabel(String label) {
    return MeetingType.values.firstWhere((e) => e.label == label);
  }

  /// Returns the background color for this meeting type
  Color getBgColor() {
    switch (this) {
      case MeetingType.online:
        return Colors.blue.shade50;
      case MeetingType.f2f:
        return Colors.pink.shade50;
    }
  }

  /// Returns the border color for this meeting type
  Color getBorderColor() {
    switch (this) {
      case MeetingType.online:
        return Colors.blue.shade200;
      case MeetingType.f2f:
        return Colors.pink.shade200;
    }
  }
}

enum AppointmentType {
  haftalik('Haftalık Görüşme','', 30), // default 30, but depends on MeetingType
  pb('Prog. Başlangıcı','Pb', 60),
  og('Ön Görüşme','Ög', 45),
  kgtakip('Kilo Takip','Kilo Takip',30),
  diger('Diğer','Diğer', 30);
  
  const AppointmentType(this.lbl,this.shortLabel, this.durationMinutes);

  final String lbl,shortLabel;
  final int durationMinutes;
  
  static AppointmentType fromLabel(String label) {
    return AppointmentType.values.firstWhere(
      (e) => e.lbl == label,
      orElse: () => AppointmentType.diger,
    );
  }

  /// Returns the default duration (minutes) for this appointment type based on
  /// meeting type. The values come from [AppointmentDurationsRegistry], which
  /// layers admin-configured overrides (see the Testing page /
  /// `admininput/appointmentDurations`) on top of the built-in defaults, so
  /// this reflects the durations configured by the admin. The built-in
  /// fallbacks match the original hard-coded behavior (haftalik: online=20,
  /// f2f=30; pb=60; og=45; kgtakip=30; diger=30).
  int getDurationForMeetingType(MeetingType meetingType) {
    final slot = AppointmentDurationSlot.forAppointment(this, meetingType);
    return AppointmentDurationsRegistry.minutesFor(slot);
  }

  /// Returns the background color for this appointment type. The mapping is
  /// admin-configurable through `admininput/appointmentColors`; values fall
  /// back to the built-in defaults (the original hard-coded colors) when no
  /// override has been set by the admin.
  Color getBgColor(MeetingType meetingType) {
    final slot = AppointmentColorSlot.forAppointment(this, meetingType);
    return AppointmentColorsRegistry.colorFor(slot);
  }

  /// Returns the border color for this appointment type
  /// For haftalik: color depends on meeting type (online=orange, f2f=blue)
  /// For pb and og: color is fixed (pink and yellow)
  Color getBorderColor([MeetingType? meetingType]) {
    switch (this) {
      case AppointmentType.pb:
        return Colors.pink.shade200;
      case AppointmentType.og:
        return Colors.yellow.shade200;
      case AppointmentType.haftalik:
        if (meetingType == null) return Colors.grey.shade200;
        return meetingType == MeetingType.online 
            ? Colors.orange.shade200 
            : Colors.blue.shade200;
      case AppointmentType.diger:
      case AppointmentType.kgtakip:
        return Colors.grey.shade200;
    }
  }
}
