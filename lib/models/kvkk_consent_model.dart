import 'package:cloud_firestore/cloud_firestore.dart';

/// Current version of the KVKK documents.
/// Increment this when KVKK texts are updated to prompt users to re-consent.
const String kvkkCurrentVersion = '1.0';

/// Model for storing KVKK consent data.
/// Tracks which versions of consent documents were accepted and when.
class KvkkConsentModel {
  /// Version of the KVKK Aydınlatma Metni that was accepted
  final String? kvkkVersion;
  
  /// Timestamp when KVKK Aydınlatma Metni was acknowledged
  final DateTime? kvkkAcceptedAt;
  
  /// Timestamp when explicit consent for special category data was given
  final DateTime? explicitConsentAcceptedAt;

  KvkkConsentModel({
    this.kvkkVersion,
    this.kvkkAcceptedAt,
    this.explicitConsentAcceptedAt,
  });

  /// Creates a KvkkConsentModel from Firestore document data
  factory KvkkConsentModel.fromMap(Map<String, dynamic> data) {
    return KvkkConsentModel(
      kvkkVersion: data['kvkkVersion'] as String?,
      kvkkAcceptedAt: data['kvkkAcceptedAt'] != null
          ? (data['kvkkAcceptedAt'] as Timestamp).toDate()
          : null,
      explicitConsentAcceptedAt: data['explicitConsentAcceptedAt'] != null
          ? (data['explicitConsentAcceptedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Converts the model to a map for Firestore storage
  Map<String, dynamic> toMap() {
    return {
      if (kvkkVersion != null) 'kvkkVersion': kvkkVersion,
      if (kvkkAcceptedAt != null)
        'kvkkAcceptedAt': Timestamp.fromDate(kvkkAcceptedAt!),
      if (explicitConsentAcceptedAt != null)
        'explicitConsentAcceptedAt':
            Timestamp.fromDate(explicitConsentAcceptedAt!),
    };
  }

  /// Returns true if the user has accepted the current version of KVKK
  /// and has given explicit consent for special category data
  bool get hasValidConsent {
    return kvkkVersion == kvkkCurrentVersion &&
        kvkkAcceptedAt != null &&
        explicitConsentAcceptedAt != null;
  }

  /// Returns true if consent needs to be updated due to version change
  bool get needsUpdate {
    if (kvkkVersion == null) return true;
    return kvkkVersion != kvkkCurrentVersion;
  }
}
