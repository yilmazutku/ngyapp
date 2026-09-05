// diet_tab.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/add_diet_dialog.dart';
import '../models/diet_model.dart';
import '../models/filter_params.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/subs_model.dart';
import '../pages/admin_diet_edit_page.dart';
import '../pages/diet_user_view_page.dart';
import '../providers/diet_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/pdf_launcher.dart';
import 'basetab.dart';
import 'filterable_tab.dart';

final Logger dietEditLogger = Logger.forClass(DietEditPage);

class DietTab extends BaseTab<DietProvider> {
  const DietTab({super.key, required super.userId})
      : super(
    allDataLabel: 'Tüm diyetler',
    subscriptionDataLabel: 'Paket Diyetleri',
  );

  @override
  DietProvider getProvider(BuildContext context) =>
      Provider.of<DietProvider>(context, listen: false);

  @override
  Future<List<dynamic>> getDataList(DietProvider provider, bool showAllData, {FilterParams? filterParams}) =>
      provider.fetchDiets(userId: userId, showAllData: true, filterParams: filterParams as DietFilterParams?);

  @override
  BaseTabState<DietProvider, BaseTab<DietProvider>> createState() =>
      _DietTabState();
}

class _DietTabState extends FilterableTabState<DietProvider, DietTab> {
  final Logger logger = Logger.forClass(_DietTabState);

