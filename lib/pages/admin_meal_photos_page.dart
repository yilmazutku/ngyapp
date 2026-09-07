// lib/pages/admin_meal_photos_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/user_model.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/user_provider.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/meal_image_card.dart';

final Logger logger = Logger.forClass(AdminMealPhotosPage);

/// Yönetici sayfası: danışanların **bugün** yüklediği öğün fotoğraflarını tek
/// ekranda toplar.
///
/// Kaynak tek: `users/{userId}/meals/{yyyy-MM-dd}/mealEntries`. Danışan
/// fotoğrafı ister sohbetten ister "Planım" sayfasından yüklesin aynı öğün
/// dokümanına yazıldığı için iki yol da buradan okunur
/// ([MealManager.fetchMealsOfUsersForDate]).
///
/// Düzen: her danışan bir kart; kartın içinde o gün yüklediği fotoğraflar
/// yatay bir şerit hâlinde, her fotoğrafın altında öğün adı ve yükleme saati
/// ile listelenir. Sayfanın kendisi dikey kaydırılır; iki yönde de kaydırma
/// çubuğu görünür durumdadır.
class AdminMealPhotosPage extends StatefulWidget {
  const AdminMealPhotosPage({super.key});

  @override
  State<AdminMealPhotosPage> createState() => _AdminMealPhotosPageState();
}

class _AdminMealPhotosPageState extends State<AdminMealPhotosPage> {
  static const String _pageTitle = 'Öğün Fotoğrafları';
  static const String _refreshLabel = 'Yenile';
  static const String _searchHint = 'Danışan ara (ad soyad)';
  static const String _mealFilterTitle = 'Öğün';
  static const String _loadingText = 'Fotoğraflar yükleniyor...';
  static const String _loadErrorText =
      'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _noSearchResultText =
      'Aramanıza / seçtiğiniz öğüne uyan fotoğraf bulunamadı.';
  static const String _sourceHint =
      'Sohbetten ve "Planım" sayfasından yüklenen tüm öğün fotoğrafları';

  /// Fotoğraf kartının genişliği; ekran genişliğine göre bu aralıkta değişir.
  static const double _minPhotoWidth = 150.0;
  static const double _maxPhotoWidth = 220.0;

  /// Geniş ekranda bir şeritte kaç kart görünsün (kart genişliği buna göre
  /// hesaplanır).
  static const int _photosPerViewport = 7;

  /// Kart yüksekliğinin genişliğine oranı: görsel + altındaki öğün/saat satırı.
  static const double _photoHeightRatio = 1.18;

  /// Şeridin kart dışında kalan dikey boşluğu (üst boşluk + kaydırma çubuğu).
  static const double _stripPadding = 30.0;

  static const double _searchFieldMaxWidth = 320.0;
  static const double _gap = 12.0;

  /// Sayfanın dikey kaydırma konumu; [Scrollbar] ile paylaşılır.
  final ScrollController _pageScrollController = ScrollController();

  /// Danışan başına bir yatay şerit kontrolcüsü (kontrolcü paylaşılmaz).
  final Map<String, ScrollController> _stripControllers = {};

  final TextEditingController _searchController = TextEditingController();

  /// Fotoğrafları gösterilen gün. Sayfa her yenilendiğinde "bugün" olur.
  DateTime _day = _todayStart();

  bool _isLoading = true;
  String? _errorText;

  /// Bugün en az bir fotoğrafı olan danışanlar, son yükleme saati yeniden
  /// eskiye sıralı.
  List<_ClientPhotoGroup> _groups = const [];

  String _searchQuery = '';
  Meals? _mealFilter;

  static DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    logger.info('AdminMealPhotosPage initialized');
    // İlk kare çizildikten sonra yüklenir: sayfa "yükleniyor" durumuyla açılır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    for (final controller in _stripControllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  /// Danışanları ve onların bugüne ait öğün fotoğraflarını çeker.
  ///
  /// Sağlayıcılar await'lerden önce alınır; sonrasında yalnızca `mounted`
  /// kontrolüyle state güncellenir.
  Future<void> _load() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final DateTime day = _todayStart();

    setState(() {
      _day = day;
      _isLoading = true;
      _errorText = null;
    });

