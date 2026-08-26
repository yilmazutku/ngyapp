import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';
import '../models/customer_summary_row.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';

final Logger logger = Logger.forClass(CustomerSummaryProvider);

/// Aggregates, for every non-admin customer that owns a subscription with a
/// given status (e.g. Aktif/Haftalık, Aktif/Kilo Takip, Donduruldu), the data
/// needed by the "Danışanlar Özet" overview page: the last payment of that
/// package (date / amount / type), the package name, and up to
/// [CustomerSummaryRow.maxSeans] session (appointment) dates.
///
/// Every cell in a row describes the *same* subscription — payments included —
/// so the overview cannot disagree with the package's own detail view.
///
/// All Firestore access lives here (per project provider convention); the UI
/// only renders the returned [CustomerSummaryRow]s.
class CustomerSummaryProvider extends ChangeNotifier {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  // Whole lira: payment amounts are never entered with a decimal part.
  final NumberFormat _amountFormat = NumberFormat('#,##0', 'tr_TR');

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      FirebaseFirestore.instance.collection('users');

  /// Builds the overview rows for every customer that owns at least one
  /// subscription with the given [status]. Customers without such a
  /// subscription are skipped. Rows are sorted alphabetically by full name.
  Future<List<CustomerSummaryRow>> fetchCustomerSummariesByStatus(
      SubActiveStatus status) async {
    try {
      // 1) Start from all non-admin customers.
      final customersSnap =
          await _usersRef.where('role', isEqualTo: 'customer').get();

      final customers = customersSnap.docs
          .map((doc) => UserModel.fromDocument(doc))
          .toList();

      logger.info('Building summary for {} customer(s)', [customers.length]);

      // 2) Resolve each customer in parallel; null => no matching subscription.
      final rows = await Future.wait(
        customers.map((c) => _buildRowForCustomer(c, status)),
      );

      final result = rows.whereType<CustomerSummaryRow>().toList()
        ..sort((a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      logger.info('Summary built: {} customer(s) with {} subscription',
          [result.length, status.label]);
      return result;
    } catch (e) {
      logger.err('Error building customer summaries: {}', [e]);
      rethrow;
    }
  }

  /// Returns a row for [user] when they own a package with [status], otherwise
  /// null — the customer is then simply not listed on that tab.
  ///
  /// İş kuralı: bir danışanın aynı anda yalnızca **bir** aktif paketi olur.
  /// Sayfanın mantığı bunun üzerine kurulur: önce o tek paket bulunur, satırın
  /// geri kalanı yalnızca ondan türetilir — ödeme, seans, ertelenen randevular,
  /// kalan erteleme hakkı, dondurulma tarihi. Danışana ait olup **bu pakete ait
  /// olmayan** hiçbir veri satıra giremez; paketten bağımsız tek alanlar
  /// danışanın kimliğidir (dosya no, ad-soyad).
  ///
  /// Per-section failures degrade to "Hata" cells rather than dropping the
  /// whole customer.
  Future<CustomerSummaryRow?> _buildRowForCustomer(
      UserModel user, SubActiveStatus status) async {
    // Satırın var olma koşulu: bu durumda bir paket olmalı.
    final SubscriptionModel? activeSub =
        await _findSubscriptionByStatus(user.userId, status);
    if (activeSub == null) return null;

    final fullName = '${user.name} ${user.surname}'.trim();

    final dosyaNo = (user.dosyaNo != null && user.dosyaNo!.trim().isNotEmpty)
        ? SummaryCell(user.dosyaNo!.trim())
        : const SummaryCell.empty();

    final packageInfo = activeSub.packageName.trim().isNotEmpty
        ? SummaryCell(activeSub.packageName.trim())
        : const SummaryCell.error();

    // Package duration type (1 Aylık / 3 Aylık) followed by a single space and
    // the meeting type (Online / Yüzyüze / Y+O for hybrid). The duration part is
    // empty for legacy packages that predate the field.
    final String meetingSuffix = _meetingTypeLabel(activeSub.meetingType);
    final String? durationLabel = activeSub.packageType?.label;
    final String packageTypeText =
        durationLabel != null ? '$durationLabel $meetingSuffix' : meetingSuffix;
    final packageTypeCell = packageTypeText.trim().isEmpty
        ? const SummaryCell.empty()
        : SummaryCell(packageTypeText);

    final notes = (activeSub.notes != null && activeSub.notes!.trim().isNotEmpty)
        ? SummaryCell(activeSub.notes!.trim())
        : const SummaryCell.empty();

    // Freeze date is only relevant for frozen packages. When a frozen package
    // is missing its freeze date (e.g. legacy data), surface it as an error so
    // the admin knows to set it; other statuses leave the cell empty.
    final SummaryCell freezeDateCell;
    if (status == SubActiveStatus.frozen) {
      freezeDateCell = activeSub.freezeDate != null
          ? SummaryCell(_dateFormat.format(activeSub.freezeDate!))
          : const SummaryCell.error();
    } else {
      freezeDateCell = const SummaryCell.empty();
    }

    // Payments and appointments are unrelated queries, so they are issued
    // together instead of costing two sequential round trips per customer.
    final paymentFuture =
        _resolveLastPayment(user.userId, activeSub.subscriptionId);
    final apptFuture =
        _resolveAppointmentCells(user.userId, activeSub.subscriptionId);
    final payment = await paymentFuture;
    final appts = await apptFuture;

    // Remaining postponement rights for the active subscription. Computed from
    // user-originated postponements only (admin postponements do not reduce the
    // right) via SubscriptionModel.remainingPostponements.
    final remainingCell =
        SummaryCell(activeSub.remainingPostponements.toString());

    return CustomerSummaryRow(
      userId: user.userId,
      dosyaNo: dosyaNo,
      fullName: fullName.isEmpty ? '(İsimsiz)' : fullName,
      paymentDate: payment.date,
      paymentAmount: payment.amount,
      paymentType: payment.type,
      paymentIsPlanned: payment.isPlanned,
      packageInfo: packageInfo,
      packageType: packageTypeCell,
      notes: notes,
      freezeDate: freezeDateCell,
      seans: appts.seans,
      postponedDates: appts.postponedDates,
      remainingPostponements: remainingCell,
    );
  }

  /// The customer's single package with [status], or null when they have none.
  ///
  /// İş kuralı gereği bu sorgu en fazla bir paket döndürmeli
  /// ([SubActiveStatus.isActive] belgesine bakın). Birden fazla çıkıyorsa veri
  /// bozuktur: durum uyarı olarak loglanır ve sayfanın kararlı kalması için
  /// başlangıç tarihi en yeni olan paket kullanılır.
  Future<SubscriptionModel?> _findSubscriptionByStatus(
      String userId, SubActiveStatus status) async {
    try {
      final snap = await _usersRef
          .doc(userId)
          .collection('subscriptions')
          .where('status', isEqualTo: status.label)
          .get();

      if (snap.docs.isEmpty) return null;

      final subs = <SubscriptionModel>[];
      for (final doc in snap.docs) {
        try {
          subs.add(SubscriptionModel.fromDocument(doc));
        } catch (e) {
          logger.warn('Skipping malformed subscription {} for user {}: {}',
              [doc.id, userId, e]);
        }
      }
      if (subs.isEmpty) return null;

      subs.sort((a, b) => b.startDate.compareTo(a.startDate));

      if (subs.length > 1) {
        // Tek aktif paket kuralı bozulmuş: hangi paketlerin çakıştığını yaz ki
        // veri düzeltilebilsin. Satır en yeni paketle kurulmaya devam eder.
        logger.warn(
          'Tek paket kuralı bozuldu: user={} durum={} paket sayısı={} ({}). '
          'En yenisi kullanılıyor: {}',
          [
            userId,
            status.label,
            subs.length,
            subs.map((s) => s.subscriptionId).join(', '),
            subs.first.subscriptionId,
          ],
        );
      }

      return subs.first;
    } catch (e) {
      logger.err('Error fetching {} subscription for user {}: {}',
          [status.label, userId, e]);
      return null;
    }
  }

  /// Resolves the payment shown for the row's package into display cells.
  ///
  /// The lookup is deliberately scoped to [subscriptionId]: a payment made for
  /// an earlier package — or a "Paketsiz" one — is not this package's payment,
  /// and showing it here made an unpaid package look paid while its own detail
  /// still (correctly) reported "Eksik Ödeme".
  ///
  /// Hangi ödeme gösterilir:
  /// - Pakette tamamlanmış ödeme varsa en son alınan o gösterilir.
  /// - Yoksa paketin planlanan ödemesi gösterilir: tutar, planlanan tarih ve
  ///   ödeme şekli aynı sütunlara yazılır, hücreler
  ///   [_PaymentCells.isPlanned] ile işaretlenir; tablo tutarın altına
  ///   "(Planlandı)" notunu düşer. Birden fazla planlanan ödeme varsa tahsil
  ///   sırası gelen (tarihi en yakın olan) gösterilir.
  /// - Pakette hiç ödeme kaydı yoksa hücreler boş kalır.
  /// - Tarihi olmayan bir ödeme => tarih hücresinde "Hata".
  Future<_PaymentCells> _resolveLastPayment(
      String userId, String subscriptionId) async {
    try {
      // A single equality filter needs no composite index, and a package only
      // ever carries a handful of payments, so the status narrowing is done
      // here instead of as a second server-side filter.
      final snap = await _usersRef
          .doc(userId)
          .collection('payments')
          .where('subscriptionId', isEqualTo: subscriptionId)
          .get();

      final completed = <PaymentModel>[];
      final planned = <PaymentModel>[];
      for (final doc in snap.docs) {
        try {
          final payment = PaymentModel.fromDocument(doc);
          if (payment.status == PaymentStatus.completed) {
            completed.add(payment);
          } else if (payment.status == PaymentStatus.planned) {
            planned.add(payment);
          }
        } catch (e) {
          logger.warn('Skipping malformed payment {} for user {}: {}',
              [doc.id, userId, e]);
        }
      }

      // Alınmış para, planlanan paranın önüne geçer: en son tahsil edilen
      // ödeme gösterilir. createDate yedek sıralama anahtarı, tarihi eksik bir
      // ödeme listeden düşmesin diye.
      if (completed.isNotEmpty) {
        completed.sort((a, b) => (b.effectiveDate ?? b.createDate)
            .compareTo(a.effectiveDate ?? a.createDate));
        return _paymentCellsFor(completed.first, isPlanned: false);
      }

      // Henüz tahsil edilmemiş paket: sırada bekleyen (tarihi en yakın)
      // planlanan ödeme gösterilir, "(Planlandı)" notuyla.
      if (planned.isNotEmpty) {
        planned.sort((a, b) => (a.effectiveDate ?? a.createDate)
            .compareTo(b.effectiveDate ?? b.createDate));
        return _paymentCellsFor(planned.first, isPlanned: true);
      }

      return const _PaymentCells.empty();
    } catch (e) {
      logger.err('Error resolving last payment for user {} sub {}: {}',
          [userId, subscriptionId, e]);
      return const _PaymentCells.error();
    }
  }

  /// Turns a single payment into the three payment cells of a row.
  _PaymentCells _paymentCellsFor(PaymentModel payment,
      {required bool isPlanned}) {
    final DateTime? date = payment.effectiveDate;
    return _PaymentCells(
      date: date != null
          ? SummaryCell(_dateFormat.format(date))
          : const SummaryCell.error(),
      amount: SummaryCell(_amountFormat.format(payment.amount)),
      type: SummaryCell(payment.paymentType.label),
      isPlanned: isPlanned,
    );
  }

  /// Resolves both the session (seans) cells and the postponed-appointment
  /// date cells for the active subscription from a single appointment query.
  ///
  /// - Seans: only appointments that actually took place — status "Yapıldı"
  ///   (completed) or "Yakıldı" (burned) — ordered by [appointmentDateTime];
  ///   missing dates become "Hata". Always [CustomerSummaryRow.maxSeans]
  ///   entries. Postponed ("Ertelendi"), still-scheduled and cancelled
  ///   appointments are intentionally excluded here; a postponed appointment
  ///   reappears once it is re-marked "Yapıldı" on its new date.
  /// - Postponed dates: appointments with status "Ertelendi" ordered by
  ///   [postponedDate]; a postponed appointment with no postponedDate becomes
  ///   "Hata". Variable length (only the postponed ones).
  Future<_AppointmentCells> _resolveAppointmentCells(
      String userId, String subscriptionId) async {
    const int max = CustomerSummaryRow.maxSeans;
    try {
      final snap = await _usersRef
          .doc(userId)
          .collection('appointments')
          .where('subscriptionId', isEqualTo: subscriptionId)
          .get();

      final seansDates = <DateTime>[];
      int seansNullCount = 0;

      final postponedDates = <DateTime>[];
      int postponedNullCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        // Match the app convention: only "live" appointments (isDeleted null).
        if (data['isDeleted'] != null) continue;

        final status = data['status'];

        // Seans column: only appointments that actually took place — "Yapıldı"
        // (completed) or "Yakıldı" (burned). Postponed ("Ertelendi"),
        // still-scheduled and cancelled ones are excluded on purpose; a
        // postponed appointment shows up here once it is re-marked "Yapıldı" on
        // its new date.
        final countsAsSeans = status == AppointmentStatus.completed.label ||
            status == AppointmentStatus.burned.label;
        if (countsAsSeans) {
          final rawDate = data['appointmentDateTime'];
          if (rawDate is Timestamp) {
            seansDates.add(rawDate.toDate());
          } else {
            // Field expected but missing/null => surface as an error cell.
            seansNullCount++;
          }
        }

        // Collect postponed ("Ertelendi") appointments separately (independent
        // of the seans filter above).
        if (status == AppointmentStatus.postponed.label) {
          final rawPostponed = data['postponedDate'];
          if (rawPostponed is Timestamp) {
            postponedDates.add(rawPostponed.toDate());
          } else {
            // Postponed but the new date is missing => error.
            postponedNullCount++;
          }
        }
      }

      return _AppointmentCells(
        seans: _buildDateCells(
          dates: seansDates,
          nullCount: seansNullCount,
          cap: max,
          padToCap: true,
        ),
        postponedDates: _buildDateCells(
          dates: postponedDates,
          nullCount: postponedNullCount,
          cap: null,
          padToCap: false,
        ),
      );
    } catch (e) {
      logger.err('Error resolving appointments for user {} sub {}: {}',
          [userId, subscriptionId, e]);
      return _AppointmentCells(
        seans: List<SummaryCell>.filled(max, const SummaryCell.error()),
        postponedDates: const [SummaryCell.error()],
      );
    }
  }

  /// Turns sorted dates (+ a count of broken/null dates) into display cells.
  /// When [cap] is set, keeps the most recent [cap] dates; when [padToCap] is
  /// true the result is padded with empty cells up to [cap].
  /// Short meeting-type label for the summary's "Paket Tipi" column:
  /// Online, Yüzyüze, or Y+O (hybrid = Yüzyüze + Online).
  String _meetingTypeLabel(SubsMeetingType type) {
    switch (type) {
      case SubsMeetingType.online:
        return 'Online';
      case SubsMeetingType.faceToFace:
        return 'Yüzyüze';
      case SubsMeetingType.hybrid:
        return 'Y+O';
    }
  }

  List<SummaryCell> _buildDateCells({
    required List<DateTime> dates,
    required int nullCount,
    required int? cap,
    required bool padToCap,
  }) {
    dates.sort((a, b) => a.compareTo(b));

    var trimmed = dates;
    if (cap != null && dates.length > cap) {
      trimmed = dates.sublist(dates.length - cap);
    }

    final cells = <SummaryCell>[
      ...trimmed.map((d) => SummaryCell(_dateFormat.format(d))),
    ];

    for (int i = 0; i < nullCount; i++) {
      if (cap != null && cells.length >= cap) break;
      cells.add(const SummaryCell.error());
    }

    if (padToCap && cap != null) {
      while (cells.length < cap) {
        cells.add(const SummaryCell.empty());
      }
    }

    return cells;
  }
}

/// Internal holder for the appointment-derived cells (seans + postponed dates).
class _AppointmentCells {
  final List<SummaryCell> seans;
  final List<SummaryCell> postponedDates;

  const _AppointmentCells({
    required this.seans,
    required this.postponedDates,
  });
}

/// Internal holder for the three payment-related cells.
class _PaymentCells {
  final SummaryCell date;
  final SummaryCell amount;
  final SummaryCell type;

  /// Gösterilen ödeme henüz tahsil edilmemiş ("Planlandı") bir ödeme mi.
  /// Tablo bu durumda tutarın altına "(Planlandı)" notunu düşer.
  final bool isPlanned;

  const _PaymentCells({
    required this.date,
    required this.amount,
    required this.type,
    this.isPlanned = false,
  });

  const _PaymentCells.empty()
      : date = const SummaryCell.empty(),
        amount = const SummaryCell.empty(),
        type = const SummaryCell.empty(),
        isPlanned = false;

  const _PaymentCells.error()
      : date = const SummaryCell.error(),
        amount = const SummaryCell.error(),
        type = const SummaryCell.error(),
        isPlanned = false;
}
