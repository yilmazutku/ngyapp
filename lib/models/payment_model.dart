import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'logger.dart';

class PaymentModel {
  final String paymentId;
  final String userId;
  final String? subscriptionId;
  final String? notes;
  final double amount;
  final DateTime? paymentDate; // Made nullable
  final PaymentStatus status;
  final PaymentType paymentType;
  final String? dekontUrl;
  final DateTime? dueDate;
  final List<int>? notificationTimes;
  final DateTime createDate; // Changed from nullable
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  PaymentModel({
    required this.paymentId,
    required this.userId,
    this.subscriptionId,
    this.notes,
    required this.amount,
    this.paymentDate, // Nullable
    required this.status,
    this.paymentType = PaymentType.na,
    this.dekontUrl,
    this.dueDate,
    this.notificationTimes,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
  }) : createDate = createDate ?? DateTime.now();

  factory PaymentModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentModel(
      paymentId: doc.id,
      userId: data['userId'],
      subscriptionId: data['subscriptionId'],
      notes: data['notes'],
      amount: data['amount'].toDouble(),
      paymentDate: data['paymentDate'] != null
          ? (data['paymentDate'] as Timestamp).toDate()
          : null,
      status: PaymentStatus.fromLabel(data['status']),
      // Legacy payments have no paymentType field; fromLabel maps null to
      // PaymentType.na so the UI shows "-" until an admin sets a real type.
      paymentType: PaymentType.fromLabel(data['paymentType']),
      dekontUrl: data['dekontUrl'],
      dueDate: data['dueDate'] != null
          ? (data['dueDate'] as Timestamp).toDate()
          : null,
      notificationTimes: data['notificationTimes'] != null
          ? List<int>.from(data['notificationTimes'])
          : null,
      // Handle both legacy field names and new field names
      createDate: data['createDate'] != null
          ? (data['createDate'] as Timestamp).toDate()
          : (data['createdAt'] != null
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now()),
      createUser: data['createUser'] ?? data['createdBy'],
      updateDate: data['updateDate'] != null
          ? (data['updateDate'] as Timestamp).toDate()
          : (data['updatedAt'] != null
              ? (data['updatedAt'] as Timestamp).toDate()
              : null),
      updateUser: data['updateUser'] ?? data['updatedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'subscriptionId': subscriptionId,
      'notes': notes,
      'amount': amount,
      'paymentDate':
          paymentDate != null ? Timestamp.fromDate(paymentDate!) : null,
      'status': status.label,
      // Persist null (not the "-" label) for the unspecified type so the data
      // stays clean and round-trips back to PaymentType.na on read.
      'paymentType': paymentType == PaymentType.na ? null : paymentType.label,
      'dekontUrl': dekontUrl,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'notificationTimes': notificationTimes,
      'createDate': Timestamp.fromDate(createDate),
      'createUser': createUser,
      'updateDate': updateDate != null ? Timestamp.fromDate(updateDate!) : null,
      'updateUser': updateUser,
    };
  }
}
// In payment_model.dart (no changes to existing code – just an addition)

// We assume you already have PaymentModel, PaymentStatus, etc. from your snippet above.

/// If the admin version of buildPaymentCard does not suit, define a user-specific version:
extension PaymentModelUIUser on PaymentModel {
  /// Builds a payment card tailored for the *user* perspective.
  Widget buildUserPaymentCard({
    // The user's own name or a placeholder (optional).
    String userDisplayName = 'Sizin Ödemeniz',

    // Called when the user taps the card (if you want to show details, for instance).
    VoidCallback? onTap,

    // Whether we want an edit button at the end. Usually false for a normal user.
    bool showEditButton = false,
    
    // Called when the user wants to delete the payment
    VoidCallback? onDelete,
    
    // Whether to show the delete button
    bool showDeleteButton = false,
  }) {
    // You can keep or remove the "overdue" color if needed.
    final now = DateTime.now();
    final isOverdue = status == PaymentStatus.planned &&
        dueDate != null &&
        dueDate!.isBefore(now);
    // Pending (planned) payments are emphasized so the user notices them: a
    // warning icon plus bold text. Overdue ones get a stronger red accent.
    final isPlanned = status == PaymentStatus.planned;
    final Color accentColor =
        isOverdue ? Colors.red.shade700 : Colors.orange.shade800;
    final TextStyle? infoStyle =
        isPlanned ? const TextStyle(fontWeight: FontWeight.bold) : null;

    return Card(
      color: isOverdue ? Colors.red.shade100 : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: isPlanned
            ? Icon(Icons.warning_amber_rounded, color: accentColor, size: 32)
            : null,
        // A row for userDisplayName and amount
        title: Row(
          children: [
            Expanded(
              child: Text(
                userDisplayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${amount.toStringAsFixed(2)} ₺',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: status == PaymentStatus.completed
                    ? Colors.green
                    : isOverdue
                        ? Colors.red
                        : Colors.blue,
              ),
            ),
          ],
        ),

        // Show minimal payment info for a user (date, status, notes, etc.)
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dueDate != null)
              Text(
                'Planlanan Tarih: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                style: infoStyle,
              ),
            if (status == PaymentStatus.completed && paymentDate != null)
              Text(
                'Ödendiği Tarih: ${DateFormat('dd/MM/yyyy').format(paymentDate!)}',
                style: infoStyle,
              ),
            Text('Durum: ${status.label}', style: infoStyle),
            if (isOverdue)
              Text(
                'Ödeme tarihiniz gecikmiştir.',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            // if (notes != null && notes!.isNotEmpty) Text('Not: $notes'),
          ],
        ),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showEditButton)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: onTap,
                tooltip: 'Düzenle',
              ),
            if (showDeleteButton && onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
                tooltip: 'Sil',
              ),
          ],
        ),
        onTap: onTap, // If you want a user to see more details, do something here
      ),
    );
  }
}

