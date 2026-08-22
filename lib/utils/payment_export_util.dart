import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';

/// Builds an .xlsx workbook out of a payment list and lets the admin choose
/// where to save it.
///
/// Desktop only (see [isSupported]): the app has no web target and mobile has
/// no real file system for the admin to save a report into.
///
/// Deliberately UI-free (no BuildContext): business logic only returns a
/// result, the caller owns the loading indicator and the info/error dialogs.
class PaymentExportUtil {
  PaymentExportUtil._();

  static final Logger _log = Logger('PaymentExportUtil');

  static const String _defaultSheetName = 'Sheet1';
  static const String _totalRowLabel = 'TOPLAM';
  static const String _typeBreakdownLabel = 'ÖDEME TİPİNE GÖRE';
  static const String _fileExtension = 'xlsx';
  static const String _unknownUserLabel = 'Bilinmiyor';
  static const String _fallbackFileName = 'Odemeler';

  static const List<String> _headers = [
    'Danışan',
    'E-posta',
    'Ödeme Tarihi',
    'Planlanan Tarih',
    'Tutar (₺)',
    'Ödeme Tipi',
    'Durum',
    'Notlar',
  ];

  /// Column widths (in characters) matching [_headers], so the exported sheet
  /// is readable without manual resizing.
  static const List<double> _columnWidths = [26, 28, 14, 16, 14, 14, 14, 34];

  /// Column the amounts live in, shared by the data rows and the summary rows.
  static const int _amountColumn = 4;

  static final DateFormat _cellDateFormat = DateFormat('dd.MM.yyyy');
  static final DateFormat _fileStampFormat = DateFormat('yyyyMMdd_HHmm');

  /// Excel export is offered on desktop only (macOS / Windows / Linux); the
  /// mobile builds have no save dialog worth exporting a report through.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Writes [payments] into a workbook and prompts for a save location.
  ///
  /// Returns the path the file was written to, or `null` when the user
  /// cancels the save dialog. Throws on encoding/write failures so the caller
  /// can surface an error dialog.
  static Future<String?> exportPayments({
    required List<PaymentModel> payments,
    required Map<String, UserModel> userById,
    required String titleLabel,
  }) async {
    _log.info('Exporting {} payments to Excel ({})', [payments.length, titleLabel]);

    final bytes = _buildWorkbook(
      payments: payments,
      userById: userById,
      titleLabel: titleLabel,
    );

    final fileName =
        '${_sanitizeFileName(titleLabel)}_${_fileStampFormat.format(DateTime.now())}.$_fileExtension';

    // Desktop only: the picker just returns the chosen path, the bytes are
    // written here.
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Excel dosyasını kaydet',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const [_fileExtension],
    );

    if (savePath == null) {
      _log.info('Excel export cancelled by the user');
      return null;
    }

    final targetPath = savePath.toLowerCase().endsWith('.$_fileExtension')
        ? savePath
        : '$savePath.$_fileExtension';
    await File(targetPath).writeAsBytes(bytes, flush: true);

    _log.info('Excel export written to {}', [targetPath]);
    return targetPath;
  }

  /// Encodes the workbook: a title row, the payment rows, a total row and a
  /// per-payment-type breakdown. Row indices are tracked explicitly so blank
  /// spacer rows never shift the summary blocks.
  static Uint8List _buildWorkbook({
    required List<PaymentModel> payments,
    required Map<String, UserModel> userById,
    required String titleLabel,
  }) {
    // The workbook's own sheet is reused as-is: Excel.rename()/delete() throw on
    // a freshly created workbook in excel 2.1.0 (unmodifiable sheet list), and
    // the report's identity lives in the file name anyway.
    final workbook = excel.Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet() ?? _defaultSheetName];
    final boldStyle = excel.CellStyle(bold: true);

    int rowIndex = 0;
    // Cell values are untyped in the excel package: Strings, doubles and ints
    // are written as-is, null leaves the cell empty.
    void writeRow(List<Object?> cells, {bool bold = false}) {
      for (int column = 0; column < cells.length; column++) {
        final value = cells[column];
        if (value == null) continue;
        sheet.updateCell(
          excel.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
          value,
          cellStyle: bold ? boldStyle : null,
        );
      }
      rowIndex++;
    }

    writeRow([titleLabel], bold: true);
    rowIndex++; // spacer
    writeRow(_headers, bold: true);

    double total = 0;
    final Map<PaymentType, double> totalByType = {};
    final Map<PaymentType, int> countByType = {};

    for (final payment in payments) {
      final user = userById[payment.userId];
      writeRow([
        _fullName(user),
        user?.email ?? '',
        _formatDate(payment.paymentDate),
        _formatDate(payment.dueDate),
        payment.amount,
        payment.paymentType.label,
        payment.status.label,
        payment.notes ?? '',
      ]);

      total += payment.amount;
      totalByType[payment.paymentType] =
          (totalByType[payment.paymentType] ?? 0) + payment.amount;
      countByType[payment.paymentType] =
          (countByType[payment.paymentType] ?? 0) + 1;
    }

    rowIndex++; // spacer
    writeRow(_summaryRow(_totalRowLabel, payments.length, total), bold: true);

    rowIndex++; // spacer
    writeRow([_typeBreakdownLabel], bold: true);
    for (final type in PaymentType.values) {
      final amount = totalByType[type];
      if (amount == null) continue;
      writeRow(_summaryRow(type.label, countByType[type] ?? 0, amount));
    }

    // Column widths must be applied after the cells: writing a row resets the
    // widths of the columns it touches.
    for (int column = 0; column < _columnWidths.length; column++) {
      sheet.setColWidth(column, _columnWidths[column]);
    }

    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('Excel dosyası oluşturulamadı.');
    }
    return Uint8List.fromList(encoded);
  }

  /// A summary line: label, payment count, and the amount under the data
  /// rows' own amount column.
  static List<Object?> _summaryRow(String label, int count, double amount) {
    final cells = List<Object?>.filled(_amountColumn + 1, null);
    cells[0] = label;
    cells[1] = count;
    cells[_amountColumn] = amount;
    return cells;
  }

  static String _fullName(UserModel? user) {
    if (user == null) return _unknownUserLabel;
    final fullName = '${user.name} ${user.surname}'.trim();
    return fullName.isEmpty ? _unknownUserLabel : fullName;
  }

  static String _formatDate(DateTime? date) =>
      date == null ? '' : _cellDateFormat.format(date);

  /// Keeps the suggested file name safe for every target file system.
  static String _sanitizeFileName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return cleaned.isEmpty
        ? _fallbackFileName
        : cleaned.replaceAll(RegExp(r'\s+'), '_');
  }
}
