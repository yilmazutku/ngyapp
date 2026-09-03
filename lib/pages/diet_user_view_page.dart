import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/diet_model.dart';
import '../models/logger.dart';
import '../providers/special_lines_provider.dart';
import '../utils/diet_menu_parser.dart';
import '../utils/pdf_launcher.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/diet_plan_view.dart';

final Logger dietUserViewLogger = Logger.forClass(DietUserViewPage);

/// Shows a diet exactly the way the user sees it on their "Planım" page:
/// collapsible meal tiles that reveal the formatted content when tapped.
class DietUserViewPage extends StatefulWidget {
  static const String pageTitle = 'Danışan Nasıl Görüyor?';

  final DietDocument dietDoc;

  const DietUserViewPage({super.key, required this.dietDoc});

  @override
  State<DietUserViewPage> createState() => _DietUserViewPageState();
}

class _DietUserViewPageState extends State<DietUserViewPage> {
  late final Future<void> _specialLinesFuture;

  @override
  void initState() {
    super.initState();
    _specialLinesFuture = _loadSpecialLines();
  }

  Future<void> _loadSpecialLines() async {
    try {
      await Provider.of<SpecialLinesProvider>(context, listen: false)
          .fetchSpecialLines();
    } catch (e) {
      dietUserViewLogger.warn(
          'Could not load admin special lines, falling back to built-ins only: {}',
          [e.toString()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diet = widget.dietDoc;
    final uploadDate = diet.uploadTime != null
        ? DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(diet.uploadTime!)
        : null;

    return Scaffold(
      appBar: const AppBarWithBack(title: DietUserViewPage.pageTitle),
      body: FutureBuilder<void>(
        future: _specialLinesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(diet.displayName, uploadDate),
                const SizedBox(height: 12),
                DietPlanView(
                  weekday: DietMenu.fromSubtitles(diet.subtitles),
                  weekend: DietMenu.fromSubtitles(diet.weekendSubtitles),
                  onRecipeTap: diet.hasRecipe
                      ? () => openPdfUrl(context, diet.recipePdfUrl)
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String displayName, String? uploadDate) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          if (uploadDate != null) ...[
            const SizedBox(height: 4),
            Text(
              uploadDate,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Bu sayfa diyetin danışanın "Planım" ekranındaki görünümüdür. '
            'Öğüne dokunarak içeriğini açabilirsiniz.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
