/// Data types backing the "Danışanlar Özet" overview page.
///
/// A [SummaryCell] represents a single cell in the overview table. It can be a
/// normal value, an intentionally empty cell (the customer simply has no data
/// for that column), or an error cell shown as "Hata" when a value is missing
/// where one is expected (e.g. a completed payment with no payment date).
class SummaryCell {
  final String text;
  final bool isError;

  const SummaryCell(this.text) : isError = false;

  const SummaryCell.empty()
      : text = '',
        isError = false;

  const SummaryCell.error()
      : text = 'Hata',
        isError = true;

  bool get isEmpty => !isError && text.isEmpty;
}

/// One row of the customer overview: a customer with an active subscription
/// plus their latest payment info and their session (seans) dates.
class CustomerSummaryRow {
  /// Max number of session (seans) columns displayed per the requirement.
  static const int maxSeans = 12;

  final String userId;
  final SummaryCell dosyaNo;
  final String fullName;
  final SummaryCell paymentDate;
  final SummaryCell paymentAmount;
  final SummaryCell paymentType;
  final SummaryCell packageInfo;

  /// Package duration type (e.g. 1 Aylık / 3 Aylık); empty for legacy packages
  /// that predate the field.
  final SummaryCell packageType;

  /// Free-text notes attached to the active subscription (may be empty).
  final SummaryCell notes;

  /// Date the package was frozen. Only populated for frozen packages; an empty
  /// cell for every other status (the column is only shown on the frozen tab).
  final SummaryCell freezeDate;

  /// Always [maxSeans] entries; unused trailing slots are empty cells.
  final List<SummaryCell> seans;

  /// Dates of postponed ("Ertelendi") appointments for the active subscription.
  /// Variable length; the table pads shorter rows to a common width.
  final List<SummaryCell> postponedDates;

  /// Remaining postponement rights, based on user-originated postponements only
  /// (admin postponements do not reduce it). See
  /// SubscriptionModel.remainingPostponements.
  final SummaryCell remainingPostponements;

  const CustomerSummaryRow({
    required this.userId,
    required this.dosyaNo,
    required this.fullName,
    required this.paymentDate,
    required this.paymentAmount,
    required this.paymentType,
    required this.packageInfo,
    this.packageType = const SummaryCell.empty(),
    required this.notes,
    this.freezeDate = const SummaryCell.empty(),
    required this.seans,
    required this.postponedDates,
    required this.remainingPostponements,
  });
}
