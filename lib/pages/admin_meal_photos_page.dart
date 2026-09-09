// lib/pages/admin_meal_photos_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/mock_test_run.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/mock_test_data_provider.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/search_text.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/meal_image_card.dart';
import '../widgets/status_note.dart';
import 'admin_mock_meal_photos_page.dart';

final Logger logger = Logger.forClass(AdminMealPhotosPage);

/// Yönetici sayfası: **aktif paketi olan** danışanların **bugün** yüklediği
/// öğün fotoğraflarını tek ekranda toplar.
///
/// Hangi danışanlar listelenir: rolü `customer` olup aktif (Aktif/Haftalık ya
/// da Aktif/Kilo Takip) paketi bulunanlar — Danışanlar Özet sayfasının danışan
/// seçme koşuluyla aynı kural (bkz.
/// [SubProvider.fetchActiveSubscriptionsOfUsers]). Bugün fotoğraf yüklememiş
/// danışan da listede kalır; kartının altı boş görünür.
///
/// Fotoğrafların kaynağı tek: `users/{userId}/meals/{yyyy-MM-dd}/mealEntries`.
/// Danışan fotoğrafı ister sohbetten ister "Planım" sayfasından yüklesin aynı
/// öğün dokümanına yazıldığı için iki yol da buradan okunur
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
  static const String _mockLabel = 'Test Verisi';
  static const String _searchHint = 'Danışan ara (ad soyad / e-posta)';
  static const String _mealFilterTitle = 'Öğün';
  static const String _loadingText = 'Fotoğraflar yükleniyor...';
  static const String _loadErrorText =
      'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _noCustomerText =
      'Aktif paketi olan danışan bulunamadı.';
  static const String _noSearchResultText =
      'Aramanıza uyan danışan bulunamadı.';
  static const String _sourceHint =
      'Aktif paketi olan danışanların sohbetten ve "Planım" sayfasından '
      'yüklediği öğün fotoğrafları';

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

  /// Fotoğraflar hâlâ yükleniyor mu (2. aşama). Kartlar çizilmiş ama fotoğrafı
  /// gelmemiş danışanda "yüklenmemiş" yerine "yükleniyor" gösterilir.
  bool _photosLoading = false;

  /// Aynı anda birden fazla yükleme başlarsa (hızlı arka arkaya "Yenile"),
  /// yalnızca en sonuncusunun sonucu ekrana işlenir.
  int _loadId = 0;

  /// Aktif paketi olan danışanlar; önce bugün fotoğraf yükleyenler (son
  /// yükleme saati yeniden eskiye), sonra yüklemeyenler (ada göre).
  List<_ClientPhotoGroup> _groups = const [];

  /// Arama + öğün filtresi uygulanmış hâli (bkz. [_applyFilters]).
  List<_ClientPhotoGroup> _visibleGroups = const [];

  String _searchQuery = '';
  Meals? _mealFilter;

  /// Sistemde duran (silinmemiş) test verisi kayıtları. Boş değilse sayfanın
  /// üstünde uyarı şeridi çıkar: test verisi danışanların üstünde unutulmasın.
  List<MockTestRun> _testRuns = const [];

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

  /// Sayfayı iki aşamada doldurur.
  ///
  /// 1. Danışan listesi (aktif paketliler) gelir gelmez kartlar çizilir.
  /// 2. Fotoğraflar partiler hâlinde gelir ve her parti ekrana işlenir.
  ///
  /// Böylece tüm danışanların sorgusu bitene kadar boş ekran beklenmez; sayfa
  /// dolarak açılır.
  ///
  /// Sağlayıcılar await'lerden önce alınır; sonrasında yalnızca `mounted`
  /// kontrolüyle state güncellenir.
  Future<void> _load() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);
    final DateTime day = _todayStart();

    // Geç gelen bir yükleme, daha yeni bir yüklemenin sonucunu ezmesin.
    final int loadId = ++_loadId;

    setState(() {
      _day = day;
      _isLoading = true;
      _photosLoading = true;
      _errorText = null;
    });

    try {
      // Danışan listesi ve test verisi uyarısı birbirinden bağımsız: aynı anda
      // istenir, iki tur beklenmez.
      final List<Object?> initial = await Future.wait<Object?>([
        userProvider.fetchAllCustomers(),
        // Uyarı sayfanın asıl işi değil: okunamazsa sayfa yine çalışır.
        mockProvider.fetchRuns().catchError((Object e) {
          logger.err('Could not read mock test runs: {}', [e]);
          return <MockTestRun>[];
        }),
      ]);
      final List<UserModel> customers = initial[0] as List<UserModel>;
      final List<MockTestRun> testRuns = initial[1] as List<MockTestRun>;

      // Sayfanın ilk koşulu: yalnızca aktif paketi olan danışanlar.
      final Map<String, SubscriptionModel> activeSubs =
          await subProvider.fetchActiveSubscriptionsOfUsers(
        customers.map((user) => user.userId).toList(),
      );
      final List<UserModel> activeCustomers = customers
          .where((user) => activeSubs.containsKey(user.userId))
          .toList();

      if (!mounted || loadId != _loadId) return;

      // 1. aşama: kartlar fotoğrafsız çizilir.
      final List<_ClientPhotoGroup> groups = activeCustomers
          .map((customer) => _ClientPhotoGroup(customer, const []))
          .toList()
        ..sort(_compareGroups);
      setState(() {
        _groups = groups;
        _testRuns = testRuns;
        _isLoading = false;
        _photosLoading = activeCustomers.isNotEmpty;
        _applyFilters();
      });

      if (activeCustomers.isEmpty) return;

      // 2. aşama: fotoğraflar parti parti gelir ve geldikçe işlenir.
      await mealManager.fetchMealsOfUsersForDate(
        userIds: activeCustomers.map((user) => user.userId).toList(),
        date: day,
        onBatch: (batch) {
          if (!mounted || loadId != _loadId || batch.isEmpty) return;
          setState(() {
            _mergePhotos(batch);
            _applyFilters();
          });
        },
      );

      if (!mounted || loadId != _loadId) return;
      setState(() => _photosLoading = false);

      logger.info(
          'Meal photo page loaded. activeCustomers={} withPhotos={} photos={}', [
        _groups.length,
        _groups.where((group) => group.photos.isNotEmpty).length,
        _groups.fold<int>(0, (sum, group) => sum + group.photos.length),
      ]);
    } catch (e) {
      logger.err('Error loading meal photos: {}', [e]);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _errorText = _loadErrorText;
        _isLoading = false;
        _photosLoading = false;
      });
    }
  }

  /// Gelen parti sonucunu mevcut kartlara işler ve sırayı tazeler.
  void _mergePhotos(Map<String, List<MealModel>> batch) {
    final List<_ClientPhotoGroup> updated = [];
    for (final _ClientPhotoGroup group in _groups) {
      final List<MealModel>? meals = batch[group.user.userId];
      updated.add(meals == null
          ? group
          : _ClientPhotoGroup(group.user, _splitIntoPhotos(meals)));
    }
    updated.sort(_compareGroups);
    _groups = updated;
  }

  /// Önce bugün fotoğraf yükleyenler (en son yükleyen en üstte), sonra hiç
  /// yüklememiş danışanlar ada göre sıralanır.
  static int _compareGroups(_ClientPhotoGroup a, _ClientPhotoGroup b) {
    final bool aHas = a.photos.isNotEmpty;
    final bool bHas = b.photos.isNotEmpty;
    if (aHas != bHas) return aHas ? -1 : 1;
    if (aHas && bHas) return b.lastUploadAt!.compareTo(a.lastUploadAt!);
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  /// Bir öğün dokümanı en fazla [MealModel.maxImages] görsel taşır. Her görsel
  /// kendi kartında görünsün diye doküman, tek görselli kopyalara ayrılır;
  /// öğün türü ve yükleme saati kopyalarda korunur.
  List<MealModel> _splitIntoPhotos(List<MealModel>? meals) {
    if (meals == null || meals.isEmpty) return const [];

    final List<MealModel> photos = [];
    for (final MealModel meal in meals) {
      for (int i = 0; i < meal.imageUrls.length; i++) {
        photos.add(
          MealModel(
            mealId: '${meal.mealId}_$i',
            mealType: meal.mealType,
            imageUrls: [meal.imageUrls[i]],
            thumbUrls: [meal.thumbUrlAt(i) ?? ''],
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

  /// Arama ve öğün filtresini uygulayıp [_visibleGroups] sonucunu tazeler.
  ///
  /// Sonuç saklanır: liste her yeniden çizimde değil, yalnızca girdiler
  /// (yükleme, arama, öğün filtresi) değişince hesaplanır.
  ///
  /// Arama danışanı listeden çıkarır; öğün filtresi ise danışanı listede
  /// bırakıp yalnızca fotoğraflarını süzer — böylece "bu öğünü kim yüklememiş"
  /// de görülebilir.
  void _applyFilters() {
    final List<String> queryWords = searchWordsOf(_searchQuery);
    final List<_ClientPhotoGroup> visible = [];

    for (final _ClientPhotoGroup group in _groups) {
      if (queryWords.isNotEmpty &&
          !matchesSearchWords(queryWords, group.searchWords)) {
        continue;
      }

      if (_mealFilter == null) {
        visible.add(group);
        continue;
      }

      visible.add(
        _ClientPhotoGroup(
          group.user,
          group.photos
              .where((photo) => photo.mealType == _mealFilter)
              .toList(),
        ),
      );
    }

    _visibleGroups = visible;
  }

  ScrollController _stripControllerFor(String userId) =>
      _stripControllers.putIfAbsent(userId, () => ScrollController());

  /// Test verisi üreten sayfayı açar; dönüşte liste tazelenir ki üretilen
  /// fotoğraflar hemen görünsün.
  Future<void> _openMockPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminMockMealPhotosPage()),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<_ClientPhotoGroup> visible = _visibleGroups;

    return Scaffold(
      appBar: AppBarWithBack(
        title: _pageTitle,
        actions: [
          LabeledActionButton(
            icon: Icons.science_outlined,
            label: _mockLabel,
            tooltip: 'Test için sahte öğün fotoğrafı yükle',
            onPressed: _isLoading ? null : _openMockPage,
          ),
          const SizedBox(width: 8),
          LabeledActionButton(
            icon: Icons.refresh,
            label: _refreshLabel,
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context, visible),
          if (_testRuns.isNotEmpty) _buildTestDataWarning(context),
          _buildFilters(context),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, visible)),
        ],
      ),
    );
  }

  /// Gün bilgisi ve o güne ait toplamlar.
  Widget _buildHeader(BuildContext context, List<_ClientPhotoGroup> visible) {
    final ThemeData theme = Theme.of(context);
    final int uploaderCount =
        visible.where((group) => group.photos.isNotEmpty).length;
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
            text: '${visible.length} aktif danışan',
          ),
          _SummaryChip(
            icon: Icons.cloud_upload_outlined,
            text: '$uploaderCount yükleme yapan',
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

  /// Sistemde silinmemiş test verisi varsa gösterilen uyarı şeridi. Amaç, test
  /// fotoğraflarının gerçek veri sanılmasını ve danışanların üstünde
  /// unutulmasını önlemek.
  Widget _buildTestDataWarning(BuildContext context) {
    final int photoCount =
        _testRuns.fold<int>(0, (sum, run) => sum + run.photos.length);
    final int dietCount =
        _testRuns.fold<int>(0, (sum, run) => sum + run.diets.length);

    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: Colors.orange.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sistemde silinmemiş test verisi var: $photoCount fotoğraf, '
              '$dietCount geçici diyet. Bu sayfadaki bazı fotoğraflar test '
              'verisi olabilir.',
              style: TextStyle(color: Colors.orange.shade900),
            ),
          ),
          const SizedBox(width: 8),
          LabeledActionButton(
            icon: Icons.cleaning_services_outlined,
            label: 'Test Verilerini Sil',
            dense: true,
            foregroundColor: Colors.orange.shade900,
            onPressed: _isLoading ? null : _openMockPage,
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
                          setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _searchQuery = value;
                _applyFilters();
              }),
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
              onSelected: (meal) => setState(() {
                _mealFilter = meal;
                _applyFilters();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<_ClientPhotoGroup> visible) {
    if (_isLoading) {
      return const StatusNote(text: _loadingText, showProgress: true);
    }

    if (_errorText != null) {
      return StatusNote(
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
      return const StatusNote(
        icon: Icons.people_outline,
        text: _noCustomerText,
      );
    }

    if (visible.isEmpty) {
      return const StatusNote(
        icon: Icons.search_off,
        text: _noSearchResultText,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double photoWidth = (constraints.maxWidth / _photosPerViewport)
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
                // Fotoğraflar geldikçe sıra değişiyor; anahtar sayesinde
                // kartlar yeniden kurulmak yerine yer değiştirir ve her
                // danışanın şerit kaydırma konumu kendinde kalır.
                key: ValueKey<String>(group.user.userId),
                group: group,
                stripController: _stripControllerFor(group.user.userId),
                photoWidth: photoWidth,
                stripHeight: stripHeight,
                isLoadingPhotos: _photosLoading,
                emptyText: _mealFilter == null
                    ? 'Bugün fotoğraf yüklenmemiş.'
                    : '"${_mealFilter!.label}" öğünü için fotoğraf yüklenmemiş.',
              );
            },
          ),
        );
      },
    );
  }
}