    try {
      final List<UserModel> customers = await userProvider.fetchAllCustomers();
      final Map<String, List<MealModel>> mealsByUser =
          await mealManager.fetchMealsOfUsersForDate(
        userIds: customers.map((user) => user.userId).toList(),
        date: day,
      );

      final List<_ClientPhotoGroup> groups = [];
      for (final UserModel customer in customers) {
        final List<MealModel>? meals = mealsByUser[customer.userId];
        if (meals == null || meals.isEmpty) continue;

        final List<MealModel> photos = _splitIntoPhotos(meals);
        if (photos.isEmpty) continue;

        groups.add(_ClientPhotoGroup(customer, photos));
      }
      groups.sort((a, b) => b.lastUploadAt.compareTo(a.lastUploadAt));

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
      logger.info('Meal photo page loaded. clients={} photos={}',
          [groups.length, groups.fold<int>(0, (sum, g) => sum + g.photos.length)]);
    } catch (e) {
      logger.err('Error loading meal photos: {}', [e]);
      if (!mounted) return;
      setState(() {
        _errorText = _loadErrorText;
        _isLoading = false;
      });
    }
  }

  /// Bir öğün dokümanı en fazla [MealModel.maxImages] görsel taşır. Her görsel
  /// kendi kartında görünsün diye doküman, tek görselli kopyalara ayrılır;
  /// öğün türü ve yükleme saati kopyalarda korunur.
  List<MealModel> _splitIntoPhotos(List<MealModel> meals) {
    final List<MealModel> photos = [];
    for (final MealModel meal in meals) {
      for (int i = 0; i < meal.imageUrls.length; i++) {
        photos.add(
          MealModel(
            mealId: '${meal.mealId}_$i',
            mealType: meal.mealType,
            imageUrls: [meal.imageUrls[i]],
            subscriptionId: meal.subscriptionId,
            description: meal.description,
            timestamp: meal.timestamp,
            calories: meal.calories,
            notes: meal.notes,
            isChecked: meal.isChecked,
          ),
        );
      }
    }
    return photos;
  }

  /// Arama kutusu ve öğün filtresi uygulanmış liste. Filtre sonrası fotoğrafı
  /// kalmayan danışan listelenmez.
  List<_ClientPhotoGroup> get _visibleGroups {
    final String query = _searchQuery.trim().toLowerCase();
    final List<_ClientPhotoGroup> visible = [];

    for (final _ClientPhotoGroup group in _groups) {
      if (query.isNotEmpty &&
          !group.user.fullName.toLowerCase().contains(query)) {
        continue;
      }

      if (_mealFilter == null) {
        visible.add(group);
        continue;
      }

      final List<MealModel> photos = group.photos
          .where((photo) => photo.mealType == _mealFilter)
          .toList();
      if (photos.isEmpty) continue;
      visible.add(_ClientPhotoGroup(group.user, photos));
    }

    return visible;
  }

  ScrollController _stripControllerFor(String userId) =>
      _stripControllers.putIfAbsent(userId, () => ScrollController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWithBack(
        title: _pageTitle,
        actions: [
          LabeledActionButton(
            icon: Icons.refresh,
            label: _refreshLabel,
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context),
          _buildFilters(context),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  /// Gün bilgisi ve o güne ait toplamlar.
  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_ClientPhotoGroup> visible = _visibleGroups;
    final int photoCount =
        visible.fold<int>(0, (sum, group) => sum + group.photos.length);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: _gap,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.today, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                DateFormat('d MMMM y, EEEE', 'tr_TR').format(_day),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          _SummaryChip(
            icon: Icons.people_alt_outlined,
            text: '${visible.length} danışan',
          ),
          _SummaryChip(
            icon: Icons.photo_library_outlined,
            text: '$photoCount fotoğraf',
          ),
          Text(
            _sourceHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Danışan araması + öğün türü filtresi.
  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _searchFieldMaxWidth),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                labelText: _searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Aramayı temizle',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: FilterChipGroup<Meals>(
              title: _mealFilterTitle,
              titleIcon: Icons.restaurant_menu,
              selectedValue: _mealFilter,
              options: {
                for (final Meals meal in Meals.dietValues) meal: meal.label,
              },
              onSelected: (meal) => setState(() => _mealFilter = meal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const _StatusNote(
        text: _loadingText,
        showProgress: true,
      );
    }

    if (_errorText != null) {
      return _StatusNote(
        icon: Icons.error_outline,
        text: _errorText!,
        isError: true,
        action: LabeledActionButton(
          icon: Icons.refresh,
          label: _refreshLabel,
          onPressed: _load,
        ),
      );
    }

    if (_groups.isEmpty) {
      return _StatusNote(
        icon: Icons.photo_library_outlined,
        text: 'Bugün (${DateFormat('d MMMM y', 'tr_TR').format(_day)}) '
            'için henüz öğün fotoğrafı yüklenmemiş.',
      );
    }

    final List<_ClientPhotoGroup> visible = _visibleGroups;
    if (visible.isEmpty) {
      return const _StatusNote(
        icon: Icons.search_off,
        text: _noSearchResultText,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double photoWidth =
            (constraints.maxWidth / _photosPerViewport)
                .clamp(_minPhotoWidth, _maxPhotoWidth);
        final double stripHeight =
            photoWidth * _photoHeightRatio + _stripPadding;

        return Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _pageScrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final _ClientPhotoGroup group = visible[index];
              return _ClientPhotoSection(
                group: group,
                stripController: _stripControllerFor(group.user.userId),
                photoWidth: photoWidth,
                stripHeight: stripHeight,
              );
            },
          ),
        );
      },
    );
  }
}