extension PaymentModelUI on PaymentModel {
  Widget buildPaymentCard({
    required String userName,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    bool showEditButton = true,
    bool showDeleteButton = true,
  }) {
    final now = DateTime.now();
    bool isOverdue = status == PaymentStatus.planned &&
        dueDate != null &&
        dueDate!.isBefore(now);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isOverdue ? Colors.red.shade100 : null,
      child: ListTile(
        title: Row(
          children: [
            Text(
              userName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '${amount.toStringAsFixed(2)} ₺',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: status == PaymentStatus.completed
                    ? Colors.green
                    : isOverdue
                    ? Colors.red
                    : Colors.blue,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dueDate != null)
              Text(
                'Planlanan Tarih: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
              ),
            if (status == PaymentStatus.completed && paymentDate != null)
              Text(
                'Ödendiği Tarih: ${DateFormat('dd/MM/yyyy').format(paymentDate!)}',
              ),
            Text('Durum: ${status.label}'),
            if (status == PaymentStatus.completed)
              Text('Ödeme Türü: ${paymentType.label}'),
            if (notes != null && notes!.isNotEmpty) Text('Not: $notes'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showEditButton && onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: onEdit,
                tooltip: 'Düzenle',
              ),
            if (showDeleteButton && onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
                tooltip: 'Sil',
              ),
          ],
        ),
        onTap: onTap ?? onEdit,
      ),
    );
  }
}

final Logger logger = Logger.forClass(PaymentStatus);

enum PaymentStatus {
  completed('Tamamlandı'),
  planned('Planlandı'),
  ;

  const PaymentStatus(this.label);

  final String label;

  // Method to get enum from label
  static PaymentStatus fromLabel(String label) {
    return PaymentStatus.values.firstWhere((e) => e.label == label);
  }

  // static PaymentStatus? fromName(String name) {
  //   try {
  //     return PaymentStatus.values.firstWhere((e) => e.label == name);
  //   } catch (e) {
  //     logger.warn('No matching PaymentStatus found for name: {}', [name]);
  //     return null; // Return null if no match is found
  //   }
  // }
}

enum PaymentType {
  nakit('Nakit'),
  pos('Pos'),
  iban('Iban'),

  /// Placeholder for payments that never had a type set (e.g. legacy records
  /// created before this field existed, or Excel imports). Displayed as "-".
  /// It is intentionally NOT user-selectable; the admin must pick a real type
  /// to move a payment out of this state. See [selectableValues].
  na('-'),
  ;

  const PaymentType(this.label);

  final String label;

  /// The payment types an admin is allowed to choose in the UI.
  /// Excludes [PaymentType.na], which only represents "unspecified".
  static List<PaymentType> get selectableValues =>
      values.where((type) => type != PaymentType.na).toList();

  /// Resolves a [PaymentType] from its stored label.
  /// Falls back to [PaymentType.na] for null/unknown values so legacy payments
  /// without a stored type are surfaced as "-" instead of a real type.
  static PaymentType fromLabel(String? label) {
    if (label == null) return PaymentType.na;
    return PaymentType.values.firstWhere(
      (e) => e.label == label,
      orElse: () => PaymentType.na,
    );
  }
}
