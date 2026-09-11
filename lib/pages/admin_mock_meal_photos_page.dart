// lib/pages/admin_mock_meal_photos_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/diet_model.dart';
import '../models/diet_section.dart';
import '../models/meal_model.dart';
import '../models/mock_test_run.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';
import '../providers/diet_provider.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/mock_test_data_provider.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/search_text.dart';
import '../utils/storage_upload.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/status_note.dart';

/// TEST ARACI: seçilen danışanlar adına geçici diyet + sahte öğün fotoğrafı
/// yükler ve ürettiği her şeyi tek tuşla geri siler.
///
/// Akış, danışanın kendi yüklemesiyle **birebir aynı** yoldan geçer
/// ([MealManager.uploadMealImg]), yani veri gerçek yüklemeyle aynı şekilde
/// `users/{uid}/meals/{gün}/mealEntries` altına yazılır. Bu yüzden üretilen her
/// fotoğraf ve her geçici diyet [MockTestDataProvider] defterine kaydedilir;
/// "Test Verilerini Sil" butonu **yalnızca defterdekileri** siler, danışanın
/// gerçek verisine hiçbir koşulda dokunmaz.
///
/// Kurallar:
/// - Yalnızca aktif paketi olan danışanlar listelenir (Öğün Fotoğrafları
///   sayfasıyla aynı koşul).
/// - Diyet seçilirse her danışana o diyetin geçici bir kopyası yüklenir ve
///   öğünler o kopyadan alınır. Seçilmezse danışanın kendi diyeti kullanılır;
///   diyeti olmayan danışan atlanır.
/// - Her öğün için [_photosPerMeal] fotoğraf yüklenir; saatler öğünün
///   varsayılan saatinden başlar, fotoğraf ve danışan başına kaydırılır ki
///   sayfada farklı saatler görünsün.
class AdminMockMealPhotosPage extends StatefulWidget {
  const AdminMockMealPhotosPage({super.key});

  @override
  State<AdminMockMealPhotosPage> createState() =>
      _AdminMockMealPhotosPageState();
}

class _AdminMockMealPhotosPageState extends State<AdminMockMealPhotosPage> {
  static const String _pageTitle = 'Test Öğün Fotoğrafı Yükle';
  static const String _refreshLabel = 'Yenile';
  static const String _searchHint = 'Danışan ara (ad soyad / e-posta / uid)';
  static const String _loadingText = 'Danışanlar yükleniyor...';
  static const String _loadErrorText =
      'Danışanlar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _noCustomerText = 'Aktif paketi olan danışan bulunamadı.';
  static const String _noSearchResultText = 'Aramanıza uyan danışan bulunamadı.';
  static const String _pickPhotoLabel = 'Mock Fotoğraf Seç';
  static const String _pickDietLabel = 'Diyet Seç';
  static const String _uploadLabel = 'Fotoğrafları Yükle';
  static const String _cleanupLabel = 'Test Verilerini Sil';
  static const String _noPendingTestDataText =
      'Sistemde bekleyen test verisi yok.';

  /// Her öğün için yüklenecek fotoğraf sayısı. [MealModel.maxImages] üstüne
  /// çıkılamaz: fazlası yüklenmez.
  static const int _photosPerMeal = 2;

  /// Aynı öğünün fotoğrafları arasındaki dakika farkı.
  static const int _minutesBetweenPhotos = 5;

  /// Danışanlar arasındaki dakika kayması: iki danışanın saatleri birebir aynı
  /// görünmesin diye sıradaki her danışan bu kadar dakika ötelenir.
  static const int _minutesBetweenClients = 3;

  /// Danışan kaymasının tekrara düşmeden gidebileceği en büyük değer.
  static const int _clientShiftLimit = 5;

  static const double _panelMinWidth = 320.0;
  static const double _panelMaxWidth = 440.0;
  static const double _panelWidthRatio = 0.34;
  static const double _previewSize = 132.0;

  final ScrollController _listScrollController = ScrollController();
  final ScrollController _panelScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// Yükleme/temizleme sırasında ilerlemeyi canlı gösteren dialog mesajı.
  final ValueNotifier<String> _progressMessage = ValueNotifier<String>('');

  /// İlerleme dialogu şu an açık mı (bkz. [_openProgress]).
  bool _progressOpen = false;

  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorText;

  /// Aktif paketi olan danışanlar (test hedefleri), ada göre sıralı.
  List<_MockClient> _clients = const [];

  /// Tüm danışanlar: kaynak diyet, aktif paketi olmayan birinden de seçilebilir.
  List<UserModel> _allCustomers = const [];