/// Bir danışanın o güne ait fotoğrafları ve karttaki özet bilgileri.
class _ClientPhotoGroup {
  final UserModel user;

  /// Her biri tek görsel taşıyan öğün kayıtları, eskiden yeniye sıralı.
  final List<MealModel> photos;

  /// Gün içindeki en son yükleme saati.
  final DateTime lastUploadAt;

  /// Öğün türü -> fotoğraf sayısı (yükleme sırasına göre).
  final Map<Meals, int> countsByMeal;

  const _ClientPhotoGroup._({
    required this.user,
    required this.photos,
    required this.lastUploadAt,
    required this.countsByMeal,
  });

  factory _ClientPhotoGroup(UserModel user, List<MealModel> photos) {
    DateTime lastUploadAt = photos.first.timestamp;
    final Map<Meals, int> countsByMeal = {};

    for (final MealModel photo in photos) {
      if (photo.timestamp.isAfter(lastUploadAt)) {
        lastUploadAt = photo.timestamp;
      }
      countsByMeal[photo.mealType] = (countsByMeal[photo.mealType] ?? 0) + 1;
    }

    return _ClientPhotoGroup._(
      user: user,
      photos: photos,
      lastUploadAt: lastUploadAt,
      countsByMeal: countsByMeal,
    );
  }

  /// Avatardaki baş harfler; ad/soyad boşsa kullanıcı adının ilk harfi.
  String get initials {
    final String first = user.name.trim();
    final String last = user.surname.trim();
    final String letters =
        '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}';
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  String get displayName =>
      user.fullName.isEmpty ? user.email : user.fullName;
}

/// Tek bir danışanın kartı: başlık (kim, kaç fotoğraf, hangi öğünler, son
/// yükleme saati) ve altında fotoğrafların yatay şeridi.
class _ClientPhotoSection extends StatelessWidget {
  final _ClientPhotoGroup group;

  /// Bu danışanın şeridine ait kontrolcü; [Scrollbar] ile paylaşılır.
  final ScrollController stripController;

  final double photoWidth;
  final double stripHeight;

  const _ClientPhotoSection({
    required this.group,
    required this.stripController,
    required this.photoWidth,
    required this.stripHeight,
  });

  static const double _avatarRadius = 22.0;
  static const double _photoGap = 8.0;

  /// Ok butonlarının tek dokunuşta kaydırdığı kart sayısı.
  static const int _scrollStepInCards = 3;

  void _scrollBy(double delta) {
    if (!stripController.hasClients) return;
    final double target = (stripController.offset + delta).clamp(
      stripController.position.minScrollExtent,
      stripController.position.maxScrollExtent,
    );
    stripController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double step = (photoWidth + _photoGap) * _scrollStepInCards;
    final double dialogImageHeight =
        (photoWidth * kMealDialogMultiplier).clamp(240.0, 480.0);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, step),
          const Divider(height: 1),
          SizedBox(
            height: stripHeight,
            child: Scrollbar(
              controller: stripController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: stripController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: group.photos.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: _photoGap),
                itemBuilder: (context, index) => SizedBox(
                  width: photoWidth,
                  child: MealImageCard(
                    meal: group.photos[index],
                    thumbSize: photoWidth,
                    dialogImageHeight: dialogImageHeight,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double step) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              group.initials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${group.photos.length} fotoğraf · son yükleme '
                  '${DateFormat('HH:mm').format(group.lastUploadAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry<Meals, int> entry
                    in group.countsByMeal.entries)
                  _MealCountChip(mealType: entry.key, count: entry.value),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Sola kaydır',
            onPressed: () => _scrollBy(-step),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Sağa kaydır',
            onPressed: () => _scrollBy(step),
          ),
        ],
      ),
    );
  }
}

/// Başlıktaki "Sabah 2" biçimindeki öğün rozeti. Renk ve ikon, fotoğraf
/// kartlarıyla aynı kaynaktan gelir (bkz. [mealTypeColor]).
class _MealCountChip extends StatelessWidget {
  final Meals mealType;
  final int count;

  const _MealCountChip({required this.mealType, required this.count});

  @override
  Widget build(BuildContext context) {
    final Color color = mealTypeColor(mealType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mealTypeIcon(mealType), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${mealType.label} $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Başlık şeridindeki sayaç rozeti ("12 danışan", "48 fotoğraf").
class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Yükleniyor / boş / hata durumları için ortalanmış bilgi bloğu.
class _StatusNote extends StatelessWidget {
  /// [showProgress] true iken ikon yerine yükleme göstergesi çizilir.
  final IconData? icon;
  final String text;
  final bool isError;
  final bool showProgress;
  final Widget? action;

  const _StatusNote({
    this.icon,
    required this.text,
    this.isError = false,
    this.showProgress = false,
    this.action,
  }) : assert(icon != null || showProgress);

  @override
  Widget build(BuildContext context) {
    final Color color =
        isError ? Colors.red.shade700 : Theme.of(context).hintColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