  // Smooth scrolling & visible scrollbar for long lists
  final ScrollController _listCtrl = ScrollController();

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  FilterParams? buildFilterParams() {
    return DietFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
    );
  }

  @override
  Widget buildFilterContent(
      BuildContext context,
      List<dynamic> allItems,
      List<dynamic> filteredItems,
      ) {
    return buildFilterSection(
      title: 'Diyet Listeleri',
      filterWidgets: [
        buildSearchField(hintText: 'Diyet içeriğinde ara...'),
        const SizedBox(height: 16),
        buildDateRangeFilter(
          placeholderText: 'Tarih Aralığı Seçin',
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        ),
        const SizedBox(height: 16),
        Text(
          '${filteredItems.length} diyet listesi gösteriliyor',
          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500),
        ),
        buildFilterActionButtons(),
      ],
    );
  }

  @override
  Widget buildFilteredContent(BuildContext context, List<dynamic> filteredItems) {
    final diets = List<DietDocument>.from(filteredItems.cast<DietDocument>());

    // Stable identity for reconciliation
    final listKey = ValueKey<String>(diets.map((d) => d.docId).join('|'));

    return Scrollbar(
      controller: _listCtrl,
      child: ListView.builder(
        key: listKey,
        controller: _listCtrl,
        padding: const EdgeInsets.all(16.0),
        itemCount: diets.length,
        cacheExtent: 800,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final diet = diets[index];
          final matchCount = _computeMatchCount(diet, searchQuery.trim().toLowerCase());
          return _buildDietCard(
            context,
            diet,
            key: ValueKey(diet.docId),
            matchCount: matchCount > 0 ? matchCount : null,
          );
        },
      ),
    );
  }

  int _computeMatchCount(DietDocument diet, String q) {
    if (q.isEmpty) return 0;
    int count = 0;
    if (diet.displayName.toLowerCase().contains(q)) count++;
    // Search both the weekday and (when present) weekend menus.
    count += _countInSubtitles(diet.subtitles, q);
    count += _countInSubtitles(diet.weekendSubtitles, q);
    return count;
  }

  int _countInSubtitles(Map<String, dynamic>? subtitles, String q) {
    if (subtitles == null) return 0;
    int count = 0;
    try {
      for (final entry in subtitles.entries) {
        final mealKey = entry.key.toLowerCase();
        if (mealKey.contains(q)) count++;
        final value = entry.value;
        final mealItems = value is Map ? value['content'] : null;
        if (mealItems is List) {
          for (final item in mealItems) {
            final text = item is Map ? (item['content']?.toString().toLowerCase() ?? '') : '';
            if (text.contains(q)) count++;
          }
        }
      }
    } catch (_) {}
    return count;
  }

  Future<SubscriptionModel?> _selectSubscription(BuildContext context, String userId) async {
    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final subs = await subProvider.fetchSubscriptions(
        userId: userId,
        showAllSubscriptions: false,
      );

      if (subs.isEmpty) {
        if (context.mounted) {
          await DialogUtils.openError(
            context,
            title: 'Uyarı',
            message:
            'Bu kullanıcının aktif paketi bulunmamaktadır. Diyet listesi eklemek için önce bir paket eklemelisiniz.',
          );
        }
        return null;
      }
      if (subs.length == 1) return subs.first;

      SubscriptionModel? selected;
      if (!context.mounted) return null;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Paket Seçin'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Lütfen diyet listesini eklemek için bir paket seçin:'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<SubscriptionModel>(
                      value: selected,
                      decoration: const InputDecoration(
                        labelText: 'Paket',
                        border: OutlineInputBorder(),
                        hintText: 'Paket seçin',
                      ),
                      items: subs
                          .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.packageName, overflow: TextOverflow.ellipsis),
                      ))
                          .toList(),
                      onChanged: (v) => setState(() => selected = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                ElevatedButton(
                  onPressed: selected == null ? null : () => Navigator.pop(context, true),
                  child: const Text('Tamam'),
                ),
              ],
            );
          },
        ),
      ).then((ok) {
        if (ok != true) selected = null;
      });

      return selected;
    } catch (e) {
      logger.err('Error selecting subscription: {}', [e]);
      if (context.mounted) {
        await DialogUtils.openError(context, title: 'Hata', message: 'Paketler yüklenirken bir hata oluştu: $e');
      }
      return null;
    }
  }

  Widget _buildDietCard(BuildContext context, DietDocument dietDoc, {Key? key, int? matchCount}) {
    return DietCard(
      key: key,
      dietDoc: dietDoc,
      matchCount: matchCount,
      onUserView: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DietUserViewPage(dietDoc: dietDoc)),
        );
      },
      onView: () {
        navigateAndRefresh(
          context,
          DietEditPage(userId: widget.userId, dietDoc: dietDoc, viewOnly: true),
        );
      },
      onDelete: () async {
        dietEditLogger.info('Attempting to delete diet: {} ({})', [dietDoc.displayName, dietDoc.docId]);
        try {
          final confirmed = await DialogUtils.openConfirm(
            context,
            title: 'Diyet Sil',
            message: '${dietDoc.displayName} silinsin mi?',
          );
          if (confirmed == true) {
            // Re-checked after the await, on the context this card was built
            // with rather than on the State.
            if (!context.mounted) return;
            final dietProvider = Provider.of<DietProvider>(context, listen: false);
            await dietProvider.deleteDiet(userId: widget.userId, docId: dietDoc.docId);
            if (mounted) refreshData();
          }
        } catch (e, s) {
          dietEditLogger.err('Unexpected error during diet deletion flow: {} \nStack trace: {}', [e, s.toString()]);
          if (context.mounted) {
            DialogUtils.openError(context, title: 'Hata', message: 'Diyet silinirken bir hata oluştu: $e');
          }
        }
      },
      onEdit: () {
        navigateAndRefresh(
          context,
          DietEditPage(userId: widget.userId, dietDoc: dietDoc, viewOnly: false),
        );
      },
    );
  }

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    final filteredItems = getFilteredItems(dataList);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: toggleFilters,
                    icon: const Icon(Icons.filter_alt),
                    label: const Text('Filtrele'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: buildActiveFiltersSummary(filteredItems.length, dataList.length)),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        // The package is resolved inside the dialog (and shown
                        // in the preview), so importing never stops to ask.
                        await showDialog(
                          context: context,
                          builder: (context) => AddDietDialog(userId: widget.userId),
                        );
                        if (mounted) refreshData();
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('İçe Aktar'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final selectedSub = await _selectSubscription(context, widget.userId);
                        if (selectedSub == null) return;

                        final now = DateTime.now();
                        final defaultDietContent = {
                          Meals.br.name: {'time': '08:00', 'content': []},
                          Meals.firstmid.name: {'time': '10:30', 'content': []},
                          Meals.lunch.name: {'time': '13:00', 'content': []},
                          Meals.secondmid.name: {'time': '16:00', 'content': []},
                          Meals.dinner.name: {'time': '19:00', 'content': []},
                          Meals.thirdmid.name: {'time': '21:30', 'content': []},
                        };

                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DietEditPage(
                              userId: widget.userId,
                              dietDoc: DietDocument(
                                docId: 'temp_${now.millisecondsSinceEpoch}',
                                userId: widget.userId,
                                displayName: 'Liste ${DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(now)}',
                                uploadTime: now,
                                subscriptionId: selectedSub.subscriptionId,
                                subtitles: defaultDietContent,
                              ),
                              isNewDiet: true,
                            ),
                          ),
                        );
                        if (mounted) refreshData();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Diyet'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty ? buildEmptyState() : buildFilteredContent(context, filteredItems),
        ),
      ],
    );
  }
}

