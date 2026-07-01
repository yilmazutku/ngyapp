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

  /// Always [maxSeans] entries; unused trailing slots are empty cells.
  final List<SummaryCell> seans;

  const CustomerSummaryRow({
    required this.userId,
    required this.dosyaNo,
    required this.fullName,
    required this.paymentDate,
    required this.paymentAmount,
    required this.paymentType,
    required this.packageInfo,
    required this.seans,
  });
}
