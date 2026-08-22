import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/appointment_model.dart';
import '../models/payment_model.dart';
import '../providers/appointment_manager.dart';
import '../providers/payment_provider.dart';

final Logger log = Logger.forClass(PaymentImportUtil);

class PaymentImportUtil {
  /// High-level: Import from a FILE PATH (convenience).
  /// Useful when your caller already has a path (not used in tests usually).
  static Future<String> importPaymentTrackingDataFromFilePath(
      BuildContext context,
      String userId,
      String path, {
        bool showConfirmation = true,
      }) async {
    log.info('Starting payment import (path) for user: {}', [userId]);
    final bytes = await File(path).readAsBytes();
    return importPaymentTrackingDataFromBytes(
      context,
      userId,
      bytes,
      showConfirmation: showConfirmation,
    );
    // No FilePicker or dialogs here beyond confirmation of parsed content.
  }

  /// Primary entrypoint: Import using BYTES (works great in tests).
  /// - Parses the Excel
  /// - Optionally shows a confirmation dialog with a preview
  /// - Writes Payments + Appointments via providers
  static Future<String> importPaymentTrackingDataFromBytes(
      BuildContext context,
      String userId,
      List<int> bytes, {
        bool showConfirmation = true,
      }) async {
    log.info('Starting payment import (bytes) for user: {}', [userId]);

    try {
      // Acquire providers before any awaits to avoid context issues
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      final appointmentManager = Provider.of<AppointmentManager>(context, listen: false);

      // 1) Parse
      final parsed = parsePaymentTrackingBytes(bytes);
      final paymentsToCreate = parsed.paymentsToCreate;
      final appointmentsToCreate = parsed.appointmentsToCreate;

      if (paymentsToCreate.isEmpty && appointmentsToCreate.isEmpty) {
        log.info('No valid data found in Excel bytes');
        return 'Excel dosyasında geçerli veri bulunamadı.';
      }

      // 2) (Optional) Show colorful preview dialog (original UI)
      if (showConfirmation) {
        if (!context.mounted) {
          return 'İşlem iptal edildi: Geçersiz BuildContext.';
        }

        // Prepare formatters just like before
        final dateFormat = DateFormat('d MMMM y', 'tr_TR');
        final currencyFormat = NumberFormat('#,##0.00 ₺', 'tr_TR');
        final navigator = Navigator.of(context);

        final bool confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            var apptShowCount = 25;
            return AlertDialog(
              title: const Text('İçe Aktarılacak Veriler'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Payments section
                    const Text(
                      'Ödemeler',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (paymentsToCreate.isEmpty)
                      const Text(
                        'Ödenecek tutar bulunamadı.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text('Tarih', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('Tutar', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),

                            // Payment rows
                            ...paymentsToCreate.map((payment) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(dateFormat.format(payment.date)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(currencyFormat.format(payment.amount)),
                                  ),
                                ],
                              ),
                            )),

                            // Total
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    flex: 2,
                                    child: Text('Toplam', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      currencyFormat.format(
                                        paymentsToCreate.fold<double>(0.0, (sum, p) => sum + p.amount),
                                      ),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Appointments section
                    const Text(
                      'Randevular',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (appointmentsToCreate.isEmpty)
                      const Text(
                        'Randevu bulunamadı.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text('Tarih', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('Tür', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),

                            // Appointment rows (limit to 10 with a "and X more" message)
                            ...appointmentsToCreate.take(apptShowCount).map((appointment) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(dateFormat.format(appointment.date)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      appointment.meetingType == MeetingType.f2f ? 'Yüz yüze' : 'Online',
                                    ),
                                  ),
                                ],
                              ),
                            )),

                            // Show "and X more"
                            if (appointmentsToCreate.length > apptShowCount)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                child: Text(
                                  've ${appointmentsToCreate.length - apptShowCount} randevu daha...',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),

                            // Total
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    flex: 2,
                                    child: Text('Toplam', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${appointmentsToCreate.length} randevu',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Warning
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bu veriler içe aktarıldığında, yukarıdaki ödemeler ve randevular oluşturulacaktır.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => navigator.pop(false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () => navigator.pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Onayla ve İçe Aktar'),
                ),
              ],
            );
          },
        ) ?? false;