  final Set<String> _selectedUserIds = <String>{};

  String _searchQuery = '';

  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoMimeType;

  /// Danışanlara kopyalanacak kaynak diyet; null ise danışanın kendi diyeti
  /// kullanılır.
  DietDocument? _sourceDiet;
  String _sourceDietOwner = '';

  /// Yüklemeden önce bu danışanların eski TEST verisi silinsin mi.
  bool _cleanBeforeUpload = true;

  /// Sistemde duran (henüz silinmemiş) test verisi kayıtları.
  List<MockTestRun> _runs = const [];

  /// Son çalıştırmanın danışan bazlı sonucu.
  List<_MockResult> _results = const [];

  static DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPage();
    });
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _panelScrollController.dispose();
    _searchController.dispose();
    _progressMessage.dispose();
    super.dispose();
  }

  /// Danışanları (aktif paketliler + tümü) ve bekleyen test verisi kayıtlarını
  /// çeker.
  Future<void> _loadPage() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final List<UserModel> customers = await userProvider.fetchAllCustomers();
      final Map<String, SubscriptionModel> activeSubs =
          await subProvider.fetchActiveSubscriptionsOfUsers(
        customers.map((user) => user.userId).toList(),
      );

      final List<_MockClient> clients = [];
      for (final UserModel customer in customers) {
        final SubscriptionModel? sub = activeSubs[customer.userId];
        if (sub == null) continue;
        clients.add(_MockClient(user: customer, subscription: sub));
      }
      clients.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

      final List<UserModel> sortedCustomers = List<UserModel>.from(customers)
        ..sort((a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      final List<MockTestRun> runs = await mockProvider.fetchRuns();

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _allCustomers = sortedCustomers;
        _runs = runs;
        _selectedUserIds
            .removeWhere((id) => !clients.any((c) => c.user.userId == id));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _loadErrorText;
        _isLoading = false;
      });
    }
  }

  /// Yalnızca bekleyen test verisi kayıtlarını tazeler.
  Future<void> _reloadRuns() async {
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);
    try {
      final List<MockTestRun> runs = await mockProvider.fetchRuns();
      if (!mounted) return;
      setState(() => _runs = runs);
    } catch (e) {
    }
  }

  List<_MockClient> get _visibleClients {
    final String rawQuery = _searchQuery.trim().toLowerCase();
    if (rawQuery.isEmpty) return _clients;

    final List<String> queryWords = searchWordsOf(_searchQuery);
    return _clients
        .where((client) => client.matchesQuery(queryWords, rawQuery))
        .toList();
  }

  int get _pendingPhotoCount =>
      _runs.fold<int>(0, (sum, run) => sum + run.photos.length);

  int get _pendingDietCount =>
      _runs.fold<int>(0, (sum, run) => sum + run.diets.length);

  /// Temizlenmemiş bir çalıştırma kaydı var mı.
  ///
  /// Sayılara değil kaydın varlığına bakılır: tek tek kayıtları eksik kalmış
  /// bir çalıştırmada da temizleme çalışabilmeli, çünkü tarama adımı asıl o
  /// durumda gerekiyor.
  bool get _hasPendingTestData => _runs.isNotEmpty;

  /// Seçilen kaynak diyette hiç öğün yoksa yükleme yapılmaz: her danışana boş
  /// bir diyet kopyalayıp sonra atlamanın anlamı yok.
  bool get _canRun =>
      !_isBusy &&
      _photoBytes != null &&
      _selectedUserIds.isNotEmpty &&
      (_sourceDiet == null || _sourceDietMeals.isNotEmpty);

  /// Yüklenecek öğünler kaynak diyetten geliyorsa, kaç fotoğraf üretileceği
  /// baştan bilinir; bilgi kutusunda gösterilir.
  List<Meals> get _sourceDietMeals =>
      _sourceDiet == null ? const [] : _mealsOfDiet(_sourceDiet!, _todayStart());

  /// Mock fotoğrafı seçtirir. Dosya belleğe alınır (`withData`) ki her yükleme
  /// için aynı baytlar farklı adlarla tekrar tekrar kullanılabilsin.
  Future<void> _pickPhoto() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.single;
      if (file.bytes == null) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Seçilen dosya okunamadı.',
        );
        return;
      }
      if (file.size > kMaxUploadBytes) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Dosya Çok Büyük',
          message: 'Fotoğraf en fazla $kMaxUploadSizeLabel olabilir.',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _photoBytes = file.bytes;
        _photoName = file.name;
        _photoMimeType = _mimeTypeOf(file.extension);
      });
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Fotoğraf seçilemedi: $e',
      );
    }
  }

  static String _mimeTypeOf(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Kaynak diyeti seçtirir: önce danışan, sonra o danışanın diyet listesi.
  Future<void> _pickSourceDiet() async {
    final _SourceDietSelection? selection =
        await showDialog<_SourceDietSelection>(
      context: context,
      builder: (_) => _SourceDietPickerDialog(customers: _allCustomers),
    );
    if (selection == null || !mounted) return;

    setState(() {
      _sourceDiet = selection.diet;
      _sourceDietOwner = selection.ownerName;
    });
  }

  void _clearSourceDiet() {
    setState(() {
      _sourceDiet = null;
      _sourceDietOwner = '';
    });
  }

  /// Danışanın diyetinde tanımlı öğünler. Bugün hafta sonuysa ve diyette ayrı
  /// bir hafta sonu menüsü varsa o menü kullanılır. Sıra [Meals.dietValues]
  /// sırasıdır, yani gün içindeki doğal öğün sırası.
  List<Meals> _mealsOfDiet(DietDocument diet, DateTime day) {
    final Map<String, dynamic> section = (isWeekendDate(day) && diet.hasWeekend)
        ? diet.weekendSubtitles!
        : diet.subtitles;

    return Meals.dietValues
        .where((meal) => section.containsKey(meal.name))
        .toList();
  }

  /// Kaynak diyetin danışana kopyalanacak hâli.
  ///
  /// Tarif PDF'i ve kaynak Word dosyası alanları BİLEREK kopyalanmaz: bunlar
  /// kaynak danışanın Storage dosyalarını işaret eder ve diyet silinirken o
  /// dosyalar da silinir ([DietProvider.deleteDiet]). Kopyalansaydı test
  /// temizliği gerçek danışanın dosyasını silerdi.
  Map<String, dynamic> _buildDietCopy(DietDocument source) {
    return <String, dynamic>{
      'displayName': '$kMockDietNamePrefix${source.displayName}',
      'subtitles': source.subtitles,
      if (source.hasWeekend) 'weekendSubtitles': source.weekendSubtitles,
      if (source.waterGoal != null) 'waterGoal': source.waterGoal,
      if (source.sportGoal != null) 'sportGoal': source.sportGoal,
      kMockTestDataField: true,
    };
  }

  /// Öğünün varsayılan saatinden (ör. Sabah 09:00) türetilen yükleme zamanı.
  /// Fotoğraf ve danışan sırasına göre kaydırılır ki sayfada hep farklı
  /// saatler görünsün.
  DateTime _uploadTimeFor(
    DateTime day,
    Meals meal,
    int photoIndex,
    int clientIndex,
  ) {
    final List<String> parts = meal.defaultTime.split(':');
    final int hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 12) : 12;
    final int minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final int shift = photoIndex * _minutesBetweenPhotos +
        (clientIndex % _clientShiftLimit) * _minutesBetweenClients;

    return DateTime(day.year, day.month, day.day, hour, minute)
        .add(Duration(minutes: shift));
  }

  /// Seçili danışanlar için geçici diyeti ve sahte fotoğrafları yükler.
  ///
  /// Üretilen her şey anında [MockTestDataProvider] defterine yazılır; bir
  /// danışanda çıkan hata diğerlerini durdurmaz ve her danışanın sonucu
  /// sayfanın sağ alt bölümünde raporlanır.
  Future<void> _runMockUpload() async {
    final Uint8List? bytes = _photoBytes;
    if (bytes == null || _selectedUserIds.isEmpty) return;

    final List<_MockClient> selected = _clients
        .where((client) => _selectedUserIds.contains(client.user.userId))
        .toList();
    final DateTime day = _todayStart();
    final DietDocument? sourceDiet = _sourceDiet;

    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Verisi Yüklensin mi?',
      message: '${selected.length} danışan seçildi.\n\n'
          '• Her danışanın diyetinde tanımlı her öğün için $_photosPerMeal '
          'fotoğraf ${DateFormat('d MMMM y', 'tr_TR').format(day)} tarihine '
          'yüklenecek.\n'
          '${sourceDiet == null ? '• Diyet seçilmedi: her danışanın kendi diyeti kullanılacak, diyeti olmayan atlanacak.' : '• "${sourceDiet.displayName}" diyetinin geçici bir kopyası her danışana yüklenecek (danışanın planında görünür).'}'
          '${_cleanBeforeUpload ? '\n• Bu danışanların ÖNCEKİ test verileri (fotoğraf + test diyeti) silinecek.' : ''}'
          '\n\nÜretilen her şey kaydedilir; "Test Verilerini Sil" butonuyla '
          'tamamen geri alınabilir.',
      confirmText: 'Yükle',
      cancelText: 'Vazgeç',
    );
    if (!confirmed || !mounted) return;

    // Context'e bağlı nesneler await'lerden önce alınır.
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final dietProvider = Provider.of<DietProvider>(context, listen: false);
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);

    setState(() {
      _isBusy = true;
      _results = const [];
    });

    _openProgress('Hazırlanıyor...');
    final List<_MockResult> results = [];
    String? runId;

    try {
      // 1) Bu danışanların önceki test verisi (istenirse) temizlenir. Yalnızca
      // deftere kayıtlı test verisi silinir; gerçek fotoğraflara dokunulmaz.
      if (_cleanBeforeUpload) {
        await mockProvider.cleanup(
          mealManager: mealManager,
          dietProvider: dietProvider,
          userIds: selected.map((client) => client.user.userId).toSet(),
          onProgress: (message) => _progressMessage.value = message,
        );
      }

      // 2) Çalıştırma defteri açılır: bundan sonra üretilen her şey buraya
      // yazılır, böylece silinebilir kalır.
      runId = await mockProvider.startRun(
        createdBy: FirebaseAuth.instance.currentUser?.uid,
        clientNames: selected.map((client) => client.displayName).toList(),
        userIds: selected.map((client) => client.user.userId).toList(),
        date: day,
      );

      for (int clientIndex = 0; clientIndex < selected.length; clientIndex++) {
        final _MockClient client = selected[clientIndex];
        final String progressPrefix =
            '${client.displayName} (${clientIndex + 1}/${selected.length})';

        try {
          final DietDocument? diet = await _resolveDietForClient(
            client: client,
            sourceDiet: sourceDiet,
            dietProvider: dietProvider,
            mockProvider: mockProvider,
            runId: runId,
            progressPrefix: progressPrefix,
          );

          if (diet == null) {
            results.add(_MockResult.skipped(
                client.displayName, 'Diyet bulunamadı, atlandı.'));
            continue;
          }

          final List<Meals> meals = _mealsOfDiet(diet, day);
          if (meals.isEmpty) {
            results.add(_MockResult.skipped(
                client.displayName, 'Diyetinde tanımlı öğün yok, atlandı.'));
            continue;
          }

          int uploaded = 0;
          for (final Meals meal in meals) {
            for (int photoIndex = 0;
                photoIndex < _photosPerMeal;
                photoIndex++) {
              _progressMessage.value =
                  '$progressPrefix - ${meal.label} (${photoIndex + 1}/'
                  '$_photosPerMeal)';

              final String fileName = '$kMockPhotoFilePrefix${meal.name}_'
                  '$photoIndex${_extensionOfSelectedPhoto()}';
              final DateTime uploadTime =
                  _uploadTimeFor(day, meal, photoIndex, clientIndex);

              final String? url = await mealManager.uploadMealImg(
                userId: client.user.userId,
                meal: meal,
                image: XFile.fromData(
                  bytes,
                  path: fileName,
                  name: fileName,
                  mimeType: _photoMimeType,
                ),
                subscriptionId: client.subscription.subscriptionId,
                overrideDate: uploadTime,
              );
              if (url == null) continue;

              // Fotoğraf yazılır yazılmaz deftere geçer: araya bir kesinti
              // girse bile silinemeyen veri kalmaz.
              await mockProvider.recordArtifacts(
                runId: runId,
                photos: [
                  MockTestPhotoRef(
                    userId: client.user.userId,
                    dateKey: DateFormat('yyyy-MM-dd').format(uploadTime),
                    mealName: meal.name,
                    url: url,
                  ),
                ],
              );
              uploaded++;
            }
          }

          results.add(_MockResult.done(
            client.displayName,
            '${meals.length} öğün · $uploaded fotoğraf yüklendi '
            '(${meals.map((meal) => meal.label).join(', ')})',
          ));
        } catch (e) {
          results.add(_MockResult.failed(client.displayName, 'Hata: $e'));
        }
      }

      _closeProgress(navigator);
      await _reloadRuns();

      if (!mounted) return;
      setState(() => _results = results);

      final int okCount = results.where((result) => result.isDone).length;
      await DialogUtils.openInfo(
        context,
        title: 'Test Verisi Yüklendi',
        message: '$okCount/${selected.length} danışan için fotoğraf yüklendi.\n\n'
            'Test bitince "Test Verilerini Sil" butonuyla tüm test verisini '
            '(fotoğraflar + geçici diyetler) kaldırabilirsiniz.',
      );
    } catch (e) {
      _closeProgress(navigator);
      await _reloadRuns();
      if (!mounted) return;
      setState(() => _results = results);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Test verisi yüklenemedi: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Danışan için kullanılacak diyeti belirler.
  ///
  /// Kaynak diyet seçilmişse kopyası oluşturulup **hemen** deftere yazılır ve
  /// o kopya kullanılır; seçilmemişse danışanın kendi son diyeti okunur.
  Future<DietDocument?> _resolveDietForClient({
    required _MockClient client,
    required DietDocument? sourceDiet,
    required DietProvider dietProvider,
    required MockTestDataProvider mockProvider,
    required String runId,
    required String progressPrefix,
  }) async {
    if (sourceDiet == null) {
      _progressMessage.value = '$progressPrefix - diyet okunuyor...';
      return dietProvider.fetchLatestDietDocument(client.user.userId);
    }

    _progressMessage.value = '$progressPrefix - geçici diyet yükleniyor...';
    final String docId = await dietProvider.createDiet(
      userId: client.user.userId,
      dietData: _buildDietCopy(sourceDiet),
      subscriptionId: client.subscription.subscriptionId,
    );

    await mockProvider.recordArtifacts(
      runId: runId,
      diets: [
        MockTestDietRef(
          userId: client.user.userId,
          docId: docId,
          displayName: '$kMockDietNamePrefix${sourceDiet.displayName}',
        ),
      ],
    );

    // Öğünler kopyanın içeriğinden okunur; içerik kaynakla birebir aynıdır.
    return sourceDiet;
  }

  /// Deftere kayıtlı TÜM test verisini siler. Testten sonra basılacak buton.
  Future<void> _cleanupAllTestData() async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Verileri Silinsin mi?',
      message: 'Kayıtlı $_pendingPhotoCount test fotoğrafı ve '
          '$_pendingDietCount geçici diyet silinecek. Ayrıca ilgili danışanlar '
          'taranır; kayda geçmemiş test verisi varsa o da temizlenir.\n\n'
          'Yalnızca bu araçla üretilen veri silinir; danışanların gerçek '
          'fotoğraf ve diyetlerine dokunulmaz.',
      confirmText: 'Sil',
      cancelText: 'Vazgeç',
    );
    if (!confirmed || !mounted) return;

    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final dietProvider = Provider.of<DietProvider>(context, listen: false);
    final mockProvider =
        Provider.of<MockTestDataProvider>(context, listen: false);

    setState(() => _isBusy = true);
    _openProgress('Test verileri siliniyor...');

    try {
      final MockCleanupResult result = await mockProvider.cleanup(
        mealManager: mealManager,
        dietProvider: dietProvider,
        onProgress: (message) => _progressMessage.value = message,
      );

      _closeProgress(navigator);
      await _reloadRuns();

      if (!mounted) return;
      setState(() => _results = const []);
      await DialogUtils.openInfo(
        context,
        title: result.hasFailures ? 'Kısmen Silindi' : 'Test Verileri Silindi',
        message: result.summary,
      );
    } catch (e) {
      _closeProgress(navigator);
      await _reloadRuns();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Test verileri silinemedi: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// İlerleme dialogunu açar.
  ///
  /// Dialog await edilmez; kullanıcı geri tuşuyla kapatırsa `whenComplete`
  /// [_progressOpen] bayrağını düşürür, böylece [_closeProgress] yanlışlıkla
  /// sayfayı kapatmaz.
  void _openProgress(String message) {
    _progressMessage.value = message;
    _progressOpen = true;
    DialogUtils.openLoadingProgress(context,
            messageListenable: _progressMessage)
        .whenComplete(() => _progressOpen = false);
  }

  /// İlerleme dialogunu kapatır; zaten kapalıysa hiçbir şey yapmaz.
  void _closeProgress(NavigatorState navigator) {
    if (!_progressOpen) return;
    _progressOpen = false;
    if (navigator.mounted) navigator.pop();
  }

  String _extensionOfSelectedPhoto() {
    final String name = _photoName ?? '';
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '.jpg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWithBack(
        title: _pageTitle,
        actions: [
          LabeledActionButton(
            icon: Icons.refresh,
            label: _refreshLabel,
            onPressed: _isLoading || _isBusy ? null : _loadPage,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
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
          onPressed: _loadPage,
        ),
      );
    }

    if (_clients.isEmpty) {
      return const StatusNote(
        icon: Icons.people_outline,
        text: _noCustomerText,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double panelWidth = (constraints.maxWidth * _panelWidthRatio)
            .clamp(_panelMinWidth, _panelMaxWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildClientPanel(context)),
            const VerticalDivider(width: 1),
            SizedBox(width: panelWidth, child: _buildSettingsPanel(context)),
          ],
        );
      },
    );
  }

  /// Sol panel: danışan arama + çoklu seçim listesi.
  Widget _buildClientPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_MockClient> visible = _visibleClients;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Görünenleri Seç'),
                onPressed: _isBusy
                    ? null
                    : () => setState(() => _selectedUserIds
                        .addAll(visible.map((client) => client.user.userId))),
              ),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Seçimi Temizle'),
                onPressed: _isBusy || _selectedUserIds.isEmpty
                    ? null
                    : () => setState(_selectedUserIds.clear),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visible.length} aktif danışan · ${_selectedUserIds.length} seçili',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const StatusNote(
                  icon: Icons.search_off,
                  text: _noSearchResultText,
                )
              : Scrollbar(
                  controller: _listScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final _MockClient client = visible[index];
                      final bool selected =
                          _selectedUserIds.contains(client.user.userId);

                      return CheckboxListTile(
                        value: selected,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _isBusy
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selectedUserIds.add(client.user.userId);
                                  } else {
                                    _selectedUserIds.remove(client.user.userId);
                                  }
                                }),
                        title: Text(
                          client.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${client.user.email}\n${client.user.userId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        isThreeLine: true,
                        secondary: Tooltip(
                          message: client.subscription.status.displayName,
                          child: Icon(
                            Icons.card_membership,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Sağ panel: mock fotoğraf, diyet, ayarlar, çalıştırma, temizleme, sonuçlar.
  Widget _buildSettingsPanel(BuildContext context) {
    return Scrollbar(
      controller: _panelScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _panelScrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPhotoCard(context),
            const SizedBox(height: 16),
            _buildDietCard(context),
            const SizedBox(height: 16),
            _buildSettingsCard(context),
            const SizedBox(height: 16),
            LabeledActionButton(
              icon: Icons.cloud_upload,
              label: _uploadLabel,
              onPressed: _canRun ? _runMockUpload : null,
            ),
            const SizedBox(height: 16),
            _buildCleanupCard(context),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildResultsCard(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _PanelCard(
      title: 'Mock Fotoğraf',
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: _previewSize,
              height: _previewSize,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoBytes == null
                  ? Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : Image.memory(
                      _photoBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _photoName ?? 'Henüz fotoğraf seçilmedi.',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          LabeledActionButton(
            icon: Icons.folder_open,
            label: _pickPhotoLabel,
            onPressed: _isBusy ? null : _pickPhoto,
          ),
        ],
      ),
    );
  }

  Widget _buildDietCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DietDocument? diet = _sourceDiet;
    final List<Meals> meals = _sourceDietMeals;

    return _PanelCard(
      title: 'Geçici Diyet',
      icon: Icons.restaurant_menu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            diet == null
                ? 'Diyet seçilmedi: her danışanın kendi diyeti kullanılır, '
                    'diyeti olmayan danışan atlanır.'
                : 'Seçilen diyetin bir kopyası her danışana yüklenir ve '
                    'öğünler bu diyetten alınır. Test verisi silinince bu '
                    'kopyalar da silinir.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (diet != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diet.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kaynak: $_sourceDietOwner',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meals.isEmpty
                        ? 'Bu diyette tanımlı öğün bulunamadı.'
                        : '${meals.length} öğün · ${meals.length * _photosPerMeal} '
                            'fotoğraf/danışan\n'
                            '${meals.map((meal) => meal.label).join(', ')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabeledActionButton(
                  icon: Icons.menu_book_outlined,
                  label: _pickDietLabel,
                  onPressed: _isBusy ? null : _pickSourceDiet,
                ),
              ),
              if (diet != null) ...[
                const SizedBox(width: 8),
                LabeledActionButton(
                  icon: Icons.close,
                  label: 'Kaldır',
                  dense: true,
                  onPressed: _isBusy ? null : _clearSourceDiet,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _PanelCard(
      title: 'Ayarlar',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Her öğün için $_photosPerMeal fotoğraf yüklenir. Saatler öğünün '
            'varsayılan saatinden başlar (Sabah ${Meals.br.defaultTime}, Öğle '
            '${Meals.lunch.defaultTime}, Akşam ${Meals.dinner.defaultTime}); '
            'fotoğraflar $_minutesBetweenPhotos dk, danışanlar '
            '$_minutesBetweenClients dk arayla kaydırılır.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _cleanBeforeUpload,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Önce eski test verilerini sil'),
            subtitle: const Text(
              'Seçili danışanların önceki test fotoğraf ve diyetlerini siler. '
              'Gerçek verilere dokunulmaz.',
            ),
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _cleanBeforeUpload = value ?? false),
          ),
        ],
      ),
    );
  }

  /// Testten sonra basılacak temizleme kutusu: ne kaldığını gösterir ve siler.
  Widget _buildCleanupCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _PanelCard(
      title: 'Test Verisi Temizliği',
      icon: Icons.cleaning_services_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_hasPendingTestData)
            Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _noPendingTestDataText,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else ...[
            Text(
              'Sistemde duran test verisi:\n'
              '$_pendingPhotoCount fotoğraf · $_pendingDietCount geçici diyet '
              '(${_runs.length} çalıştırma)',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            for (final MockTestRun run in _runs.take(_maxListedRuns))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${DateFormat('d MMMM y HH:mm', 'tr_TR').format(run.createdAt)}'
                  ' · ${run.photos.length} fotoğraf · ${run.diets.length} diyet'
                  '${run.clientNames.isEmpty ? '' : '\n  ${run.clientNames.join(', ')}'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (_runs.length > _maxListedRuns)
              Text(
                've ${_runs.length - _maxListedRuns} çalıştırma daha...',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
          const SizedBox(height: 12),
          LabeledActionButton(
            icon: Icons.delete_forever,
            label: _cleanupLabel,
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            onPressed:
                _isBusy || !_hasPendingTestData ? null : _cleanupAllTestData,
          ),
        ],
      ),
    );
  }

  /// Temizleme kutusunda en fazla kaç çalıştırma tek tek listelensin.
  static const int _maxListedRuns = 3;

  Widget _buildResultsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _PanelCard(
      title: 'Sonuçlar',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final _MockResult result in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(result.icon, size: 16, color: result.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.clientName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          result.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Listede gösterilen danışan: kullanıcı kaydı + aktif paketi.
class _MockClient {
  final UserModel user;
  final SubscriptionModel subscription;

  _MockClient({required this.user, required this.subscription});

  String get displayName => user.fullName.isEmpty ? user.email : user.fullName;

  /// Ad/e-posta kelimeleri (normalize). Her tuş vuruşunda yeniden
  /// hesaplanmaması için kurulurken bir kez üretilir.
  late final List<String> _searchWords =
      searchWordsOf('${user.fullName} ${user.email}');

  /// Uid ile arama: uid rastgele karakterlerden oluştuğu için **içinde**
  /// aranmaz (iki harflik sorgu alakasız danışanları getirirdi), yalnızca
  /// baştan eşleşme kabul edilir — yapıştırılan uid yine bulunur.
  bool matchesQuery(List<String> queryWords, String rawQuery) {
    if (matchesSearchWords(queryWords, _searchWords)) return true;
    return rawQuery.length >= _minUidQueryLength &&
        user.userId.toLowerCase().startsWith(rawQuery);
  }

  /// Uid aramasının başlayacağı en küçük sorgu uzunluğu.
  static const int _minUidQueryLength = 4;
}

/// Kaynak diyet seçiminin sonucu.
class _SourceDietSelection {
  final String ownerName;
  final DietDocument diet;

  const _SourceDietSelection({required this.ownerName, required this.diet});
}

/// Kaynak diyeti seçtiren iki adımlı dialog: solda danışan, sağda o danışanın
/// diyet listesi.
class _SourceDietPickerDialog extends StatefulWidget {
  final List<UserModel> customers;

  const _SourceDietPickerDialog({required this.customers});

  @override
  State<_SourceDietPickerDialog> createState() =>
      _SourceDietPickerDialogState();
}

class _SourceDietPickerDialogState extends State<_SourceDietPickerDialog> {
  static const double _minDialogWidth = 480.0;
  static const double _maxDialogWidth = 860.0;
  static const double _dialogWidthRatio = 0.7;
  static const double _minDialogHeight = 320.0;
  static const double _maxDialogHeight = 520.0;
  static const double _dialogHeightRatio = 0.7;

  final ScrollController _customerScrollController = ScrollController();
  final ScrollController _dietScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  UserModel? _selectedCustomer;
  List<DietDocument> _diets = const [];
  bool _loadingDiets = false;
  String? _dietError;

  @override
  void dispose() {
    _customerScrollController.dispose();
    _dietScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> get _visibleCustomers {
    final List<String> queryWords = searchWordsOf(_query);
    if (queryWords.isEmpty) return widget.customers;

    return widget.customers
        .where((user) => matchesSearchWords(
            queryWords, searchWordsOf('${user.fullName} ${user.email}')))
        .toList();
  }

  Future<void> _loadDiets(UserModel customer) async {
    final dietProvider = Provider.of<DietProvider>(context, listen: false);

    setState(() {
      _selectedCustomer = customer;
      _loadingDiets = true;
      _dietError = null;
      _diets = const [];
    });

    try {
      final List<DietDocument> diets = await dietProvider.fetchDiets(
        userId: customer.userId,
        showAllData: true,
      );
      if (!mounted) return;
      setState(() {
        _diets = diets;
        _loadingDiets = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dietError = 'Diyetler yüklenemedi.';
        _loadingDiets = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final double width = (screen.width * _dialogWidthRatio)
        .clamp(_minDialogWidth, _maxDialogWidth);
    final double height = (screen.height * _dialogHeightRatio)
        .clamp(_minDialogHeight, _maxDialogHeight);

    return AlertDialog(
      title: const Text('Diyet Seç'),
      content: SizedBox(
        width: width,
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildCustomerList(context)),
            const VerticalDivider(width: 16),
            Expanded(child: _buildDietList(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }

  Widget _buildCustomerList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<UserModel> visible = _visibleCustomers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Danışan ara',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const StatusNote(
                  icon: Icons.search_off,
                  text: 'Danışan bulunamadı.',
                )
              : Scrollbar(
                  controller: _customerScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _customerScrollController,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final UserModel customer = visible[index];
                      final bool selected =
                          _selectedCustomer?.userId == customer.userId;

                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor:
                            theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        title: Text(
                          customer.fullName.isEmpty
                              ? customer.email
                              : customer.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          customer.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () => _loadDiets(customer),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDietList(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_selectedCustomer == null) {
      return const StatusNote(
        icon: Icons.arrow_back,
        text: 'Önce soldan bir danışan seçin.',
      );
    }
    if (_loadingDiets) {
      return const StatusNote(text: 'Diyetler yükleniyor...', showProgress: true);
    }
    if (_dietError != null) {
      return StatusNote(
        icon: Icons.error_outline,
        text: _dietError!,
        isError: true,
      );
    }
    if (_diets.isEmpty) {
      return const StatusNote(
        icon: Icons.no_meals,
        text: 'Bu danışanın diyeti yok.',
      );
    }

    return Scrollbar(
      controller: _dietScrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _dietScrollController,
        itemCount: _diets.length,
        itemBuilder: (context, index) {
          final DietDocument diet = _diets[index];
          final int mealCount = diet.subtitles.length;

          return ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined, size: 20),
            title: Text(
              diet.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${diet.uploadTime == null ? '-' : DateFormat('d MMMM y', 'tr_TR').format(diet.uploadTime!)}'
              ' · $mealCount öğün${diet.hasWeekend ? ' · hafta sonu menüsü var' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => Navigator.pop(
              context,
              _SourceDietSelection(
                ownerName: _selectedCustomer!.fullName.isEmpty
                    ? _selectedCustomer!.email
                    : _selectedCustomer!.fullName,
                diet: diet,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bir danışan için çalıştırma sonucu.
class _MockResult {
  final String clientName;
  final String message;
  final _MockOutcome outcome;

  const _MockResult._(this.clientName, this.message, this.outcome);

  factory _MockResult.done(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.done);

  factory _MockResult.skipped(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.skipped);

  factory _MockResult.failed(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.failed);

  bool get isDone => outcome == _MockOutcome.done;

  IconData get icon {
    switch (outcome) {
      case _MockOutcome.done:
        return Icons.check_circle;
      case _MockOutcome.skipped:
        return Icons.info_outline;
      case _MockOutcome.failed:
        return Icons.error_outline;
    }
  }

  Color get color {
    switch (outcome) {
      case _MockOutcome.done:
        return Colors.green.shade700;
      case _MockOutcome.skipped:
        return Colors.orange.shade800;
      case _MockOutcome.failed:
        return Colors.red.shade700;
    }
  }
}

enum _MockOutcome { done, skipped, failed }

/// Sağ paneldeki başlıklı kart.
class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
