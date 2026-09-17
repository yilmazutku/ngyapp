// lib/pages/admin_meal_photos_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_model.dart';
import '../models/mock_test_run.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';
import '../providers/chat_manager_new.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/mock_test_data_provider.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/search_text.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/meal_image_card.dart';
import '../widgets/reaction_picker.dart';
import '../widgets/search_field.dart';
import '../widgets/status_note.dart';
import 'admin_mock_meal_photos_page.dart';
import 'chat_page_new.dart';

/// Yönetici sayfası: **aktif paketi olan** danışanların **seçilen güne** ait
/// öğün fotoğraflarını tek ekranda toplar. Sayfa bugünle açılır; üstteki tarih
/// seçicisiyle geçmiş bir güne gidilebilir.
///
/// Hangi danışanlar listelenir: rolü `customer` olup aktif (Aktif/Haftalık ya
/// da Aktif/Kilo Takip) paketi bulunanlar — Danışanlar Özet sayfasının danışan
/// seçme koşuluyla aynı kural (bkz.
/// [SubProvider.fetchActiveSubscriptionsOfUsers]). O gün fotoğraf yüklememiş
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
/// Fotoğrafa sağ tıklandığında (dokunmatikte uzun basıldığında) açılan
/// menüdeki işlemler.
enum _PhotoAction {
  /// Sohbeti fotoğrafın mesajında açar.
  goToChat,

  /// Fotoğrafın sohbetteki mesajına ifade bırakır.
  react,
}

class AdminMealPhotosPage extends StatefulWidget {
  const AdminMealPhotosPage({super.key});

  @override
  State<AdminMealPhotosPage> createState() => _AdminMealPhotosPageState();
}

class _AdminMealPhotosPageState extends State<AdminMealPhotosPage> {
  static const String _pageTitle = 'Öğün Fotoğrafları';
  static const String _refreshLabel = 'Yenile';
  // Test verisi yükleme şimdilik kapalı; geri açılırken bu sabit ve aşağıdaki
  // "Test Verisi" butonu birlikte yorumdan çıkarılmalı.
  // static const String _mockLabel = 'Test Verisi';
  static const String _searchHint = 'Danışan ara (ad soyad / e-posta)';
  static const String _mealFilterTitle = 'Öğün';
  static const String _loadingText = 'Fotoğraflar yükleniyor...';
  static const String _loadErrorText =
      'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _noCustomerText =
      'Aktif paketi olan danışan bulunamadı.';
  static const String _noSearchResultText =
      'Aramanıza uyan danışan bulunamadı.';
  static const String _dayPickerHelpText = 'Gün seç';
  static const String _todayLabel = 'Bugün';
  static const String _previousDayTooltip = 'Önceki gün';
  static const String _nextDayTooltip = 'Sonraki gün';
  static const String _emptyTodayText = 'Bugün fotoğraf yüklenmemiş.';
  static const String _emptyOtherDayText = 'Bu gün fotoğraf yüklenmemiş.';
  static const String _goToChatLabel = 'Chate git';
  static const String _reactLabel = 'İfade Bırak';
  static const String _chatLookupText = 'Sohbetteki mesaj aranıyor...';
  static const String _chatNotFoundTitle = 'Mesaj Bulunamadı';
  static const String _chatNotFoundText =
      'Bu fotoğrafın sohbette bir mesajı yok; sohbete düşmeden yüklenmiş '
      'olabilir.';
  static const String _reactNotFoundText =
      'Bu fotoğrafın sohbette bir mesajı yok; ifade yalnızca sohbetteki '
      'mesaja bırakılabilir.';
  static const String _chatErrorTitle = 'Hata';
  static const String _chatErrorText =
      'Sohbete gidilemedi. Lütfen tekrar deneyin.';
  static const String _reactErrorText =
      'İfade bırakılamadı. Lütfen tekrar deneyin.';
  static const String _reactionSavedText = 'İfade bırakıldı:';
  static const String _reactionRemovedText = 'İfade kaldırıldı.';

  /// İfade sonrası bilgi şeridinin ekranda kalma süresi.
  static const Duration _reactionFeedbackDuration = Duration(seconds: 2);