        if (!confirmed) {
          log.info('User cancelled the import operation');
          return 'İçe aktarma işlemi iptal edildi.';
        }
      }


      // 3) Persist
      int paymentsCreated = 0;
      int appointmentsCreated = 0;

      // Get today's date (at midnight) once before the loop for efficient comparison
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      // Imported rows are independent of each other (fresh document ids, no
      // subscription link), so they are written a few at a time instead of one
      // round trip after another. The cap keeps a large sheet from opening
      // hundreds of concurrent writes at once.
      final appointmentModels = appointmentsToCreate.map((appt) {
        // Mark past appointments as completed ("Yapıldı")
        final apptDateOnly = DateTime(appt.date.year, appt.date.month, appt.date.day);
        final status = apptDateOnly.isBefore(todayMidnight)
            ? AppointmentStatus.completed
            : AppointmentStatus.scheduled;

        return AppointmentModel(
          appointmentId: FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('appointments')
              .doc()
              .id,
          userId: userId,
          subscriptionId: null,
          meetingType: appt.meetingType,
          appointmentDateTime: appt.date,
          status: status,
          notes: 'Excel içe aktarım',
          createDate: DateTime.now(),
          createUser: 'admin',
          appointmentType: AppointmentType.haftalik,
          durationMinutes: AppointmentType.haftalik.durationMinutes,
        );
      }).toList();

      // Appointments first
      appointmentsCreated = await _runInChunks(
        appointmentModels,
        (model) => appointmentManager.addAppointment(model),
      );

      // Payments
      paymentsCreated = await _runInChunks(
        paymentsToCreate,
        (payment) => paymentProvider.addPayment(
          userId: userId,
          amount: payment.amount,
          paymentDate: payment.date,
          status: PaymentStatus.completed,
          // Excel imports don't carry a payment type; default to cash.
          paymentType: PaymentType.nakit,
          notes: 'Excel içe aktarım',
        ),
      );

      log.info('Payment import completed. Created {} payments and {} appointments',
          [paymentsCreated, appointmentsCreated]);

      return 'İçe aktarma tamamlandı.\n$paymentsCreated ödeme ve $appointmentsCreated randevu oluşturuldu.';
    } catch (e) {
      log.err('Error importing payment data: {}', [e]);
      return 'Hata: $e';
    }
  }

  /// Maximum writes issued at the same time while importing a sheet.
  static const int _importConcurrency = 10;

  /// Runs [action] over [items] a few at a time and returns how many finished.
  /// A failing item aborts the import, exactly as the sequential loop did.
  static Future<int> _runInChunks<T>(
    List<T> items,
    Future<void> Function(T item) action,
  ) async {
    int done = 0;
    for (var start = 0; start < items.length; start += _importConcurrency) {
      final end = (start + _importConcurrency < items.length)
          ? start + _importConcurrency
          : items.length;
      await Future.wait(items.sublist(start, end).map(action));
      done = end;
    }
    return done;
  }

  /// Pure parsing: does NOT touch UI or providers. Great for unit tests.
  /// Returns the parsed items you could assert on.
  static _ParsedImport parsePaymentTrackingBytes(List<int> bytes) {
    final excelFile = excel.Excel.decodeBytes(bytes);

    // Take the first sheet
    final sheetName = excelFile.tables.keys.first;
    final table = excelFile.tables[sheetName];

    final List<_ImportPayment> paymentsToCreate = [];
    final List<_ImportAppointment> appointmentsToCreate = [];

    if (table == null) {
      log.info('Excel: no tables found');
      return _ParsedImport(
        paymentsToCreate: paymentsToCreate,
        appointmentsToCreate: appointmentsToCreate,
      );
    }

    // Go through each row, skipping header row if needed (keeping your logic)
    for (int i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      // If row is too short, skip
      if (row.length < 5) continue;

      // Column0 might have "ÜCRET:" ...
      final firstCell = row[0]?.value?.toString().trim() ?? '';
      if (firstCell.isEmpty) continue;

      // Attempt to parse a number from "ÜCRET:XYZ"
      double? parsedPrice;
      if (firstCell.contains('ÜCRET:')) {
        final pricePart = firstCell.replaceRange(0, 'ÜCRET:'.length, '').trim();
        parsedPrice = double.tryParse(pricePart);
      }

      // Gather up to 4 appointment date columns
      final List<String> dateStrings = [];
      for (int d = 1; d < 5; d++) {
        dateStrings.add(row[d]?.value?.toString().trim() ?? '');
      }

      log.debug('Processing date strings: {}', [dateStrings]);

      // For each date, create an appointment if we can parse it as a date
      final List<DateTime> validDates = [];
      for (final ds in dateStrings) {
        if (ds.isEmpty) continue;
        final dt = _tryParseDate(ds);
        if (dt != null) {
          validDates.add(dt);
          log.debug('Valid date parsed: {}', [dt]);
        }
      }

      for (final dt in validDates) {
        appointmentsToCreate.add(_ImportAppointment(
          date: dt,
          meetingType: MeetingType.f2f,
        ));
      }

      // If we have a parsedPrice and at least one valid date, create a payment
      if (parsedPrice != null && validDates.isNotEmpty) {
        final paymentDate = validDates.first;
        paymentsToCreate.add(_ImportPayment(
          amount: parsedPrice,
          date: paymentDate,
        ));
      }
    }

    // Sort for nicer presentation / determinism in tests
    paymentsToCreate.sort((a, b) => a.date.compareTo(b.date));
    appointmentsToCreate.sort((a, b) => a.date.compareTo(b.date));

    return _ParsedImport(
      paymentsToCreate: paymentsToCreate,
      appointmentsToCreate: appointmentsToCreate,
    );
  }

  /// Tries to parse multiple date representations.
  /// Also handles Excel numeric dates (days since 1899-12-30).
  static DateTime? _tryParseDate(String input) {
    log.debug('Trying to parse date: {}', [input]);

    // Excel numeric date?
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(input)) {
      final numericValue = double.tryParse(input);
      if (numericValue != null && numericValue > 10000) {
        try {
          final excelEpoch = DateTime(1899, 12, 30);
          return excelEpoch.add(Duration(days: numericValue.toInt()));
        } catch (e) {
          log.err('Error parsing Excel numeric date: {}', [e]);
        }
      }
    }

    // ISO-ish parse
    try {
      return DateTime.parse(input);
    } catch (_) {
      // Try dd.MM.yyyy, yyyy.MM.dd, d.M.yyyy
      if (input.contains('.')) {
        final parts = input.split('.');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            try {
              return DateTime(year, month, day);
            } catch (_) {}
          }
        }
      }
    }

    return null;
  }
}

/// Simple container for parsed results (test-friendly).
class _ParsedImport {
  final List<_ImportPayment> paymentsToCreate;
  final List<_ImportAppointment> appointmentsToCreate;

  _ParsedImport({
    required this.paymentsToCreate,
    required this.appointmentsToCreate,
  });
}

/// Helper class to store payment data for confirmation & creation
class _ImportPayment {
  final double amount;
  final DateTime date;

  _ImportPayment({
    required this.amount,
    required this.date,
  });
}

/// Helper class to store appointment data for confirmation & creation
class _ImportAppointment {
  final DateTime date;
  final MeetingType meetingType;

  _ImportAppointment({
    required this.date,
    required this.meetingType,
  });
}
