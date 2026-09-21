import 'package:flutter/material.dart';

import '../models/diet_goals.dart';
import '../models/diet_section.dart';
import '../models/meal_model.dart';
import '../utils/diet_menu_parser.dart';
import '../utils/meal_formatter.dart';

const double kDietMealTitleFontSize = 14.0;
const double kDietMealContentFontSize = 13.0;

/// Visual state of a meal tile on the plan.
///
/// [active] is today's still-pending meal, [completed] one the user ticked off
/// and [reference] a meal from the menu that is not today's (shown read-only).
enum DietMealTone { active, completed, reference }

/// The diet's goal lines ("Su Hedefi: ...", "Spor Hedefi: ...") shown above the
/// first meal, each on its own row and kept exactly as written in the imported
/// document. Renders nothing when the diet has no goal lines.
class DietGoalsCard extends StatelessWidget {
  final DietGoals goals;

  const DietGoalsCard({super.key, required this.goals});

  IconData _iconFor(DietGoalType type) {
    switch (type) {
      case DietGoalType.water:
        return Icons.water_drop;
      case DietGoalType.sport:
        return Icons.directions_run;
    }
  }

  Color _colorFor(DietGoalType type) {
    switch (type) {
      case DietGoalType.water:
        return Colors.blue.shade600;
      case DietGoalType.sport:
        return Colors.teal.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = goals.entries;
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    _iconFor(entries[i].type),
                    size: 18,
                    color: _colorFor(entries[i].type),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entries[i].line,
                    style: const TextStyle(
                      fontSize: kDietMealContentFontSize,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class DietSectionHeader extends StatelessWidget {
  final DietSection section;
  final IconData? icon;
  final bool isToday;

  const DietSectionHeader({
    super.key,
    required this.section,
    required this.isToday,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2),
      child: Row(
        children: [
          Icon(icon ?? Icons.restaurant_menu,
              size: 20, color: Colors.deepOrange.shade700),
          const SizedBox(width: 8),
          Text(
            section.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange.shade800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isToday ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isToday ? Colors.green.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Text(
              isToday ? 'Bugün' : 'Referans',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isToday ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single collapsible meal tile of the user's plan: title, time badge and,
/// once expanded, the formatted meal content.
///
/// [trailing] and [subtitle] carry the tracking controls (upload / check-off /
/// upload status) on the interactive plan; a read-only preview leaves them out.
class DietMealTile extends StatelessWidget {
  final Meals mealCategory;
  final List<String> contents;
  final TimeOfDay mealTime;
  final String expansionKey;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final DietMealTone tone;
  final List<Widget> trailing;
  final Widget? subtitle;
  final double titleFontSize;
  final double contentFontSize;
  final VoidCallback? onRecipeTap;

  const DietMealTile({
    super.key,
    required this.mealCategory,
    required this.contents,
    required this.mealTime,
    required this.expansionKey,
    required this.expanded,
    required this.onExpansionChanged,
    this.tone = DietMealTone.active,
    this.trailing = const <Widget>[],
    this.subtitle,
    this.titleFontSize = kDietMealTitleFontSize,
    this.contentFontSize = kDietMealContentFontSize,
    this.onRecipeTap,
  });

  Color get _accentColor {
    switch (tone) {
      case DietMealTone.completed:
        return Colors.green.shade600;
      case DietMealTone.reference:
        return Colors.blueGrey.shade400;
      case DietMealTone.active:
        return Colors.deepOrange.shade600;
    }
  }

  Color get _titleColor {
    switch (tone) {
      case DietMealTone.completed:
        return Colors.green.shade700;
      case DietMealTone.reference:
        return Colors.blueGrey.shade700;
      case DietMealTone.active:
        return Colors.deepOrange.shade700;
    }
  }

  Color get _badgeColor {
    switch (tone) {
      case DietMealTone.completed:
        return Colors.green.shade50;
      case DietMealTone.reference:
        return Colors.blueGrey.shade50;
      case DietMealTone.active:
        return Colors.deepOrange.shade50;
    }
  }

  IconData get _icon {
    switch (tone) {
      case DietMealTone.completed:
        return Icons.check_circle;
      case DietMealTone.reference:
        return Icons.restaurant_menu;
      case DietMealTone.active:
        return Icons.restaurant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>(expansionKey),
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          collapsedShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, size: 18, color: _accentColor),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  mealCategory.displayLabel,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                    color: _titleColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  formatTimeOfDay24(mealTime),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
          subtitle: subtitle,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: MealFormatter.formatMealContentWithOptions(
                contents.map((line) => {'content': line}).toList(),
                fontSize: contentFontSize,
                onRecipeTap: onRecipeTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only rendering of a whole diet plan, exactly as the user sees it on the
/// "Planım" page: one collapsible tile per meal, split into Hafta İçi /
/// Hafta Sonu sections when the diet defines a weekend menu.
class DietPlanView extends StatefulWidget {
  final DietMenu weekday;
  final DietMenu weekend;

  /// Opens the diet's attached recipe PDF when a content line references one
  /// ("*tarifi ektedir"). Null renders the phrase as plain text.
  final VoidCallback? onRecipeTap;

  /// Date used to decide which section is marked as "Bugün".
  final DateTime? referenceDate;

  /// Goal lines rendered above the first meal. Empty by default.
  final DietGoals goals;

  final String emptyMessage;

  const DietPlanView({
    super.key,
    required this.weekday,
    this.weekend = const DietMenu.empty(),
    this.onRecipeTap,
    this.referenceDate,
    this.goals = const DietGoals.empty(),
    this.emptyMessage = 'Henüz öğün planı oluşturulmamış',
  });

  @override
  State<DietPlanView> createState() => _DietPlanViewState();
}

class _DietPlanViewState extends State<DietPlanView> {
  final Map<String, bool> _expandedMeals = <String, bool>{};

  String _expansionKey(Meals meal, DietSection? section) =>
      section == null ? meal.name : '${section.key}_${meal.name}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.goals.hasAny) DietGoalsCard(goals: widget.goals),
        _buildPlan(),
      ],
    );
  }

  Widget _buildPlan() {
    final bool hasWeekend = widget.weekend.hasContent;

    if (!hasWeekend && !widget.weekday.hasContent) {
      return SizedBox(width: double.infinity, child: _buildEmptyState());
    }

    if (!hasWeekend) {
      return _buildSection(menu: widget.weekday, tone: DietMealTone.active);
    }

    final bool weekendToday =
        isWeekendDate(widget.referenceDate ?? DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DietSectionHeader(
          section: DietSection.weekday,
          icon: Icons.calendar_view_week,
          isToday: !weekendToday,
        ),
        _buildSection(
          menu: widget.weekday,
          section: DietSection.weekday,
          tone: weekendToday ? DietMealTone.reference : DietMealTone.active,
        ),
        const SizedBox(height: 12),
        DietSectionHeader(
          section: DietSection.weekend,
          icon: Icons.weekend,
          isToday: weekendToday,
        ),
        _buildSection(
          menu: widget.weekend,
          section: DietSection.weekend,
          tone: weekendToday ? DietMealTone.active : DietMealTone.reference,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.restaurant_menu, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              widget.emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required DietMenu menu,
    required DietMealTone tone,
    DietSection? section,
  }) {
    final meals = menu.mealsWithContent;

    if (meals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          'Bu bölüm için öğün planı bulunmuyor.',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: meals.map((meal) {
        final key = _expansionKey(meal, section);
        return DietMealTile(
          mealCategory: meal,
          contents: menu.linesOf(meal),
          mealTime: menu.timeOf(meal, const TimeOfDay(hour: 0, minute: 0)),
          expansionKey: key,
          expanded: _expandedMeals[key] ?? false,
          onExpansionChanged: (isExpanded) =>
              setState(() => _expandedMeals[key] = isExpanded),
          tone: tone,
          onRecipeTap: widget.onRecipeTap,
        );
      }).toList(),
    );
  }
}