  /// Öğün filtresindeki seçenekler. Ara öğünler tek seçenekte toplanır:
  /// [Meals.firstmid] üçünü birden temsil eder (bkz. [_matchesMealFilter]),
  /// böylece filtrede üç ayrı "Ara Öğün" satırı çıkmaz.
  static const List<Meals> _mealFilterOptions = [
    Meals.br,
    Meals.firstmid,
    Meals.lunch,
    Meals.dinner,
  ];

  /// Tarih seçicide gidilebilecek en eski gün. Uygulamada bundan öncesine ait
  /// öğün kaydı yok; sınır, seçicinin sonsuz geriye gitmesini engeller.
  static final DateTime _firstSelectableDay = DateTime(2023, 1, 1);

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

  /// Fotoğrafları gösterilen gün (gece yarısına normalize). Sayfa bugünle
  /// açılır; tarih seçicisiyle değişir ve "Yenile" seçili günü korur.
  DateTime _day = _todayStart();

  bool _isLoading = true;
  String? _errorText;

  /// Fotoğraflar hâlâ yükleniyor mu (2. aşama). Kartlar çizilmiş ama fotoğrafı
  /// gelmemiş danışanda "yüklenmemiş" yerine "yükleniyor" gösterilir.
  bool _photosLoading = false;

  /// Aynı anda birden fazla yükleme başlarsa (hızlı arka arkaya "Yenile"),
  /// yalnızca en sonuncusunun sonucu ekrana işlenir.
  int _loadId = 0;

  /// Aktif paketi olan danışanlar; önce o gün fotoğraf yükleyenler (son
  /// yükleme saati yeniden eskiye), sonra yüklemeyenler (ada göre).
  List<_ClientPhotoGroup> _groups = const [];

  /// Arama + öğün filtresi uygulanmış hâli (bkz. [_applyFilters]).
  List<_ClientPhotoGroup> _visibleGroups = const [];

