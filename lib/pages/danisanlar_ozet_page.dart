import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_summary_row.dart';
import '../models/logger.dart';
import '../providers/customer_summary_provider.dart';

final Logger logger = Logger.forClass(DanisanlarOzetPage);

/// Admin overview: every customer with an active subscription, with their
/// latest payment (date / amount / type), the active package, and up to
/// [CustomerSummaryRow.maxSeans] session (seans) dates.
class DanisanlarOzetPage extends StatefulWidget {
  const DanisanlarOzetPage({super.key});

  @override
  State<DanisanlarOzetPage> createState() => _DanisanlarOzetPageState();
}

class _DanisanlarOzetPageState extends State<DanisanlarOzetPage> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  bool _loading = true;
  String? _error;
  List<CustomerSummaryRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider =
          Provider.of<CustomerSummaryProvider>(context, listen: false);
      final rows = await provider.fetchActiveCustomerSummaries();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      logger.err('Failed to load customer summaries: {}', [e]);
      if (!mounted) return;
      setState(() {
        _error = 'Özet verileri yüklenirken bir hata oluştu.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danışanlar Özet'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_rows.isEmpty) {
      return const Center(
        child: Text('Aktif aboneliği olan danışan bulunamadı.'),
      );
    }

    return _buildTable();
  }

  Widget _buildTable() {
    // Postponed-date columns are dynamic: use the widest row so every row lines
    // up, then pad shorter rows with empty cells.
    final int postponedColumns = _rows.fold<int>(
      0,
      (m, r) => r.postponedDates.length > m ? r.postponedDates.length : m,
    );

    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalController,
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
              columns: _buildColumns(postponedColumns),
              rows: _rows.map((r) => _buildRow(r, postponedColumns)).toList(),
            ),
          ),
        ),
      ),
    );
  }

  List<DataColumn> _buildColumns(int postponedColumns) {
    return <DataColumn>[
      const DataColumn(label: Text('Dosya No')),
      const DataColumn(label: Text('Ad-Soyad')),
      const DataColumn(label: Text('Ödeme Alınan Tarih')),
      const DataColumn(label: Text('Ödeme Tutarı'), numeric: true),
      const DataColumn(label: Text('Ödeme Şekli')),
      const DataColumn(label: Text('Paket Bilgisi')),
      for (int i = 1; i <= CustomerSummaryRow.maxSeans; i++)
        DataColumn(label: Text('$i.Seans')),
      for (int i = 1; i <= postponedColumns; i++)
        DataColumn(label: Text('$i. Ertelenen Randevu')),
      const DataColumn(label: Text('Kalan Erteleme Hakkı'), numeric: true),
    ];
  }

  DataRow _buildRow(CustomerSummaryRow row, int postponedColumns) {
    return DataRow(
      cells: <DataCell>[
        _cell(row.dosyaNo),
        DataCell(
          Text(
            row.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        _cell(row.paymentDate),
        _cell(row.paymentAmount),
        _cell(row.paymentType),
        _cell(row.packageInfo),
        for (final seans in row.seans) _cell(seans),
        for (int i = 0; i < postponedColumns; i++)
          _cell(i < row.postponedDates.length
              ? row.postponedDates[i]
              : const SummaryCell.empty()),
        _cell(row.remainingPostponements),
      ],
    );
  }

  DataCell _cell(SummaryCell cell) {
    return DataCell(
      Text(
        cell.text,
        style: TextStyle(
          color: cell.isError ? Colors.red.shade700 : null,
          fontWeight: cell.isError ? FontWeight.bold : null,
        ),
      ),
    );
  }
}