/// Bir danışanın o güne ait fotoğrafları ve karttaki özet bilgileri.
/// [photos] boş olabilir: o danışan bugün fotoğraf yüklememiştir.
class _ClientPhotoGroup {
  final UserModel user;

  /// Her biri tek görsel taşıyan öğün kayıtları, eskiden yeniye sıralı.
  final List<MealModel> photos;

  /// Gün içindeki en son yükleme saati; fotoğraf yoksa null.
  final DateTime? lastUploadAt;

  /// Öğün türü -> fotoğraf sayısı (yükleme sırasına göre).
  final Map<Meals, int> countsByMeal;

  /// Aramada karşılaştırılan kelimeler (ad soyad + e-posta), önceden
  /// normalize edilmiş. Her tuş vuruşunda yeniden hesaplanmaz.
  final List<String> searchWords;

  const _ClientPhotoGroup._({
    required this.user,
    required this.photos,
    required this.lastUploadAt,
    required this.countsByMeal,
    required this.searchWords,
  });

  factory _ClientPhotoGroup(UserModel user, List<MealModel> photos) {
    DateTime? lastUploadAt;
    final Map<Meals, int> countsByMeal = {};

    for (final MealModel photo in photos) {
      if (lastUploadAt == null || photo.timestamp.isAfter(lastUploadAt)) {
        lastUploadAt = photo.timestamp;
      }
      countsByMeal[photo.mealType] = (countsByMeal[photo.mealType] ?? 0) + 1;
    }

    return _ClientPhotoGroup._(
      user: user,
      photos: photos,
      lastUploadAt: lastUploadAt,
      countsByMeal: countsByMeal,
      searchWords: searchWordsOf('${user.fullName} ${user.email}'),
    );
  }