class DietCard extends StatelessWidget {
  static const String userViewLabel = 'Danışan Nasıl Görüyor?';
  static const String recipeLabel = 'Ekli Tarif';
  static const String sourceFileLabel = 'Kaynak Word Dosyası';
  static const String openAttachmentHint = 'Görüntülemek için dokunun';

  final DietDocument dietDoc;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onUserView;
  final int? matchCount;

  const DietCard({
    super.key,
    required this.dietDoc,
    required this.onView,
    required this.onDelete,
    required this.onEdit,
    required this.onUserView,
    this.matchCount,
  });

  @override
  Widget build(BuildContext context) {
    final mealCount = dietDoc.subtitles.length;
    final uploadDate = dietDoc.uploadTime != null
        ? DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(dietDoc.uploadTime!)
        : 'Tarih bilgisi yok';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dietDoc.displayName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(uploadDate,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  InkWell(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.blue.shade300, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit,
                              size: 16, color: Colors.blue.shade800),
                          const SizedBox(width: 4),
                          Text('Düzenle',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text('$mealCount öğün',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                            fontSize: 12)),
                  ),
                  if (dietDoc.hasWeekend) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.weekend,
                              size: 14, color: Colors.purple.shade800),
                          const SizedBox(width: 4),
                          Text('Hafta Sonu',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade800,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  if (matchCount != null && matchCount! > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search,
                              size: 14, color: Colors.orange.shade800),
                          const SizedBox(width: 4),
                          Text('$matchCount eşleşme',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Attached recipe PDF, shown directly under the diet so the link is
            // clearly associated with this diet.
            if (dietDoc.hasRecipe) ...[
              const SizedBox(height: 12),
              _buildAttachmentRow(
                icon: Icons.picture_as_pdf,
                color: Colors.red,
                title: recipeLabel,
                fileName: dietDoc.recipePdfName,
                onTap: () => openPdfUrl(context, dietDoc.recipePdfUrl),
              ),
            ],
            if (dietDoc.hasSourceFile) ...[
              const SizedBox(height: 8),
              _buildAttachmentRow(
                icon: Icons.description,
                color: Colors.indigo,
                title: sourceFileLabel,
                fileName: dietDoc.sourceFileName,
                onTap: () => openFileUrl(
                  context,
                  dietDoc.sourceFileUrl,
                  fileLabel: 'Word dosyası',
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Full width so the long label never pushes the row into a scroll.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onUserView,
                icon: const Icon(Icons.phone_iphone, size: 18),
                label: const Text(userViewLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  side: BorderSide(color: Colors.deepPurple.shade200),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Düzenle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Görüntüle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentRow({
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String? fileName,
    required VoidCallback onTap,
  }) {
    final trimmed = fileName?.trim();
    final label = (trimmed != null && trimmed.isNotEmpty)
        ? trimmed
        : openAttachmentHint;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: color.shade600, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, color: color.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}