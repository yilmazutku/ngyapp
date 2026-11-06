import 'admin_notification.dart';

class BloodTestScanWaiting {
  final NotificationCustomer customer;
  final DateTime listedFrom;

  const BloodTestScanWaiting({
    required this.customer,
    required this.listedFrom,
  });
}

class BloodTestScanPreview {
  final DateTime at;
  final List<NotificationCustomer> missing;
  final List<BloodTestScanWaiting> waiting;
  final int unrecordedCount;

  const BloodTestScanPreview({
    required this.at,
    required this.missing,
    required this.waiting,
    required this.unrecordedCount,
  });
}

class BloodTestScanState {
  final String? lastScanDay;
  final DateTime? lastScanAt;
  final String? lastScanBy;
  final DateTime? presenceInitializedAt;

  const BloodTestScanState({
    this.lastScanDay,
    this.lastScanAt,
    this.lastScanBy,
    this.presenceInitializedAt,
  });

  bool get hasScanned => lastScanDay != null;
}