  /// Avatardaki baş harfler: ad ve soyadın ilk harfleri, ikisi de boşsa "?".
  String get initials {
    final String first = user.name.trim();
    final String last = user.surname.trim();
    final String letters =
        '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}';
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  String get displayName => user.fullName.isEmpty ? user.email : user.fullName;
}

/// Tek bir danışanın kartı: başlık (kim, kaç fotoğraf, hangi öğünler, son
/// yükleme saati) ve altında fotoğrafların yatay şeridi. Fotoğraf yoksa şerit
/// yerine kısa bir bilgi satırı gösterilir.
class _ClientPhotoSection extends StatelessWidget {
  final _ClientPhotoGroup group;

  /// Bu danışanın şeridine ait kontrolcü; [Scrollbar] ile paylaşılır.
  final ScrollController stripController;

  final double photoWidth;
  final double stripHeight;

  /// Fotoğraf yokken kartın altında yazan metin.
  final String emptyText;

  /// Fotoğraflar hâlâ yükleniyorsa, fotoğrafı gelmemiş kartta "yüklenmemiş"
  /// yerine yükleniyor satırı gösterilir.
  final bool isLoadingPhotos;

  const _ClientPhotoSection({
    super.key,
    required this.group,
    required this.stripController,
    required this.photoWidth,
    required this.stripHeight,
    required this.emptyText,
    required this.isLoadingPhotos,
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
    final bool hasPhotos = group.photos.isNotEmpty;

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
          _buildHeader(context, hasPhotos),
          const Divider(height: 1),
          if (hasPhotos) _buildStrip(context) else _buildEmptyStrip(context),
        ],
      ),
    );
  }

  Widget _buildStrip(BuildContext context) {
    final double dialogImageHeight =
        (photoWidth * kMealDialogMultiplier).clamp(240.0, 480.0);

    return SizedBox(
      height: stripHeight,
      child: Scrollbar(
        controller: stripController,
        thumbVisibility: true,
        child: ListView.separated(
          controller: stripController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: group.photos.length,
          separatorBuilder: (context, index) => const SizedBox(width: _photoGap),
          itemBuilder: (context, index) => SizedBox(
            width: photoWidth,
            child: MealImageCard(
              meal: group.photos[index],
              dialogImageHeight: dialogImageHeight,
              backfillUserId: group.user.userId,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStrip(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          if (isLoadingPhotos)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Icon(
              Icons.no_photography_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isLoadingPhotos ? 'Fotoğraflar yükleniyor...' : emptyText,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool hasPhotos) {
    final ThemeData theme = Theme.of(context);
    final double step = (photoWidth + _photoGap) * _scrollStepInCards;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, hasPhotos ? 8 : 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: hasPhotos
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Text(
              group.initials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hasPhotos
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
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
                  hasPhotos
                      ? '${group.photos.length} fotoğraf · son yükleme '
                          '${DateFormat('HH:mm').format(group.lastUploadAt!)}'
                      : 'Fotoğraf yok',
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
          if (hasPhotos) ...[
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

/// Başlık şeridindeki sayaç rozeti ("12 aktif danışan", "48 fotoğraf").
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