  /// Fotoğraf adresi -> o fotoğrafın sohbetteki mesajına bırakılan tepkiler
  /// (uid -> emoji). Kartların köşesindeki rozet buradan çizilir; fotoğraflarla
  /// aynı anda, ayrı bir sorgu kümesiyle doldurulur (bkz. [_load]).
  final Map<String, Map<String, String>> _reactionsByImageUrl = {};

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
  /// 2. Fotoğraflar ve fotoğraflara bırakılmış tepkiler **aynı anda** istenir;
  ///    iki sorgu kümesi birbirini beklemez, her parti geldikçe ekrana işlenir.
  ///
  /// Böylece tüm danışanların sorgusu bitene kadar boş ekran beklenmez; sayfa
  /// dolarak açılır ve tepkiler yükleme süresine ek yük bindirmez.
  ///
  /// [day] verilmezse o an seçili gün yeniden yüklenir; böylece "Yenile"
  /// seçili günü korur.
  ///
  /// Sağlayıcılar await'lerden önce alınır; sonrasında yalnızca `mounted`
  /// kontrolüyle state güncellenir.
  Future<void> _load({DateTime? day}) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final chatManager = Provider.of<ChatManager>(context, listen: false);
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);
    final DateTime targetDay = day ?? _day;

    // Geç gelen bir yükleme, daha yeni bir yüklemenin sonucunu ezmesin.
    final int loadId = ++_loadId;

    setState(() {
      _day = targetDay;
      _isLoading = true;
      _photosLoading = true;
      _errorText = null;
      // Gün değişti: eski günün kartları hemen kalksın, ekranda yanlış güne
      // ait fotoğraf ya da tepki durmasın.
      _groups = const [];
      _visibleGroups = const [];
      _reactionsByImageUrl.clear();
    });

    try {
      // Danışan listesi ve test verisi uyarısı birbirinden bağımsız: aynı anda
      // istenir, iki tur beklenmez.
      final List<Object?> initial = await Future.wait<Object?>([
        userProvider.fetchAllCustomers(),
        // Uyarı sayfanın asıl işi değil: okunamazsa sayfa yine çalışır.
        mockProvider.fetchRuns().catchError((Object e) {
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

      // 2. aşama: fotoğraflar ve tepkileri yan yana istenir. İkisi de aynı
      // danışan listesini partiler hâlinde tarar; toplam süre ikisinin toplamı
      // değil, uzun olanı kadardır.
      final List<String> userIds =
          activeCustomers.map((user) => user.userId).toList();

      // Şerit altındaki "yükleniyor" satırı fotoğraflarla ilgili: tepkileri
      // beklemeden, fotoğraflar biter bitmez kalkar.
      final Future<void> photos = mealManager
          .fetchMealsOfUsersForDate(
        userIds: userIds,
        date: targetDay,
        onBatch: (batch) {
          if (!mounted || loadId != _loadId || batch.isEmpty) return;
          setState(() {
            _mergePhotos(batch);
            _applyFilters();
          });
        },
      )
          .then((_) {
        if (!mounted || loadId != _loadId) return;
        setState(() => _photosLoading = false);
      });

      // Tepkiler sayfanın asıl işi değil: okunamazsa rozet çıkmaz, fotoğraflar
      // yine gösterilir. Bu yüzden hatası yükleme akışını düşürmez.
      final Future<void> reactions = chatManager
          .fetchImageReactionsOfUsersForDate(
            userIds: userIds,
            date: targetDay,
            onBatch: (batch) {
              if (!mounted || loadId != _loadId || batch.isEmpty) return;
              setState(() => _reactionsByImageUrl.addAll(batch));
            },
          )
          .catchError((Object e) => <String, Map<String, String>>{});

      await Future.wait<void>([photos, reactions]);
    } catch (e) {
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

  /// Önce o gün fotoğraf yükleyenler (en son yükleyen en üstte), sonra hiç
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
  /// [type] seçili öğün filtresine uyuyor mu. Filtre bir ara öğünse üç ara
  /// öğünün hepsi eşleşir (bkz. [_mealFilterOptions]).
  bool _matchesMealFilter(Meals type) {
    final Meals? filter = _mealFilter;
    if (filter == null) return true;
    return filter.isSnack ? type.isSnack : type == filter;
  }

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
              .where((photo) => _matchesMealFilter(photo.mealType))
              .toList(),
        ),
      );
    }

    _visibleGroups = visible;
  }

  ScrollController _stripControllerFor(String userId) =>
      _stripControllers.putIfAbsent(userId, () => ScrollController());

  /// Seçili gün bugün mü.
  bool get _isToday => _day == _todayStart();

  /// Seçili günü değiştirir ve o günün fotoğraflarını yükler. Aynı gün ise
  /// gereksiz yere yeniden yüklemez.
  Future<void> _selectDay(DateTime day) async {
    final DateTime normalized = DateTime(day.year, day.month, day.day);
    if (normalized == _day) return;
    await _load(day: normalized);
  }

  /// Bir gün geri/ileri gider. İleri yön bugünü aşmaz: gelecekte fotoğraf
  /// olamaz.
  Future<void> _shiftDay(int days) =>
      _selectDay(_day.add(Duration(days: days)));

  /// Takvimden gün seçtirir.
  Future<void> _pickDay() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstSelectableDay,
      lastDate: _todayStart(),
      helpText: _dayPickerHelpText,
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked == null || !mounted) return;
    await _selectDay(picked);
  }

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

  /// Fotoğrafa sağ tıklandığında (dokunmatikte uzun basıldığında) açılan menü:
  /// fotoğrafın sohbetteki mesajına gitmek ya da o mesaja ifade bırakmak.
  Future<void> _openPhotoMenu(
    _ClientPhotoGroup group,
    MealModel photo,
    Offset globalPosition,
  ) async {
    final RenderObject? overlay =
        Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;

    final _PhotoAction? action = await showMenu<_PhotoAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<_PhotoAction>(
          value: _PhotoAction.goToChat,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.chat_bubble_outline),
            title: Text(_goToChatLabel),
          ),
        ),
        PopupMenuItem<_PhotoAction>(
          value: _PhotoAction.react,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_reaction_outlined),
            title: Text(_reactLabel),
          ),
        ),
      ],
    );

    if (action == null) return;
    // Menü açıkken sayfadan çıkılmış olabilir.
    if (!mounted) return;

    switch (action) {
      case _PhotoAction.goToChat:
        await _goToChatMessage(group, photo);
      case _PhotoAction.react:
        await _leaveReaction(group, photo, globalPosition);
    }
  }

  /// Fotoğrafın sohbetteki mesajını yükleme diyaloğu eşliğinde arar.
  ///
  /// Öğün fotoğrafı sohbete yüklenirken mesaja aynı indirme adresi yazıldığı
  /// için eşleme adres üzerinden yapılır. Mesaj yoksa (ör. "Planım"
  /// sayfasından yüklenmiş, sohbete düşmemiş eski bir kayıt) ya da arama
  /// başarısız olursa kullanıcıya diyalog gösterilip null dönülür; çağıran
  /// yalnızca sonucu kontrol eder.
  Future<MessageData?> _findChatMessage(
    _ClientPhotoGroup group,
    MealModel photo, {
    required String notFoundText,
    required String errorText,
  }) async {
    final ChatManager chatManager =
        Provider.of<ChatManager>(context, listen: false);

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: _chatLookupText);
      loadingOpen = true;
    }

    try {
      final MessageData? message = await chatManager.findImageMessage(
        group.user.userId,
        photo.imageUrl,
      );

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (!mounted) return null;

      if (message == null) {
        await DialogUtils.openInfo(
          context,
          title: _chatNotFoundTitle,
          message: notFoundText,
        );
        return null;
      }

      return message;
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (!mounted) return null;
      await DialogUtils.openError(
        context,
        title: _chatErrorTitle,
        message: errorText,
      );
      return null;
    }
  }

  /// Sohbeti fotoğrafın mesajında açar.
  ///
  /// Mesaj sohbetin gösterdiği son 50 mesajdan eskiyse sohbet her zamanki gibi
  /// en alttan açılır.
  Future<void> _goToChatMessage(
    _ClientPhotoGroup group,
    MealModel photo,
  ) async {
    final NavigatorState navigator = Navigator.of(context);

    final MessageData? message = await _findChatMessage(
      group,
      photo,
      notFoundText: _chatNotFoundText,
      errorText: _chatErrorText,
    );
    if (message == null) return;
    if (!mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          overrideChatId: group.user.userId,
          focusMessageId: message.id,
        ),
      ),
    );
  }

  /// Fotoğrafın sohbetteki mesajına ifade bırakır.
  ///
  /// Sohbetteki uzun basma ile aynı seçici açılır ve ifade aynı yere yazılır
  /// (mesaj dokümanındaki `reactions.<uid>`, bkz. [ChatManager.toggleReaction]):
  /// sohbete girildiğinde fotoğrafın altında görünür ve danışana giden bildirim
  /// de aynı şekilde çalışır. Bırakanın o mesajdaki mevcut ifadesi seçicide
  /// işaretli gelir; aynı ifadeye basmak onu kaldırır.
  Future<void> _leaveReaction(
    _ClientPhotoGroup group,
    MealModel photo,
    Offset globalPosition,
  ) async {
    final ChatManager chatManager =
        Provider.of<ChatManager>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final MessageData? message = await _findChatMessage(
      group,
      photo,
      notFoundText: _reactNotFoundText,
      errorText: _reactErrorText,
    );
    if (message == null) return;
    if (!mounted) return;

    final String? currentEmoji = message.reactions[chatManager.userId];
    final String? selected = await showReactionPicker(
      context,
      globalPosition: globalPosition,
      currentEmoji: currentEmoji,
    );
    if (selected == null) return;

    try {
      await chatManager.toggleReaction(
        group.user.userId,
        message.id,
        selected,
        currentEmoji: currentEmoji,
      );

      // Kart rozeti hemen tazelenir: sunucudan yeni okuma beklenmez. Taban,
      // az önce okunan mesajın tepkileri; üstüne bu işlem yazılır.
      if (mounted) {
        setState(() {
          final Map<String, String> updated =
              Map<String, String>.from(message.reactions);
          if (selected == currentEmoji) {
            updated.remove(chatManager.userId);
          } else {
            updated[chatManager.userId] = selected;
          }

          if (updated.isEmpty) {
            _reactionsByImageUrl.remove(photo.imageUrl);
          } else {
            _reactionsByImageUrl[photo.imageUrl] = updated;
          }
        });
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(selected == currentEmoji
              ? _reactionRemovedText
              : '$_reactionSavedText $selected'),
          duration: _reactionFeedbackDuration,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _chatErrorTitle,
        message: _reactErrorText,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_ClientPhotoGroup> visible = _visibleGroups;

    return Scaffold(
      appBar: AppBarWithBack(
        title: _pageTitle,
        actions: [
          // Test verisi yükleme şimdilik kapalı.
          // LabeledActionButton(
          //   icon: Icons.science_outlined,
          //   label: _mockLabel,
          //   tooltip: 'Test için sahte öğün fotoğrafı yükle',
          //   onPressed: _isLoading ? null : _openMockPage,
          // ),
          // const SizedBox(width: 8),
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
          _buildDaySelector(context),
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

  /// Gün seçici: önceki/sonraki gün okları, takvimi açan tarih düğmesi ve
  /// bugüne dönüş kısayolu.
  ///
  /// İleri ok bugünde kapalıdır; gelecekte fotoğraf olamaz.
  Widget _buildDaySelector(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isToday = _isToday;
    final bool enabled = !_isLoading;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: _previousDayTooltip,
          onPressed: enabled ? () => _shiftDay(-1) : null,
          visualDensity: VisualDensity.compact,
        ),
        Flexible(
          child: TextButton.icon(
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(
              DateFormat('d MMMM y, EEEE', 'tr_TR').format(_day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            onPressed: enabled ? _pickDay : null,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: _nextDayTooltip,
          onPressed: enabled && !isToday ? () => _shiftDay(1) : null,
          visualDensity: VisualDensity.compact,
        ),
        if (!isToday) ...[
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.today, size: 18),
            label: const Text(_todayLabel),
            onPressed: enabled ? () => _selectDay(_todayStart()) : null,
          ),
        ],
      ],
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
          SearchField(
            controller: _searchController,
            label: _searchHint,
            maxWidth: _searchFieldMaxWidth,
            onChanged: (value) => setState(() {
              _searchQuery = value;
              _applyFilters();
            }),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: FilterChipGroup<Meals>(
              title: _mealFilterTitle,
              titleIcon: Icons.restaurant_menu,
              selectedValue: _mealFilter,
              options: {
                for (final Meals meal in _mealFilterOptions)
                  meal: meal.photoLabel,
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
                onPhotoMenu: (photo, globalPosition) =>
                    _openPhotoMenu(group, photo, globalPosition),
                reactionsByImageUrl: _reactionsByImageUrl,
                stripController: _stripControllerFor(group.user.userId),
                photoWidth: photoWidth,
                stripHeight: stripHeight,
                isLoadingPhotos: _photosLoading,
                emptyText: _mealFilter == null
                    ? (_isToday ? _emptyTodayText : _emptyOtherDayText)
                    : '"${_mealFilter!.photoLabel}" öğünü için fotoğraf '
                        'yüklenmemiş.',
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

  /// Öğün türü -> fotoğraf sayısı (yükleme sırasına göre). Ara öğünler tek
  /// anahtarda toplanır ([Meals.firstmid]); rozet "Ara Öğün (3)" der.
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
      // Ara öğünler numaralanmadan tek rozette toplanır.
      final Meals key =
          photo.mealType.isSnack ? Meals.firstmid : photo.mealType;
      countsByMeal[key] = (countsByMeal[key] ?? 0) + 1;
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

  /// Bir fotoğrafa sağ tıklandığında (ya da uzun basıldığında) çağrılır;
  /// menü [globalPosition] noktasında açılır.
  final void Function(MealModel photo, Offset globalPosition) onPhotoMenu;

  /// Fotoğraf adresi -> o fotoğrafa bırakılan tepkiler; kart rozetleri buradan
  /// çizilir. Tepkisi olmayan fotoğraf bu map'te bulunmaz.
  final Map<String, Map<String, String>> reactionsByImageUrl;

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
    required this.onPhotoMenu,
    required this.reactionsByImageUrl,
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
          itemBuilder: (context, index) {
            final MealModel photo = group.photos[index];
            return SizedBox(
              width: photoWidth,
              // Sağ tık masaüstünde, uzun basma dokunmatikte aynı menüyü açar.
              // Karta sol tık (büyütme) [MealImageCard] içinde kalır.
              child: GestureDetector(
                onSecondaryTapDown: (details) =>
                    onPhotoMenu(photo, details.globalPosition),
                onLongPressStart: (details) =>
                    onPhotoMenu(photo, details.globalPosition),
                child: MealImageCard(
                  meal: photo,
                  dialogImageHeight: dialogImageHeight,
                  backfillUserId: group.user.userId,
                  reactions:
                      reactionsByImageUrl[photo.imageUrl] ?? const {},
                ),
              ),
            );
          },
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

/// Başlıktaki "Sabah (2)" biçimindeki öğün rozeti. Renk ve ikon, fotoğraf
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
            '${mealType.photoLabel} ($count)',
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
